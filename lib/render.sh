# shellcheck shell=sh
# Render the Compose model from the validated config. Lane capabilities are
# fixed: no published ports, no Docker socket, no host mounts. sudo, extra
# capabilities and devices are explicit per-lane opt-ins.

# no-new-privileges would break sudo, so it is applied only to non-sudo lanes.
lane_security_opt() {
  [ "$(lane_sudo "$1")" = true ] || printf '    security_opt:\n      - no-new-privileges:true\n'
}

lane_caps() {
  _caps=$(lane_list "$1" cap_add)
  [ -z "$_caps" ] || {
    printf '    cap_add:\n'
    for _c in $_caps; do printf '      - %s\n' "$_c"; done
  }
}

lane_devices() {
  _devs=$(lane_list "$1" devices)
  [ -z "$_devs" ] || {
    printf '    devices:\n'
    for _d in $_devs; do printf '      - %s:%s\n' "$_d" "$_d"; done
  }
}

render_compose() {
  printf 'name: self-runner\nservices:\n'
  for _l in $SR_LANES; do
    cat <<YAML
  runner-$_l:
    build:
      context: $SR_ROOT/image
      args:
        TARGETARCH: arm64
        RUNNER_ALLOW_SUDO: "$(lane_sudo "$_l")"
    image: $(lane_image "$_l")
    pull_policy: never
    command: run
    init: true
    restart: unless-stopped
YAML
    # Called directly, not via $(...), which would strip the trailing newline.
    lane_security_opt "$_l"
    lane_caps "$_l"
    lane_devices "$_l"
    cat <<YAML
    cpus: "$(cfg_get "lane.$_l.cpus" 2.0)"
    mem_limit: $(cfg_get "lane.$_l.memory" 3g)
    pids_limit: $(cfg_get "lane.$_l.pids" 512)
    environment:
      RUNNER_NAME: $_l-1
      RUNNER_LABEL: $(lane_label "$_l")
    volumes:
      - $_l-config:/runner
      - $_l-work:/runner/_work
    networks:
      - $_l-egress
YAML
  done
  printf 'volumes:\n'
  for _l in $SR_LANES; do
    printf '  %s-config:\n  %s-work:\n' "$_l" "$_l"
  done
  printf 'networks:\n'
  for _l in $SR_LANES; do
    printf '  %s-egress:\n' "$_l"
  done
}
