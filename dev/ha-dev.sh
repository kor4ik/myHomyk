#!/usr/bin/env bash
# Disposable Home Assistant test instance built from a clean clone of this repo.
set -euo pipefail

DEV_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$DEV_DIR/.." && pwd)
WORK="$DEV_DIR/.work"
CONFIG="$WORK/config"
NAME=${HA_NAME:-myhomyk-ha}
PORT=${HA_PORT:-8123}
SRC=${HA_SRC:-$REPO_DIR}
REF=${HA_REF:-}
WORKTREE=${HA_WORKTREE:-0}
TZ_NAME=${TZ:-UTC}
DEV_USER=${HA_USER:-dev}
DEV_PASS=${HA_PASS:-dev-pass-123}
BASE="http://localhost:$PORT"

ULM_VER=v1.5.9
SMARTIR_VER=1.18.2
BUTTON_CARD_VER=v7.0.1
LAYOUT_CARD_VER=v2.4.7
STATE_SWITCH_VER=1.9.6
CLOCK_CARD_VER=1.8
MY_CARDS_VER=v2.3.1
ENV_FILE="$DEV_DIR/.env"

die() { echo "error: $*" >&2; exit 1; }
py() { python3 -c "$1"; }
dl() { curl -fsSL --retry 3 -o "$2" "$1"; }
json_get() { py "import sys,json;print(json.load(sys.stdin)[\"$1\"])"; }

wait_up() {
  local i
  for i in $(seq 1 60); do
    curl -fs --max-time 3 "$BASE/manifest.json" >/dev/null 2>&1 && return 0
    sleep 3
  done
  die "Home Assistant did not come up on $BASE"
}

