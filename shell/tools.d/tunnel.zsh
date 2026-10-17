# tools tunnel: выход в интернет через свой сервер по ssh.
# Три способа: SOCKS на 127.0.0.1 (ssh -D) для оболочки, браузера или
# системного прокси; sshuttle для всего трафика разом; пробросы портов -L и -R.
# По сети во всех случаях идёт только ssh.

TOOLS_TUNNEL_HOST="${TOOLS_TUNNEL_HOST:-}"
TOOLS_TUNNEL_PORT="${TOOLS_TUNNEL_PORT:-1080}"
TOOLS_STATE="${TOOLS_STATE:-$HOME/.local/state/tools}"
TOOLS_SSH_OPTS=(-o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ConnectTimeout=15)

_tunnel_sock() { print "$HOME/.ssh/tools-$1.sock"; }
_tunnel_state() { print "$TOOLS_STATE/tunnel-$1"; }

_tunnel_host() {
  local host="${1:-$TOOLS_TUNNEL_HOST}"
  [[ -n "$host" ]] || { print -P "%F{red}сервер не задан: аргументом или TOOLS_TUNNEL_HOST в shell/tools.conf%f" >&2; return 1 }
  print "$host"
}

# Жив ли туннель с именем name (socks-<host>, fwd-<порт>, rev-<порт>).
_tunnel_alive() {
  local name="$1" host
  [[ -S "$(_tunnel_sock "$name")" ]] || return 1
  host=$(awk '{print $1}' "$(_tunnel_state "$name")" 2>/dev/null)
  ssh -S "$(_tunnel_sock "$name")" -O check "${host:-x}" >/dev/null 2>&1
}

# Поднять ssh в фоне с control-сокетом: name host "описание" аргументы ssh...
_tunnel_start() {
  local label dim warn bad info off; _tools_colors
  local name="$1" host="$2" desc="$3"; shift 3
  mkdir -p "$TOOLS_STATE"
  if _tunnel_alive "$name"; then print -P "${dim}${desc}: уже поднят${off}"; return 0; fi
  rm -f "$(_tunnel_sock "$name")"
  if [[ -n "$TOOLS_DRY_RUN" ]]; then print "  ssh -f -N -M -S $(_tunnel_sock "$name") ${TOOLS_SSH_OPTS[*]} $* $host"; return 0; fi
  if ssh -f -N -M -S "$(_tunnel_sock "$name")" "${TOOLS_SSH_OPTS[@]}" "$@" "$host"; then
    print "$host $desc" > "$(_tunnel_state "$name")"
    print -P "${label}${desc}${off} через ${host}"
  else
    print -P "${bad}${desc}: ssh до ${host} не поднялся${off}"; return 1
  fi
}

_tunnel_stop() {
  local label dim warn bad info off; _tools_colors
  local name="$1" host
  host=$(awk '{print $1}' "$(_tunnel_state "$name")" 2>/dev/null)
  if [[ -n "$TOOLS_DRY_RUN" ]]; then print "  ssh -S $(_tunnel_sock "$name") -O exit ${host:-?}"; return 0; fi
  if [[ -S "$(_tunnel_sock "$name")" ]]; then
    ssh -S "$(_tunnel_sock "$name")" -O exit "${host:-x}" >/dev/null 2>&1
    print -P "${label}${name}${off} снят"
  else
    print -P "${dim}${name}: не было${off}"
  fi
  rm -f "$(_tunnel_sock "$name")" "$(_tunnel_state "$name")"
}

_tunnel_socks_up() {
  local label dim warn bad info off; _tools_colors
  local host port="${2:-$TOOLS_TUNNEL_PORT}" have
  host=$(_tunnel_host "$1") || return 1
  if have=$(_tunnel_socks_port "$host") && [[ -z "$TOOLS_DRY_RUN" ]]; then
    print -P "${dim}SOCKS через ${host} уже поднят на 127.0.0.1:${have}${off}"
    return 0
  fi
  _tunnel_start "socks-$host" "$host" "SOCKS 127.0.0.1:$port" -D "127.0.0.1:$port" || return 1
  [[ -n "$TOOLS_DRY_RUN" ]] || print "$host SOCKS $port" > "$(_tunnel_state "socks-$host")"
}

