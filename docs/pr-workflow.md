# PR Workflow

## Before you start

1. Run the resume checklist in [resuming.md](resuming.md).
2. Open or claim a GitHub issue (`gh issue list`, `gh issue view <number>`) or
   file one for anything you discover.
3. Pick the next unchecked item from `plans/parity.md`; one feature per branch.

## Branching

- Branch from an up-to-date `main`, name it after the feature:
  `port/inline-snapshot-design`, `fix/glob-empty-match`.
- Rebase rather than merge (`git pull --rebase`); the repository history stays
  linear and each `port:` commit is atomic.

## Commit format

```text
port: <feature name>

- what changed and why (API, behavior, files)
- upstream test/spec that pinned the behavior
- intentional divergence, if any
- gates: make lint => ok, make test => ok (N examples), make inventory => ok

mitsuhiko/insta 1.48.0 (3d62572f910cd19eba45673b37ad91293d82b689)
```

Include the `marcoroth/insta-ruby v0.3.0 (500434be4370d68bc9bb224f25c541dde7b59df9)`
line when Ruby behavior informed the change. Non-port work (scaffolding, CI,
dependency bumps) uses a conventional prefix (`chore:`, `fix:`, `docs:`) and
still lists the gates it ran.

## Required checks

| Gate | Command | Notes |
| --- | --- | --- |
| Format | `make format-check` | must be clean |
| Lint | `make lint` | zero Ameba failures |
| Tests | `make test` | all examples pass |
| Inventory | `make inventory` | red until `plans/inventory/` is bootstrapped |

Run the inventory gate when the change touches ported symbols; a failing gate
means the ledger and the vendor tree disagree, not that the tests are wrong.

## Definition of done

A PR is mergeable only when the feature satisfies the **Definition of done** in
`AGENTS.md`: API implemented, upstream-equivalent specs pass, all gates green,
inventory rows updated, `plans/parity.md` (including **Where we are**) refreshed,
and divergences documented.

## Review expectations

- Each `port:` commit should be reviewable on its own; do not mix a feature with
  unrelated refactors or dependency bumps.
- Reviewers compare behavior against `vendor/insta`, not style preferences.
- New public API needs a README entry and a CHANGELOG bullet.
- If a behavior is intentionally different from upstream, the PR description and
  `plans/parity.md` must both say why.

## After merge

```bash
git pull --rebase
git push
git status   # must report up to date with origin
```

Close the GitHub issue, refresh `plans/parity.md` if the next focus changed, and
record any follow-up work as a new issue rather than a TODO comment.
