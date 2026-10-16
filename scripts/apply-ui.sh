#!/usr/bin/env bash
# Глобальные UI-настройки iTerm2: тема Minimal, отступы, приглушение
# неактивных панелей и профиль по умолчанию.
# Выполнять строго при закрытом iTerm2 - кэш запущенного приложения
# перезаписывает значения, записанные через defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if pgrep -xq iTerm2; then
  fail "iTerm2 запущен - закройте его и повторите (меню iTerm2 > Quit, либо: osascript -e 'quit app \"iTerm2\"')"
fi

backup_plist

# Тема интерфейса (Settings > Appearance > General > Theme).
# Карта значений TabStyleWithAutomaticOption:
#   0=Light, 1=Dark, 2=Light High Contrast, 3=Dark High Contrast,
#   4=Automatic, 5=Minimal, 6=Compact
# Проверено на этой машине: до изменения ключ имел значение 6 (Compact,
# выставленное в UI), что совпадает с картой.
defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 5

# Отступы (Settings > Advanced):
#   TerminalMargin  - "Width of left and right margins in terminal panes"
#   TerminalVMargin - "Height of top and bottom margins in terminal panes"
defaults write com.googlecode.iterm2 TerminalMargin -int 20
defaults write com.googlecode.iterm2 TerminalVMargin -int 20

# Приглушение (Settings > Appearance > Dimming): фокус виден сразу,
# остальное уходит на второй план. 0.2 - мягко, дефолт iTerm2 (0.4) резковат.
defaults write com.googlecode.iterm2 DimInactiveSplitPanes -bool true
defaults write com.googlecode.iterm2 DimBackgroundWindows -bool true
defaults write com.googlecode.iterm2 DimOnlyText -bool false
defaults write com.googlecode.iterm2 SplitPaneDimmingAmount -float 0.2

# Профиль по умолчанию - "timcode.ru" из profiles/50-timcode.json (палитра сайта).
# Прежний "Auto (Catppuccin)": DA7C06BA-09EE-4638-8F7C-345B23DE1E82.
defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "6C1D89A5-F581-4C3D-B676-F7D9A7F5B6D1"

done_msg "UI применён - вступит в силу при следующем запуске iTerm2"
