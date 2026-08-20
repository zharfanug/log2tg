#!/bin/sh

SCRIPT_NAME=${0##*/}
SCRIPT_BASENAME=${SCRIPT_NAME%.*}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKSPACE_DIR=$(pwd)

LOG_FILE=${LOG_FILE:-/tmp/${SCRIPT_NAME}.log}
LOG_TO_FILE=${LOG_TO_FILE:-false}

if [ -t 2 ]; then
  ESC=$(printf '\033')

  W="${ESC}[0;39m"
  R="${ESC}[1;31m"
  G="${ESC}[1;32m"
  Y="${ESC}[1;33m"
  B="${ESC}[1;34m"
  DIM="${ESC}[2m"
  C0="${ESC}[0m"
else
  W=
  R=
  G=
  Y=
  B=
  DIM=
  C0=
fi

log_format() {
  _level=$1
  shift

  _ts=$(date '+%Y-%m-%d %H:%M:%S %z')
  _msg=$_ts" - $_level : $*"

  case $_level in
    INFO)
      _print=$_msg
      _fd=1
      ;;
    WARN)
      _print=$_ts" - ${Y}WARN${C0} : $*"
      _fd=2
      ;;
    ERROR)
      _print=$_ts" - ${R}ERROR${C0} : $*"
      _fd=2
      ;;
    *)
      _print=$_msg
      _fd=1
      ;;
  esac

  printf '%b\n' "$_print" >&$_fd

  if [ "$LOG_TO_FILE" = "true" ]; then
    printf '%s\n' "$_msg" >>"$LOG_FILE"
  fi
}

log() {
  log_format INFO "$@"
}

log_warn() {
  log_format WARN "$@"
}

log_error() {
  log_format ERROR "$@"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Required command not found: $1"
    exit 1
  fi
}

require_cmd_list() {
  for cmd do
    require_cmd "$cmd"
  done
}

download() {
  _url="$1"
  _output="$2"
  _exit_on_error="${3:-0}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 5 --max-time 30 -o "$_output" "$_url"
    _rc=$?
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_output" --timeout=5 --tries=1 "$_url"
    _rc=$?
  else
    log_error "Neither curl nor wget is available — please install one of them"
    if [ "$_exit_on_error" = "1" ]; then
      exit 1
    fi
    return 1
  fi

  if [ "$_rc" -ne 0 ]; then
    log_error "Failed to download ${_url}"
    if [ "$_exit_on_error" = "1" ]; then
      exit 1
    fi
  fi

  return "$_rc"
}

REPO="zharfanug/log2tg"
PKG_URL="https://raw.githubusercontent.com/${REPO}/latest/log2tg.py"
LOG2TG_HOME="$HOME/.log2tg"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME -l
  $SCRIPT_NAME -a <name> -f <log file/glob> -k <api key> -c <chat id> [-b <interval>] [-ts <format>] [-ge <pattern>] [-pre <string>] [-y]
  $SCRIPT_NAME -rm <name> [-y]
  $SCRIPT_NAME -x -f <log file/glob> -k <api key> -c <chat id> [-b <interval>] [-ts <format>] [-ge <pattern>] [-pre <string>]

  -l             List configured monitors
  -a <name>      Add or update a monitor named <name>
  -rm <name>     Remove a monitor named <name>
  -x             Run in the current terminal without creating a service (for testing)
  -f <file>      Log file path or glob pattern (e.g. "*.log", "/home/*/mylog.log")
  -k <key>       Telegram bot API key
  -c <id>        Telegram chat id
  -b <interval>  Batch new lines and send every <interval>: 5, 5s, 5m or 5h. Default: no batching
  -ts <format>   Prefix messages with a timestamp in this strftime format. Default: no timestamp
  -ge <pattern>  Exclude log lines matching this Python re pattern. Default: no exclusion
  -pre <string>  Prefix every message with this string. Default: no prefix
  -y             Auto-confirm prompts
EOF
}

# --- arg parsing ---------------------------------------------------------

