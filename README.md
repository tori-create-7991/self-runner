# self-runner

Hardened GitHub Actions self-hosted runners in a dedicated [Colima](https://github.com/abiosoft/colima) VM on Apple Silicon Macs.

- **Lanes** – define one or more runner lanes in a config file (default: one `ci` lane).
- **No workflow edits to switch** – each lane has a repository variable holding its `runs-on` label; unset it and jobs fall back to GitHub-hosted runners.
- **Locked down by default** – outbound HTTPS only, no published ports, no Docker socket, no host mounts, no sudo, pinned base image and packages, checksum-verified runner, auto-update disabled.
- **Small** – POSIX `sh` CLI and a generated Compose file. No runtime beyond Docker/Colima and `gh`.

> Status: `0.2.0`, early. Supports macOS on Apple Silicon (ARM64) and repository-scoped runners only. Org-level runners, Linux hosts and ephemeral/JIT runners are not implemented.
> Lanes that need extra privileges (sudo, `NET_ADMIN`, `/dev/net/tun`, e.g. for a Tailscale-based deploy lane) are explicit per-lane opt-ins; see [docs/security.md](docs/security.md).

## Requirements

- macOS on Apple Silicon, [Colima](https://github.com/abiosoft/colima) and the Docker CLI with the Compose plugin
- [`gh`](https://cli.github.com/) authenticated with permission to manage the repository's runners and Actions variables

## Quick start

```sh
git clone https://github.com/tori-create-7991/self-runner && cd self-runner
ln -s "$PWD/bin/self-runner" /usr/local/bin/self-runner   # optional

colima start --profile self-runner --arch aarch64 --cpu 4 --memory 8
docker context use <your previous context>   # colima start switches the active context; see `docker context ls`
self-runner init                  # writes ./self-runner.conf; edit `repository=`
self-runner build

# Create a short-lived registration token in the repo's Settings > Actions > Runners.
# It is read from the prompt (or stdin / $RUNNER_REGISTRATION_TOKEN) and never lands in argv or a file.
self-runner configure ci
self-runner start
self-runner status                # online, idle, label present?
self-runner route ci on           # sets vars.SELF_RUNNER_LANE_CI
```

Use the lane in a workflow (see [`examples/workflow.yml`](examples/workflow.yml)):

```yaml
runs-on: ${{ vars.SELF_RUNNER_LANE_CI || 'ubuntu-24.04' }}
```

`self-runner route ci off` deletes the variable and jobs return to GitHub-hosted runners. If a routed lane is offline, GitHub leaves jobs queued; there is no automatic fallback.

## Configuration

`self-runner.conf` is `key=value` text (parsed, never sourced):

| key | default | meaning |
|---|---|---|
| `repository` | required | `owner/name` the runners register to |
| `scope` | `repo` | only `repo` is supported |
| `colima_profile` | `self-runner` | Colima profile; Docker context is `colima-<profile>` |
| `docker_context` | `colima-<profile>` | exact context every command must use |
| `image_tag` | required | immutable local release tag; never reuse or retag |
| `user` | `none` | `auto` (your `gh` login), a GitHub login, or `none`. See [Teams](#teams-one-runner-per-person) |
| `auto_route` | `false` | `true`: `start` points routing at you once online, `stop` releases it |
| `lanes` | required | comma/space separated lane names (`[a-z][a-z0-9-]*`) |
| `lane.<name>.label` | required | comma-separated labels jobs can target; the first is primary and is the value of the routing variable |
| `lane.<name>.cpus` / `.memory` / `.pids` | `2.0` / `3g` / `512` | container caps |
| `lane.<name>.sudo` | `false` | passwordless sudo for the `runner` user (builds a separate `<image_tag>-sudo` image) |
| `lane.<name>.cap_add` | none | comma-separated Linux capabilities, e.g. `NET_ADMIN` |
| `lane.<name>.devices` | none | comma-separated host device paths, e.g. `/dev/net/tun` |

Lane `ci` maps to variable `SELF_RUNNER_LANE_CI`; `build-x` maps to `SELF_RUNNER_LANE_BUILD_X`. Unknown keys are rejected.

## Teams: one runner per person

Set `user=auto` (or your login) and each person runs their own runner on their own Mac, identified by GitHub login:

- runner name `<login>--<lane>-1`; labels are the lane labels plus a personal one, `<first label>--<login>` (`--` cannot occur in a GitHub login, so two people can never collide)
- the routing variable `SELF_RUNNER_LANE_<NAME>` is an **on-duty pointer**: whoever last ran `self-runner route <lane> on` receives all new jobs of that lane. Workflows stay `runs-on: ${{ vars.SELF_RUNNER_LANE_CI || 'ubuntu-24.04' }}`.

```sh
self-runner route ci on            # take duty (refused if someone else holds it)
self-runner route ci on --take     # switch duty to you
self-runner route ci off           # release; only deletes routing you hold
self-runner route ci off --force   # clear routing held by anyone (stale or departed holder); proceeds, with a warning, even if the variable cannot be read
self-runner status                 # also prints who holds routing, and flags an offline holder
```

With `auto_route=true`, `self-runner start` takes duty once your runner is online (exit status 1 if it could not) and `stop` releases routing first, waits up to about a minute for the lane to drain, then stops (it aborts if routing cannot be released or the lane is still busy; `--force` stops anyway; a lane that is not running is stopped without waiting). `stop` waits the same way without `auto_route`. Jobs already queued keep the label they were created with, so the previous holder should stay up until `status` shows idle.

Failures reading the routing variable are never treated as "unset": `route on`/`off` stop and `status` prints `routing unknown`.

**Permissions.** Registering a runner needs a repository registration token (repo admin), and `route` writes repository variables (write/admin access to Actions variables). Each team member needs both on the repository.

**Changing `user`.** The runner name and labels are fixed at registration. After switching `user` (including `none` ↔ a login, or an `auto` login that changed after a rename), `start`/`status` report a name mismatch: `route <lane> off`, `stop`, delete the old runner in *Settings → Actions → Runners*, remove the lane's config volume, then `configure` again. `user=auto` asks `gh` for the login on every command; after registering, pin it with `user=<login>` for unattended use.

**Leaving the team.** Release or clear routing (`route <lane> off --force`), delete the person's runners in *Settings → Actions → Runners*, remove their volumes on their Mac, then drop their repository access.

This is *not* per-trigger routing: the person on duty runs everyone's jobs, including pull-request code, so use it only inside a trusted team (see [docs/security.md](docs/security.md)). `user=none` keeps the single-runner behavior.

## Multiple repositories

Runners are registered per repository (`scope=repo`), so each additional repository needs its own registration token and its own `self-runner configure`. Keep one config per repository and select it with `--config FILE` or `SELF_RUNNER_CONFIG`. Give each config a distinct `colima_profile` (or run them in separate directories with distinct lane names) so containers and volumes do not collide. Organization-level runners, which register once for every repository in an org, are not implemented yet.

## Commands

`init`, `render`, `build`, `configure <lane>`, `start [lane]`, `status [lane]`, `stop [--force] <lane>`, `route <lane> on|off [--take]`, `version`, `help`. Use `--config FILE` or `SELF_RUNNER_CONFIG` to pick another config.

- `status` requires the container, `Runner.Listener`, local identity and GitHub state (online, idle, label) to agree.
- `stop` and `route on` require the lane to be online and idle; `stop --force` is for incident recovery only.
- Every docker call uses `docker --context <configured context>`, so credentials are never registered in an unrelated VM.

## Security model

See [docs/security.md](docs/security.md). In short: self-hosted runners must never run untrusted pull-request code; repository write access, workflow review and GitHub Environments remain your security boundary.

## Development

```sh
make test   # shellcheck, shfmt, bats (docker/gh are stubbed)
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
