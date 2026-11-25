# Development

## Prerequisites

- Crystal `>= 1.19.1` (the local toolchain is 1.22.x)
- `shards`
- `ameba` (`shards install` installs it as a development dependency)
- Optional, only for parity inventory work: Ruby 3+, Python 3, and the
  cross-language-crystal-parity skill with its Chiasmus tree-sitter toolchain

```bash
make install   # shards install
make test      # crystal spec
```

## Repository structure

See [architecture.md](architecture.md) for the module map and snapshot
lifecycle. In short: `src/golden.cr` is the library, `src/golden/cli.cr` the
command dispatcher, `src/golden/review.cr` the TUI, `src/golden_cli.cr` the
binary entry point.

## Upstream source of truth

| Upstream | Path | Pin | Role |
| --- | --- | --- | --- |
| [`mitsuhiko/insta`](https://github.com/mitsuhiko/insta) (Rust) | `vendor/insta` | `1.48.0` @ `3d62572f910cd19eba45673b37ad91293d82b689` | parity contract |
| [`marcoroth/insta-ruby`](https://github.com/marcoroth/insta-ruby) (Ruby) | `vendor/insta-ruby` | `v0.3.0` @ `500434be4370d68bc9bb224f25c541dde7b59df9` | secondary reference |

Both are git submodules. `.gitmodules` also declares `vendor/x` (Charm's Go
`x`), which is not checked out and is not part of parity work.

Refresh deliberately, never incidentally:

```bash
git -C vendor/insta fetch --tags
git -C vendor/insta checkout <tag-or-sha>
git add vendor/insta
```

After a bump:

1. update the pin table above, `AGENTS.md`, and `docs/resuming.md`;
2. re-base the parity ledger (`plans/inventory/*`) instead of appending rows;
3. record the old→new release notes in `plans/inventory/v<NN>_delta_triage.tsv`;
4. run `make inventory` and refresh the **Where we are** block in
   `plans/parity.md`.

## Day-to-day workflow

1. Pick the next feature from `plans/parity.md`.
2. Read the upstream module under `vendor/insta` and its nearest tests.
3. Add or port a failing spec in `spec/` first.
4. Implement the smallest change that turns it green.
5. Run `make format`, `make lint`, `make test`.
6. Update the plan and inventory, commit atomically with a `port: ...` message.

Full checklist: [resuming.md](resuming.md). Commit and review rules:
[pr-workflow.md](pr-workflow.md).

## Configuration for consumers

Projects using the shard can create `.golden.yml` in their root:

```yaml
update_mode: "auto"
dir: "spec/testdata"
filters:
  - pattern: "\\d{4}-\\d{2}-\\d{2}"
    replacement: "[DATE]"
redactions:
  - pattern: "token=\\w+"
    replacement: "token=REDACTED"
```

`Golden.init` loads `GOLDEN_UPDATE` and auto-discovers the config file; see the
[README](../README.md) for the full public API.

## Environment variables

| Variable | Effect |
| --- | --- |
| `GOLDEN_UPDATE=1` | force update mode (writes `.golden` files) |
| `GOLDEN_FORCE_PASS=1` | write `.golden.new` on new snapshots instead of failing |
| `CI=true` / `TF_BUILD` | `Auto` mode compares strictly |
| `PORT_PARSER` | parser mode for `make inventory` (default `tree-sitter`) |
| `PARITY_SKILL_DIR` | overrides the installed parity skill path |

## Parity inventory

`plans/inventory/` is empty as of this setup. `make inventory` invokes the
canonical `check_port_inventory.sh` from the installed
cross-language-crystal-parity skill for every ledger that exists and fails with
instructions when none does. Bootstrapping the Rust (and optionally Ruby)
ledger is tracked as the first next-up item in `plans/parity.md`.

## Known gaps

- Inline snapshots (`plans/parity.md` Phase 4.1) are unimplemented.
- `shard.yml` still advertises `0.2.0` while `CHANGELOG.md` and the README
  describe `0.3.0`; bump both when preparing the next release.
