# golden

> **How to resume:** read `plans/parity.md` first and use its **Where we are**
> block (current focus + ordered "Next up"), then run `make lint` and
> `make test`. Details: [docs/resuming.md](docs/resuming.md). Do not re-derive
> state from git.

Crystal shard for golden-file (snapshot) testing. The parity contract is the
Rust [`insta`](https://github.com/mitsuhiko/insta) crate, vendored at
`vendor/insta` (release `1.48.0`, commit `3d62572`). The Ruby
[`insta-ruby`](https://github.com/marcoroth/insta-ruby) gem at
`vendor/insta-ruby` (release `v0.3.0`, commit `500434b`) is a secondary
reference. The original API inspiration was Charm's Go
[`x/exp/golden`](https://github.com/charmbracelet/x/tree/main/exp/golden),
which is not vendored.

## Commands

```bash
make install        # shards install
make update         # shards update
make format         # crystal tool format src spec examples
make format-check   # crystal tool format --check src spec examples
make lint           # ameba src spec examples
make test           # crystal spec
make test-examples  # crystal spec examples
make inventory      # parity ledger drift check against the pinned vendor trees
make test-review    # crystal spec && golden review
make clean          # remove temp/, .crystal-cache/, bin/golden, AppleDouble files
```

## Docs

- [Resuming work](docs/resuming.md)
- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Coding Guidelines](docs/coding-guidelines.md)
- [Testing](docs/testing.md)
- [PR Workflow](docs/pr-workflow.md)

## Principles

1. Upstream behavior is the source of truth; `vendor/insta` wins over local
   preference.
2. Port behavior, not style.
3. Port upstream tests early and never weaken assertions.
4. Track parity in `plans/parity.md` and `plans/inventory/`.
5. Commit one completed feature at a time.

## Parity tooling

The active cross-language parity skill is
`/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity`.
Run its current `scripts/` directly; `make inventory` invokes
`check_port_inventory.sh` from that directory and never a copied parity
implementation. Updating the installed skill does not update this repository.

The curated ledgers will use `tree-sitter` discovery vocabulary (`rust` for
`vendor/insta`, `ruby` for `vendor/insta-ruby`). Keep that mode for the regular
gate. Before relying on discovery, run:

```bash
PARITY_SKILL_DIR="/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity"
"${PARITY_SKILL_DIR}/scripts/verify_skill_install.sh" . rust tree-sitter
make inventory
```

Check `PARITY_DISCOVERY_BACKEND` in the gate output and `backend` in each
manifest's `.metadata.json`. A requested parser mode does not prove tree-sitter
ran.

Status: `plans/inventory/` is **not bootstrapped yet**, so `make inventory`
exits non-zero with instructions. Bootstrapping the ledgers with the
cross-language parity skill is the first **Next up** item in
`plans/parity.md`; until then the inventory gate is a known-red baseline.

## Issue tracking

Work is tracked as GitHub issues in `dsisnero/golden`. Use the CLI:

```bash
gh issue list                  # Find available work
gh issue view <number>         # View issue details
gh issue comment <number>      # Record progress
gh issue close <number>        # Complete work
```

## Session continuity (read this first)

`plans/parity.md` is the single source of truth for where we are. At the start
of every session:

1. Read `plans/parity.md` and use its **Where we are** block to find the
   current focus, the ordered "Next up" list, and per-area chunk status. Do not
   re-derive state from git history.
2. Skim `git log --oneline -10` and `git status` to confirm the working tree.
3. Confirm the **Parity tooling** commands still point at the installed skill
   scripts and the ledger's parser mode, then run `make lint`, `make test`, and
   `make inventory` before changes.

See [docs/resuming.md](docs/resuming.md) for the full resume checklist.

### Keeping `plans/parity.md` resumable

- `plans/parity.md` starts with a **Where we are** block (`Current focus`,
  `Next up`, chunk status by area). Keep it accurate after every feature.
- Work items are feature-sized (roughly one branch/commit). Per-symbol state
  lives in `plans/inventory/<language>_port_inventory.tsv`, not in the plan.
- The ledger is a **current-state** artifact of the pinned baseline (say so in
  its leading `# baseline=` comment). Re-base it when the target release
  changes; never append across versions. Per-release history belongs in
  `plans/inventory/v<NN>_delta_triage.tsv` — one file per release, never
  edited afterwards.
- If `plans/parity.md` grows too large, split it into `plans/<area>.md` files,
  link each from `plans/parity.md`, and mark each split file
  complete/in-progress plus the file being worked on next.

### Definition of done for every feature (required)

A feature is complete only when all of the following are true, and all of it
must be committed as **one** atomic commit before starting the next feature:

1. the API surface is implemented;
2. upstream tests (or equivalent characterization specs) exist and pass;
3. gates pass: `make lint`, `make test`, and `make inventory`;
4. parity inventory rows for the feature are updated
   (`plans/inventory/<language>_port_inventory.tsv`) and `make inventory`
   passes — it checks every row against the pinned tree *and* that each
   `crystal_refs` file still exists, which is the half that rots when this
   repository's own files move;
5. `plans/parity.md` status is updated and the **Where we are** block refreshed
   (current focus + next up);
6. any intentional divergence is documented (in `plans/parity.md` and/or the
   commit message).

### Commit message

Start with `port:` and a one-line feature name, then bullets for what changed,
then the upstream revision (`mitsuhiko/insta 1.48.0 (3d62572f910cd19eba45673b37ad91293d82b689)`,
plus `marcoroth/insta-ruby v0.3.0 (500434be4370d68bc9bb224f25c541dde7b59df9)`
when Ruby behavior is involved). Include new/changed files, divergences, and
the gate results so a new session can resume from the commit alone.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT
complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** — open a GitHub issue for anything that
   needs follow-up.

2. **Run quality gates** (if code changed) — tests, linters, builds.

3. **Update issue status** — close finished work, update in-progress items.

4. **PUSH TO REMOTE** — this is MANDATORY:

   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up** — clear stashes, prune remote branches.

6. **Verify** — all changes committed AND pushed.

7. **Hand off** — provide context for the next session.

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds.
- NEVER stop before pushing — that leaves work stranded locally.
- NEVER say "ready to push when you are" — YOU must push.
- If push fails, resolve and retry until it succeeds.