# Порт SOCKS живого туннеля до host; в dry-run порт из настроек.
_tunnel_socks_port() {
  local host="$1"
  [[ -n "$TOOLS_DRY_RUN" ]] && { print "$TOOLS_TUNNEL_PORT"; return 0 }
  _tunnel_alive "socks-$host" || return 1
  awk '{print $3}' "$(_tunnel_state "socks-$host")"
}

_tunnel_status() {
  local label dim warn bad info off; _tools_colors
  local f name host rest any=0
  for f in "$TOOLS_STATE"/tunnel-*(N); do
    name=${${f:t}#tunnel-}; read -r host rest < "$f"
    any=1
    if _tunnel_alive "$name"; then print -P "${label}${(r:22:)name}${off} ${rest}  ${dim}через ${host}${off}"
    else print -P "${dim}${(r:22:)name} ${rest}  оборван, tools tunnel down ${name}${off}"; fi
  done
  if [[ -f "$TOOLS_STATE/sshuttle.pid" ]] && kill -0 "$(cat "$TOOLS_STATE/sshuttle.pid")" 2>/dev/null; then
    any=1; print -P "${label}all${off} весь трафик через $(cat "$TOOLS_STATE/sshuttle.host" 2>/dev/null) (sshuttle)"
  fi
  (( any )) || print -P "${dim}туннелей нет; tools tunnel up [сервер]${off}"
  local proxy; proxy=$(networksetup -getsocksfirewallproxy "$(_tunnel_service)" 2>/dev/null | awk -F': ' '/^Enabled/ {print $2}')
  [[ "$proxy" == Yes ]] && print -P "${warn}системный SOCKS-прокси включён${off}  ${dim}tools tunnel system off${off}"
  return 0
}

# Имя сетевой службы macOS для активного физического интерфейса.
_tunnel_service() {
  local device; device=$(_tools_phys_iface) || return 1
  networksetup -listnetworkserviceorder 2>/dev/null |
    awk -v d="$device" '/^\([0-9]+\) / { name = $0; sub(/^\([0-9]+\) /, "", name) } $0 ~ "Device: " d "\\)" { print name; exit }'
}

_tunnel_check() {
  local label dim warn bad info off; _tools_colors
  local host port direct via
  host=$(_tunnel_host "$1") || return 1
  port=$(_tunnel_socks_port "$host") || { print -P "${bad}туннель до ${host} не поднят${off}"; return 1 }
  direct=$(curl -fsS -m 8 https://ifconfig.me 2>/dev/null)
  via=$(curl -fsS -m 8 --proxy "socks5h://127.0.0.1:$port" https://ifconfig.me 2>/dev/null)
  print -P "${label}напрямую${off} ${direct:-нет ответа}   ${label}через ${host}${off} ${via:-нет ответа}"
  if [[ -z "$via" ]]; then print -P "${bad}через туннель ответа нет${off}"; return 1
  elif [[ "$via" == "$direct" ]]; then print -P "${warn}адрес тот же: трафик и так идёт через этот сервер${off}"
  else print -P "${label}выход через сервер работает${off}"; fi
}

_tunnel_proxy_env() { # host -> печатает export-строки
  local port; port=$(_tunnel_socks_port "$1") || return 1
  print "export ALL_PROXY=socks5h://127.0.0.1:$port HTTP_PROXY=socks5h://127.0.0.1:$port HTTPS_PROXY=socks5h://127.0.0.1:$port http_proxy=socks5h://127.0.0.1:$port https_proxy=socks5h://127.0.0.1:$port TOOLS_TUNNEL=$1"
}

_tunnel_shell() {
  local label dim warn bad info off; _tools_colors
  local host; host=$(_tunnel_host "$1") || return 1
  _tunnel_socks_up "$host" || return 1
  print -P "${dim}подоболочка с прокси через ${host}; curl, git, composer, pip пойдут через сервер; exit вернёт обратно${off}"
  [[ -n "$TOOLS_DRY_RUN" ]] && return 0
  ( eval "$(_tunnel_proxy_env "$host")"; exec zsh -i )
}

_tunnel_run() {
  local host; host=$(_tunnel_host "$TOOLS_TUNNEL_HOST") || return 1
  _tunnel_socks_up "$host" >/dev/null || return 1
  [[ -n "$TOOLS_DRY_RUN" ]] && { print "  $(_tunnel_proxy_env "$host"); $*"; return 0 }
  ( eval "$(_tunnel_proxy_env "$host")"; "$@" )
}

# Браузер отдельным профилем с прокси, чтобы не трогать основной.
_tunnel_app() {
  local label dim warn bad info off; _tools_colors
  local app="${1:-chrome}" host port dir
  host=$(_tunnel_host "$2") || return 1
  _tunnel_socks_up "$host" >/dev/null || return 1
  port=$(_tunnel_socks_port "$host")
  dir="$TOOLS_STATE/$app-tunnel"; mkdir -p "$dir"
  case "$app" in
    chrome|brave|chromium)
      local bundle
      case "$app" in chrome) bundle="Google Chrome" ;; brave) bundle="Brave Browser" ;; chromium) bundle="Chromium" ;; esac
      _tools_run "open -na \"$bundle\" --args --proxy-server=socks5://127.0.0.1:$port --user-data-dir=$dir" ;;
    firefox)
      printf 'user_pref("network.proxy.type", 1);\nuser_pref("network.proxy.socks", "127.0.0.1");\nuser_pref("network.proxy.socks_port", %s);\nuser_pref("network.proxy.socks_remote_dns", true);\n' "$port" > "$dir/user.js"
      _tools_run "/Applications/Firefox.app/Contents/MacOS/firefox --no-remote --profile $dir >/dev/null 2>&1 &!" ;;
    *) print -P "${bad}tools tunnel app chrome|brave|chromium|firefox${off}"; return 1 ;;
  esac
}

