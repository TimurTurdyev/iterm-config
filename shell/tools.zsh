# tools: швейцарский нож для терминала. Список команд: tools help.
# Сводка tools motd печатается при открытии окна профиля timcode.ru (iterm2.zsh);
# в ней только быстрые локальные источники, чтобы окно открывалось без задержки.
# Маршруты в обход VPN взяты из mercurio-infra/vpn-bypass.sh: при раздельном
# туннелировании боевые адреса уезжают в туннель, лечится host-маршрутом
# через физический шлюз. TOOLS_DRY_RUN=1 печатает команды route вместо запуска.

TOOLS_HOSTS="${TOOLS_HOSTS:-${0:A:h}/tools.hosts}"
TOOLS_SSH_PORT=22
TOOLS_PROBE_TIMEOUT=2

_tools_colors() {
  label='%F{green}' dim='%F{8}' warn='%F{yellow}' bad='%F{red}' info='%F{cyan}' off='%f'
}

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

# Кто слушает порт; tools port <n> kill завершает процесс.
tools_port() {
  local label dim warn bad info off; _tools_colors
  local port="$1" rows
  [[ -n "$port" ]] || { print -P "${bad}укажи порт: tools port 8000 [kill]${off}"; return 1 }
  rows=$(lsof +c 0 -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $2, $1 }' | sort -u)
  if [[ -z "$rows" ]]; then
    print -P "${dim}порт ${port} свободен${off}"
    return 0
  fi
  local pid proc
  while read -r pid proc; do
    print -P "${label}${port}${off}  pid ${pid}  ${proc}"
    if [[ "$2" == kill ]]; then
      kill "$pid" 2>/dev/null && print -P "  ${warn}завершён${off}" || print -P "  ${bad}не удалось завершить, попробуй sudo kill ${pid}${off}"
    fi
  done <<< "$rows"
}

# Сброс DNS-кэша macOS.
tools_dns() {
  local label dim warn bad info off; _tools_colors
  case "${1:-flush}" in
    flush)
      sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder && print -P "${label}DNS-кэш сброшен${off}" ;;
    servers)
      scutil --dns | awk '/nameserver\[/ { print $3 }' | sort -u ;;
    *) print -P "${bad}tools dns flush|servers${off}"; return 1 ;;
  esac
}

# Срок действия сертификата домена.
tools_ssl() {
  local label dim warn bad info off; _tools_colors
  local host="$1" dates not_after days
  [[ -n "$host" ]] || { print -P "${bad}укажи домен: tools ssl timcode.ru${off}"; return 1 }
  dates=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)
  [[ -n "$dates" ]] || { print -P "${bad}${host}: сертификат не получен${off}"; return 1 }
  not_after=$(print "$dates" | awk -F= '/notAfter/ { print $2 }')
  # Дата от openssl на английском, под русской локалью %b её не разберёт.
  days=$(( ($(LC_ALL=C date -j -f '%b %d %T %Y %Z' "$not_after" +%s 2>/dev/null || print 0) - $(date +%s)) / 86400 ))
  print -P "${label}${host}${off}  $(print "$dates" | awk -F= '/issuer/ { print $NF }' | sed 's/^ *//')"
  if (( days < 14 )); then
    print -P "  ${bad}истекает через ${days} дн.${off} ${dim}${not_after}${off}"
  else
    print -P "  ${label}действует ещё ${days} дн.${off} ${dim}${not_after}${off}"
  fi
}

# ---- сводка и её разделы ----
MOTD_DEV_PORTS=(80 443 3000 3306 5173 5432 6379 8000 8080 9000)

# Сервисы разработки: "метка:имя процесса" для pgrep -x.
MOTD_SERVICES=(
  postgres:postgres mariadb:mariadbd mysql:mysqld redis:redis-server
  meilisearch:meilisearch searchd:searchd nginx:nginx php-fpm:php-fpm
  orbstack:"OrbStack Helper" docker:com.docker.backend
)

MOTD_REPOS_ROOT="$HOME/Dev"
MOTD_SECTIONS=(ports services net repos procs versions)

