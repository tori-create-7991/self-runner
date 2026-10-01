# Security notes

## What the defaults do

| Control | Where |
|---|---|
| Outbound HTTPS only; no published ports, no host network | rendered `compose.yml` |
| No Docker socket, no host bind mounts | rendered `compose.yml` |
| No sudo, `no-new-privileges`, non-root `runner` user (default lane) | `image/Dockerfile`, compose |
| CPU / memory / PID caps per lane | `lane.<name>.*` |
| Per-lane config volume, work volume and network | rendered `compose.yml` |
| Base image digest and apt snapshot pinned; snapshot `InRelease` files SHA-256 pinned | `image/Dockerfile` |
| Runner archive checksum verified; runner auto-update disabled | `image/Dockerfile`, entrypoint |
| `pull_policy: never`: only the reviewed local build runs | rendered `compose.yml` |
| Registration token via env/prompt/stdin only | `self-runner configure` |
| Exact Docker context on every call | CLI |

## Privileged lanes (opt-in)

`lane.<name>.sudo=true`, `cap_add` and `devices` widen one lane only; the default lane never receives them. A sudo lane uses its own `<image_tag>-sudo` image and does not get `no-new-privileges` (it would break sudo). `self-runner start` verifies each lane's boundary: non-sudo lanes must fail `sudo -n true`, sudo lanes must pass it. Give a privileged lane only to protected, trusted workflows and never to `pull_request` jobs from untrusted code: sudo inside the container plus `NET_ADMIN` makes a job able to reconfigure networking and read anything the lane can reach. Use separate lanes per trust level.

## Team (on-duty) routing

With `user=` set, the routing variable names the runner on duty and that person's Mac runs every job of the lane, whoever triggered it. Consequences:

- A teammate's pull-request code runs on the on-duty person's Mac. Use this only among people who already trust each other with that machine, and keep credentials off it.
- Labels are not authentication. Anyone who can change a workflow can target a personal label such as `self-runner-ci-alice`; for forks, require approval for outside collaborators and keep `pull_request` workflows from untrusted forks off self-hosted labels (for example guard with `github.event.pull_request.head.repo.fork == false`).
- Routing is last-writer-wins. `route on` refuses to displace another holder without `--take`, and `route off` only releases routing you hold, but the compare-then-write is not atomic.
- If the on-duty runner goes offline, new jobs queue until someone takes duty or releases routing.

## What it does not do

- It does not make untrusted code safe. Do not route `pull_request` jobs from forks or untrusted contributors to a lane.
- A long-lived lane is not an ephemeral boundary: a compromised job can persist into later jobs on that lane. Keep credentialed workflows off shared lanes or use separate lanes per trust level.
- Jobs needing Docker cannot run here (no socket). Add that only with a separate reviewed design.
- Named volumes have no quota; monitor Colima disk usage.

## Updating the image

Bump `RUNNER_VERSION`, `RUNNER_SHA256`, the Ubuntu digest and snapshot together, choose a **new** `image_tag`, `self-runner build`, `self-runner route <lane> off`, `self-runner stop <lane>`, `self-runner start`. Keep the previous image so you can roll back by restoring the previous `image_tag`.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository rather than a public issue.