MODE=
NAME=
LOG_FILE_ARG=
API_KEY_ARG=
CHAT_ID_ARG=
BATCH_ARG=
TS_ARG=
GE_ARG=
PRE_ARG=
AUTO_YES=false

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -l)
      MODE=list
      shift
      ;;
    -a)
      [ "$#" -ge 2 ] || { log_error "-a requires a name"; usage; exit 1; }
      MODE=add
      NAME="$2"
      shift 2
      ;;
    -rm)
      [ "$#" -ge 2 ] || { log_error "-rm requires a name"; usage; exit 1; }
      MODE=remove
      NAME="$2"
      shift 2
      ;;
    -x)
      MODE=x
      shift
      ;;
    -f)
      [ "$#" -ge 2 ] || { log_error "-f requires a value"; usage; exit 1; }
      LOG_FILE_ARG="$2"
      shift 2
      ;;
    -k)
      [ "$#" -ge 2 ] || { log_error "-k requires a value"; usage; exit 1; }
      API_KEY_ARG="$2"
      shift 2
      ;;
    -c)
      [ "$#" -ge 2 ] || { log_error "-c requires a value"; usage; exit 1; }
      CHAT_ID_ARG="$2"
      shift 2
      ;;
    -b)
      [ "$#" -ge 2 ] || { log_error "-b requires a value"; usage; exit 1; }
      BATCH_ARG="$2"
      shift 2
      ;;
    -ts)
      [ "$#" -ge 2 ] || { log_error "-ts requires a value"; usage; exit 1; }
      TS_ARG="$2"
      shift 2
      ;;
    -ge)
      [ "$#" -ge 2 ] || { log_error "-ge requires a value"; usage; exit 1; }
      GE_ARG="$2"
      shift 2
      ;;
    -pre)
      [ "$#" -ge 2 ] || { log_error "-pre requires a value"; usage; exit 1; }
      PRE_ARG="$2"
      shift 2
      ;;
    -y)
      AUTO_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [ -z "$MODE" ]; then
  usage
  exit 1
fi

# --- helpers ---------------------------------------------------------------

is_root() {
  [ "$(id -u)" -eq 0 ]
}

systemctl_cmd() {
  if is_root; then
    systemctl "$@"
  else
    systemctl --user "$@"
  fi
}

unit_file_path() {
  if is_root; then
    printf '/etc/systemd/system/log2tg@.service'
  else
    printf '%s/.config/systemd/user/log2tg@.service' "$HOME"
  fi
}

conf_path() {
  printf '%s/%s.conf' "$LOG2TG_HOME" "$1"
}

conf_get() {
  sed -n "s/^${2}=//p" "$1" | head -n1
}

confirm() {
  printf '%s [Y/n] ' "$1"
  read -r _ans
  case "$_ans" in
    ''|[Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

parse_interval() {
  _val="$1"
  case "$_val" in
    *h) _unit=3600; _num=${_val%h} ;;
    *m) _unit=60; _num=${_val%m} ;;
    *s) _unit=1; _num=${_val%s} ;;
    *) _unit=1; _num=$_val ;;
  esac
  case "$_num" in
    ''|*[!0-9]*)
      log_error "Invalid interval: $_val"
      exit 1
      ;;
  esac
  echo $((_num * _unit))
}

# --- setup sequence ----------------------------------------------------

find_python() {
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    _ver=$(python -c 'import sys; print(sys.version_info[0])' 2>/dev/null)
    if [ "$_ver" = "3" ]; then
      PYTHON_BIN=python
      return 0
    fi
    log_error "Found 'python' on PATH but it is not Python 3"
    exit 1
  fi
  log_error "Neither python3 nor python found on PATH"
  exit 1
}

ensure_venv() {
  if [ ! -f "$LOG2TG_HOME/pyvenv.cfg" ]; then
    log "Creating virtualenv at $LOG2TG_HOME"
    mkdir -p "$LOG2TG_HOME"
    "$PYTHON_BIN" -m venv "$LOG2TG_HOME" || { log_error "Failed to create virtualenv"; exit 1; }
  fi
  VENV_PYTHON="$LOG2TG_HOME/bin/python3"
}

install_deps() {
  "$VENV_PYTHON" -m pip install --quiet --upgrade-strategy only-if-needed requests \
    || { log_error "Failed to install dependencies"; exit 1; }
}

ensure_script() {
  if [ -f "$WORKSPACE_DIR/log2tg.py" ]; then
    cp "$WORKSPACE_DIR/log2tg.py" "$LOG2TG_HOME/log2tg.py"
  else
    download "$PKG_URL" "$LOG2TG_HOME/log2tg.py" 1
  fi
}

setup() {
  find_python

  if ! "$PYTHON_BIN" -m venv --help >/dev/null 2>&1; then
    log_error "Python venv module is not available"
    exit 1
  fi

  ensure_venv
  install_deps
  ensure_script
}

