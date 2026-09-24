# Security notes

## What the defaults do

| Control | Where |
|---|---|
| Outbound HTTPS only; no published ports, no host network | rendered `compose.yml` |
| No Docker socket, no host bind mounts | rendered `compose.yml` |
| No sudo, `no-new-privileges`, non-root `runner` user | `image/Dockerfile`, compose |
| CPU / memory / PID caps per lane | `lane.<name>.*` |
| Per-lane config volume, work volume and network | rendered `compose.yml` |
| Base image digest and apt snapshot pinned; snapshot `InRelease` files SHA-256 pinned | `image/Dockerfile` |
| Runner archive checksum verified; runner auto-update disabled | `image/Dockerfile`, entrypoint |
| `pull_policy: never`: only the reviewed local build runs | rendered `compose.yml` |
| Registration token via env/prompt/stdin only | `self-runner configure` |
| Exact Docker context on every call | CLI |

## What it does not do

- It does not make untrusted code safe. Do not route `pull_request` jobs from forks or untrusted contributors to a lane.
- A long-lived lane is not an ephemeral boundary: a compromised job can persist into later jobs on that lane. Keep credentialed workflows off shared lanes or use separate lanes per trust level.
- Jobs needing Docker cannot run here (no socket). Add that only with a separate reviewed design.
- Named volumes have no quota; monitor Colima disk usage.

## Updating the image

Bump `RUNNER_VERSION`, `RUNNER_SHA256`, the Ubuntu digest and snapshot together, choose a **new** `image_tag`, `self-runner build`, `self-runner route <lane> off`, `self-runner stop <lane>`, `self-runner start`. Keep the previous image so you can roll back by restoring the previous `image_tag`.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository rather than a public issue.
