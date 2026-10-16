#!/usr/bin/env bash
# Идемпотентная установка шрифтов профилей через Homebrew (Nerd Font-сборки).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# cask -> маска установленного файла (Nerd Fonts переименовывает Monaspace в Monaspice).
FONTS=(
  "font-jetbrains-mono-nerd-font:JetBrainsMonoNerdFont-Regular.*"
  "font-monaspice-nerd-font:MonaspiceNeNerdFont-Regular.*"
)

font_installed() {
  # Маска должна раскрываться, поэтому без кавычек.
  # shellcheck disable=SC2086
  ls "$HOME/Library/Fonts"/$1 >/dev/null 2>&1 || ls /Library/Fonts/$1 >/dev/null 2>&1
}

missing=()
for entry in "${FONTS[@]}"; do
  cask="${entry%%:*}"
  glob="${entry#*:}"
  font_installed "$glob" || missing+=("$cask")
done

if [ ${#missing[@]} -eq 0 ]; then
  done_msg "шрифты уже установлены"
  exit 0
fi

if ! require_brew; then
  warn "установите шрифты вручную: https://www.nerdfonts.com/font-downloads (JetBrainsMono, Monaspace)"
  exit 1
fi

for cask in "${missing[@]}"; do
  brew install --cask "$cask" >/dev/null || fail "brew install --cask $cask завершился с ошибкой"
done

done_msg "шрифты установлены: ${missing[*]}"
