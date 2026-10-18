#!/usr/bin/env bash
# Полная установка внешнего вида iTerm2: шрифт + Dynamic Profiles.
# Только оркестратор вызывает узкие скрипты; друг друга они не вызывают.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

"$SCRIPT_DIR/install-fonts.sh" ||
  warn "шрифт не установлен - профили временно откроются с fallback-шрифтом; поставьте Homebrew и перезапустите установку"

"$SCRIPT_DIR/install-profiles.sh"

"$SCRIPT_DIR/install-shell.sh" ||
  warn "промпт не настроен - проверьте сеть и повторите scripts/install-shell.sh"

if pgrep -xq iTerm2; then
  warn "iTerm2 запущен - тема Minimal и отступы не применены; закройте iTerm2 и запустите scripts/apply-ui.sh отдельно"
else
  "$SCRIPT_DIR/apply-ui.sh"
fi

done_msg "готово"
cat <<'EOF'

Профили уже появились в iTerm2 (перезапуск не нужен):
  Base, Tokyo Night, Catppuccin Mocha, Dracula, TokyoNight Storm, Gruvbox Dark, Nord,
  Default Dark+, Nuno, Auto (Catppuccin) - Mocha/Latte по теме macOS,
  timcode.ru - профиль по умолчанию, со сводкой при открытии окна

Попробовать вид:   Profiles > <имя профиля> (откроется новая вкладка)
Сделать основным:  Settings > Profiles > выбрать профиль > Other Actions... > Set as Default

В новой вкладке: промпт Starship и, если установлен tim, сводка при открытии окна (tim motd).
Тема Minimal и отступы требуют перезапуска iTerm2
(если шаг был пропущен - закройте iTerm2 и запустите scripts/apply-ui.sh).
EOF
