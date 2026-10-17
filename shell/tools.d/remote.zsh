# tools ssh, deploy, pull: удалённые серверы по алиасам ssh и реестру.

TOOLS_SSH_CONFIG="${TOOLS_SSH_CONFIG:-$HOME/.ssh/config}"

_tools_ssh_aliases() {
  [[ -f "$TOOLS_SSH_CONFIG" ]] || return 0
  awk '$1 == "Host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?]/) print $i }' "$TOOLS_SSH_CONFIG"
}

_tools_ssh_hostname() { ssh -G "$1" 2>/dev/null | awk '/^hostname / { print $2; exit }'; }

# IPv4 хоста алиаса: сам адрес или через DNS.
_tools_ssh_ip() {
  local host; host=$(_tools_ssh_hostname "$1")
  [[ -n "$host" ]] || return 1
  [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { print "$host"; return 0 }
  dscacheutil -q host -a name "$host" 2>/dev/null | awk '/^ip_address:/ { print $2; exit }'
}

# Алиас ssh из аргумента: алиас как есть или поле реестра для имени проекта.
_tools_ssh_alias() {
  local want="$1"
  if _tools_ssh_aliases | grep -qx "$want"; then print "$want"; return 0; fi
  if _tools_project "$want"; then
    [[ "${reply[3]}" != "-" ]] && { print "${reply[3]}"; return 0 }
    print -P "%F{red}у проекта ${want} нет ssh-алиаса в реестре%f" >&2; return 1
  fi
  print -P "%F{red}нет алиаса ${want} в ${TOOLS_SSH_CONFIG} и проекта с таким именем%f" >&2
  return 1
}

# Предупреждение, если адрес уходит в туннель или на устаревший шлюз.
_tools_ssh_route_hint() {
  local label dim warn bad info off; _tools_colors
  local ip="$1" rgw riface device gw
  read -r rgw riface <<< "$(_tools_route_of "$ip")"
  case "$riface" in
    utun*|tun*|ppp*) print -P "${warn}${ip} идёт в туннель ${riface}: если не отвечает, tools route up ${ip}${off}" ;;
    *) device=$(_tools_phys_iface) && gw=$(_tools_iface_gateway "$device")
       [[ -n "$gw" && "$rgw" != "-" && "$rgw" != "$gw" && "$riface" == "$device" ]] &&
         print -P "${bad}${ip}: маршрут на старый шлюз ${rgw}, нужен tools route up ${ip}${off}" ;;
  esac
  return 0
}

_tools_ssh_list() {
  local label dim warn bad info off; _tools_colors
  local alias host user projects
  for alias in $(_tools_ssh_aliases); do
    [[ "$alias" == github.com || "$alias" == git.* ]] && continue
    host=$(_tools_ssh_hostname "$alias"); user=$(ssh -G "$alias" 2>/dev/null | awk '/^user / { print $2; exit }')
    projects=$(_tools_registry | awk -F'\t' -v a="$alias" '$3 == a { printf "%s ", $1 }')
    local target="${user}@${host}"
    print -P "${label}${(r:24:)alias}${off} ${(r:34:)target} ${dim}${projects}${off}"
  done
}

# tools ssh <алиас|проект> [аргументы ssh]
tools_ssh() {
  local alias ip
  [[ "$1" == list || -z "$1" ]] && { _tools_ssh_list; return 0 }
  alias=$(_tools_ssh_alias "$1") || return 1; shift
  ip=$(_tools_ssh_ip "$alias") && _tools_ssh_route_hint "$ip"
  [[ -n "$TOOLS_DRY_RUN" ]] && { print "  ssh $alias $*"; return 0 }
  ssh "$alias" "$@"
}

