load helpers

setup() { setup_env; }
teardown() { teardown_env; }

@test "render writes a compose file next to the config" {
  run "$CLI" render
  [ "$status" -eq 0 ]
  [ -f .self-runner/compose.yml ]
}

@test "rendered lane has caps, per-lane volumes and network" {
  "$CLI" render
  run cat .self-runner/compose.yml
  [[ "$output" == *"runner-ci:"* ]]
  [[ "$output" == *'cpus: "2.0"'* ]]
  [[ "$output" == *"mem_limit: 3g"* ]]
  [[ "$output" == *"pids_limit: 512"* ]]
  [[ "$output" == *"RUNNER_NAME: ci-1"* ]]
  [[ "$output" == *"RUNNER_LABEL: self-runner-ci"* ]]
  [[ "$output" == *"ci-config:/runner"* ]]
  [[ "$output" == *"ci-work:/runner/_work"* ]]
  [[ "$output" == *"pull_policy: never"* ]]
  [[ "$output" == *"no-new-privileges:true"* ]]
}

@test "rendered compose never grants ports, sockets, host mounts or privileges" {
  "$CLI" render
  run grep -Ei 'ports:|docker\.sock|privileged|cap_add|devices:|network_mode|/Users|\.\./' .self-runner/compose.yml
  # only the build context path may match /Users; nothing else may
  [ -z "$(printf '%s\n' "$output" | grep -Ev 'context:')" ]
}

@test "lane overrides and multiple lanes render" {
  sed -i.bak 's#^lanes=.*#lanes=ci,build-x#' self-runner.conf
  printf 'lane.build-x.label=self-runner-build\nlane.build-x.cpus=1.5\nlane.build-x.memory=2g\nlane.build-x.pids=256\n' >>self-runner.conf
  "$CLI" render
  run cat .self-runner/compose.yml
  [[ "$output" == *"runner-build-x:"* ]]
  [[ "$output" == *'cpus: "1.5"'* ]]
  [[ "$output" == *"mem_limit: 2g"* ]]
  [[ "$output" == *"pids_limit: 256"* ]]
  [[ "$output" == *"RUNNER_NAME: build-x-1"* ]]
}

@test "rendered compose is valid for docker compose" {
  command -v docker >/dev/null || skip "docker not installed"
  PATH=${PATH#"$STUB_BIN":} # use the real docker
  docker compose version >/dev/null 2>&1 || skip "docker compose plugin missing"
  "$CLI" render
  run docker compose -f .self-runner/compose.yml config --quiet
  [ "$status" -eq 0 ]
}

deploy_lane() {
  sed -i.bak 's#^lanes=.*#lanes=ci,deploy#' self-runner.conf
  cat >>self-runner.conf <<'CONF'
lane.deploy.label=self-runner-deploy,my-mac
lane.deploy.sudo=true
lane.deploy.cap_add=NET_ADMIN
lane.deploy.devices=/dev/net/tun
CONF
}

@test "opt-in lane renders sudo image, capability, device and multiple labels" {
  deploy_lane
  "$CLI" render
  run cat .self-runner/compose.yml
  [[ "$output" == *'RUNNER_ALLOW_SUDO: "true"'* ]]
  [[ "$output" == *"image: self-runner:r1-sudo"* ]]
  [[ "$output" == *"- NET_ADMIN"* ]]
  [[ "$output" == *"- /dev/net/tun:/dev/net/tun"* ]]
  [[ "$output" == *"RUNNER_LABEL: self-runner-deploy,my-mac"* ]]
}

@test "opt-in privileges apply only to the lane that asks for them" {
  deploy_lane
  "$CLI" render
  run sed -n '/^  runner-ci:/,/^  runner-deploy:/p' .self-runner/compose.yml
  [[ "$output" != *"NET_ADMIN"* ]]
  [[ "$output" != *"/dev/net/tun"* ]]
  [[ "$output" == *"no-new-privileges:true"* ]]
  [[ "$output" == *"image: self-runner:r1"$'\n'* ]]
}

@test "sudo lane does not set no-new-privileges" {
  deploy_lane
  "$CLI" render
  run sed -n '/^  runner-deploy:/,/^volumes:/p' .self-runner/compose.yml
  [[ "$output" != *"no-new-privileges"* ]]
}

@test "opt-in compose is valid for docker compose" {
  command -v docker >/dev/null || skip "docker not installed"
  PATH=${PATH#"$STUB_BIN":}
  docker compose version >/dev/null 2>&1 || skip "docker compose plugin missing"
  deploy_lane
  "$CLI" render
  run docker compose -f .self-runner/compose.yml config --quiet
  [ "$status" -eq 0 ]
}

@test "invalid sudo, capability and device values are rejected" {
  printf 'lane.ci.sudo=yes\n' >>self-runner.conf
  run "$CLI" render
  [[ "$output" == *"sudo must be true or false"* ]]
  sed -i.bak '/^lane.ci.sudo/d' self-runner.conf
  printf 'lane.ci.cap_add=net_admin\n' >>self-runner.conf
  run "$CLI" render
  [[ "$output" == *"invalid capability"* ]]
  sed -i.bak '/^lane.ci.cap_add/d' self-runner.conf
  printf 'lane.ci.devices=../etc\n' >>self-runner.conf
  run "$CLI" render
  [[ "$output" == *"invalid device"* ]]
}
