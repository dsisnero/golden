PARITY_SKILL_DIR ?= $(HOME)/.agents/skills/crystal_forge/skills/cross-language-crystal-parity
PARITY_PARSER ?= tree-sitter
# Scope is relative to vendor/insta and must match the ledger baseline.
PARITY_SCOPE_RUST ?= insta/src,insta/tests

.PHONY: install update format format-check lint test test-examples inventory inventory-refresh test-review clean

install:
	shards install

update:
	shards update

format:
	crystal tool format src spec examples

format-check:
	crystal tool format --check src spec examples

lint:
	ameba src spec examples

test:
	crystal spec

test-examples:
	crystal spec examples

# Check the curated ledger and the generated manifests against the pinned
# vendor tree. The canonical scripts live in the installed
# cross-language-crystal-parity skill; do not copy them into this repo.
inventory:
	@test -f plans/inventory/rust_port_inventory.tsv || { \
	  echo "Missing plans/inventory/rust_port_inventory.tsv."; \
	  echo "Bootstrap it with the cross-language-crystal-parity skill."; \
	  exit 1; \
	}
	PORT_PARSER=$(PARITY_PARSER) PORT_SCOPE_INCLUDE=$(PARITY_SCOPE_RUST) "$(PARITY_SKILL_DIR)/scripts/check_port_inventory.sh" . plans/inventory/rust_port_inventory.tsv vendor/insta rust
	PORT_PARSER=$(PARITY_PARSER) PORT_SCOPE_INCLUDE=$(PARITY_SCOPE_RUST) "$(PARITY_SKILL_DIR)/scripts/check_source_parity.sh" . plans/inventory/rust_source_parity.tsv vendor/insta rust
	PORT_PARSER=$(PARITY_PARSER) PORT_SCOPE_INCLUDE=$(PARITY_SCOPE_RUST) "$(PARITY_SKILL_DIR)/scripts/check_test_parity.sh" . plans/inventory/rust_test_parity.tsv vendor/insta rust

# Refresh only the generated reference manifests; never overwrites the
# curated rust_port_inventory.tsv.
inventory-refresh:
	PORT_PARSER=$(PARITY_PARSER) "$(PARITY_SKILL_DIR)/scripts/ensure_parity_plan.sh" . vendor/insta rust $(PARITY_PARSER) 1 "$(PARITY_SCOPE_RUST)"

test-review:
	crystal spec && golden review

clean:
	rm -rf ./temp/* .crystal-cache ./bin/golden
	find . -name '._*' -not -path './.git/*' -delete
