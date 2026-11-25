# Resuming Work

This is the first thing to read in a new session. It takes a few minutes to get
back to a known-good state.

## 1. Read where we are

- `plans/parity.md` — start at the **Where we are** block. It names the current
  focus, the ordered "Next up" list, per-area chunk status, and any scoping
  notes or gotchas, plus the last commit and current gate results. Do not
  re-derive state from git history.

- `plans/inventory/rust_port_inventory.tsv` — the per-symbol ledger (status +
  `crystal_refs`), keyed to the baseline in its own leading `# baseline=`
  comment and re-based when the target release changes; the per-release history
  is `plans/inventory/v<NN>_delta_triage.tsv`. Run `make inventory` before
  trusting it: it fails on a stale row and on a `crystal_refs` file that no
  longer exists. Use it to see what is left inside the current chunk:

  ```bash
  awk -F '\t' '!/^#/ && NF {print $3}' \
    plans/inventory/rust_port_inventory.tsv | sort | uniq -c
  ```

  The ledger baseline is `mitsuhiko/insta 1.48.0` scoped to `insta/src` and
  `insta/tests`. Current shape: 116 ported, 23 partial, 0 missing, 415 skipped.
  `skipped` rows are insta's content/serialization engine and cargo internals
  that Crystal replaces with stdlib or does not expose.

## 2. Confirm the working tree

```bash
git log --oneline -10
git status
```

The last commit should be the previous feature (`port: ...`), committed
atomically. If the tree is dirty, finish or stash before starting.

## 3. Confirm a clean baseline

```bash
make lint
make test
PARITY_SKILL_DIR="${HOME}/.agents/skills/crystal_forge/skills/cross-language-crystal-parity"
"${PARITY_SKILL_DIR}/scripts/verify_skill_install.sh" . rust tree-sitter
PORT_PARSER=tree-sitter make inventory
```

Lint and tests must pass before changing anything. Run the inventory gate and
compare any drift with the **Where we are** block; recorded upstream drift may
be the next feature to fix. Confirm the command uses the installed skill scripts
and that its reported backend matches the ledger policy in `AGENTS.md`; inspect
`.metadata.json` when regenerating manifests.

## 4. Pick the next feature

Take the first unchecked item in the **Next up** list (or the next `[ ]` item in
the current phase). For each feature:

1. Read the upstream source under `vendor/insta` and the nearest upstream
   tests. Use `vendor/insta-ruby` when the Ruby behavior differs and matters.
2. Port the tests first (red → green); never weaken assertions.
3. Satisfy the **Definition of done** in `AGENTS.md` (API, tests, gates,
   inventory rows, `plans/parity.md` status + **Where we are** refresh,
   divergences).
4. Commit atomically with the `port: ...` message format from `AGENTS.md`.

## If the plan is split

When `plans/parity.md` grows too large it is split into `plans/<area>.md`
files. In that case every split file is linked from `plans/parity.md`, and
`plans/parity.md` marks each file complete/in-progress and names the file being
worked on plus the next file/phase to start.

## Environment notes

This checkout lives on a non-APFS volume, so macOS writes AppleDouble `._*`
sidecars next to tracked files. A `._foo_spec.cr` sidecar can break test
discovery, so `make clean` strips them and `.gitignore` ignores them. If a git
pack operation prints `non-monotonic index .../._pack-*.idx`, delete the
sidecars with `find .git -name '._*' -delete`.

`vendor/` is real filesystem state for the two upstream submodules in
`.gitmodules`. `vendor/x` (Charm's Go `x`) is declared there but is not
checked out and is not needed for parity work.

The skill's adversarial signoff (`verify_parity_adversarial.sh`) is not usable
on this checkout yet: it runs all three manifest gates successfully, then its
completion gate calls `chiasmus-facts` over the whole Rust tree, which has
stalled for 45+ minutes here. Use `make inventory` plus `make test` as the
signoff until that is resolved.
