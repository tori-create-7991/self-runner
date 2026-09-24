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
