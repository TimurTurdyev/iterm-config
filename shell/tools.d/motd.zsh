# tools motd и разделы сводки: только быстрые локальные источники,
# чтобы окно открывалось без задержки.

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
  local proj; proj=$(_tools_project_here 2>/dev/null)
  if [[ -n "$proj" ]]; then
    _tools_project "$proj"
    print -P "${label}проект${off} ${proj}  ${dim}$(_tools_stack "${TOOLS_DEV}/${reply[2]}"), порт ${reply[6]}, база ${reply[7]}, деплой ${reply[5]}${off}"
  fi
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

tools_help_add сводка "tools motd [раздел...]" "сводка, как при открытии окна, плюс разделы"
tools_help_add сводка "tools ports|services|repos|procs|versions" "разделы сводки"
tools_help_add сводка "tools net [public]" "адреса, шлюз, VPN, внешний IP"
