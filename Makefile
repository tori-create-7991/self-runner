.PHONY: test lint shellcheck shfmt bats

test: lint bats

lint: shellcheck shfmt

shellcheck:
	shellcheck -x bin/self-runner lib/*.sh image/entrypoint.sh

shfmt:
	shfmt -d -i 2 -ci bin lib image

bats:
	bats tests
