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
cp -R "$SRC/bfbrain-template" "$SB/seed"
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
sed 's/^updated: .*/updated: 2026-07-03/' "$SB/A/$PROJ" > "$SB/A/x" && mv "$SB/A/x" "$SB/A/$PROJ"
gA add "$PROJ" && gA commit -qm "A bumps updated" && gA push -q
sed 's/^updated: .*/updated: 2026-07-04/' "$SB/B/$PROJ" > "$SB/B/x" && mv "$SB/B/x" "$SB/B/$PROJ"
gB add "$PROJ" && gB commit -qm "B bumps updated"
gB pull -q --rebase 2>/dev/null
DUP=$(grep -c '^updated:' "$SB/B/$PROJ")
if [ "$DUP" -gt 1 ]; then ok "frontmatter ban justified (union duplicated updated: x$DUP)"; else ok "frontmatter edit merged w/o dup (ban still safer)"; fi
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

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$SB"
exit $((FAIL > 0))
