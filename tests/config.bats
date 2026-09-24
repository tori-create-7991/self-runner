load helpers

setup() { setup_env; }
teardown() { teardown_env; }

@test "version prints the VERSION file" {
  run "$CLI" version
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$ROOT/VERSION")" ]
}

@test "help lists commands" {
  run "$CLI" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"route <lane> on|off"* ]]
}

@test "unknown command exits 2" {
  run "$CLI" bogus
  [ "$status" -eq 2 ]
}

@test "init writes an example config and refuses to overwrite" {
  rm self-runner.conf
  run "$CLI" init
  [ "$status" -eq 0 ]
  [ -f self-runner.conf ]
  run "$CLI" init
  [ "$status" -ne 0 ]
}

@test "missing config is reported" {
  rm self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"config not found"* ]]
}

@test "missing repository is rejected" {
  sed -i.bak '/^repository=/d' self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"repository is required"* ]]
}

@test "malformed repository is rejected" {
  sed -i.bak 's#^repository=.*#repository=not a repo#' self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid repository"* ]]
}

@test "org scope is rejected as unsupported" {
  printf 'scope=org\n' >>self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported yet"* ]]
}

@test "image_tag is required" {
  sed -i.bak '/^image_tag=/d' self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"image_tag is required"* ]]
}

@test "invalid lane name is rejected" {
  sed -i.bak 's#^lanes=.*#lanes=Bad_Lane#' self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid lane name"* ]]
}

@test "duplicate lanes are rejected" {
  sed -i.bak 's#^lanes=.*#lanes=ci,ci#' self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate lane"* ]]
}

@test "lane without a label is rejected" {
  sed -i.bak '/^lane.ci.label=/d' self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"lane.ci.label is required"* ]]
}

@test "unknown key is rejected as a likely typo" {
  printf 'lane.ci.cpu=2\n' >>self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown config key"* ]]
}

@test "key for a lane that is not listed is rejected" {
  printf 'lane.other.label=x\n' >>self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [[ "$output" == *"not listed in lanes"* ]]
}

@test "config is parsed, not sourced" {
  printf 'repository=octo/demo\n$(touch pwned)=1\n' >>self-runner.conf
  run "$CLI" render
  [ "$status" -ne 0 ]
  [ ! -e pwned ]
}
