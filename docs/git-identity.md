# Prevent private commit emails

The opt-in identity guard gives every local agent harness the same Git checks. It sets a
verified GitHub noreply default for one account's repositories and rejects unapproved author
or committer emails before ordinary commits, merge commits, and patch commits. It checks
outgoing commit metadata before push, including commits created with Git plumbing.

Account policy belongs in the private brain. The public tool contains no account identity.
Keep GitHub's private-email push protection enabled.

## Enroll an account

Verify the authenticated GitHub account with `gh api user --jq '{login,id,created_at}'`.
For accounts created after July 18, 2017, GitHub documents the noreply format as
`ID+USERNAME@users.noreply.github.com`. Verify older accounts' actual noreply address before
enrollment. This version supports the ID-based format only.

Review and publish a private `config/git-identity.json` file:

```json
{
  "version": 1,
  "github_login": "ExampleOwner",
  "github_id": 1234,
  "email": "1234+ExampleOwner@users.noreply.github.com",
  "allowed_author_emails": []
}
```

An additional author email is an explicit exception for legitimate imported attribution.
The guard never rewrites authors or commits. Review an exception before publishing it.
The committer must use the enrolled account's noreply email.

After the guard's reviewed software release is published, add
`"git_identity_policy": "config/git-identity.json"` to the existing per-user fleet updater
configuration. Run the configured session update check. If that check started with a version
of the updater that predates identity support, run the updated checker once more. Coverage is
established only when its `git_identity.status` is `current` and the repository doctor passes.
No scheduler is needed.

The updater reads policy from synchronized, published Prometheus Git objects and checks the
working copy against them. It installs deterministic files under the updater state directory's
`identity/` directory. It recognizes earlier published policy versions during upgrades and
preserves unknown local edits instead of replacing them. The hook launchers invoke the same
reviewed source checkout that the updater verifies. Fixed private permissions work under a
restrictive umask.

## Check the working repository

Run the doctor from the exact worktree and environment used for the commit:

```sh
python3 /path/to/reviewed/source/tools/git-identity.py doctor --state /path/to/updater-state/identity
```

`protected` confirms the managed hook directory is effective, installed files match the
policy, and current author and committer emails are approved. `out-of-scope` means the tool
found no remote owned by the enrolled account. It does not certify that repository's identity.
An unsafe identity or hook override returns a nonzero status.

Inspect identity precedence with `git config --show-origin --show-scope` for the specific
`user.email`, `author.email`, `committer.email`, and `core.hooksPath` keys. Git's effective
identity also includes `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_EMAIL`, `EMAIL`, `git -c`, and
`--author`. Avoid dumping unrelated Git configuration or credential-bearing environment values.
Hooks inspect `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` in the commit's own
environment, so an earlier successful doctor is not the only check.

The global Git configuration receives conditional includes for canonical and lowercase account
spellings with HTTPS, SCP-style SSH, and `ssh://git@github.com/` remotes. Unrelated Git identities
and repository settings are preserved. Existing local or worktree identity overrides still win
Git's precedence rules, but the hooks reject an unsafe result. Correct only a confirmed override
within the authorized repository. Add the intended remote before the first commit in a new repo.

Git's conditional includes match raw `remote.*.url` values, not `pushurl`. Mixed-case account
spellings, Git URL rewrites, and pushurl-only matches can therefore be in scope without activating
the include. The doctor reports those matches as unprotected. It does not resolve SSH host aliases;
an alias may report out-of-scope and still require account-specific protection. Use a canonical
remote URL or explicitly review an integration; do not interpret an absent hook as approval.

## Preserve project hooks

The shared directory forwards every documented Git hook to the repository's original executable
hook in its common Git directory. Arguments, working directory, output, exit status, and stdin
are preserved. Pre-push input is replayed after identity inspection. Linked worktrees use the
common hook directory.

Enrollment refuses competing hook managers visible in its current Git configuration, including
system and global settings. A conditional manager may become visible only in a target repository.
The doctor detects that conflict there, and commit/push hooks fail closed until explicit integration.
Other hooks still forward to the existing manager, preserving post-checkout and similar behavior.
Repository and worktree overrides are preserved and reported. Do not replace project hooks or
change `core.hooksPath` to `/dev/null` to pass a check.

## Inspect commits created outside ordinary Git commit commands

`prepare-commit-msg` also checks identity because Git still runs it with `--no-verify`.
Git plumbing, some replay operations, explicit hook overrides, and remote APIs can bypass
commit hooks. The pre-push check is the second local gate. It reads advertised refs from the actual
push destination with `git ls-remote`, then checks the commits being added. It excludes only the
old destination ref and destination history whose objects exist locally. Local remote-tracking
refs alone are not proof: fetch and push URLs can differ or change. This preserves other authors
on already-published branches merged into the candidate. A missing old destination object requires
a fetch. A failed destination read or a Git inspection exceeding 30 seconds blocks the push.
It does not rewrite or certify old history already on the server.

For a workflow that does not run local push hooks, inspect an exact candidate or range explicitly:

```sh
python3 /path/to/reviewed/source/tools/git-identity.py check-range --state /path/to/updater-state/identity FULL_BASE_SHA..FULL_HEAD_SHA
```

Set and verify author and committer fields before any remote commit-creation API call; local
hooks cannot intercept that call. Verify the returned metadata too. Deliberately disabled hooks,
replacement Git configuration, unregistered machines, and other Git implementations are not
enforced by this local guard. This is accident prevention, not protection from a hostile caller.

If GitHub reports GH007, preserve the rejected commits and diagnose the effective identity.
Changing configuration does not repair existing commit metadata. Any history rewrite or recovery
branch needs the owner's authorization for that operation.

## Verify changes

Run `python3 -B tests/test-git-identity.py` and `python3 -B tests/test-fleet-sync.py`.
The identity suite uses isolated homes, real commits, linked worktrees, and local bare remotes.
It covers identity precedence, retained authors, hook forwarding, unsafe plumbing commits,
policy updates, restrictive permissions, and preservation of unknown local edits.

References: [Git hooks](https://git-scm.com/docs/githooks),
[Git configuration](https://git-scm.com/docs/git-config), and
[GitHub email addresses](https://docs.github.com/en/account-and-profile/reference/email-addresses-reference).
