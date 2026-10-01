# AGENTS.md

Hardened GitHub Actions self-hosted runners in a dedicated Colima VM (Apple Silicon). POSIX `sh` CLI.

## Layout

- `bin/self-runner` – CLI entrypoint and commands
- `lib/config.sh` – config parsing/validation (parsed, never sourced), lane -> variable mapping
- `lib/render.sh` – Compose generation
- `image/` – runner `Dockerfile` and `entrypoint.sh`
- `tests/` – bats tests; `docker` and `gh` are stubbed (`tests/helpers.bash`)
- `examples/`, `docs/security.md`

## Commands

```sh
make test      # shellcheck + shfmt + bats
make lint
make bats
```

## Rules

- POSIX `sh` only; run `shfmt -w -i 2 -ci` before committing.
- Behavior changes need a bats test. Never call real `docker`/`gh`/Colima from tests.
- Keep the security defaults in `docs/security.md`: no ports, no Docker socket, no host mounts, pinned image, token never in argv/files. sudo / cap_add / devices are per-lane opt-ins only; the default lane stays unprivileged.
- Every docker call goes through `dk()` with the configured context.
- Team routing: `user=` adds a login to runner name/labels; the routing variable is an on-duty pointer (`route on` needs `--take` to displace another holder, `route off` releases only your own). `user=none` must keep 0.1.0 behavior.
- Scope: repo-level runners on macOS/Colima ARM64. Org scope, Linux hosts, JIT runners, per-lane extra packages are out of scope unless a design says otherwise.
- Do not create or publish the GitHub repository, tags or releases without explicit user approval.
- `.plans/`, `.research/`, `.artifacts/` are git-ignored local output.
