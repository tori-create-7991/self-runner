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
- Identity is asserted, not verified. `user=<login>` is only a string (anyone can write `user=bob`); `user=auto` takes the login from `gh`. The "release only what you hold" rule is a cooperative guard, not access control, and anyone with write access to repository variables can set the pointer to any value.
- Labels are not authentication. Anyone who can change a workflow can put a personal label such as `self-runner-ci--alice` directly in `runs-on`. Keep every workflow that can run untrusted code off self-hosted labels: guard `pull_request` with `github.event.pull_request.head.repo.fork == false`, and do not use self-hosted labels in `pull_request_target`, `workflow_run` or `issue_comment` workflows that check out untrusted refs. Require approval for outside collaborators.
- The plain lane label stays registered on every personal runner, so a workflow using it can land on any teammate's Mac.
- The runner is persistent: one teammate's job can leave state in the shared `<lane>-work` volume for later jobs, and a job runs as the same user as the runner process, so it can read the runner credentials under `/runner`. Treat the on-duty Mac as shared between everyone who can trigger jobs.
- Routing is last-writer-wins. `route on` refuses to displace another holder without `--take`, and `route off` only releases routing you hold, but the compare-then-write is not atomic.
- If the on-duty runner goes offline (a sleeping Mac, a stopped VM, a departed teammate), new jobs queue. `status` flags an offline holder; recover with `route <lane> on --take` or `route <lane> off --force`. Keep an on-duty Mac awake (for example with `caffeinate`). Using personal devices for shared CI is a policy question for your organization.

## What it does not do

- It does not make untrusted code safe. Do not route `pull_request` jobs from forks or untrusted contributors to a lane.
- A long-lived lane is not an ephemeral boundary: a compromised job can persist into later jobs on that lane. Keep credentialed workflows off shared lanes or use separate lanes per trust level.
- Jobs needing Docker cannot run here (no socket). Add that only with a separate reviewed design.
- Named volumes have no quota; monitor Colima disk usage.

## Updating the image

Bump `RUNNER_VERSION`, `RUNNER_SHA256`, the Ubuntu digest and snapshot together, choose a **new** `image_tag`, `self-runner build`, `self-runner route <lane> off`, `self-runner stop <lane>`, `self-runner start`. Keep the previous image so you can roll back by restoring the previous `image_tag`.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository rather than a public issue.
