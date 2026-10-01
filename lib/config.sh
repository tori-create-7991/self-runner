# shellcheck shell=sh
# Config parsing and validation. The config is key=value text that is parsed,
# never sourced, so a config file cannot execute code.

sr_die() {
  printf 'self-runner: %s\n' "$*" >&2
  exit 1
}

sr_matches() {
  printf '%s\n' "$2" | grep -Eq "$1"
}

cfg_raw() {
  awk -v k="$1" '
    /^[[:space:]]*(#|$)/ { next }
    {
      i = index($0, "=")
      if (i == 0) next
      key = substr($0, 1, i - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == k) {
        v = substr($0, i + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        r = v
        f = 1
      }
    }
    END { if (f) print r; exit !f }
  ' "$SR_CONFIG"
}

# cfg_get KEY [DEFAULT]: an empty value counts as unset.
cfg_get() {
  if v=$(cfg_raw "$1") && [ -n "$v" ]; then
    printf '%s\n' "$v"
  else
    printf '%s\n' "${2:-}"
  fi
}

lane_var() {
  printf 'SELF_RUNNER_LANE_%s\n' "$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')"
}

# lane.<n>.label is a comma-separated list; the first label is primary and is
# the value written to the routing variable.
lane_label() {
  cfg_get "lane.$1.label"
}

lane_labels() {
  printf '%s\n' "$(lane_label "$1")" | tr ',' ' '
}

lane_primary_label() {
  lane_label "$1" | cut -d, -f1
}

# With a user, the runner is named <login>-<lane>-1 and also carries a personal
# label <primary>-<login>; that label is what the routing variable points at.
# "--" joins login and lane: a GitHub login cannot contain it, so two different
# (login, lane) pairs can never produce the same name or label.
runner_name_for() {
  printf '%s--%s-1\n' "$2" "$1"
}

lane_runner_name() {
  if [ -n "$SR_USER" ]; then
    runner_name_for "$1" "$SR_USER"
  else
    printf '%s-1\n' "$1"
  fi
}

lane_personal_label() {
  [ -z "$SR_USER" ] || printf '%s--%s\n' "$(lane_primary_label "$1")" "$SR_USER"
}

# Space-separated labels the runner registers with and status verifies.
lane_register_labels() {
  _p=$(lane_personal_label "$1")
  if [ -n "$_p" ]; then
    printf '%s %s\n' "$(lane_labels "$1")" "$_p"
  else
    lane_labels "$1"
  fi
}

# Value written to the routing variable when this user takes the lane.
lane_route_value() {
  if [ -n "$SR_USER" ]; then lane_personal_label "$1"; else lane_primary_label "$1"; fi
}

# Login that holds routing, derived from a personal label; empty if unknown.
lane_holder_of() {
  _pre="$(lane_primary_label "$1")--"
  case "$2" in
    "$_pre"?*)
      # The value is attacker-controlled (anyone who can write variables), and
      # the result is spliced into a jq filter: only a valid login is a holder.
      login_ok "${2#"$_pre"}" && printf '%s\n' "${2#"$_pre"}"
      ;;
  esac
}

# GitHub logins, plus "_" for Enterprise Managed Users; "--" is reserved as the separator.
login_ok() {
  sr_matches '^[A-Za-z0-9]([A-Za-z0-9_-]{0,37}[A-Za-z0-9])?$' "$1" || return 1
  case "$1" in *--*) return 1 ;; esac
}

lane_sudo() {
  cfg_get "lane.$1.sudo" false
}

lane_list() {
  printf '%s\n' "$(cfg_get "lane.$1.$2")" | tr ',' ' '
}

# Compose image tag: sudo lanes use a separate image built with sudo enabled.
lane_image() {
  if [ "$(lane_sudo "$1")" = true ]; then
    printf 'self-runner:%s-sudo\n' "$SR_IMAGE_TAG"
  else
    printf 'self-runner:%s\n' "$SR_IMAGE_TAG"
  fi
}

lane_known() {
  for _l in $SR_LANES; do
    [ "$_l" = "$1" ] && return 0
  done
  return 1
}

