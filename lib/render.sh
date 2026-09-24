# shellcheck shell=sh
# Render the Compose model from the validated config. Lane capabilities are
# fixed: no published ports, no Docker socket, no host mounts, no sudo.

render_compose() {
  printf 'name: self-runner\nservices:\n'
  for _l in $SR_LANES; do
    cat <<YAML
  runner-$_l:
    build:
      context: $SR_ROOT/image
      args:
        TARGETARCH: arm64
    image: self-runner:$SR_IMAGE_TAG
    pull_policy: never
    command: run
    init: true
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
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
