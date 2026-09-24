#!/bin/sh
set -eu

distribution=${RUNNER_DISTRIBUTION_PATH:-/opt/actions-runner}
runtime=${RUNNER_RUNTIME_PATH:-/runner}
config_paths='.runner .runner_migrated .credentials .credentials_migrated .credentials_rsaparams .service .credential_store .certificates .options .setup_info .env .path'

required() {
  name=$1
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "$name must be set" >&2
    exit 1
  fi
}

seed_runtime() {
  stage=$(mktemp -d)
  backup=$runtime/_work/.runner-seed-backup
  backup_complete=$runtime/_work/.runner-seed-backup.complete
  restore_needed=false

  restore_backup() {
    find "$runtime" -mindepth 1 -maxdepth 1 ! -name _work -exec rm -rf -- {} +
    /bin/cp -Rp "$backup"/. "$runtime"/
  }

  cleanup_seed() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ "$restore_needed" = true ] && [ -d "$backup" ]; then
      if restore_backup; then
        restore_needed=false
      else
        status=1
      fi
    fi
    rm -rf "$stage"
    if [ "$restore_needed" = false ]; then
      rm -rf "$backup" "$backup_complete"
    fi
    exit "$status"
  }
  trap cleanup_seed EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # A hard-killed prior seed leaves its persistent rollback copy in _work.
  if [ -d "$backup" ] && [ -f "$backup_complete" ]; then
    restore_needed=true
    restore_backup
    restore_needed=false
  fi
  rm -rf "$backup" "$backup_complete"

  # Finish every fallible copy before replacing the current distribution.
  cp -R "$distribution"/. "$stage"/
  install -d "$backup"
  for path in "$runtime"/* "$runtime"/.[!.]* "$runtime"/..?*; do
    if { [ -e "$path" ] || [ -L "$path" ]; } && [ "$path" != "$runtime/_work" ]; then
      /bin/cp -Rp "$path" "$backup"/
    fi
  done
  : >"$backup_complete"

  restore_needed=true
  find "$runtime" -mindepth 1 -maxdepth 1 ! -name _work -exec rm -rf -- {} +
  cp -R "$stage"/. "$runtime"/
  for path in $config_paths; do
    if [ -e "$backup/$path" ]; then
      /bin/cp -Rp "$backup/$path" "$runtime/$path"
    fi
  done
  if [ -f "$backup/_diag/.telemetry" ]; then
    install -d "$runtime/_diag"
    /bin/cp -p "$backup/_diag/.telemetry" "$runtime/_diag/.telemetry"
  fi

  restore_needed=false
  rm -rf "$stage" "$backup" "$backup_complete"
  trap - EXIT HUP INT TERM
}

case "${1:-}" in
  configure)
    required RUNNER_REPOSITORY_URL
    required RUNNER_REGISTRATION_TOKEN
    required RUNNER_NAME
    required RUNNER_LABEL
    seed_runtime
    if [ -f "$runtime/.runner" ]; then
      echo "runner is already configured" >&2
      exit 1
    fi
    cd "$runtime"
    ./config.sh \
      --url "$RUNNER_REPOSITORY_URL" \
      --token "$RUNNER_REGISTRATION_TOKEN" \
      --name "$RUNNER_NAME" \
      --labels "$RUNNER_LABEL" \
      --work _work \
      --disableupdate \
      --unattended \
      --replace
    ;;
  run)
    seed_runtime
    if [ ! -f "$runtime/.runner" ]; then
      echo "runner is not configured; run 'self-runner configure <lane>' first" >&2
      exit 1
    fi
    cd "$runtime"
    exec ./run.sh
    ;;
  *)
    echo "usage: runner-entrypoint configure|run" >&2
    exit 2
    ;;
esac