ensure_unit_template() {
  _unit_path=$(unit_file_path)
  if [ -f "$_unit_path" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$_unit_path")"

  if is_root; then
    _wanted_by="multi-user.target"
  else
    _wanted_by="default.target"
  fi

  cat >"$_unit_path" <<EOF
[Unit]
Description=log2tg monitor (%i)
After=network.target

[Service]
EnvironmentFile=$LOG2TG_HOME/%i.conf
ExecStart=$LOG2TG_HOME/bin/python3 $LOG2TG_HOME/log2tg.py
Restart=on-failure

[Install]
WantedBy=$_wanted_by
EOF
}

write_conf() {
  _path=$(conf_path "$1")
  {
    printf 'LOG_FILE=%s\n' "$2"
    printf 'API_KEY=%s\n' "$3"
    printf 'CHAT_ID=%s\n' "$4"
    printf 'BATCH_INTERVAL=%s\n' "$5"
    printf 'TS_FORMAT=%s\n' "$6"
    printf 'GREP_EXCLUDE=%s\n' "$7"
    printf 'PREFIX=%s\n' "$8"
  } >"$_path"
  chmod 600 "$_path"
}

# --- commands ------------------------------------------------------------

cmd_list() {
  require_cmd systemctl
  setup

  _found=0
  for _conf in "$LOG2TG_HOME"/*.conf; do
    [ -e "$_conf" ] && _found=1
    break
  done

  if [ "$_found" -eq 0 ]; then
    log "No monitors configured"
    return
  fi

  {
    printf 'NAME\tLOG FILE\tSTATUS\n'
    for _conf in "$LOG2TG_HOME"/*.conf; do
      [ -e "$_conf" ] || continue
      _name=$(basename "$_conf" .conf)
      _file=$(conf_get "$_conf" LOG_FILE)
      _status=$(systemctl_cmd is-active "log2tg@${_name}.service" 2>/dev/null)
      printf '%s\t%s\t%s\n' "$_name" "$_file" "${_status:-unknown}"
    done
  } | awk -F'\t' '
    {
      name[NR] = $1; file[NR] = $2; status[NR] = $3
      if (length($1) > w1) w1 = length($1)
      if (length($2) > w2) w2 = length($2)
    }
    END {
      for (i = 1; i <= NR; i++) {
        printf "%-*s  %-*s  %s\n", w1, name[i], w2, file[i], status[i]
      }
    }
  '
}

cmd_add() {
  require_cmd systemctl

  if [ -z "$LOG_FILE_ARG" ] || [ -z "$API_KEY_ARG" ] || [ -z "$CHAT_ID_ARG" ]; then
    log_error "-a requires -f, -k and -c"
    usage
    exit 1
  fi

  _batch_seconds=0
  if [ -n "$BATCH_ARG" ]; then
    _batch_seconds=$(parse_interval "$BATCH_ARG")
  fi

  setup

  _conf=$(conf_path "$NAME")
  if [ -f "$_conf" ] && [ "$AUTO_YES" != "true" ]; then
    if ! confirm "Instance '$NAME' already exists. Overwrite?"; then
      log "Aborted"
      exit 0
    fi
  fi

  write_conf "$NAME" "$LOG_FILE_ARG" "$API_KEY_ARG" "$CHAT_ID_ARG" "$_batch_seconds" "$TS_ARG" "$GE_ARG" "$PRE_ARG"
  ensure_unit_template
  systemctl_cmd daemon-reload
  systemctl_cmd enable --now "log2tg@${NAME}.service"
  log "Monitor '$NAME' added and started"
}

cmd_remove() {
  require_cmd systemctl
  setup

  _conf=$(conf_path "$NAME")
  if [ ! -f "$_conf" ]; then
    log_error "No such monitor: $NAME"
    exit 1
  fi

  if [ "$AUTO_YES" != "true" ]; then
    if ! confirm "Remove instance '$NAME'?"; then
      log "Aborted"
      exit 0
    fi
  fi

  systemctl_cmd disable --now "log2tg@${NAME}.service"
  rm -f "$_conf"
  systemctl_cmd daemon-reload
  log "Monitor '$NAME' removed"
}

cmd_x() {
  if [ -z "$LOG_FILE_ARG" ] || [ -z "$API_KEY_ARG" ] || [ -z "$CHAT_ID_ARG" ]; then
    log_error "-x requires -f, -k and -c"
    usage
    exit 1
  fi

  _batch_seconds=0
  if [ -n "$BATCH_ARG" ]; then
    _batch_seconds=$(parse_interval "$BATCH_ARG")
  fi

  setup

  LOG_FILE="$LOG_FILE_ARG" API_KEY="$API_KEY_ARG" CHAT_ID="$CHAT_ID_ARG" \
    BATCH_INTERVAL="$_batch_seconds" TS_FORMAT="$TS_ARG" \
    GREP_EXCLUDE="$GE_ARG" PREFIX="$PRE_ARG" \
    "$VENV_PYTHON" "$LOG2TG_HOME/log2tg.py"
}

case "$MODE" in
  list) cmd_list ;;
  add) cmd_add ;;
  remove) cmd_remove ;;
  x) cmd_x ;;
esac

