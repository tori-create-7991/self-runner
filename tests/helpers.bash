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
  export STUB_STATE=$WORK/state
  mkdir -p "$STUB_STATE"
  export SR_WAIT_TRIES=1 SR_WAIT_SLEEP=0
  : >"$STUB_LOG"
  cat >"$STUB_BIN/docker" <<'STUB'
#!/bin/sh
printf 'docker %s\n' "$*" >>"$STUB_LOG"
printf 'TOKEN=%s\n' "${RUNNER_REGISTRATION_TOKEN:-}" >>"$STUB_ENVLOG"
case "$*" in
  *" info"*) [ -z "${STUB_DOCKER_DOWN:-}" ] || exit 1 ;;
  *"--services"*) [ -z "${STUB_RUNNING-1}" ] || echo "${STUB_SERVICE:-runner-ci}" ;;
  *" run "*"test -f"*) [ -z "${STUB_UNREGISTERED:-}" ] || exit 1 ;;
  *"jq -r"*) printf '%s\t%s\n' "${STUB_LOCAL_ID:-42}" "${STUB_LOCAL_NAME:-ci-1}" ;;
esac
exit 0
STUB
  cat >"$STUB_BIN/gh" <<'STUB'
#!/bin/sh
printf 'gh %s\n' "$*" >>"$STUB_LOG"
VF=$STUB_STATE/var
# The routing variable starts as $STUB_VAR (if set) and then follows set/delete.
init() {
  [ -e "$STUB_STATE/init" ] && return 0
  [ -z "${STUB_VAR+x}" ] || printf '%s\n' "$STUB_VAR" >"$VF"
  : >"$STUB_STATE/init"
}
case "$*" in
  "api user"*) printf '%s\n' "${STUB_GH_USER-Alice}" ;;
  "variable get"*)
    init
    if [ -n "${STUB_VAR_ERROR:-}" ]; then
      echo "HTTP 401: Bad credentials" >&2
      exit 1
    fi
    if [ -f "$VF" ]; then cat "$VF"; else
      if [ -n "${STUB_NOTFOUND_404:-}" ]; then echo "HTTP 404: Not Found" >&2; else echo "variable $3 was not found" >&2; fi
      exit 1
    fi
    ;;
  "variable set"*)
    init
    printf '%s\n' "$5" >"$VF"
    [ -z "${STUB_RACE:-}" ] || printf '%s\n' "$STUB_RACE" >"$VF"
    ;;
  "variable delete"*)
    init
    # Real gh exits non-zero when the variable does not exist.
    [ -f "$VF" ] || {
      echo "HTTP 404: Not Found" >&2
      exit 1
    }
    rm -f "$VF"
    ;;
  "api repos/octo/demo --jq"*)
    if [ -n "${STUB_REPO_404:-}" ]; then
      echo "HTTP 404: Not Found" >&2
      exit 1
    fi
    echo octo/demo
    ;;
  api*"| .status") printf '%s\n' "${STUB_HOLDER_STATUS-}" ;;
  api*) printf '%b\n' "${STUB_GH_REMOTE-42\tci-1\tonline\tfalse\tself-runner-ci}" ;;
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
