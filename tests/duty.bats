load helpers

ROW_ME='42\talice--ci-1\tonline\tfalse\tself-runner-ci,self-runner-ci--alice'

setup() {
  setup_env
  printf 'user=alice\n' >>self-runner.conf
  export STUB_LOCAL_NAME=alice--ci-1
  export STUB_GH_REMOTE=$ROW_ME
}
teardown() { teardown_env; }

@test "explicit user names the runner and adds a personal label" {
  "$CLI" render
  run cat .self-runner/compose.yml
  [[ "$output" == *"RUNNER_NAME: alice--ci-1"* ]]
  [[ "$output" == *"RUNNER_LABEL: self-runner-ci,self-runner-ci--alice"* ]]
}

@test "user=auto resolves the login from gh and lowercases it" {
  sed -i.bak 's#^user=alice#user=auto#' self-runner.conf
  STUB_GH_USER=BobSmith run "$CLI" render
  [ "$status" -eq 0 ]
  grep -q 'RUNNER_NAME: bobsmith--ci-1' .self-runner/compose.yml
}

@test "user=auto fails clearly when gh cannot resolve a login" {
  sed -i.bak 's#^user=alice#user=auto#' self-runner.conf
  STUB_GH_USER= run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot resolve your GitHub login"* ]]
}

@test "user=auto rejects an unusable login before it reaches the compose file" {
  sed -i.bak 's#^user=alice#user=auto#' self-runner.conf
  STUB_GH_USER='a b: c' run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"unusable login"* ]]
  [ ! -e .self-runner/compose.yml ]
}

@test "invalid explicit users are rejected" {
  for bad in '-bad' 'bad-' 'a--b' 'has space' 'x/y'; do
    sed -i.bak "s#^user=.*#user=$bad#" self-runner.conf
    run "$CLI" render
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid user"* ]]
  done
}

@test "Enterprise Managed User logins with an underscore are accepted" {
  sed -i.bak 's#^user=.*#user=Alice_Corp#' self-runner.conf
  run "$CLI" render
  [ "$status" -eq 0 ]
  grep -q 'RUNNER_NAME: alice_corp--ci-1' .self-runner/compose.yml
}

@test "different login and lane pairs never share a runner name or label" {
  sed -i.bak 's#^lanes=.*#lanes=c,b-c#; s#^lane.ci.label=.*#lane.c.label=lab#' self-runner.conf
  printf 'lane.b-c.label=lab\n' >>self-runner.conf
  sed -i.bak 's#^user=.*#user=a-b#' self-runner.conf
  "$CLI" render
  names_ab=$(grep 'RUNNER_NAME' .self-runner/compose.yml)
  sed -i.bak 's#^user=.*#user=a#' self-runner.conf
  "$CLI" render
  names_a=$(grep 'RUNNER_NAME' .self-runner/compose.yml)
  [ "$names_ab" != "$names_a" ]
}

@test "multi-label, hyphenated lane and multi-lane renders keep personal labels per lane" {
  sed -i.bak 's#^lanes=.*#lanes=ci,build-x#; s#^lane.ci.label=.*#lane.ci.label=self-runner-ci,extra#' self-runner.conf
  printf 'lane.build-x.label=bx\n' >>self-runner.conf
  "$CLI" render
  run cat .self-runner/compose.yml
  [[ "$output" == *"RUNNER_LABEL: self-runner-ci,extra,self-runner-ci--alice"* ]]
  [[ "$output" == *"RUNNER_NAME: alice--build-x-1"* ]]
  [[ "$output" == *"RUNNER_LABEL: bx,bx--alice"* ]]
}

@test "without user the runner keeps the plain name and labels" {
  sed -i.bak '/^user=/d' self-runner.conf
  "$CLI" render
  grep -q 'RUNNER_NAME: ci-1' .self-runner/compose.yml
  grep -q 'RUNNER_LABEL: self-runner-ci$' .self-runner/compose.yml
}

@test "explicit user=none renders the plain name" {
  sed -i.bak 's#^user=.*#user=none#' self-runner.conf
  "$CLI" render
  grep -q 'RUNNER_NAME: ci-1' .self-runner/compose.yml
}

@test "status queries the personal runner name and requires the personal label" {
  run "$CLI" status ci
  [ "$status" -eq 0 ]
  grep -q 'select(.name == "alice--ci-1")' "$STUB_LOG"
  [[ "$output" == *"labels self-runner-ci self-runner-ci--alice present"* ]]
  [[ "$output" == *"ci: routing off"* ]]
}