# Слушающие TCP-порты: "порт pid процесс", по одной строке на порт.
_motd_listening() {
  lsof +c 0 -nP -iTCP -sTCP:LISTEN 2>/dev/null |
    awk 'NR > 1 { n = split($9, a, ":"); print a[n], $2, $1 }' |
    sort -un -k1,1
}

# Запущенные сервисы из MOTD_SERVICES: метки через пробел.
_motd_services_up() {
  local entry
  for entry in "${MOTD_SERVICES[@]}"; do
    pgrep -xq "${entry#*:}" && print -n "${entry%%:*} "
  done
}

_motd_docker_up() {
  pgrep -xq "OrbStack Helper" || pgrep -xq com.docker.backend
}

tools_ports() {
  emulate -L zsh
  local label dim warn bad info off; _tools_colors
  local rows port pid proc
  rows=$(_motd_listening)
  if [[ -z "$rows" ]]; then
    print -P "${dim}слушающих портов нет${off}"
  else
    print -P "${dim}PORT    PID     PROCESS${off}"
    while read -r port pid proc; do
      print -P "${label}${(r:7:)port}${off} ${(r:7:)pid} ${proc}"
    done <<< "$rows"
  fi

  local free=() p
  local busy=("${(@)${(f)rows}%% *}")
  for p in "${MOTD_DEV_PORTS[@]}"; do
    (( ${busy[(Ie)$p]} )) || free+=("$p")
  done
  print -P "${dim}свободны из частых:${off} ${free[*]:-нет}"
}

