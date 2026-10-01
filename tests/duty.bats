load helpers

setup() {
  setup_env
  printf 'user=alice\n' >>self-runner.conf
  export STUB_LOCAL_NAME=alice-ci-1
  export STUB_GH_REMOTE='42\talice-ci-1\tonline\tfalse\ttrue'
}
teardown() { teardown_env; }

@test "explicit user names the runner and adds a personal label" {
  "$CLI" render
  run cat .self-runner/compose.yml
  [[ "$output" == *"RUNNER_NAME: alice-ci-1"* ]]
  [[ "$output" == *"RUNNER_LABEL: self-runner-ci,self-runner-ci-alice"* ]]
}

@test "user=auto resolves the login from gh and lowercases it" {
  sed -i.bak 's#^user=alice#user=auto#' self-runner.conf
  STUB_GH_USER=BobSmith run "$CLI" render
  [ "$status" -eq 0 ]
  grep -q 'RUNNER_NAME: bobsmith-ci-1' .self-runner/compose.yml
}

@test "user=auto fails clearly when gh cannot resolve a login" {
  sed -i.bak 's#^user=alice#user=auto#' self-runner.conf
  STUB_GH_USER= run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot resolve your GitHub login"* ]]
}

@test "invalid user is rejected" {
  sed -i.bak 's#^user=alice#user=-bad_name#' self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid user"* ]]
}

@test "without user the runner keeps the plain name and labels" {
  sed -i.bak '/^user=/d' self-runner.conf
  "$CLI" render
  grep -q 'RUNNER_NAME: ci-1' .self-runner/compose.yml
  grep -q 'RUNNER_LABEL: self-runner-ci$' .self-runner/compose.yml
}

@test "status verifies the personal label and shows routing off" {
  run "$CLI" status ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"labels self-runner-ci self-runner-ci-alice present"* ]]
  [[ "$output" == *"ci: routing off"* ]]
  [ "$(grep -c '^gh api repos' "$STUB_LOG")" -eq 2 ]
}

@test "status shows who holds routing" {
  STUB_VAR=self-runner-ci-bob run "$CLI" status ci
  [[ "$output" == *"ci: routing -> bob"* ]]
  STUB_VAR=self-runner-ci-alice run "$CLI" status ci
  [[ "$output" == *"routing -> self-runner-ci-alice (you)"* ]]
}

@test "route on takes free routing with the personal label" {
  run "$CLI" route ci on
  [ "$status" -eq 0 ]
  grep -q 'variable set SELF_RUNNER_LANE_CI --body self-runner-ci-alice --repo octo/demo' "$STUB_LOG"
}

@test "route on refuses when another login holds routing" {
  STUB_VAR=self-runner-ci-bob run "$CLI" route ci on
  [ "$status" -ne 0 ]
  [[ "$output" == *"held by bob"* ]]
  [[ "$output" == *"--take"* ]]
  ! grep -q 'variable set' "$STUB_LOG"
}

@test "route on --take displaces the holder" {
  STUB_VAR=self-runner-ci-bob run "$CLI" route ci on --take
  [ "$status" -eq 0 ]
  grep -q 'variable set SELF_RUNNER_LANE_CI --body self-runner-ci-alice' "$STUB_LOG"
}

@test "route on is idempotent when you already hold routing" {
  STUB_VAR=self-runner-ci-alice run "$CLI" route ci on
  [ "$status" -eq 0 ]
}

@test "route on still requires an online idle runner" {
  STUB_GH_REMOTE='' run "$CLI" route ci on --take
  [ "$status" -ne 0 ]
  ! grep -q 'variable set' "$STUB_LOG"
}

@test "route off deletes only routing you hold" {
  STUB_VAR=self-runner-ci-alice run "$CLI" route ci off
  [ "$status" -eq 0 ]
  grep -q 'variable delete SELF_RUNNER_LANE_CI' "$STUB_LOG"
}

@test "route off leaves another login's routing alone" {
  STUB_VAR=self-runner-ci-bob run "$CLI" route ci off
  [ "$status" -eq 0 ]
  [[ "$output" == *"held by bob"* ]]
  ! grep -q 'variable delete' "$STUB_LOG"
}

@test "route off is a no-op when routing is already off" {
  run "$CLI" route ci off
  [ "$status" -eq 0 ]
  ! grep -q 'variable delete' "$STUB_LOG"
}

@test "route --take is only valid with on" {
  run "$CLI" route ci off --take
  [ "$status" -eq 2 ]
}

@test "auto_route start takes routing after the lane is online" {
  printf 'auto_route=true\n' >>self-runner.conf
  run "$CLI" start
  [ "$status" -eq 0 ]
  grep -q 'up -d runner-ci' "$STUB_LOG"
  grep -q 'variable set SELF_RUNNER_LANE_CI --body self-runner-ci-alice' "$STUB_LOG"
}

@test "auto_route start keeps running but reports when another login holds routing" {
  printf 'auto_route=true\n' >>self-runner.conf
  STUB_VAR=self-runner-ci-bob run "$CLI" start
  [ "$status" -eq 0 ]
  [[ "$output" == *"routing was not taken"* ]]
  ! grep -q 'variable set' "$STUB_LOG"
}

@test "auto_route stop releases routing before stopping" {
  printf 'auto_route=true\n' >>self-runner.conf
  STUB_VAR=self-runner-ci-alice run "$CLI" stop ci
  [ "$status" -eq 0 ]
  del=$(grep -n 'variable delete' "$STUB_LOG" | head -1 | cut -d: -f1)
  stp=$(grep -n 'stop runner-ci' "$STUB_LOG" | head -1 | cut -d: -f1)
  [ -n "$del" ] && [ -n "$stp" ] && [ "$del" -lt "$stp" ]
}

@test "invalid auto_route is rejected" {
  printf 'auto_route=maybe\n' >>self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"auto_route must be true or false"* ]]
}
