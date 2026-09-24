load helpers

setup() { setup_env; }
teardown() { teardown_env; }

@test "docker commands use the exact configured context" {
  run "$CLI" build
  [ "$status" -eq 0 ]
  grep -q '^docker --context colima-self-runner ' "$STUB_LOG"
  ! grep -v '^docker --context colima-self-runner ' "$STUB_LOG" | grep -q '^docker'
}

@test "docker_context override is honoured" {
  printf 'docker_context=custom-ctx\n' >>self-runner.conf
  run "$CLI" build
  [ "$status" -eq 0 ]
  grep -q '^docker --context custom-ctx ' "$STUB_LOG"
}

@test "unreachable context fails before touching compose" {
  STUB_DOCKER_DOWN=1 run "$CLI" build
  [ "$status" -ne 0 ]
  [[ "$output" == *"colima start --profile self-runner"* ]]
  ! grep -q 'compose' "$STUB_LOG"
}

@test "configure takes the token from the environment and keeps it out of argv" {
  RUNNER_REGISTRATION_TOKEN=SECRETTOKEN123 run "$CLI" configure ci
  [ "$status" -eq 0 ]
  ! grep -q SECRETTOKEN123 "$STUB_LOG"
  grep -q 'TOKEN=SECRETTOKEN123' "$STUB_ENVLOG"
  grep -q 'RUNNER_REPOSITORY_URL=https://github.com/octo/demo' "$STUB_LOG"
  grep -q 'runner-ci configure' "$STUB_LOG"
}

@test "configure reads the token from stdin when not a tty" {
  run sh -c "printf 'SECRETSTDIN\n' | '$CLI' configure ci"
  [ "$status" -eq 0 ]
  ! grep -q SECRETSTDIN "$STUB_LOG"
  grep -q 'TOKEN=SECRETSTDIN' "$STUB_ENVLOG"
}

@test "configure fails on an empty token" {
  run sh -c "printf '\n' | '$CLI' configure ci"
  [ "$status" -ne 0 ]
  [[ "$output" == *"token is empty"* ]]
}

@test "configure rejects an unknown lane" {
  RUNNER_REGISTRATION_TOKEN=x run "$CLI" configure nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown lane"* ]]
}

@test "start refuses an unregistered lane" {
  STUB_UNREGISTERED=1 run "$CLI" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"not registered"* ]]
  ! grep -q ' up ' "$STUB_LOG"
}

@test "start brings up registered lanes" {
  run "$CLI" start
  [ "$status" -eq 0 ]
  grep -q 'up -d runner-ci' "$STUB_LOG"
}

@test "status passes for an online idle labelled lane" {
  run "$CLI" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"ci: online, idle"* ]]
}

@test "status fails when the runner is busy" {
  STUB_GH_REMOTE='42\tci-1\tonline\ttrue\ttrue' run "$CLI" status ci
  [ "$status" -ne 0 ]
}

@test "status fails when the label is missing" {
  STUB_GH_REMOTE='42\tci-1\tonline\tfalse\tfalse' run "$CLI" status ci
  [ "$status" -ne 0 ]
}

@test "status fails when GitHub does not list the runner" {
  STUB_GH_REMOTE='' run "$CLI" status ci
  [ "$status" -ne 0 ]
}

@test "status fails when local and remote runner ids differ" {
  STUB_LOCAL_ID=7 run "$CLI" status ci
  [ "$status" -ne 0 ]
}

@test "status fails when the container is not running" {
  STUB_RUNNING= run "$CLI" status ci
  [ "$status" -ne 0 ]
  [[ "$output" == *"not running"* ]]
}

@test "stop refuses when the lane is not idle" {
  STUB_GH_REMOTE='42\tci-1\tonline\ttrue\ttrue' run "$CLI" stop ci
  [ "$status" -ne 0 ]
  ! grep -q ' stop ' "$STUB_LOG"
}

@test "stop stops an idle lane" {
  run "$CLI" stop ci
  [ "$status" -eq 0 ]
  grep -q 'stop runner-ci' "$STUB_LOG"
}

@test "stop --force skips the idle check" {
  STUB_GH_REMOTE='' run "$CLI" stop --force ci
  [ "$status" -eq 0 ]
  grep -q 'stop runner-ci' "$STUB_LOG"
  ! grep -q '^gh api' "$STUB_LOG"
}

@test "route on sets the lane variable to the label when the lane is idle" {
  run "$CLI" route ci on
  [ "$status" -eq 0 ]
  grep -q 'gh variable set SELF_RUNNER_LANE_CI --body self-runner-ci --repo octo/demo' "$STUB_LOG"
}

@test "route on is refused when the lane is not online and idle" {
  STUB_GH_REMOTE='' run "$CLI" route ci on
  [ "$status" -ne 0 ]
  ! grep -q 'variable set' "$STUB_LOG"
}

@test "route off deletes the variable without needing docker" {
  STUB_DOCKER_DOWN=1 run "$CLI" route ci off
  [ "$status" -eq 0 ]
  grep -q 'gh variable delete SELF_RUNNER_LANE_CI --repo octo/demo' "$STUB_LOG"
}

@test "lane names map to upper snake variables" {
  sed -i.bak 's#^lanes=.*#lanes=build-x#; s#^lane.ci.label=#lane.build-x.label=#' self-runner.conf
  STUB_DOCKER_DOWN=1 run "$CLI" route build-x off
  [ "$status" -eq 0 ]
  grep -q 'variable delete SELF_RUNNER_LANE_BUILD_X' "$STUB_LOG"
}
