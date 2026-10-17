# tools: швейцарский нож для терминала. Список команд: tools help.
# Разделы лежат в tools.d/*.zsh, каждый объявляет функции tools_<команда>
# и регистрирует строки справки через tools_help_add. Сводка tools motd
# печатается при открытии окна профиля timcode.ru (см. iterm2.zsh).
# TOOLS_DRY_RUN=1 печатает команды, меняющие систему, вместо запуска.

TOOLS_DIR="${0:A:h}"
typeset -ga TOOLS_HELP
TOOLS_HELP=()

_tools_colors() {
  label='%F{green}' dim='%F{8}' warn='%F{yellow}' bad='%F{red}' info='%F{cyan}' off='%f'
}

# tools_help_add <группа> <команда> <описание>
tools_help_add() {
  TOOLS_HELP+=("$1"$'\t'"$2"$'\t'"$3")
}

# Синонимы подкоманд.
typeset -gA TOOLS_ALIASES
TOOLS_ALIASES=(routes route cert ssl)

TOOLS_HELP_ORDER=(сводка проекты запуск базы удалённое сеть маршруты)

tools_help() {
  local label dim warn bad info off; _tools_colors
  local want="$1" line group cmd desc g first=1
  for g in "${TOOLS_HELP_ORDER[@]}"; do
    [[ -n "$want" && "$g" != "$want" ]] && continue
    (( first )) || print
    first=0
    print -P "${dim}# ${g}${off}"
    for line in "${TOOLS_HELP[@]}"; do
      group=${line%%$'\t'*}; cmd=${${line#*$'\t'}%%$'\t'*}; desc=${line##*$'\t'}
      [[ "$group" == "$g" ]] || continue
      print -P "${label}${(r:42:)cmd}${off} ${desc}"
    done
  done
  [[ -z "$want" ]] && print -P "\n${dim}tools help <группа> покажет одну группу; TOOLS_DRY_RUN=1 печатает команды вместо запуска${off}"
}

tools() {
  emulate -L zsh
  local cmd="${1:-help}"; (( $# > 0 )) && shift
  cmd=${TOOLS_ALIASES[$cmd]:-$cmd}
  case "$cmd" in
    help|-h|--help) tools_help "$@" ;;
    *)
      if (( $+functions[tools_$cmd] )); then
        "tools_$cmd" "$@"
      else
        print -P "%F{red}tools: неизвестная команда ${cmd}%f"
        tools_help
        return 1
      fi ;;
  esac
}

local _tools_module
for _tools_module in "$TOOLS_DIR"/tools.d/*.zsh(N); do
  source "$_tools_module"
done
unset _tools_module

# Короткое имя для сводки: так её зовёт iterm2.zsh при открытии окна.
alias motd='tools motd'