fetch_components() {
  local t="$WORK/dl" w="$CONFIG/www/community"
  rm -rf "$t"; mkdir -p "$t" "$w"/{button-card,layout-card,state-switch,simple-clock-card,my-cards}
  dl "https://github.com/UI-Lovelace-Minimalist/UI/releases/download/$ULM_VER/ui_lovelace_minimalist.zip" "$t/ulm.zip"
  mkdir -p "$CONFIG/custom_components/ui_lovelace_minimalist"
  unzip -oq "$t/ulm.zip" -d "$CONFIG/custom_components/ui_lovelace_minimalist"
  dl "https://github.com/smartHomeHub/SmartIR/archive/refs/tags/$SMARTIR_VER.zip" "$t/smartir.zip"
  unzip -oq "$t/smartir.zip" -d "$t/smartir"
  cp -R "$t"/smartir/*/custom_components/smartir "$CONFIG/custom_components/"
  dl "https://github.com/custom-cards/button-card/releases/download/$BUTTON_CARD_VER/button-card.js" "$w/button-card/button-card.js"
  dl "https://raw.githubusercontent.com/thomasloven/lovelace-layout-card/$LAYOUT_CARD_VER/layout-card.js" "$w/layout-card/layout-card.js"
  dl "https://raw.githubusercontent.com/thomasloven/lovelace-state-switch/$STATE_SWITCH_VER/state-switch.js" "$w/state-switch/state-switch.js"
  dl "https://raw.githubusercontent.com/fufar/simple-clock-card/$CLOCK_CARD_VER/simple-clock-card.js" "$w/simple-clock-card/simple-clock-card.js"
  dl "https://github.com/AnthonMS/my-cards/releases/download/$MY_CARDS_VER/my-slider.js" "$w/my-cards/my-slider.js"
  rm -rf "$t"
}

apply_overlay() {
  local k
  cp "$DEV_DIR/overlay/demo-secrets.yaml" "$CONFIG/secrets.yaml"
  grep -rhoE '!secret [A-Za-z0-9_]+' "$CONFIG" --include='*.yaml' | awk '{print $2}' | sort -u |
    while read -r k; do
      grep -q "^$k:" "$CONFIG/secrets.yaml" || echo "$k: dummy" >> "$CONFIG/secrets.yaml"
    done
  printf '\n' >> "$CONFIG/configuration.yaml"
  cat "$DEV_DIR/overlay/configuration.append.yaml" >> "$CONFIG/configuration.yaml"
  printf '\n' >> "$CONFIG/climate.yaml"
  cat "$DEV_DIR/overlay/climate.standins.yaml" >> "$CONFIG/climate.yaml"
  cp -R "$DEV_DIR/overlay/standin" "$CONFIG/custom_components/"
  mkdir -p "$CONFIG/themes" "$CONFIG/.storage"
  cp "$DEV_DIR/overlay/lovelace_resources.json" "$CONFIG/.storage/lovelace_resources"
}

copy_worktree() {
  local f
  mkdir -p "$CONFIG"
  (cd "$REPO_DIR" && git ls-files -co --exclude-standard -z | while IFS= read -r -d '' f; do
    case "$f" in dev/*|.cache/*) continue ;; esac
    [ -e "$f" ] && printf '%s\0' "$f"
  done | xargs -0 tar -cf -) | tar -xf - -C "$CONFIG"
}

clone_repo() {
  rm -rf "$CONFIG"; mkdir -p "$WORK"
  if [ "$WORKTREE" = 1 ]; then copy_worktree
  elif [ -n "$REF" ]; then git clone -q --branch "$REF" "$SRC" "$CONFIG"; else git clone -q "$SRC" "$CONFIG"; fi
}

prepare() {
  clone_repo
  fetch_components
  apply_overlay
}

login_token() {
  local f code
  f=$(curl -fsS -X POST "$BASE/auth/login_flow" -H 'Content-Type: application/json' \
    -d "{\"client_id\":\"$BASE/\",\"handler\":[\"homeassistant\",null],\"redirect_uri\":\"$BASE/\"}" | json_get flow_id)
  code=$(curl -fsS -X POST "$BASE/auth/login_flow/$f" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$DEV_USER\",\"password\":\"$DEV_PASS\",\"client_id\":\"$BASE/\"}" | json_get result)
  curl -fsS -X POST "$BASE/auth/token" -d "client_id=$BASE/&grant_type=authorization_code&code=$code" | json_get access_token
}

wait_running() {
  local tok=${1:-} i
  [ -n "$tok" ] || tok=$(login_token)
  for i in $(seq 1 60); do
    [ "$(curl -fs -H "Authorization: Bearer $tok" "$BASE/api/config" 2>/dev/null | json_get state 2>/dev/null)" = RUNNING ] && return 0
    sleep 2
  done
  die "Home Assistant did not reach RUNNING"
}

restart_ha() {
  local tok i
  tok=$(login_token)
  curl -fsS -X POST "$BASE/api/services/homeassistant/restart" -H "Authorization: Bearer $tok" \
    -H 'Content-Type: application/json' -d '{}' >/dev/null
  for i in $(seq 1 30); do
    curl -fs --max-time 2 "$BASE/manifest.json" >/dev/null 2>&1 || break
    sleep 1
  done
  wait_up
  wait_running
}

bootstrap() {
  local r code tok auth fid i
  r=$(curl -fsS -X POST "$BASE/api/onboarding/users" -H 'Content-Type: application/json' \
    -d "{\"client_id\":\"$BASE/\",\"name\":\"Dev\",\"username\":\"$DEV_USER\",\"password\":\"$DEV_PASS\",\"language\":\"en\"}")
  code=$(echo "$r" | json_get auth_code)
  tok=$(curl -fsS -X POST "$BASE/auth/token" -d "client_id=$BASE/&grant_type=authorization_code&code=$code" | json_get access_token)
  auth="Authorization: Bearer $tok"
  wait_running "$tok"
  for s in core_config analytics; do
    curl -fsS -X POST "$BASE/api/onboarding/$s" -H "$auth" -H 'Content-Type: application/json' -d '{}' >/dev/null
  done
  curl -fsS -X POST "$BASE/api/onboarding/integration" -H "$auth" -H 'Content-Type: application/json' \
    -d "{\"client_id\":\"$BASE/\",\"redirect_uri\":\"$BASE/?auth_callback=1\"}" >/dev/null
  fid=$(curl -fsS -X POST "$BASE/api/config/config_entries/flow" -H "$auth" -H 'Content-Type: application/json' \
    -d '{"handler":"ui_lovelace_minimalist","show_advanced_options":false}' | json_get flow_id)
  curl -fsS -X POST "$BASE/api/config/config_entries/flow/$fid" -H "$auth" -H 'Content-Type: application/json' \
    -d '{"community_cards_enabled":false}' >/dev/null
  for i in $(seq 1 30); do
    [ -d "$CONFIG/custom_components/ui_lovelace_minimalist/__ui_minimalist__/ulm_templates" ] && return 0
    sleep 2
  done
  die "Minimalist templates were not generated"
}

cmd_down() {
  container stop "$NAME" >/dev/null 2>&1 || true
  container delete --force "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
  [ "$WORK" = "$DEV_DIR/.work" ] && rm -f "$ENV_FILE"
  if [ "${1:-}" = "--purge" ]; then
    container image delete "ghcr.io/home-assistant/home-assistant:${HA_VERSION:-$(cat "$REPO_DIR/.HA_VERSION" | tr -d '[:space:]')}" >/dev/null 2>&1 || true
  fi
  echo "removed container $NAME and $WORK"
}

cmd_up() {
  command -v container >/dev/null || die "Apple container CLI not found"
  command -v git >/dev/null || die "git not found"
  cmd_down
  container system start >/dev/null 2>&1 || true
  prepare
  local ver=${HA_VERSION:-$(tr -d '[:space:]' < "$CONFIG/.HA_VERSION")}
  container run -d --name "$NAME" -p "127.0.0.1:$PORT:8123" -v "$CONFIG:/config" -e "TZ=$TZ_NAME" \
    "ghcr.io/home-assistant/home-assistant:$ver" >/dev/null
  wait_up
  bootstrap
  restart_ha
  echo "Home Assistant $ver at $BASE (user: $DEV_USER, password: $DEV_PASS)"
}

LOG_NOISE='metno|homeassistant_alerts|async_upnp_client|HACS (Frontend|Integration) repo|ui_lovelace_minimalist.base|camera.demo_camera does not support play stream|Setup of config entry .* cancelled'

use_test_instance() {
  NAME=$NAME-test
  PORT=${HA_PORT:-8125}
  BASE="http://localhost:$PORT"
  WORK="$DEV_DIR/.work-test"
  CONFIG="$WORK/config"
}

check_secrets() {
  local k missing=""
  for k in $(grep -rhoE '!secret [A-Za-z0-9_]+' "$CONFIG"/*.yaml "$CONFIG/ui_lovelace_minimalist" --include='*.yaml' | awk '{print $2}' | sort -u); do
    grep -q "^$k:" "$CONFIG/secrets.example.yaml" 2>/dev/null || missing="$missing $k"
  done
  [ -z "$missing" ] || { echo "missing from secrets.example.yaml:$missing"; return 1; }
}

step() {
  if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; FAILED=1; fi
}

cmd_test() {
  local keep=0 browser=0 out rc allow token arg
  for arg in "$@"; do
    case "$arg" in --keep) keep=1 ;; --browser) browser=1 ;; *) die "unknown test option: $arg" ;; esac
  done
  FAILED=0
  use_test_instance
  if [ "$keep" = 0 ]; then trap 'cmd_down >/dev/null' EXIT; fi
  cmd_up

  rc=0; out=$(check_secrets) || rc=1
  step "$rc" "secrets.example.yaml covers every !secret"
  [ "$rc" = 0 ] || echo "  $out"

  token=$(login_token)
  rc=0; curl -fs -H "Authorization: Bearer $token" "$BASE/api/states/automation.wake_up_screenblet_on_motion" >/dev/null || rc=1
  step "$rc" "automation wake_up_screenblet_on_motion is loaded"

  rc=0; out=$(container exec "$NAME" python -m homeassistant --script check_config -c /config 2>&1) || rc=1
  echo "$out" | grep -qiE 'failed config|invalid config|error' && rc=1
  step "$rc" "check_config"
  [ "$rc" = 0 ] || echo "$out" | sed 's/^/  /'

  out=$(container logs "$NAME" 2>&1 | grep 'ERROR' | grep -vE "$LOG_NOISE" || true)
  rc=0; [ -z "$out" ] || rc=1
  step "$rc" "startup log has no unexpected errors"
  [ "$rc" = 0 ] || echo "$out" | sed 's/^/  /'

  allow=$(grep -v '^#' "$DEV_DIR/overlay/allow-missing.txt" | paste -sd, -)
  rc=0; out=$(container exec -i -e "HA_TOKEN=$token" -e "HA_ALLOW_MISSING=$allow" "$NAME" python - < "$DEV_DIR/overlay/dashboard_check.py" 2>&1) || rc=1
  step "$rc" "dashboards: templates, custom cards, entity refs"
  echo "$out" | sed 's/^/  /'

  if [ "$browser" = 1 ]; then
    command -v node >/dev/null || die "node not found"
    [ -d "$DEV_DIR/node_modules/playwright-core" ] || (cd "$DEV_DIR" && npm ci --silent)
    rc=0; out=$(HA_BASE=$BASE HA_USER=$DEV_USER HA_PASS=$DEV_PASS HA_TOKEN=$token node "$DEV_DIR/browser_check.mjs" 2>&1) || rc=1
    step "$rc" "browser: every view renders without card errors"
    echo "$out" | sed 's/^/  /'
  fi

  [ "$FAILED" = 0 ] && echo "all checks passed" || echo "some checks failed"
  return "$FAILED"
}

cmd_prepare() {
  prepare
  {
    echo "HA_VERSION=${HA_VERSION:-$(tr -d '[:space:]' < "$CONFIG/.HA_VERSION")}"
    echo "HA_PORT=$PORT"
    echo "HA_NAME=$NAME"
    echo "HA_TZ=$TZ_NAME"
  } > "$ENV_FILE"
  echo "prepared $CONFIG and $ENV_FILE; start the compose service, then run: ha-dev.sh bootstrap"
}

cmd_bootstrap() {
  wait_up
  bootstrap
  restart_ha
  echo "Home Assistant at $BASE (user: $DEV_USER, password: $DEV_PASS)"
}

case "${1:-}" in
  test) shift; cmd_test "$@" ;;
  up) cmd_up ;;
  down) shift; if [ "${1:-}" = "--test" ]; then use_test_instance; shift; fi; cmd_down "$@" ;;
  reset) cmd_down; cmd_up ;;
  prepare) cmd_prepare ;;
  bootstrap) cmd_bootstrap ;;
  logs) container logs "$NAME" ;;
  *) echo "usage: ha-dev.sh up | down [--purge] [--test] | reset | test [--keep] [--browser] | prepare | bootstrap | logs"; exit 2 ;;
esac
