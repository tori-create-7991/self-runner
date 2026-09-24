# Shared bats helpers: an isolated config dir and stubbed docker/gh.
ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
CLI=$ROOT/bin/self-runner

setup_env() {
  WORK=$(mktemp -d)
  cd "$WORK"
  STUB_BIN=$WORK/stubs
  mkdir -p "$STUB_BIN"
  export STUB_LOG=$WORK/calls.log
  export STUB_ENVLOG=$WORK/env.log
  : >"$STUB_LOG"
  cat >"$STUB_BIN/docker" <<'STUB'
#!/bin/sh
printf 'docker %s\n' "$*" >>"$STUB_LOG"
printf 'TOKEN=%s\n' "${RUNNER_REGISTRATION_TOKEN:-}" >>"$STUB_ENVLOG"
case "$*" in
  *" info"*) [ -z "${STUB_DOCKER_DOWN:-}" ] || exit 1 ;;
  *"--services"*) [ -z "${STUB_RUNNING-1}" ] || echo "${STUB_SERVICE:-runner-ci}" ;;
  *"jq -r"*) printf '%s\t%s\n' "${STUB_LOCAL_ID:-42}" "${STUB_LOCAL_NAME:-ci-1}" ;;
  *" run "*"test -f"*) [ -z "${STUB_UNREGISTERED:-}" ] || exit 1 ;;
esac
exit 0
STUB
  cat >"$STUB_BIN/gh" <<'STUB'
#!/bin/sh
printf 'gh %s\n' "$*" >>"$STUB_LOG"
case "$1" in
  api) printf '%b\n' "${STUB_GH_REMOTE-42\tci-1\tonline\tfalse\ttrue}" ;;
esac
exit 0
STUB
  chmod +x "$STUB_BIN/docker" "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  write_conf
}

teardown_env() {
  cd /
  rm -rf "$WORK"
}

write_conf() {
  cat >"$WORK/self-runner.conf" <<'CONF'
repository=octo/demo
colima_profile=self-runner
image_tag=r1
lanes=ci
lane.ci.label=self-runner-ci
CONF
}