@test "status fails when GitHub lacks the personal label" {
  STUB_GH_REMOTE='42\talice--ci-1\tonline\tfalse\tself-runner-ci' run "$CLI" status ci
  [ "$status" -ne 0 ]
  [[ "$output" == *"lacks label self-runner-ci--alice"* ]]
}

@test "status fails when the local runner was registered under the old name" {
  STUB_LOCAL_NAME=ci-1 run "$CLI" status ci
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match 'alice--ci-1'"* ]]
}

@test "start refuses a lane registered under a different name and says how to migrate" {
  STUB_UNREGISTERED=1 run "$CLI" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"registered as 'alice--ci-1'"* ]]
  [[ "$output" == *"remove the old runner"* ]]
  grep -q "agentName" "$STUB_LOG"
}

@test "status shows who holds routing" {
  STUB_VAR=self-runner-ci--bob STUB_HOLDER_STATUS=online run "$CLI" status ci
  [[ "$output" == *"ci: routing -> bob"* ]]
  [[ "$output" != *"queue"* ]]
  rm -rf "${STUB_STATE:?}"/*
  STUB_VAR=self-runner-ci--alice run "$CLI" status ci
  [[ "$output" == *"routing -> self-runner-ci--alice (you)"* ]]
}

@test "status flags a holder whose runner is offline" {
  STUB_VAR=self-runner-ci--bob STUB_HOLDER_STATUS=offline run "$CLI" status ci
  [[ "$output" == *"routing -> bob"* ]]
  [[ "$output" == *"runner offline"* ]]
  [[ "$output" == *"route ci off --force"* ]]
}

@test "status says routing is unknown instead of off when GitHub cannot be read" {
  STUB_VAR_ERROR=1 run "$CLI" status ci
  [[ "$output" == *"routing unknown"* ]]
  [[ "$output" != *"routing off"* ]]
}

@test "route on takes free routing with the personal label" {
  run "$CLI" route ci on
  [ "$status" -eq 0 ]
  grep -q 'variable set SELF_RUNNER_LANE_CI --body self-runner-ci--alice --repo octo/demo' "$STUB_LOG"
}

@test "route on refuses when another login holds routing" {
  STUB_VAR=self-runner-ci--bob run "$CLI" route ci on
  [ "$status" -ne 0 ]
  [[ "$output" == *"held by bob"* ]]
  [[ "$output" == *"--take"* ]]
  ! grep -q 'variable set' "$STUB_LOG"
}

@test "route on --take displaces the holder" {
  STUB_VAR=self-runner-ci--bob run "$CLI" route ci on --take
  [ "$status" -eq 0 ]
  grep -q 'variable set SELF_RUNNER_LANE_CI --body self-runner-ci--alice' "$STUB_LOG"
}

@test "route on --take also works when routing is unset" {
  run "$CLI" route ci on --take
  [ "$status" -eq 0 ]
  grep -q 'variable set SELF_RUNNER_LANE_CI --body self-runner-ci--alice' "$STUB_LOG"
}

@test "route on is idempotent when you already hold routing" {
  STUB_VAR=self-runner-ci--alice run "$CLI" route ci on
  [ "$status" -eq 0 ]
  grep -q 'variable set SELF_RUNNER_LANE_CI --body self-runner-ci--alice' "$STUB_LOG"
}

@test "route on reports a lost race when someone else writes in between" {
  STUB_RACE=self-runner-ci--bob run "$CLI" route ci on
  [ "$status" -ne 0 ]
  [[ "$output" == *"lost a race"* ]]
  [[ "$output" == *"bob"* ]]
}

@test "route on still requires an online idle runner" {
  STUB_GH_REMOTE='' run "$CLI" route ci on --take
  [ "$status" -ne 0 ]
  ! grep -q 'variable set' "$STUB_LOG"
}

@test "route on fails closed when the variable cannot be read" {
  STUB_VAR_ERROR=1 run "$CLI" route ci on
  [ "$status" -ne 0 ]
  [[ "$output" == *"state is unknown"* ]]
  ! grep -q 'variable set' "$STUB_LOG"
}

@test "route off deletes only routing you hold" {
  STUB_VAR=self-runner-ci--alice run "$CLI" route ci off
  [ "$status" -eq 0 ]
  grep -q 'variable delete SELF_RUNNER_LANE_CI' "$STUB_LOG"
}

@test "route off leaves another login's routing alone and points to --force" {
  STUB_VAR=self-runner-ci--bob run "$CLI" route ci off
  [ "$status" -eq 0 ]
  [[ "$output" == *"held by bob"* ]]
  [[ "$output" == *"--force"* ]]
  ! grep -q 'variable delete' "$STUB_LOG"
}

@test "route off --force clears routing held by someone else" {
  STUB_VAR=self-runner-ci--bob run "$CLI" route ci off --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"clearing routing held by bob"* ]]
  grep -q 'variable delete SELF_RUNNER_LANE_CI' "$STUB_LOG"
}

@test "route off --force works without any runner or docker" {
  STUB_DOCKER_DOWN=1 STUB_VAR=self-runner-ci--bob run "$CLI" route ci off --force
  [ "$status" -eq 0 ]
  grep -q 'variable delete' "$STUB_LOG"
}

@test "route off is a no-op when routing is already off" {
  run "$CLI" route ci off
  [ "$status" -eq 0 ]
  ! grep -q 'variable delete' "$STUB_LOG"
}

@test "route off fails closed when the variable cannot be read" {
  STUB_VAR_ERROR=1 run "$CLI" route ci off
  [ "$status" -ne 0 ]
  ! grep -q 'variable delete' "$STUB_LOG"
}

@test "route --take is only valid with on and --force only with off" {
  run "$CLI" route ci off --take
  [ "$status" -eq 2 ]
  run "$CLI" route ci on --force
  [ "$status" -eq 2 ]
}

@test "auto_route start takes routing after the lane is online" {
  printf 'auto_route=true\n' >>self-runner.conf
  run "$CLI" start
  [ "$status" -eq 0 ]
  grep -q 'up -d runner-ci' "$STUB_LOG"
  grep -q 'variable set SELF_RUNNER_LANE_CI --body self-runner-ci--alice' "$STUB_LOG"
}

@test "auto_route start exits non-zero and says so when another login holds routing" {
  printf 'auto_route=true\n' >>self-runner.conf
  STUB_VAR=self-runner-ci--bob run "$CLI" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"routing was not taken"* ]]
  grep -q 'up -d runner-ci' "$STUB_LOG"
  ! grep -q 'variable set' "$STUB_LOG"
}

@test "auto_route start exits non-zero when the lane does not come online" {
  printf 'auto_route=true\n' >>self-runner.conf
  STUB_GH_REMOTE='' run "$CLI" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not come online"* ]]
}

@test "auto_route stop releases routing before stopping" {
  printf 'auto_route=true\n' >>self-runner.conf
  STUB_VAR=self-runner-ci--alice run "$CLI" stop ci
  [ "$status" -eq 0 ]
  del=$(grep -n 'variable delete' "$STUB_LOG" | head -1 | cut -d: -f1)
  stp=$(grep -n 'stop runner-ci' "$STUB_LOG" | head -1 | cut -d: -f1)
  [ -n "$del" ] && [ -n "$stp" ] && [ "$del" -lt "$stp" ]
}

@test "auto_route stop aborts if routing cannot be released" {
  printf 'auto_route=true\n' >>self-runner.conf
  STUB_VAR_ERROR=1 run "$CLI" stop ci
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not release routing"* ]]
  ! grep -q 'stop runner-ci' "$STUB_LOG"
}

@test "auto_route stop --force still stops and warns when routing cannot be released" {
  printf 'auto_route=true\n' >>self-runner.conf
  STUB_VAR_ERROR=1 run "$CLI" stop --force ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"may still point at ci"* ]]
  grep -q 'stop runner-ci' "$STUB_LOG"
}

@test "auto_route stop releases routing even when the lane is busy, then refuses to stop" {
  printf 'auto_route=true\n' >>self-runner.conf
  STUB_VAR=self-runner-ci--alice STUB_GH_REMOTE='42\talice--ci-1\tonline\ttrue\tself-runner-ci,self-runner-ci--alice' run "$CLI" stop ci
  [ "$status" -ne 0 ]
  grep -q 'variable delete' "$STUB_LOG"
  ! grep -q 'stop runner-ci' "$STUB_LOG"
}

@test "stop without auto_route warns when routing still points at you" {
  STUB_VAR=self-runner-ci--alice run "$CLI" stop ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"routing still points at ci"* ]]
}

@test "invalid auto_route is rejected" {
  printf 'auto_route=maybe\n' >>self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"auto_route must be true or false"* ]]
}
