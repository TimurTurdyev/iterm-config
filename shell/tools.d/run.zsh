# tools serve, env, svc, php: локальный запуск проектов и сервисы разработки.

TOOLS_BREW_SERVICES=(mariadb postgresql@18 meilisearch manticoresearch redis memcached)
TOOLS_ENV_KEYS=(APP_URL APP_ENV DB_CONNECTION DB_HOST DB_PORT DB_DATABASE DB_USERNAME MEILISEARCH_HOST REDIS_HOST CACHE_STORE QUEUE_CONNECTION)

# Значение ключа из .env: последнее вхождение, без кавычек и хвостового комментария.
_tools_env_get() {
  setopt localoptions extendedglob
  local file="$1" key="$2" line val
  [[ -f "$file" ]] || return 1
  line=$(grep -E "^(export[[:space:]]+)?${key}=" "$file" 2>/dev/null | tail -1)
  [[ -n "$line" ]] || return 1
  val=${line#*=}; val=${val%$'\r'}
  if [[ "$val" == \"* ]]; then
    val=${val[2,-1]}; val=${val%%\"*}
  elif [[ "$val" == \'* ]]; then
    val=${val[2,-1]}; val=${val%%\'*}
  else
    val=${val%%[[:space:]]#\#*}
    val=${val%%[[:space:]]#}
  fi
  print -r -- "$val"
}

# Папка проекта по имени или текущей папке.
_tools_project_dir() {
  local name; name=$(_tools_project_arg "$1") || return 1
  _tools_project "$name"
  print "${TOOLS_DEV}/${reply[2]}"
}

# Порт проекта: реестр, затем APP_URL из .env, иначе 8000.
_tools_project_port() {
  local name="$1" dir="$2" port url
  _tools_project "$name" && port=${reply[6]}
  if [[ -z "$port" || "$port" == "-" ]]; then
    url=$(_tools_env_get "$dir/.env" APP_URL)
    port=${url##*:}; [[ "$port" == <-> ]] || port=""
  fi
  print "${port:-8000}"
}

_tools_make_has() { [[ -f "$1/Makefile" ]] && grep -qE "^$2:" "$1/Makefile"; }
_tools_json_has_script() { [[ -f "$1" ]] && grep -qE "\"$2\"[[:space:]]*:" "$1"; }

_tools_run() {
  local label dim warn bad info off; _tools_colors
  print -P "${dim}\$ $*${off}"
  [[ -n "$TOOLS_DRY_RUN" ]] && return 0
  eval "$*"
}

# tools serve [имя] [порт]: запустить проект по стеку в текущем терминале.
tools_serve() {
  local label dim warn bad info off; _tools_colors
  local name dir port stack busy
  name=$(_tools_project_arg "$1") || return 1
  dir=$(_tools_project_dir "$name") || return 1
  port=${2:-$(_tools_project_port "$name" "$dir")}
  stack=$(_tools_stack "$dir")
  busy=$(lsof +c 0 -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $1 " (pid " $2 ")"; exit }')
  if [[ -n "$busy" ]]; then
    print -P "${bad}порт ${port} занят:${off} ${busy}  ${dim}tools port ${port} kill${off}"
    return 1
  fi
  print -P "${label}${name}${off}  ${dim}${stack}, порт ${port}, ${dir}${off}"
  cd "$dir" || return 1
  case "$stack" in
    laravel)
      if _tools_json_has_script "$dir/composer.json" dev; then
        _tools_run "SERVER_PORT=$port composer dev"
      else
        _tools_json_has_script "$dir/package.json" dev && _tools_run "npm run dev &"
        _tools_run "php artisan serve --port=$port"
      fi ;;
    vitepress|node)
      if _tools_make_has "$dir" dev; then _tools_run "make dev"; else _tools_run "npm run dev -- --port $port"; fi ;;
    go)
      if _tools_make_has "$dir" dev; then _tools_run "make dev"; else _tools_run "go run ."; fi ;;
    python)
      [[ -d "$dir/.venv" ]] && _tools_run "source .venv/bin/activate"
      [[ -d "$dir/venv" ]] && _tools_run "source venv/bin/activate"
      if _tools_make_has "$dir" dev; then _tools_run "make dev"
      elif [[ -f "$dir/server.py" ]]; then _tools_run "python server.py"
      elif [[ -f "$dir/main.py" ]]; then _tools_run "python main.py"
      else print -P "${warn}не знаю, чем запускать: смотри README в ${dir}${off}"; fi ;;
    *)
      if _tools_make_has "$dir" dev; then _tools_run "make dev"
      else print -P "${warn}стек не определён, цели dev в Makefile нет${off}"; return 1; fi ;;
  esac
}

# tools env [имя]: безопасная выжимка .env без паролей, сверка с реестром.
tools_env() {
  local label dim warn bad info off; _tools_colors
  local name dir key val file
  name=$(_tools_project_arg "$1") || return 1
  dir=$(_tools_project_dir "$name") || return 1
  file="$dir/.env"
  [[ -f "$file" ]] || { print -P "${dim}${name}: .env нет${off}"; return 0 }
  print -P "${label}${name}${off}  ${dim}${file}${off}"
  for key in "${TOOLS_ENV_KEYS[@]}"; do
    val=$(_tools_env_get "$file" "$key") || continue
    print -P "${label}${(r:18:)key}${off} ${val}"
  done
  _tools_project "$name"
  local reg_port="${reply[6]}" reg_db="${reply[7]}" env_port env_db
  env_port=$(_tools_project_port "$name" "$dir")
  env_db=$(_tools_env_get "$file" DB_DATABASE)
  [[ "$reg_db" != "-" && -n "$env_db" && "${reg_db#*:}" != "$env_db" ]] &&
    print -P "${warn}база в реестре ${reg_db#*:}, в .env ${env_db}${off}"
  val=$(_tools_env_get "$file" APP_URL); val=${val##*:}; [[ "$val" == <-> ]] || val=""
  [[ "$reg_port" != "-" && -n "$val" && "$reg_port" != "$val" ]] &&
    print -P "${warn}порт в реестре ${reg_port}, в APP_URL ${val}${off}"
  return 0
}

# tools svc [start|stop|restart|logs <имя>]: сервисы brew для разработки.
tools_svc() {
  local label dim warn bad info off; _tools_colors
  local cmd="${1:-status}" name="$2" prefix
  case "$cmd" in
    status|"")
      brew services list 2>/dev/null | awk -v want=" ${TOOLS_BREW_SERVICES[*]} " '
        NR > 1 && index(want, " " $1 " ") { printf "%-16s %s\n", $1, $2 }' |
      while read -r name state; do
        if [[ "$state" == started ]]; then print -P "${label}${(r:16:)name}${off} ${state}"
        else print -P "${dim}${(r:16:)name} ${state}${off}"; fi
      done ;;
    start|stop|restart)
      [[ -n "$name" ]] || { print -P "${bad}tools svc ${cmd} <имя>${off}"; return 1 }
      _tools_run "brew services $cmd $name" ;;
    logs)
      [[ -n "$name" ]] || { print -P "${bad}tools svc logs <имя>${off}"; return 1 }
      prefix=$(brew --prefix)
      local logs=("$prefix"/var/log/${name%%@*}*.log(N) "$prefix"/var/log/${name%%@*}/*.log(N) "$prefix"/var/mysql/$(hostname -s)*.err(N))
      [[ "$name" == mariadb || "$name" == mysql ]] || logs=(${logs:#*/var/mysql/*})
      (( ${#logs} )) || { print -P "${dim}логов ${name} в ${prefix}/var/log нет${off}"; return 1 }
      _tools_run "tail -n 50 -f ${(q)logs[*]}" ;;
    *) print -P "${bad}tools svc [start|stop|restart|logs <имя>]${off}"; return 1 ;;
  esac
}

# tools php [версия] [--global]: показать или переключить PHP из brew.
tools_php() {
  local label dim warn bad info off; _tools_colors
  local want="$1" d ver current
  current=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
  if [[ -z "$want" ]]; then
    for d in /opt/homebrew/opt/php@*(N); do
      ver=${d##*php@}
      if [[ "$ver" == "$current" ]]; then print -P "${label}${ver}${off}  ${dim}активная, $(command -v php)${off}"
      else print -P "${dim}${ver}${off}"; fi
    done
    print -P "${dim}tools php 8.3 переключит в этой оболочке, --global через brew link${off}"
    return 0
  fi
  d="/opt/homebrew/opt/php@${want}"
  [[ -d "$d" ]] || { print -P "${bad}php@${want} в brew нет: brew install php@${want}${off}"; return 1 }
  if [[ "$2" == "--global" ]]; then
    _tools_run "brew unlink php >/dev/null; brew link --overwrite --force php@${want}"
  else
    [[ -n "$TOOLS_DRY_RUN" ]] && { print "  PATH=$d/bin:$d/sbin:\$PATH"; return 0 }
    path=("$d/bin" "$d/sbin" ${path:#/opt/homebrew/opt/php@*/*})
    print -P "${label}php ${want}${off} в этой оболочке: $(php -v | head -1)"
  fi
}

tools_help_add запуск "tools serve [имя] [порт]" "запустить проект по стеку, проверив порт"
tools_help_add запуск "tools env [имя]" "выжимка .env без паролей, сверка с реестром"
tools_help_add запуск "tools svc [start|stop|restart|logs <имя>]" "сервисы brew: mariadb, postgres, meilisearch, manticore"
tools_help_add запуск "tools php [версия] [--global]" "показать или переключить PHP из brew"