# tools deploy [имя] [stage] [-y]: команда деплоя по полю реестра, с подтверждением.
tools_deploy() {
  local label dim warn bad info off; _tools_colors
  local name dir spec kind arg stage recipe yes="" cmd workdir override="" a
  local args=()
  for a in "$@"; do [[ "$a" == -y ]] && yes=1 || args+=("$a"); done
  override="${args[2]}"
  name=$(_tools_project_arg "${args[1]}") || return 1
  _tools_project "$name"
  dir="${TOOLS_DEV}/${reply[2]}"; spec="${reply[5]}"; workdir="$dir"
  kind=${spec%%:*}; arg=${spec#*:}
  case "$kind" in
    -|"") print -P "${dim}${name}: деплой не описан в реестре (поле 5 в tools.projects)${off}"; return 1 ;;
    ci) print -P "${label}${name}${off}: деплой через CI после push в $(git -C "$dir" remote get-url origin 2>/dev/null || print 'remote')"
        print -P "${dim}ветка $(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null), ahead $(git -C "$dir" rev-list --count '@{u}..HEAD' 2>/dev/null || print '?')${off}"
        return 0 ;;
    make) cmd="make $arg" ;;
    remote-make)
      [[ "${reply[3]}" != "-" && "${reply[4]}" != "-" ]] || { print -P "${bad}${name}: для remote-make нужны ssh-алиас и удалённый путь${off}"; return 1 }
      cmd="ssh ${reply[3]} 'cd ${reply[4]} && make $arg'" ;;
    dep)
      # dep:<репо с рецептами от ~/Dev>:<рецепт внутри репо>:<stage>; stage можно передать аргументом.
      local parts=("${(@s/:/)arg}")
      workdir="${TOOLS_DEV}/${parts[1]}"; recipe="${parts[2]}"; stage="${override:-${parts[3]}}"
      [[ -f "$workdir/$recipe" ]] || { print -P "${bad}рецепт ${workdir}/${recipe} не найден${off}"; return 1 }
      [[ -n "$stage" && "$stage" != "-" ]] || { print -P "${bad}${name}: укажи stage: tools deploy ${name} <stage>${off}"; return 1 }
      cmd="dep -f $recipe deploy $stage" ;;
    ansible) cmd="ansible-playbook -i $arg site.yml" ;;
    cmd) cmd="$arg" ;;
    *) print -P "${bad}${name}: неизвестный вид деплоя ${kind}${off}"; return 1 ;;
  esac
  print -P "${label}${name}${off}  ${dim}в ${workdir}${off}"
  print -P "${dim}\$ ${cmd}${off}"
  [[ -n "$yes" ]] || _tools_confirm "выполнить?" || return 1
  [[ -n "$TOOLS_DRY_RUN" ]] && return 0
  ( cd "$workdir" && eval "$cmd" )
}

# tools pull [имя] db|storage [--apply]: забрать дамп или картинки с сервера проекта.
tools_pull() {
  local label dim warn bad info off; _tools_colors
  local name dir what apply="" alias remote file cmd
  for a in "$@"; do case "$a" in --apply) apply=1 ;; db|storage) what="$a" ;; *) name="$a" ;; esac; done
  [[ -n "$what" ]] || { print -P "${bad}tools pull [имя] db|storage [--apply]${off}"; return 1 }
  name=$(_tools_project_arg "$name") || return 1
  _tools_project "$name"; dir="${TOOLS_DEV}/${reply[2]}"; alias="${reply[3]}"; remote="${reply[4]}"
  [[ "$alias" != "-" && "$remote" != "-" ]] || { print -P "${bad}${name}: нужны ssh-алиас и удалённый путь в реестре${off}"; return 1 }
  case "$what" in
    storage)
      local dry=" --dry-run"; [[ -n "$apply" ]] && dry=""
      cmd="rsync -avh --partial --timeout=600${dry} ${alias}:${remote}/storage/app/public/ ${dir}/storage/app/public/"
      print -P "${label}${name}${off} storage ${dim}${apply:-dry-run, добавь --apply}${off}"
      print -P "${dim}\$ ${cmd}${off}"
      [[ -n "$TOOLS_DRY_RUN" ]] && return 0
      eval "$cmd" ;;
    db)
      mkdir -p "$TOOLS_DUMPS"
      file="$TOOLS_DUMPS/${name}-prod-$(date +%Y%m%d-%H%M).sql.gz"
      # Параметры базы читаются из .env на сервере, пароль по сети не возвращается.
      cmd="ssh ${alias} 'cd ${remote} && eval \"\$(grep -E \"^DB_(CONNECTION|HOST|PORT|DATABASE|USERNAME|PASSWORD)=\" .env | sed \"s/^/export /\")\" && if [ \"\$DB_CONNECTION\" = pgsql ]; then PGPASSWORD=\"\$DB_PASSWORD\" pg_dump --no-owner -h \"\$DB_HOST\" -p \"\${DB_PORT:-5432}\" -U \"\$DB_USERNAME\" \"\$DB_DATABASE\"; else MYSQL_PWD=\"\$DB_PASSWORD\" mysqldump --single-transaction --quick -h \"\$DB_HOST\" -P \"\${DB_PORT:-3306}\" -u \"\$DB_USERNAME\" \"\$DB_DATABASE\"; fi | gzip' > ${file}"
      print -P "${label}${name}${off} db ${dim}-> ${file}${off}"
      print -P "${dim}\$ ${cmd}${off}"
      [[ -n "$apply" ]] || { print -P "${dim}dry-run, добавь --apply${off}"; return 0 }
      [[ -n "$TOOLS_DRY_RUN" ]] && return 0
      eval "$cmd" && print -P "${label}дамп:${off} ${file} ($(du -h "$file" | cut -f1))" ;;
  esac
}

tools_help_add удалённое "tools ssh [list]" "алиасы ssh с проектами"
tools_help_add удалённое "tools ssh <алиас|проект> [args]" "ssh с проверкой маршрута до адреса"
tools_help_add удалённое "tools deploy [имя] [stage] [-y]" "команда деплоя из реестра, с подтверждением"
tools_help_add удалённое "tools pull [имя] db|storage [--apply]" "дамп базы или картинки с сервера проекта"