# Системный SOCKS-прокси macOS: Safari, Chrome и всё, что чтит настройки системы.
_tunnel_system() {
  local label dim warn bad info off; _tools_colors
  local mode="$1" host port service
  service=$(_tunnel_service) || { print -P "${bad}сетевая служба не найдена${off}"; return 1 }
  case "$mode" in
    on)
      host=$(_tunnel_host "$2") || return 1
      _tunnel_socks_up "$host" >/dev/null || return 1
      port=$(_tunnel_socks_port "$host")
      _tools_run "sudo networksetup -setsocksfirewallproxy \"$service\" 127.0.0.1 $port" &&
      _tools_run "sudo networksetup -setsocksfirewallproxystate \"$service\" on" &&
      print -P "${label}системный прокси${off} ${service} -> SOCKS 127.0.0.1:${port} через ${host}" ;;
    off)
      _tools_run "sudo networksetup -setsocksfirewallproxystate \"$service\" off" &&
      print -P "${label}системный прокси выключен${off} (${service})" ;;
    *) print -P "${bad}tools tunnel system on|off [сервер]${off}"; return 1 ;;
  esac
}

# Весь трафик через сервер: sshuttle перехватывает TCP и DNS, ходит по ssh.
_tunnel_all() {
  local label dim warn bad info off; _tools_colors
  local host def
  if [[ "$1" == off ]]; then
    if [[ -f "$TOOLS_STATE/sshuttle.pid" ]]; then
      _tools_run "sudo kill $(cat "$TOOLS_STATE/sshuttle.pid")" && rm -f "$TOOLS_STATE/sshuttle.pid" "$TOOLS_STATE/sshuttle.host"
      print -P "${label}весь трафик снова напрямую${off}"
    else print -P "${dim}sshuttle не запущен${off}"; fi
    return 0
  fi
  command -v sshuttle >/dev/null 2>&1 || { print -P "${bad}нужен sshuttle: brew install sshuttle${off}"; return 1 }
  host=$(_tunnel_host "$1") || return 1
  def=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')
  [[ "$def" == utun* ]] && print -P "${warn}маршрут по умолчанию сейчас в VPN (${def}); sshuttle поверх VPN обычно не нужен${off}"
  mkdir -p "$TOOLS_STATE"
  _tools_run "sudo sshuttle -r $host 0/0 --dns -D --pidfile $TOOLS_STATE/sshuttle.pid" || return 1
  [[ -n "$TOOLS_DRY_RUN" ]] && return 0
  print "$host" > "$TOOLS_STATE/sshuttle.host"
  print -P "${label}весь трафик через ${host}${off}  ${dim}выключить: tools tunnel all off${off}"
}

