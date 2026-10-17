# tools db: клиент, дамп и восстановление базы проекта по его .env.

TOOLS_DUMPS="${TOOLS_DUMPS:-$HOME/Dev/data/db-dumps}"

_tools_confirm() {
  [[ -n "$TOOLS_DRY_RUN" ]] && return 0
  local answer
  read -q "answer?$1 [y/N] " || { print; return 1 }
  print
}

# Параметры базы проекта в глобальные db_*; пароль остаётся в переменной, не печатается.
_tools_db_load() {
  local dir="$1" file="$1/.env"
  db_conn=$(_tools_env_get "$file" DB_CONNECTION) || db_conn=sqlite
  db_host=$(_tools_env_get "$file" DB_HOST); db_host=${db_host:-127.0.0.1}
  db_port=$(_tools_env_get "$file" DB_PORT)
  db_name=$(_tools_env_get "$file" DB_DATABASE)
  db_user=$(_tools_env_get "$file" DB_USERNAME); db_user=${db_user:-root}
  db_pass=$(_tools_env_get "$file" DB_PASSWORD)
  case "$db_conn" in
    mysql|mariadb) db_port=${db_port:-3306} ;;
    pgsql) db_port=${db_port:-5432} ;;
    sqlite) [[ -n "$db_name" && "$db_name" != /* ]] && db_name="$dir/$db_name"
            db_name=${db_name:-$dir/database/database.sqlite} ;;
  esac
  [[ -n "$db_name" ]]
}

# Команда клиента или дампа; пароль уходит через окружение процесса.
_tools_db_exec() {
  local mode="$1"; shift
  local cmd
  case "$db_conn" in
    mysql|mariadb)
      case "$mode" in
        shell) cmd=(mysql -h "$db_host" -P "$db_port" -u "$db_user" "$db_name") ;;
        dump) cmd=(mysqldump --single-transaction --quick -h "$db_host" -P "$db_port" -u "$db_user" "$db_name") ;;
        restore) cmd=(mysql -h "$db_host" -P "$db_port" -u "$db_user" "$db_name") ;;
      esac
      [[ -n "$TOOLS_DRY_RUN" ]] && { print "  MYSQL_PWD=*** ${cmd[*]}"; return 0 }
      MYSQL_PWD="$db_pass" "${cmd[@]}" "$@" ;;
    pgsql)
      case "$mode" in
        shell) cmd=(psql -h "$db_host" -p "$db_port" -U "$db_user" "$db_name") ;;
        dump) cmd=(pg_dump --no-owner --no-privileges -h "$db_host" -p "$db_port" -U "$db_user" "$db_name") ;;
        restore) cmd=(psql -q -h "$db_host" -p "$db_port" -U "$db_user" "$db_name") ;;
      esac
      [[ -n "$TOOLS_DRY_RUN" ]] && { print "  PGPASSWORD=*** ${cmd[*]}"; return 0 }
      PGPASSWORD="$db_pass" "${cmd[@]}" "$@" ;;
    sqlite)
      case "$mode" in
        shell) cmd=(sqlite3 "$db_name") ;;
        dump) cmd=(sqlite3 "$db_name" .dump) ;;
        restore) cmd=(sqlite3 "$db_name") ;;
      esac
      [[ -n "$TOOLS_DRY_RUN" ]] && { print "  ${cmd[*]}"; return 0 }
      "${cmd[@]}" "$@" ;;
    *) print -P "%F{red}неизвестный DB_CONNECTION: ${db_conn}%f" >&2; return 1 ;;
  esac
}

# tools db [имя] [dump|restore <файл>]
tools_db() {
  local label dim warn bad info off; _tools_colors
  local name dir action file db_conn db_host db_port db_name db_user db_pass
  # Первый аргумент может быть действием, тогда проект берётся из текущей папки.
  case "$1" in dump|restore) action="$1"; shift ;; esac
  if [[ -z "$action" ]]; then
    name=$(_tools_project_arg "$1") || return 1
    case "$2" in dump|restore) action="$2"; shift 2 ;; esac
  else
    name=$(_tools_project_arg) || return 1
  fi
  dir=$(_tools_project_dir "$name") || return 1
  _tools_db_load "$dir" || { print -P "${bad}${name}: в .env нет DB_DATABASE${off}"; return 1 }
  if [[ "$db_conn" == sqlite ]]; then print -P "${label}${name}${off}  ${dim}sqlite ${db_name}${off}"
  else print -P "${label}${name}${off}  ${dim}${db_conn} ${db_name} @ ${db_host}:${db_port}${off}"; fi
  case "${action:-shell}" in
    shell) _tools_db_exec shell ;;
    dump)
      mkdir -p "$TOOLS_DUMPS"
      file="$TOOLS_DUMPS/${db_name:t}-$(date +%Y%m%d-%H%M).sql.gz"
      if [[ -n "$TOOLS_DRY_RUN" ]]; then _tools_db_exec dump; print "  | gzip > $file"; return 0; fi
      _tools_db_exec dump | gzip > "$file" && print -P "${label}дамп:${off} ${file} ($(du -h "$file" | cut -f1))" ;;
    restore)
      file="$1"
      [[ -f "$file" ]] || { print -P "${bad}укажи файл дампа: tools db restore <файл.sql[.gz]>${off}"; return 1 }
      _tools_confirm "залить ${file:t} в ${db_conn} ${db_name}, текущие данные будут перезаписаны?" || return 1
      if [[ -n "$TOOLS_DRY_RUN" ]]; then print -n "  gunzip -c $file |"; _tools_db_exec restore; return 0; fi
      if [[ "$file" == *.gz ]]; then gunzip -c "$file" | _tools_db_exec restore; else _tools_db_exec restore < "$file"; fi &&
        print -P "${label}восстановлено из${off} ${file:t}" ;;
  esac
}

tools_help_add базы "tools db [имя]" "клиент mysql, psql или sqlite по .env проекта"
tools_help_add базы "tools db [имя] dump" "дамп в ~/Dev/data/db-dumps/<база>-<дата>.sql.gz"
tools_help_add базы "tools db [имя] restore <файл>" "залить дамп с подтверждением"
