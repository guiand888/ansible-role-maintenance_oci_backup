.PHONY: help lint syntax check verify clean

help:
	@echo "make lint      - yamllint + ansible-lint (run inside the nix devShell)"
	@echo "make syntax    - --syntax-check tests/test.yml"
	@echo "make check     - --check --diff against localhost via tests/test.yml"
	@echo "make verify    - lint + syntax + check + pre-commit, in order"
	@echo "make clean     - remove nix/direnv/ansible runtime state"

lint:
	yamllint .
	ansible-lint

syntax:
	ansible-playbook -i tests/inventory tests/test.yml --syntax-check

check:
	ansible-playbook -i tests/inventory tests/test.yml --check --diff

verify: lint syntax check
	pre-commit run --all-files

clean:
	rm -rf .ansible .direnv