# Проброс портов: port <локальный>:<хост>:<удалённый> и expose <локальный> [удалённый].
_tunnel_port() {
  local spec="$1" host lport
  [[ "$spec" == *:*:* ]] || { print -P "%F{red}tools tunnel port <локальный>:<хост>:<удалённый> [сервер]%f"; return 1 }
  host=$(_tunnel_host "$2") || return 1
  lport=${spec%%:*}
  _tunnel_start "fwd-$lport" "$host" "127.0.0.1:$lport -> ${spec#*:} на стороне $host" -L "127.0.0.1:$spec"
}

_tunnel_expose() {
  local lport="$1" rport="${2:-$1}" host
  [[ "$lport" == <-> ]] || { print -P "%F{red}tools tunnel expose <локальный порт> [порт на сервере] [сервер]%f"; return 1 }
  host=$(_tunnel_host "$3") || return 1
  _tunnel_start "rev-$lport" "$host" "порт $rport на $host -> 127.0.0.1:$lport здесь" -R "127.0.0.1:$rport:127.0.0.1:$lport"
}

tools_tunnel() {
  local cmd="${1:-status}"; (( $# > 0 )) && shift
  case "$cmd" in
    status|"") _tunnel_status ;;
    up) _tunnel_socks_up "$@" ;;
    down)
      if [[ -z "$1" || "$1" == all ]]; then
        local f; for f in "$TOOLS_STATE"/tunnel-*(N); do _tunnel_stop "${${f:t}#tunnel-}"; done
        [[ "$1" == all ]] && _tunnel_all off
      else
        local name="$1"; [[ -f "$(_tunnel_state "$name")" ]] || name="socks-$1"
        _tunnel_stop "$name"
      fi ;;
    check) _tunnel_check "$@" ;;
    shell) _tunnel_shell "$@" ;;
    run) _tunnel_run "$@" ;;
    app) _tunnel_app "$@" ;;
    system) _tunnel_system "$@" ;;
    all) _tunnel_all "$@" ;;
    port) _tunnel_port "$@" ;;
    expose) _tunnel_expose "$@" ;;
    *) print -P "%F{red}tools tunnel: нет команды ${cmd}%f"; tools_help туннели; return 1 ;;
  esac
}

tools_help_add туннели "tools tunnel" "состояние туннелей и системного прокси"
tools_help_add туннели "tools tunnel up [сервер] [порт]" "SOCKS на 127.0.0.1 через ssh к серверу"
tools_help_add туннели "tools tunnel check [сервер]" "внешний IP напрямую и через туннель"
tools_help_add туннели "tools tunnel shell|run <cmd>" "подоболочка или команда с прокси через сервер"
tools_help_add туннели "tools tunnel app chrome|firefox" "браузер отдельным профилем через туннель"
tools_help_add туннели "tools tunnel system on|off" "системный SOCKS-прокси macOS (sudo)"
tools_help_add туннели "tools tunnel all [сервер]|all off" "весь трафик через сервер (sshuttle, sudo)"
tools_help_add туннели "tools tunnel port L:host:R" "проброс удалённого порта на локальный"
tools_help_add туннели "tools tunnel expose L [R]" "локальный порт наружу на сервер"
tools_help_add туннели "tools tunnel down [имя|all]" "снять туннель, все, или всё вместе с sshuttle"
