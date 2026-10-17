# tools proj, go, open: реестр проектов ~/Dev (tools.projects) и навигация.

TOOLS_DEV="${TOOLS_DEV:-$HOME/Dev}"
TOOLS_PROJECTS="${TOOLS_PROJECTS:-${TOOLS_DIR}/tools.projects}"

# Строки реестра без комментариев: имя, путь, ssh, удалённый путь, деплой, порт, база.
_tools_registry() {
  [[ -f "$TOOLS_PROJECTS" ]] || return 0
  awk -F'\t' '!/^#/ && NF >= 2 { for (i = NF + 1; i <= 7; i++) $i = "-"; print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 }' OFS='\t' "$TOOLS_PROJECTS"
}

# Поля проекта по имени в массив reply: name path ssh remote deploy port db.
_tools_project() {
  local line
  line=$(_tools_registry | awk -F'\t' -v n="$1" '$1 == n { print; exit }')
  [[ -n "$line" ]] || return 1
  reply=("${(@s:	:)line}")
}

_tools_project_names() { _tools_registry | cut -f1; }

# Имя проекта для текущей папки: самая длинная подходящая строка реестра.
_tools_project_here() {
  local here="${PWD:A}" name pdir best="" best_len=0
  while IFS=$'\t' read -r name pdir _; do
    pdir="${TOOLS_DEV}/${pdir}"; pdir="${pdir:A}"
    [[ "$here" == "$pdir" || "$here" == "$pdir"/* ]] || continue
    (( ${#pdir} > best_len )) && { best=$name; best_len=${#pdir} }
  done <<< "$(_tools_registry)"
  [[ -n "$best" ]] && print "$best"
}

# Имя проекта из аргумента или текущей папки; иначе ошибка.
_tools_project_arg() {
  local name="$1"
  [[ -n "$name" ]] || name=$(_tools_project_here)
  [[ -n "$name" ]] || { print -P "%F{red}укажи проект или зайди в его папку: tools proj list%f" >&2; return 1 }
  _tools_project "$name" || { print -P "%F{red}нет проекта ${name} в реестре: tools proj list%f" >&2; return 1 }
  print "$name"
}

# Стек по файлам в папке проекта.
_tools_stack() {
  local d="$1"
  if [[ -f "$d/artisan" ]]; then print laravel
  elif [[ -d "$d/.vitepress" ]]; then print vitepress
  elif [[ -f "$d/go.mod" ]]; then print go
  elif [[ -f "$d/pyproject.toml" || -f "$d/requirements.txt" || -d "$d/venv" || -d "$d/.venv" ]]; then print python
  elif [[ -f "$d/composer.json" ]]; then print php
  elif [[ -f "$d/package.json" ]]; then print node
  elif [[ -f "$d/Makefile" ]]; then print make
  else print other
  fi
}

_tools_proj_list() {
  local label dim warn bad info off; _tools_colors
  local group="$1" name pdir ssh remote deploy port db
  print -P "${dim}ИМЯ                      ПУТЬ                                       ПОРТ   БАЗА                   ДЕПЛОЙ${off}"
  while IFS=$'\t' read -r name pdir ssh remote deploy port db; do
    [[ -n "$group" && "$pdir" != "$group"/* && "$name" != "$group"* ]] && continue
    print -P "${label}${(r:24:)name}${off} ${(r:42:)pdir} ${(r:6:)port} ${(r:22:)db} ${dim}${deploy}${off}"
  done <<< "$(_tools_registry)"
}

_tools_proj_info() {
  local label dim warn bad info off; _tools_colors
  local name; name=$(_tools_project_arg "$1") || return 1
  _tools_project "$name"
  local dir="${TOOLS_DEV}/${reply[2]}"
  print -P "${label}${name}${off}  ${dim}$(_tools_stack "$dir")${off}"
  print -P "${label}путь${off}     ${dir}"
  print -P "${label}ssh${off}      ${reply[3]}"
  [[ "${reply[4]}" != "-" ]] && print -P "${label}удалённо${off} ${reply[4]}"
  print -P "${label}деплой${off}   ${reply[5]}"
  print -P "${label}порт${off}     ${reply[6]}   ${label}база${off} ${reply[7]}"
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local branch changes
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    changes=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    print -P "${label}git${off}      ${branch}${${changes:#0}:+  ${warn}${changes} changes${off}}"
  fi
}

# Клоны под ~/Dev без строки в реестре.
_tools_proj_scan() {
  local label dim warn bad info off; _tools_colors
  local g d rel known
  known=$(_tools_registry | cut -f2)
  find "$TOOLS_DEV" -maxdepth 5 -name .git \( -type d -o -type f \) \
      -not -path "*/node_modules/*" -not -path "*/vendor/*" -not -path "*/archive/*" -not -path "*/sandbox/*" 2>/dev/null |
  sort | while read -r g; do
    d=${g%/.git}; rel=${d#$TOOLS_DEV/}
    print -r -- "$known" | grep -qx "$rel" && continue
    print -P "${warn}${rel}${off}  ${dim}$(_tools_stack "$d")${off}"
  done
}

tools_proj() {
  local cmd="${1:-list}"; (( $# > 0 )) && shift
  case "$cmd" in
    list|ls) _tools_proj_list "$@" ;;
    info|show) _tools_proj_info "$@" ;;
    scan) _tools_proj_scan ;;
    here) _tools_project_here || { print -P "%F{8}не в проекте реестра%f"; return 1 } ;;
    *) print -P "%F{red}tools proj list [группа]|info [имя]|scan|here%f"; return 1 ;;
  esac
}

# tools go <имя> [.]: cd в клон проекта; с точкой в обёртку (папку выше app/).
tools_go() {
  local name="$1" dir
  if [[ -z "$name" ]]; then
    if command -v fzf >/dev/null 2>&1; then
      name=$(_tools_project_names | fzf --height 40% --reverse --prompt 'проект> ') || return 1
    else
      _tools_proj_list; return 0
    fi
  fi
  _tools_project "$name" || { print -P "%F{red}нет проекта ${name}: tools proj list%f"; return 1 }
  dir="${TOOLS_DEV}/${reply[2]}"
  [[ "$2" == "." && "${dir:t}" == app ]] && dir="${dir:h}"
  [[ -d "$dir" ]] || { print -P "%F{red}папки нет: ${dir}%f"; return 1 }
  cd "$dir"
}

# tools open [имя]: открыть проект в IDE JetBrains по стеку (скрипты Toolbox в PATH).
tools_open() {
  local name; name=$(_tools_project_arg "$1") || return 1
  _tools_project "$name"
  local dir="${TOOLS_DEV}/${reply[2]}" ide
  case "$(_tools_stack "$dir")" in
    go) ide=goland ;;
    python) ide=pycharm ;;
    *) ide=phpstorm ;;
  esac
  command -v "$ide" >/dev/null 2>&1 || { print -P "%F{red}команда ${ide} не найдена: включи shell-скрипты в JetBrains Toolbox%f"; return 1 }
  if [[ -n "$TOOLS_DRY_RUN" ]]; then print "  $ide $dir"; return 0; fi
  "$ide" "$dir" >/dev/null 2>&1 &!
}

tools_help_add проекты "tools proj list [группа]" "реестр проектов (projects, clients, work, wv-)"
tools_help_add проекты "tools proj info [имя]" "путь, стек, ssh, деплой, порт, база, ветка"
tools_help_add проекты "tools proj scan" "клоны под ~/Dev без строки в реестре"
tools_help_add проекты "tools go [имя] [.]" "перейти в клон проекта, с точкой в обёртку"
tools_help_add проекты "tools open [имя]" "открыть проект в PhpStorm, GoLand или PyCharm"
