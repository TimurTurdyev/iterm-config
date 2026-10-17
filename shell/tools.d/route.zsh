# tools route: маршруты в обход VPN. Логика из mercurio-infra/vpn-bypass.sh:
# при раздельном туннелировании боевые адреса уезжают в туннель, лечится
# host-маршрутом через физический шлюз.

TOOLS_HOSTS="${TOOLS_HOSTS:-${TOOLS_DIR}/tools.hosts}"
TOOLS_SSH_PORT=22
TOOLS_PROBE_TIMEOUT=2

# Активный физический интерфейс: туннели и мосты пропускаем.
_tools_phys_iface() {
  local device
  for device in $(networksetup -listnetworkserviceorder 2>/dev/null | grep -oE 'Device: [a-z0-9]+' | awk '{print $2}'); do
    case "$device" in utun*|tun*|tap*|ppp*|bridge*) continue ;; esac
    ifconfig "$device" 2>/dev/null | grep -q 'status: active' && { print "$device"; return 0 }
  done
  return 1
}

# Шлюз интерфейса по DHCP; при статике из таблицы маршрутов. Маршрут по умолчанию
# не подходит: при поднятом туннеле там сам туннель.
_tools_iface_gateway() {
  local device="$1" router
  router=$(ipconfig getoption "$device" router 2>/dev/null)
  if [[ -z "$router" || "$router" == "0.0.0.0" ]]; then
    router=$(netstat -rn -f inet 2>/dev/null | awk -v i="$device" '$1 == "default" && $NF == i { print $2; exit }')
  fi
  [[ -n "$router" ]] && print "$router"
}

# Список адресов: "адрес пометка".
_tools_hosts() {
  [[ -f "$TOOLS_HOSTS" ]] || return 0
  sed 's/#.*//' "$TOOLS_HOSTS" | awk 'NF { print $1, ($2 == "" ? "-" : $2) }'
}

