# Contributing

Thanks for helping. This is a small POSIX `sh` project; keep changes focused.

## Setup

```sh
brew install shellcheck shfmt bats-core
make test
```

`make test` runs `shellcheck`, `shfmt -d -i 2 -ci` and the bats suite. `docker` and `gh` are stubbed in tests (see `tests/helpers.bash`), so no Colima VM is needed.

## Guidelines

- POSIX `sh` only (no bashisms) in `bin/`, `lib/` and `image/entrypoint.sh`.
- Add a bats test for every behavior change; test names are English sentences describing behavior.
- Do not weaken the defaults in `docs/security.md` without discussing it in an issue first.
- Secrets never go in argv, files, logs or Git.
- Changes to `image/Dockerfile` must keep the digest/snapshot/checksum pins and use a new `image_tag` in examples.
- Conventional Commit messages (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## Pull requests

Describe the behavior change (before → after), how you tested it, and any security impact.
