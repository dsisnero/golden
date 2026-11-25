PARITY_SKILL_DIR ?= $(HOME)/.agents/skills/crystal_forge/skills/cross-language-crystal-parity
PARITY_PARSER ?= tree-sitter

.PHONY: install update format format-check lint test test-examples inventory test-review clean

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

# Check every parity ledger that exists against its pinned vendor tree.
# The canonical scripts live in the installed cross-language-crystal-parity
# skill; do not copy them into this repo.
inventory:
	@found=0; \
	for pair in rust:vendor/insta ruby:vendor/insta-ruby; do \
	  lang=$${pair%%:*}; src=$${pair#*:}; \
	  ledger=plans/inventory/$${lang}_port_inventory.tsv; \
	  if [ -f "$$ledger" ]; then \
	    found=1; \
	    echo "== $$lang ($$src)"; \
	    PORT_PARSER=$(PARITY_PARSER) "$(PARITY_SKILL_DIR)/scripts/check_port_inventory.sh" . "$$ledger" "$$src" "$$lang" || exit 1; \
	  fi; \
	done; \
	if [ $$found -eq 0 ]; then \
	  echo "No parity ledgers in plans/inventory yet."; \
	  echo "Bootstrap them with the cross-language-crystal-parity skill, then re-run make inventory."; \
	  exit 1; \
	fi

test-review:
	crystal spec && golden review

clean:
	rm -rf ./temp/* .crystal-cache ./bin/golden
	find . -name '._*' -not -path './.git/*' -delete