# Пометка или адрес из списка, IPv4 как есть, остальное через DNS.
_tools_resolve() {
  local want="$1" addr label
  while read -r addr label; do
    [[ "$want" == "$addr" || "$want" == "$label" ]] && { print "$addr"; return 0 }
  done <<< "$(_tools_hosts)"
  [[ "$want" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { print "$want"; return 0 }
  addr=$(dscacheutil -q host -a name "$want" 2>/dev/null | awk '/^ip_address:/ { print $2; exit }')
  [[ -n "$addr" ]] && { print "$addr"; return 0 }
  return 1
}

_tools_route_of() {
  route -n get "$1" 2>/dev/null |
    awk '/gateway:/ { g = $2 } /interface:/ { i = $2 } END { print (g == "" ? "-" : g), (i == "" ? "-" : i) }'
}

_tools_label_of() {
  _tools_hosts | awk -v a="$1" '$1 == a { print $2; exit }'
}

# Адреса для up/down: названные либо весь список.
_tools_collect() {
  local want addr
  if (( $# > 0 )); then
    for want in "$@"; do
      addr=$(_tools_resolve "$want") || { print -P "%F{red}не удалось разобрать адрес: ${want}%f" >&2; return 1 }
      print "$addr"
    done
  else
    _tools_hosts | awk '{ print $1 }'
  fi
}

_tools_sudo_route() {
  if [[ -n "$TOOLS_DRY_RUN" ]]; then
    print "  sudo route -n $*"
    return 0
  fi
  sudo route -n "$@" >/dev/null 2>&1
}

_tools_route_status() {
  local label dim warn bad info off; _tools_colors
  local device gw def addr lbl rgw riface state probe="$1"
  device=$(_tools_phys_iface)
  if [[ -n "$device" ]]; then
    gw=$(_tools_iface_gateway "$device")
    print -P "${dim}физический интерфейс${off} ${device}  ${dim}шлюз${off} ${gw:-не определён}"
  else
    print -P "${warn}физический интерфейс не найден: сеть выключена?${off}"
  fi
  def=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')
  print -P "${dim}маршрут по умолчанию${off} ${def:-нет}${${(M)def:#utun*}:+  ${warn}(весь трафик в туннель)${off}}"

  print -P "${dim}АДРЕС            ПОМЕТКА     ШЛЮЗ             ИНТЕРФЕЙС  СОСТОЯНИЕ${off}"
  while read -r addr lbl; do
    [[ -z "$addr" ]] && continue
    read -r rgw riface <<< "$(_tools_route_of "$addr")"
    case "$riface" in
      utun*|tun*|tap*|ppp*) state="${warn}идёт в туннель${off}" ;;
      *) if [[ -n "$gw" && "$rgw" != "-" && "$rgw" != "$gw" ]]; then
           state="${bad}шлюз устарел, нужен tools route up${off}"
         elif [[ "$rgw" == "$gw" ]]; then
           state="${label}в обход${off}"
         else
           state="${dim}без своего маршрута${off}"
         fi ;;
    esac
    if [[ -n "$probe" ]]; then
      if nc -z -G "$TOOLS_PROBE_TIMEOUT" -w "$TOOLS_PROBE_TIMEOUT" "$addr" "$TOOLS_SSH_PORT" >/dev/null 2>&1; then
        state+="  ${label}порт ${TOOLS_SSH_PORT} отвечает${off}"
      else
        state+="  ${bad}порт ${TOOLS_SSH_PORT} молчит${off}"
      fi
    fi
    print -P "${(r:16:)addr} ${(r:11:)lbl} ${(r:16:)rgw} ${(r:10:)riface} ${state}"
  done <<< "$(_tools_hosts)"
}

_tools_route_up() {
  local label dim warn bad info off; _tools_colors
  local device gw addr rgw riface addrs lbl
  addrs=$(_tools_collect "$@") || return 1
  device=$(_tools_phys_iface) || { print -P "${bad}активный физический интерфейс не найден${off}"; return 1 }
  gw=$(_tools_iface_gateway "$device") || { print -P "${bad}шлюз интерфейса ${device} не определён${off}"; return 1 }
  print -P "${dim}через${off} ${device} ${dim}шлюз${off} ${gw}"
  for addr in ${(f)addrs}; do
    read -r rgw riface <<< "$(_tools_route_of "$addr")"
    if [[ "$rgw" == "$gw" && "$riface" == "$device" ]]; then
      print -P "${dim}${addr}: уже в обход${off}"
      continue
    fi
    _tools_sudo_route delete -host "$addr"
    if _tools_sudo_route add -host "$addr" "$gw"; then
      lbl=$(_tools_label_of "$addr")
      print -P "${label}${addr}: маршрут заведён${off}${lbl:+ ${dim}${lbl}${off}}"
    else
      print -P "${bad}${addr}: завести не удалось${off}"
    fi
  done
}

_tools_route_down() {
  local label dim warn bad info off; _tools_colors
  local addr addrs
  addrs=$(_tools_collect "$@") || return 1
  for addr in ${(f)addrs}; do
    if _tools_sudo_route delete -host "$addr"; then
      print -P "${label}${addr}: маршрут снят${off}"
    else
      print -P "${dim}${addr}: маршрута не было${off}"
    fi
  done
}

# Все host-маршруты таблицы, не только из списка.
_tools_route_table() {
  local label dim warn bad info off; _tools_colors
  print -P "${dim}host-маршруты в таблице (netstat -rn):${off}"
  netstat -rn -f inet | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $3 ~ /H/ && $3 ~ /S/ { printf "%-16s %-16s %s\n", $1, $2, $4 }'
}

tools_route() {
  local cmd="${1:-status}"; (( $# > 0 )) && shift
  case "$cmd" in
    status|"") _tools_route_status "" ;;
    check) _tools_route_status 1 ;;
    up|add) _tools_route_up "$@" ;;
    down|del|delete) _tools_route_down "$@" ;;
    list|ls) print -P "%F{8}список: ${TOOLS_HOSTS}%f"; _tools_hosts ;;
    table) _tools_route_table ;;
    *) print -P "%F{red}tools route: неизвестная команда ${cmd}%f"; tools_help route; return 1 ;;
  esac
}

tools_help_add маршруты "tools route" "состояние маршрутов в обход VPN"
tools_help_add маршруты "tools route check" "то же плюс проверка порта ${TOOLS_SSH_PORT}"
tools_help_add маршруты "tools route up [адрес...]" "завести маршруты (sudo), без адресов весь список"
tools_help_add маршруты "tools route down [адрес...]" "снять маршруты (sudo)"
tools_help_add маршруты "tools route list" "список адресов из tools.hosts"
tools_help_add маршруты "tools route table" "все host-маршруты таблицы"
