# shellcheck shell=bash
# Общая библиотека для скриптов установки. Подключение:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# Логирование минимальное: WARN/ERROR в stderr + одно итоговое сообщение на скрипт.

SCRIPT_NAME="$(basename "${0:-common}" .sh)"

warn() { echo "[$SCRIPT_NAME] WARN: $*" >&2; }

fail() {
  echo "[$SCRIPT_NAME] ОШИБКА: $*" >&2
  exit 1
}

done_msg() { echo "[$SCRIPT_NAME] $*"; }

require_iterm2() {
  [ -d "/Applications/iTerm.app" ] || fail "iTerm2 не установлен (/Applications/iTerm.app не найден)"
}

# Возвращает 1 (без выхода), если brew отсутствует - решение принимает вызывающий скрипт.
require_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew не найден (https://brew.sh)"
    return 1
  fi
}

backup_plist() {
  local backup_dir="$HOME/backups/iterm2"
  mkdir -p "$backup_dir"
  defaults export com.googlecode.iterm2 "$backup_dir/iterm-$(date +%Y%m%d-%H%M%S).plist" ||
    fail "не удалось создать бэкап настроек iTerm2"
  done_msg "бэкап plist: $backup_dir"
}
