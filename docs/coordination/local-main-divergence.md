# Local `main` divergence from `origin/main`

**Status:** investigation note only. No ref, index, or working-tree mutation was
performed. This note is written in a separate verifier worktree; the shared
main checkout was not touched.

## Observed state (2026-09-25)

Commands were read-only (`git branch -vv`, `git rev-parse`, `git merge-base`,
`git log`, `git diff`, `git show`, and `git status`).

```
main        22d476d7e83f5ff8275ac5c93f72e2564e5c69fa
origin/main d52e3e770fadb0870497d281f746bf3660a78ea5
merge-base  f6d4a173e7ad3c31f302fced923da46380330bc1
ahead/behind (main...origin/main): 1 / 110
```

`git log --oneline origin/main..main` contains exactly one commit:

```
22d476d docs: update agent coordination policy
```

That commit is not literally an ancestor of `origin/main`
(`git merge-base --is-ancestor main origin/main` returns 1), but it contributes
no unique patch:

- `git show 22d476d --format=''` and `git show d00d9fc --format=''` are
  byte-identical (`cmp` returns success).
- `d00d9fc` ("docs: update agent coordination policy") is already in
  `origin/main`.
- `git log --left-right --cherry-pick main...origin/main` has zero `<` entries.

The main-only commit is not limited to `.opencode/agents/*.md`: its stat also
includes `AGENTS.md` (13 files total). This is a correction to the earlier
summary, not a new finding; it does not change the identical-patch conclusion.

The trees of `22d476d` and `d00d9fc` differ in exactly three paths:

```
M project.godot
M tools/godot-lock.sh
M tools/verify-all.sh
```

Those differences come from later/intermediate history, not from the policy
patch: `e8e9f35` changed `project.godot`, and `5ba0439` changed the two
verification tools before `d00d9fc`. `git diff main origin/main` currently
reports 111 changed paths overall, consistent with the 110-commit divergence.

The shared main checkout is dirty and must not be treated as disposable. At
inspection time it reported 45 `git status --short` lines, 39 tracked modified
paths, 17 untracked paths, and 0 staged paths. Those uncommitted files are lane
work, not evidence about the committed ref. The coordinator worktree was also
observed at `e8e9f35`, roughly 100 commits behind `origin/main` at the time of
inspection, so edits made from that stale worktree are not based on current
main.

## Hazard

1. A lane that bases work on local `main` starts from a tree 110 commits stale;
   merging that lineage back can reintroduce dead content.
2. `git push` from this local `main` is non-fast-forward and is rejected by the
   repository ruleset, so the failure appears late rather than at the point of
   divergence.
3. Two commits with the same subject but different SHAs invite the duplicate
   commit/path-scope confusion seen in earlier lane incidents.
4. A stale coordinator worktree can produce edits against content that no
   longer exists on the current integration branch.

## Remedies (coordinator/user decision; none executed)

**(a) Leave the ref alone.** Rely on the ruleset and require every lane to fetch
and base work on an explicit `origin/main` SHA. Lowest immediate risk, but the
misleading local branch remains.

**(b) Move only the ref:**
`git update-ref refs/heads/main origin/main`. This changes no working-tree or
index bytes, so dirty lane files survive. The index still records the old
commit, however, so status for other lanes reading that checkout can change
interpretation; coordinate before doing it.

**(c) Reconcile the checkout fully** only after the dirty files are safely
relocated: fast-forward/rebase local `main` to `origin/main` in a controlled
window. A hard reset would overwrite the 39 tracked dirty paths and risks losing
uncommitted lane work; a mixed reset changes the index and status semantics.
This needs explicit user approval and a preservation plan.

## Working conclusion

Resetting the **committed branch lineage** to `origin/main` would lose no unique
committed work: the sole main-only commit is patch-equivalent to `d00d9fc`,
already present in `origin/main`. That conclusion does **not** authorize a hard
reset of the dirty shared checkout. The uncommitted 39 tracked modifications and
17 untracked paths must be preserved independently of the ref decision.
