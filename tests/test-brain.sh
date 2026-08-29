#!/usr/bin/env bash
# Live functional proof of the brain protocol: two clones (machine A and B)
# exercising the exact flows the schema specifies, against a real bare remote.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi }
gA() { git -C "$SB/A" "$@"; }
gB() { git -C "$SB/B" "$@"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- init: bare remote + template + two machine clones ---
git init -q --bare "$SB/remote.git"
git -C "$SB/remote.git" symbolic-ref HEAD refs/heads/main
cp -R "$SRC/prometheus-template" "$SB/seed"
git -C "$SB/seed" init -q -b main
git -C "$SB/seed" add -A && git -C "$SB/seed" commit -qm "brain: init from template"
git -C "$SB/seed" remote add origin "$SB/remote.git" && git -C "$SB/seed" push -q origin main
git clone -q "$SB/remote.git" "$SB/A"
git clone -q "$SB/remote.git" "$SB/B"
check "template clones cleanly"        test -f "$SB/A/.gitattributes"

# --- 1. concurrent journal appends (same day file) merge via union ---
DAY=journal/2026-07-02.md
echo "- 09:00: machine A note [claude@A]" >> "$SB/A/$DAY"
gA add "$DAY" && gA commit -qm "brain: capture $DAY [claude@A]" && gA push -q
echo "- 09:01: machine B note [openclaw@B]" >> "$SB/B/$DAY"   # B is stale
gB add "$DAY" && gB commit -qm "brain: capture $DAY [openclaw@B]"
check "B stale push rejected"          bash -c "! git -C '$SB/B' push -q 2>/dev/null"
check "B pull --rebase succeeds"       gB pull -q --rebase
check "B push after rebase"            gB push -q
gA pull -q --rebase
check "journal: A line survived"       grep -q 'machine A note' "$SB/A/$DAY"
check "journal: B line survived"       grep -q 'machine B note' "$SB/A/$DAY"
check "journal: no conflict markers"   bash -c "! grep -qE '^(<<<<<<<|=======|>>>>>>>)' '$SB/A/$DAY'"

# --- 2. concurrent Queue claims on the same project page ---
PROJ=projects/example-app.md
sed 's/<Project Name>/Example App/' "$SB/A/projects/_template.md" > "$SB/A/$PROJ"
gA add "$PROJ" && gA commit -qm "brain: capture $PROJ [claude@A]" && gA push -q
gB pull -q --rebase
awk '/^## Queue$/{print; print "- claimed url-A by maintainer [claude@A] 2026-07-02T22:00:00Z"; next}1' "$SB/A/$PROJ" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$PROJ"
gA add "$PROJ" && gA commit -qm "claim A" && gA push -q
awk '/^## Queue$/{print; print "- claimed url-B by maintainer [openclaw@B] 2026-07-02T22:00:01Z"; next}1' "$SB/B/$PROJ" > "$SB/B/x" && mv "$SB/B/x" "$SB/B/$PROJ"
gB add "$PROJ" && gB commit -qm "claim B"
gB pull -q --rebase && gB push -q
gA pull -q --rebase
check "claims: both present"           bash -c "grep -q 'url-A' '$SB/A/$PROJ' && grep -q 'url-B' '$SB/A/$PROJ'"
check "claims: no conflict markers"    bash -c "! grep -qE '^(<<<<<<<|=======|>>>>>>>)' '$SB/A/$PROJ'"
check "claims: single frontmatter"     test "$(grep -c '^type: project' "$SB/A/$PROJ")" -eq 1
check "claims: single Queue section"   test "$(grep -c '^## Queue$' "$SB/A/$PROJ")" -eq 1

# --- 3. the banned scenario really is dangerous: concurrent frontmatter edits ---
# The schema's union-merge caveat states this unconditionally: same-line edits concatenate into
# duplicated YAML, and the rebase absorbs it silently. Assert exactly that — a git-behavior
# change under the claim must turn this red, not pass quietly.
sed 's/^updated: .*/updated: 2026-07-03/' "$SB/A/$PROJ" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$PROJ"
gA add "$PROJ" && gA commit -qm "A bumps updated" && gA push -q
sed 's/^updated: .*/updated: 2026-07-04/' "$SB/B/$PROJ" > "$SB/B/x" && mv "$SB/B/x" "$SB/B/$PROJ"
gB add "$PROJ" && gB commit -qm "B bumps updated"
check "frontmatter: stale pull --rebase completes silently" gB pull -q --rebase
check "frontmatter ban justified: union duplicated updated:" test "$(grep -c '^updated:' "$SB/B/$PROJ")" -gt 1
gB checkout -q "$PROJ" 2>/dev/null; gB rebase --abort 2>/dev/null; gB reset -q --hard '@{u}' 2>/dev/null

# --- 4. inbox writer-suffix files never collide ---
echo idea-a > "$SB/A/inbox/2026-07-02-idea-claude.md"
gA add -A && gA commit -qm "brain: capture inbox [claude@A]" && gA push -q
echo idea-b > "$SB/B/inbox/2026-07-02-idea-openclaw.md"
gB add -A && gB commit -qm "brain: capture inbox [openclaw@B]"
gB pull -q --rebase && gB push -q
gA pull -q --rebase
check "inbox: both files present"      bash -c "test -f '$SB/A/inbox/2026-07-02-idea-claude.md' && test -f '$SB/A/inbox/2026-07-02-idea-openclaw.md'"

# --- 5. digest lock: push-wins arbitration ---
printf 'holder: claude@A\nclaimed: 2026-07-02T22:10:00Z\n' > "$SB/A/.locks/digest.md"
gA add -A && gA commit -qm "digest: lock [claude@A]" && gA push -q
printf 'holder: openclaw@B\nclaimed: 2026-07-02T22:10:01Z\n' > "$SB/B/.locks/digest.md"
gB add -A && gB commit -qm "digest: lock [openclaw@B]"
if ! gB push -q 2>/dev/null; then
  ok "lock: B push rejected"
  gB fetch -q
  if gB cat-file -e "origin/main:.locks/digest.md" 2>/dev/null; then
    ok "lock: B sees remote lock"
    gB reset -q --hard 'origin/main'
    check "lock: B dropped own claim"  grep -q 'claude@A' "$SB/B/.locks/digest.md"
  else fail "lock: B sees remote lock"; fi
else fail "lock: B push rejected"; fi
# release
gA rm -q .locks/digest.md && gA commit -qm "digest: release [claude@A]" && gA push -q
gB pull -q --rebase
check "lock: released everywhere"      bash -c "! test -e '$SB/B/.locks/digest.md'"

# --- 6. digest inbox promotion by whole-file move survives concurrent append ---
gB pull -q --rebase
gA mv inbox/2026-07-02-idea-claude.md notes/idea-from-inbox.md
gA commit -qm "brain: digest promote [claude@A]" && gA push -q
echo "- appended-while-promoting [openclaw@B]" >> "$SB/B/inbox/2026-07-02-idea-openclaw.md"
gB add -A && gB commit -qm "brain: capture [openclaw@B]"
gB pull -q --rebase && gB push -q
gA pull -q --rebase
check "promote: file moved"            test -f "$SB/A/notes/idea-from-inbox.md"
check "promote: B append survived"     grep -q 'appended-while-promoting' "$SB/A/inbox/2026-07-02-idea-openclaw.md"

# --- 7. retrieval primitives: wikilink graph + backlinks are greppable ---
cat > "$SB/A/people/jane-doe.md" <<'EOF'
---
type: person
created: 2026-07-02
updated: 2026-07-02
tags: [test]
source: chat
status: active
---
# Jane Doe
## Relations
- works_at [[companies/acme]]
## Log
- 2026-07-02: mentioned [[projects/example-app]] [claude@A]
EOF
gA add -A && gA commit -qm "brain: capture people/jane-doe.md [claude@A]" && gA push -q
check "graph: outlinks extractable"    bash -c "cd '$SB/A' && grep -o '\[\[[^]]*\]\]' people/jane-doe.md | grep -q 'companies/acme'"
check "graph: backlinks queryable"     bash -c "cd '$SB/A' && grep -rl '\[\[projects/example-app\]\]' --include='*.md' . | grep -q jane-doe"
check "graph: dangling link findable"  bash -c "cd '$SB/A' && test ! -f companies/acme.md"

# --- 8. reconcile drop-and-redo: rejected push is dropped, redone from fresh state, ends clean ---
gB pull -q --rebase
sed 's/^updated: .*/updated: 2026-07-05/' "$SB/A/$PROJ" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$PROJ"
gA add "$PROJ" && gA commit -qm "brain: digest reconcile $PROJ [claude@A]"
awk '/^## Queue$/{print; print "- claimed url-C by maintainer [openclaw@B] 2026-07-05T09:00:00Z"; next}1' "$SB/B/$PROJ" > "$SB/B/x" && mv "$SB/B/x" "$SB/B/$PROJ"
gB add "$PROJ" && gB commit -qm "claim C" && gB push -q
check "redo: stale reconcile push rejected"    bash -c "! git -C '$SB/A' push -q 2>/dev/null"
gA reset -q --hard HEAD~1   # protocol step 4: drop the edit — never rebase a union-path edit
gA pull -q --rebase
sed 's/^updated: .*/updated: 2026-07-05/' "$SB/A/$PROJ" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$PROJ"
gA add "$PROJ" && gA commit -qm "brain: digest reconcile $PROJ [claude@A]"
check "redo: push accepted from fresh state"   gA push -q
check "redo: single updated: key"              test "$(grep -c '^updated:' "$SB/A/$PROJ")" -eq 1
check "redo: reconciled value landed"          grep -q '^updated: 2026-07-05' "$SB/A/$PROJ"
check "redo: concurrent claim survived"        grep -q 'url-C' "$SB/A/$PROJ"
check "redo: nothing left unpushed"            test -z "$(gA log --oneline '@{u}..')"

# --- 9. final-bullet ban is load-bearing: edited final bullet + in-flight append corrupts ---
LAB=projects/adjacency-lab.md
sed 's/<Project Name>/Adjacency Lab/' "$SB/A/projects/_template.md" > "$SB/A/$LAB"
echo "- 2026-07-05: settled bullet [claude@A]" >> "$SB/A/$LAB"
echo "- 2026-07-06: final bullet, see [[projects/old-name]] [claude@A]" >> "$SB/A/$LAB"
gA add "$LAB" && gA commit -qm "brain: capture $LAB [claude@A]" && gA push -q
gB pull -q --rebase
sed 's|\[\[projects/old-name\]\]|[[projects/new-name]]|' "$SB/A/$LAB" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$LAB"
gA add "$LAB" && gA commit -qm "brain: digest reconcile $LAB [claude@A]" && gA push -q
echo "- 2026-07-06: in-flight append [openclaw@B]" >> "$SB/B/$LAB"
gB add "$LAB" && gB commit -qm "brain: capture $LAB [openclaw@B]"
check "final bullet: rebase absorbs silently"  gB pull -q --rebase
check "final bullet: stale line resurrected"   bash -c "grep -q 'projects/old-name' '$SB/B/$LAB' && grep -q 'projects/new-name' '$SB/B/$LAB'"
check "final bullet: bullet duplicated"        test "$(grep -c '2026-07-06: final bullet' "$SB/B/$LAB")" -eq 2
gB rebase --abort 2>/dev/null; gB reset -q --hard '@{u}' 2>/dev/null   # discard the corrupted lab commit
# control: the same edit one settled bullet away merges clean against the same in-flight append
sed 's/settled bullet/settled bullet (link repaired)/' "$SB/A/$LAB" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$LAB"
gA add "$LAB" && gA commit -qm "brain: digest reconcile $LAB [claude@A]" && gA push -q
echo "- 2026-07-07: second in-flight append [openclaw@B]" >> "$SB/B/$LAB"
gB add "$LAB" && gB commit -qm "brain: capture $LAB [openclaw@B]"
check "settled edit: rebase merges clean"      gB pull -q --rebase
check "settled edit: push accepted"            gB push -q
check "settled edit: repair present once"      test "$(grep -c 'settled bullet (link repaired)' "$SB/B/$LAB")" -eq 1
check "settled edit: no resurrected original"  bash -c "! grep -q 'settled bullet \[' '$SB/B/$LAB'"
check "settled edit: append survived"          grep -q 'second in-flight append' "$SB/B/$LAB"

# --- 10. post-Queue append point on projects/ pages is live: edit there + in-flight claim corrupts ---
gA pull -q --rebase
sed 's/url-C by/url-C-audited by/' "$SB/A/$PROJ" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$PROJ"
gA add "$PROJ" && gA commit -qm "brain: digest reconcile $PROJ [claude@A]" && gA push -q
awk '/^## Queue$/{print; print "- claimed url-D by maintainer [openclaw@B] 2026-07-07T09:00:00Z"; next}1' "$SB/B/$PROJ" > "$SB/B/x" && mv "$SB/B/x" "$SB/B/$PROJ"
gB add "$PROJ" && gB commit -qm "claim D"
check "queue point: rebase absorbs silently"   gB pull -q --rebase
check "queue point: stale claim resurrected"   bash -c "grep -q 'url-C-audited' '$SB/B/$PROJ' && grep -q 'url-C by' '$SB/B/$PROJ'"
gB rebase --abort 2>/dev/null; gB reset -q --hard '@{u}' 2>/dev/null   # discard the corrupted lab commit

# --- 11. stranded reconcile: unguarded pull --rebase corrupts silently; the guard avoids it ---
SLAB=projects/stranded-lab.md
sed 's/<Project Name>/Stranded Lab/' "$SB/A/projects/_template.md" > "$SB/A/$SLAB"
gA add "$SLAB" && gA commit -qm "brain: capture $SLAB [claude@A]" && gA push -q
gB pull -q --rebase
sed 's/^updated: .*/updated: 2026-07-10/' "$SB/A/$SLAB" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$SLAB"
gA add "$SLAB" && gA commit -qm "brain: digest reconcile $SLAB [claude@A]"   # stranded: never pushed
sed 's/^updated: .*/updated: 2026-07-11/' "$SB/B/$SLAB" > "$SB/B/x" && mv "$SB/B/x" "$SB/B/$SLAB"
gB add "$SLAB" && gB commit -qm "brain: digest reconcile $SLAB [openclaw@B]" && gB push -q
check "stranded: unguarded pull --rebase exits 0" gA pull -q --rebase
check "stranded: silent duplicated updated: keys" test "$(grep -c '^updated:' "$SB/A/$SLAB")" -gt 1
gA rebase --abort 2>/dev/null; gA reset -q --hard '@{u}' 2>/dev/null   # discard the corrupted replay
# the guard: detect the sole unpushed reconcile, drop it BEFORE pulling — no corruption
sed 's/^updated: .*/updated: 2026-07-12/' "$SB/A/$SLAB" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$SLAB"
gA add "$SLAB" && gA commit -qm "brain: digest reconcile $SLAB [claude@A]"   # stranded again
sed 's/^updated: .*/updated: 2026-07-13/' "$SB/B/$SLAB" > "$SB/B/x" && mv "$SB/B/x" "$SB/B/$SLAB"
gB add "$SLAB" && gB commit -qm "brain: digest reconcile $SLAB [openclaw@B]" && gB push -q
check "guard: exactly one unpushed commit"     test "$(gA rev-list --count '@{u}..')" -eq 1
check "guard: it is a digest reconcile"        bash -c "git -C '$SB/A' log -1 --format=%s | grep -q '^brain: digest reconcile'"
gA reset -q --hard '@{u}'   # the guard's drop, before any pull touches the stranded edit
check "guard: pull after drop stays clean"     gA pull -q --rebase
check "guard: single updated: key"             test "$(grep -c '^updated:' "$SB/A/$SLAB")" -eq 1
check "guard: remote reconcile preserved"      grep -q '^updated: 2026-07-13' "$SB/A/$SLAB"

# --- brain-lint: the follow-up ledger (schema §Follow-ups) ---
# Scratch trees per case; only the targeted error string is asserted, because a template copy in
# live mode reddens on unrelated checks by design.
mk_ledger_brain() { # mk_ledger_brain <dir> — template copy plus one open follow-up lesson
  cp -R "$SRC/prometheus-template" "$1"
  cat > "$1/lessons/sample-open-item.md" << 'PAGE'
---
type: lesson
created: 2026-07-01
updated: 2026-07-01
tags: [fixture]
source: agent-run
status: active
---

# Sample open item

Prevention: `follow-up`. Add the guard when the next release branch opens.
PAGE
}

# Delete the heading and its body up to the next heading, never to EOF: a range ending on
# '(none)' eats the rest of the file the moment a fixture carries a real entry instead.
drop_ledger_section() { # drop_ledger_section <index-file>
  awk '/^## Open follow-ups/{skip=1; next} /^## /{skip=0} !skip' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

mk_ledger_brain "$SB/L1"
drop_ledger_section "$SB/L1/INDEX.md"
OUT="$(bash "$SRC/tools/brain-lint.sh" "$SB/L1" 2>&1)" || true
check "ledger: missing INDEX section is flagged" \
  grep -qF "missing '## Open follow-ups' section" <<<"$OUT"
check "ledger: dropping the section keeps later sections" \
  grep -q '^## Needs review' "$SB/L1/INDEX.md"

mk_ledger_brain "$SB/L2"
OUT="$(bash "$SRC/tools/brain-lint.sh" "$SB/L2" 2>&1)" || true
check "ledger: unlisted open follow-up is flagged" \
  grep -qF 'follow-up sweep due' <<<"$OUT"

mk_ledger_brain "$SB/L3"
sed -i.bak 's|^(none)$|- [Sample open item](lessons/sample-open-item.md): add the guard (since 2026-07-01)|' "$SB/L3/INDEX.md" && rm -f "$SB/L3/INDEX.md.bak"
OUT="$(bash "$SRC/tools/brain-lint.sh" "$SB/L3" 2>&1)" || true
if grep -qF 'follow-up sweep due' <<<"$OUT"; then
  fail "ledger: listed follow-up passes the sweep check"
else
  ok "ledger: listed follow-up passes the sweep check"
fi

cp -R "$SRC/prometheus-template" "$SB/L4"
drop_ledger_section "$SB/L4/INDEX.md"
if bash "$SRC/tools/brain-lint.sh" --template "$SB/L4" >/dev/null 2>&1; then
  fail "ledger: template mode requires the section skeleton"
else
  ok "ledger: template mode requires the section skeleton"
fi

# A prefix-sharing entry must not satisfy a different lesson's check.
mk_ledger_brain "$SB/L5"
sed -i.bak 's|^(none)$|- [Other](lessons/sample-open-item.md-old.md): unrelated (since 2026-07-01)|' "$SB/L5/INDEX.md" && rm -f "$SB/L5/INDEX.md.bak"
OUT="$(bash "$SRC/tools/brain-lint.sh" "$SB/L5" 2>&1)" || true
check "ledger: prefix-sharing entry does not satisfy the check" \
  grep -qF 'follow-up sweep due' <<<"$OUT"

# The guard must see the legacy spellings digest migrates, or it is blind to the migration set.
mk_ledger_brain "$SB/L6"
# shellcheck disable=SC2016  # backticks are intentional literal page text
sed -i.bak 's|^Prevention: `follow-up`\. |Prevention: Open follow-up — |' "$SB/L6/lessons/sample-open-item.md" && rm -f "$SB/L6/lessons/sample-open-item.md.bak"
OUT="$(bash "$SRC/tools/brain-lint.sh" "$SB/L6" 2>&1)" || true
check "ledger: legacy Prevention spelling is still swept" \
  grep -qF 'follow-up sweep due' <<<"$OUT"

# A closed lesson that merely mentions a follow-up in prose is not an open item.
mk_ledger_brain "$SB/L7"
# shellcheck disable=SC2016  # backticks are intentional literal page text
sed -i.bak 's|^Prevention: `follow-up`\. .*|Prevention: `encoded`. The follow-up landed in the guard.|' "$SB/L7/lessons/sample-open-item.md" && rm -f "$SB/L7/lessons/sample-open-item.md.bak"
OUT="$(bash "$SRC/tools/brain-lint.sh" "$SB/L7" 2>&1)" || true
if grep -qF 'follow-up sweep due' <<<"$OUT"; then
  fail "ledger: closed lesson mentioning a follow-up is not flagged"
else
  ok "ledger: closed lesson mentioning a follow-up is not flagged"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
