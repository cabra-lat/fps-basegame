# Merge procedure

The coordinator is the integration and merge owner. This is the queue, the
order, and the evidence bar. It exists because ad-hoc merging produced one
merged branch out of 27 while a green submodule pin was reported as progress.

## Order

Dependencies first, owner-visible second, infrastructure last. Never by size.

1. **Owner-visible features** — anything a person can see or click.
2. **Dependencies of those** — data, contracts, shared helpers.
3. **Harnesses and gates** — only after the code they test has landed.
4. **Investigations and reports** — only if they produced a fix worth keeping.

A branch is not a work item. A branch is a container someone happened to work
in, and several lanes share paths.

## The bar

Every merge records, before it happens:

- **exact repository and worktree** — `game:…` or `addon:…`, and the path
- **branch name and full SHA range** that will land
- **what the merge changes**, in product terms, not commit terms
- **what is excluded** and why
- **positive control**: the thing that was verified to exist before, which
  fails if the branch is wrong

A merge without a positive control is a merge on faith.

## Conflicts

**A conflict is not the coordinator's to resolve.** The lane that owns the path
resolves it. The coordinator reproduces it, names the paths, and hands it back.

Reason: resolving a conflict means choosing between two lanes' intent. That is
a product decision wearing a merge costume, and it is where provenance gets
laundered — a resolved file looks merged and records that someone chose.

Two lanes touching one path is a finding, not an obstacle. Report it.

## Rules

- **Never sweep.** Untracked files, `bin/`, and any file not on the branch do
  not enter a merge. If a working tree is dirty, the merge is the lane's, not
  the coordinator's.
- **Throwaway index for the game repo.** The worktree is shared and the index
  carries other lanes' staging. `GIT_INDEX_FILE`, `git read-tree <base>`, add
  only your paths, commit, then path-scoped `git reset`.
- **Verify the committed blob**, not the working tree. They differ.
- **Never force-push.** Preserve both sides and diagnose.
- **An unpushed branch is not merged.** It is stored. Say which it is.

## After every merge

- **Update the game repo's gitlink** to the new addon SHA, in the same change.
  A pin that disagrees with the checkout is the failure `submodule_pins` exists
  to catch, and a merge that does not move the pin recreates it immediately.
- **Push the addon, then the game repo.** A pointer to an unpushed SHA is a
  broken clone.
- **Re-run the gate** and report per-gate results, not a summary adjective.

## A green pin is not integration

`submodule_pins` compares a recorded SHA against a checkout. It says the
repository agrees with itself. It does not say the work landed — a repo can be
internally consistent while 27 branches sit unmerged. **Never report a green
pin as progress without the branch count beside it.**

## Before shipping anything

- Every branch listed, with owner and ahead/behind
- Conflicts surfaced, not resolved unilaterally
- Each lane's own merge, in order, by the coordinator queueing them
- The pin updated, pushed, and the gate re-run green