tools_services() {
  emulate -L zsh
  local label dim warn bad info off; _tools_colors
  local entry name proc pid
  for entry in "${MOTD_SERVICES[@]}"; do
    name=${entry%%:*}; proc=${entry#*:}
    pid=$(pgrep -x "$proc" | head -1)
    if [[ -n "$pid" ]]; then
      print -P "${label}${(r:12:)name}${off} up    ${dim}pid ${pid}${off}"
    else
      print -P "${dim}${(r:12:)name} down${off}"
    fi
  done
  if _motd_docker_up; then
    print -P "${label}containers${off}   $(docker ps -q 2>/dev/null | wc -l | tr -d ' ') running"
  fi
}

# tools net [public]: локальный адрес, шлюз, Wi-Fi, VPN-туннели; с public ещё и внешний IP.
tools_net() {
  emulate -L zsh
  local label dim warn bad info off; _tools_colors
  local iface gateway ip ssid i
  iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  gateway=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
  ip=$(ipconfig getifaddr "${iface:-en0}" 2>/dev/null)
  print -P "${label}local${off}    ${ip:-нет сети}  ${dim}${iface} via ${gateway}${off}"
  # SSID macOS отдаёт только приложениям с доступом к геопозиции, иначе <redacted>.
  ssid=$(ipconfig getsummary "${iface:-en0}" 2>/dev/null | awk -F': ' '/ SSID :/{print $2}')
  [[ -n "$ssid" && "$ssid" != "<redacted>" ]] && print -P "${label}wi-fi${off}    ${ssid}"
  for i in $(ifconfig -l); do
    [[ "$i" == utun* ]] || continue
    ip=$(ifconfig "$i" | awk '/inet /{print $2}')
    [[ -n "$ip" ]] && print -P "${label}vpn${off}      ${i} ${ip}"
  done
  if [[ "$1" == public ]]; then
    print -P "${label}public${off}   $(curl -fsS -m 3 https://ifconfig.me 2>/dev/null || print -P "${dim}недоступно${off}")"
  fi
}

# Репозитории под ~/Dev с незакоммиченными или неотправленными изменениями.
tools_repos() {
  emulate -L zsh
  local label dim warn bad info off; _tools_colors
  local g d changes ahead found=0
  find "$MOTD_REPOS_ROOT" -maxdepth 4 -name .git \( -type d -o -type f \) \
      -not -path "*/node_modules/*" -not -path "*/vendor/*" -not -path "*/archive/*" 2>/dev/null |
  sort | while read -r g; do
    d=${g%/.git}
    changes=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    ahead=$(git -C "$d" rev-list --count '@{u}..HEAD' 2>/dev/null || print 0)
    (( changes == 0 && ahead == 0 )) && continue
    found=1
    print -nP "${label}${d#$MOTD_REPOS_ROOT/}${off}"
    (( changes > 0 )) && print -nP "  ${warn}${changes} changes${off}"
    (( ahead > 0 )) && print -nP "  ${info}${ahead} unpushed${off}"
    print
  done
}

# Топ процессов по CPU и по памяти.
tools_procs() {
  emulate -L zsh
  local label dim warn bad info off; _tools_colors
  local n=${1:-5}
  print -P "${dim}по CPU          %%CPU  %%MEM${off}"
  ps -Aro pid=,pcpu=,pmem=,comm= | head -n "$n" | awk '{ name = $0; sub(/^ *[0-9]+ +[0-9.,]+ +[0-9.,]+ +/, "", name); n = split(name, a, "/"); printf "%-16s %5s %5s\n", substr(a[n], 1, 16), $2, $3 }'
  print -P "${dim}по памяти       %%CPU  %%MEM${off}"
  ps -Amo pid=,pcpu=,pmem=,comm= | head -n "$n" | awk '{ name = $0; sub(/^ *[0-9]+ +[0-9.,]+ +[0-9.,]+ +/, "", name); n = split(name, a, "/"); printf "%-16s %5s %5s\n", substr(a[n], 1, 16), $2, $3 }'
}

tools_versions() {
  emulate -L zsh
  local label dim warn bad info off; _tools_colors
  local v
  command -v php >/dev/null && print -P "${label}php${off}      $(php -r 'echo PHP_VERSION;' 2>/dev/null)"
  command -v composer >/dev/null && print -P "${label}composer${off} $(composer --version 2>/dev/null | awk '{print $3}')"
  command -v node >/dev/null && print -P "${label}node${off}     $(node -v 2>/dev/null)"
  command -v go >/dev/null && print -P "${label}go${off}       $(go version 2>/dev/null | awk '{print $3}')"
  command -v python3 >/dev/null && print -P "${label}python${off}   $(python3 -V 2>/dev/null | awk '{print $2}')"
  command -v psql >/dev/null && print -P "${label}psql${off}     $(psql --version 2>/dev/null | awk '{print $3}')"
  command -v docker >/dev/null && print -P "${label}docker${off}   $(docker -v 2>/dev/null | awk '{print $3}' | tr -d ,)"
}

tools_motd() {
  emulate -L zsh
  local label dim warn bad info off; _tools_colors

  # Время работы: kern.boottime -> "{ sec = 1760000000, usec = 0 } ..."
  local boot now up_d up_h up_m uptime
  boot=$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+).*/\1/')
  now=$(date +%s)
  (( up_m = (now - boot) / 60, up_d = up_m / 1440, up_h = up_m % 1440 / 60, up_m %= 60 ))
  if (( up_d > 0 )); then uptime="${up_d}d ${up_h}h"; else uptime="${up_h}h ${up_m}m"; fi

  local load; load=$(LC_ALL=C sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1" "$2" "$3}')

  # Память: занято = active + wired + compressed, в гигабайтах.
  local mem_total mem_used page
  mem_total=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
  page=$(sysctl -n hw.pagesize)
  mem_used=$(vm_stat | awk -v p="$page" '
    /Pages active|Pages wired|occupied by compressor/ { gsub("\\.", "", $NF); n += $NF }
    END { printf "%.0f", n * p / 1024 / 1024 / 1024 }')

  local disk; disk=$(df -H /System/Volumes/Data | awk 'NR==2 {print $3"/"$2" ("$5")"}')

  local batt
  batt=$(pmset -g batt 2>/dev/null | awk -F'[;\t]' 'NR==2 {gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); print $2" "$3}')

  local docker="off"
  _motd_docker_up && docker="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ') running"

  local git_line=""
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local branch changes
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    changes=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    git_line="${label}git${off} ${branch}"
    (( changes > 0 )) && git_line+=" ${warn}${changes} changes${off}"
  fi

  local listening=("${(@)${(f)$(_motd_listening)}%% *}") ports_line
  ports_line="${#listening} listening"
  (( ${#listening} > 0 )) && ports_line+="  ${dim}${listening[1,12]}${off}"
  (( ${#listening} > 12 )) && ports_line+="${dim} ...${off}"

  local up_services; up_services=$(_motd_services_up)

  local iface ip vpn=() i
  iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  ip=$(ipconfig getifaddr "${iface:-en0}" 2>/dev/null)
  for i in $(ifconfig -l); do
    [[ "$i" == utun* ]] && ifconfig "$i" | grep -q "inet " && vpn+=("$i")
  done

  # % внутри значений экранируем: для print -P это начало prompt-последовательности.
  disk=${disk//\%/%%}; batt=${batt//\%/%%}
  print -P "${label}${USER}@${HOST%%.*}${off}  macOS $(sw_vers -productVersion)  $(date '+%a %d %b, %H:%M')  ${dim}up ${uptime}${off}"
  print -P "${label}load${off} ${load}   ${label}mem${off} ${mem_used}/${mem_total} GB   ${label}disk${off} ${disk}   ${label}batt${off} ${batt:-n/a}"
  print -P "${label}net${off} ${ip:-нет сети} ${dim}${iface}${off}${vpn:+   ${label}vpn${off} ${vpn[*]}}   ${label}docker${off} ${docker}   ${git_line}"
  print -P "${label}services${off} ${${up_services% }:-нет запущенных}"
  print -P "${label}ports${off} ${ports_line}"
  print -P "${dim}Подсказка: tools motd повторит сводку; разделы: tools ${(j:|:)MOTD_SECTIONS}; tools help${off}"

  local section
  for section in "$@"; do
    (( ${MOTD_SECTIONS[(Ie)$section]} )) || { print -P "${warn}нет раздела ${section}${off}"; continue }
    print -P "\n${dim}# ${section}${off}"
    "tools_$section"
  done
}

tools_help() {
  local label dim warn bad info off; _tools_colors
  local topic="$1"
  if [[ "$topic" == route || -z "$topic" ]]; then
    print -P "${label}tools route${off}                 состояние маршрутов в обход VPN"
    print -P "${label}tools route check${off}           то же плюс проверка порта ${TOOLS_SSH_PORT}"
    print -P "${label}tools route up [адрес...]${off}   завести маршруты (sudo), без адресов весь список"
    print -P "${label}tools route down [адрес...]${off} снять маршруты (sudo)"
    print -P "${label}tools route list${off}            список адресов, файл ${dim}${TOOLS_HOSTS}${off}"
    print -P "${label}tools route table${off}           все host-маршруты таблицы"
  fi
  [[ -n "$topic" ]] && return 0
  print -P "${label}tools port <n> [kill]${off}       кто слушает порт, при kill завершить"
  print -P "${label}tools dns flush|servers${off}     сбросить DNS-кэш (sudo) или показать серверы"
  print -P "${label}tools ssl <домен>${off}           срок действия сертификата"
  print -P "${label}tools net [public]${off}          адреса, шлюз, VPN, внешний IP"
  print -P "${label}tools motd [раздел...]${off}      сводка, как при открытии окна, плюс разделы"
  print -P "${label}tools ports|services|repos|procs|versions${off}  разделы сводки"
  print -P "${dim}адрес в route: IP, пометка из списка или доменное имя; TOOLS_DRY_RUN=1 покажет команды${off}"
}

tools() {
  emulate -L zsh
  local cmd="${1:-help}"; (( $# > 0 )) && shift
  case "$cmd" in
    route|routes) tools_route "$@" ;;
    port) tools_port "$@" ;;
    dns) tools_dns "$@" ;;
    ssl|cert) tools_ssl "$@" ;;
    net|ports|services|repos|procs|versions|motd) "tools_$cmd" "$@" ;;
    help|-h|--help) tools_help "$@" ;;
    *) print -P "%F{red}tools: неизвестная команда ${cmd}%f"; tools_help; return 1 ;;
  esac
}

# Короткое имя для сводки: так её зовёт iterm2.zsh при открытии окна.
alias motd='tools motd'