cfg_validate() {
  [ -f "$SR_CONFIG" ] || sr_die "config not found: $SR_CONFIG (run 'self-runner init')"

  SR_REPOSITORY=$(cfg_get repository)
  [ -n "$SR_REPOSITORY" ] || sr_die "repository is required (owner/name)"
  sr_matches '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' "$SR_REPOSITORY" ||
    sr_die "invalid repository '$SR_REPOSITORY' (expected owner/name)"

  scope=$(cfg_get scope repo)
  [ "$scope" = repo ] || sr_die "scope '$scope' is not supported yet (only 'repo')"

  SR_USER_SETTING=$(cfg_get user none)
  case "$SR_USER_SETTING" in
    none) SR_USER= ;;
    auto)
      command -v gh >/dev/null 2>&1 || sr_die "user=auto needs gh (or set user=<github-login>)"
      SR_USER=$(gh api user --jq .login 2>/dev/null | tr '[:upper:]' '[:lower:]')
      [ -n "$SR_USER" ] || sr_die "cannot resolve your GitHub login (run 'gh auth login' or set user=<github-login>)"
      login_ok "$SR_USER" || sr_die "gh returned an unusable login '$SR_USER'; set user=<github-login>"
      ;;
    *)
      login_ok "$SR_USER_SETTING" || sr_die "invalid user '$SR_USER_SETTING' (none, auto, or a GitHub login)"
      SR_USER=$(printf '%s' "$SR_USER_SETTING" | tr '[:upper:]' '[:lower:]')
      ;;
  esac
  SR_AUTO_ROUTE=$(cfg_get auto_route false)
  case "$SR_AUTO_ROUTE" in true | false) ;; *) sr_die "auto_route must be true or false" ;; esac

  SR_PROFILE=$(cfg_get colima_profile self-runner)
  sr_matches '^[a-z0-9][a-z0-9-]*$' "$SR_PROFILE" || sr_die "invalid colima_profile '$SR_PROFILE'"
  SR_CONTEXT=$(cfg_get docker_context "colima-$SR_PROFILE")
  sr_matches '^[A-Za-z0-9][A-Za-z0-9._-]*$' "$SR_CONTEXT" || sr_die "invalid docker_context '$SR_CONTEXT'"

  SR_IMAGE_TAG=$(cfg_get image_tag)
  [ -n "$SR_IMAGE_TAG" ] || sr_die "image_tag is required (use an immutable release tag)"
  sr_matches '^[A-Za-z0-9][A-Za-z0-9._-]*$' "$SR_IMAGE_TAG" || sr_die "invalid image_tag '$SR_IMAGE_TAG'"

  SR_LANES=$(printf '%s' "$(cfg_get lanes)" | tr ',' ' ')
  [ -n "$SR_LANES" ] || sr_die "lanes is required (e.g. lanes=ci)"
  seen=' '
  for _l in $SR_LANES; do
    sr_matches '^[a-z][a-z0-9-]*$' "$_l" || sr_die "invalid lane name '$_l' (use [a-z][a-z0-9-]*)"
    case "$seen" in *" $_l "*) sr_die "duplicate lane '$_l'" ;; esac
    seen="$seen$_l "
    [ -n "$(lane_label "$_l")" ] || sr_die "lane.$_l.label is required"
    for label in $(lane_labels "$_l"); do
      sr_matches '^[A-Za-z0-9][A-Za-z0-9._-]*$' "$label" || sr_die "invalid label '$label' for lane $_l"
    done
    case "$(lane_sudo "$_l")" in true | false) ;; *) sr_die "lane.$_l.sudo must be true or false" ;; esac
    for _c in $(lane_list "$_l" cap_add); do
      sr_matches '^[A-Z][A-Z_]*$' "$_c" || sr_die "invalid capability '$_c' in lane.$_l.cap_add"
    done
    for _d in $(lane_list "$_l" devices); do
      sr_matches '^/dev/[A-Za-z0-9/_.-]+$' "$_d" || sr_die "invalid device '$_d' in lane.$_l.devices"
    done
    sr_matches '^[0-9]+(\.[0-9]+)?$' "$(cfg_get "lane.$_l.cpus" 2.0)" || sr_die "invalid lane.$_l.cpus"
    sr_matches '^[0-9]+[mg]$' "$(cfg_get "lane.$_l.memory" 3g)" || sr_die "invalid lane.$_l.memory (e.g. 3g)"
    sr_matches '^[0-9]+$' "$(cfg_get "lane.$_l.pids" 512)" || sr_die "invalid lane.$_l.pids"
  done

  # Reject unknown keys so typos do not silently fall back to defaults.
  # shellcheck disable=SC2013 # keys are whitespace-stripped by awk
  for _k in $(awk '/^[[:space:]]*(#|$)/ { next } { i = index($0, "="); if (i) { k = substr($0, 1, i - 1); gsub(/[[:space:]]/, "", k); print k } }' "$SR_CONFIG"); do
    case "$_k" in
      repository | scope | colima_profile | docker_context | image_tag | lanes | user | auto_route) ;;
      lane.*.label | lane.*.cpus | lane.*.memory | lane.*.pids | lane.*.sudo | lane.*.cap_add | lane.*.devices)
        _n=${_k#lane.}
        _n=${_n%.*}
        lane_known "$_n" || sr_die "config key '$_k' refers to a lane not listed in lanes"
        ;;
      *) sr_die "unknown config key '$_k'" ;;
    esac
  done
}
