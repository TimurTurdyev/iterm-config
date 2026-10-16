#!/usr/bin/env bash
# Идемпотентная установка минимального промпта: Starship + маркерный блок в ~/.zshrc.
# Starship ставится официальным скриптом в ~/.local/bin (без brew и без sudo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZSHRC="$HOME/.zshrc"
MARKER_START="# >>> iterm-config >>>"
MARKER_END="# <<< iterm-config <<<"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if ! command -v starship >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/starship" ]; then
  mkdir -p "$HOME/.local/bin"
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin" >/dev/null 2>&1 ||
    fail "установка starship не удалась (https://starship.rs)"
fi

touch "$ZSHRC"
if ! grep -qF "$MARKER_START" "$ZSHRC"; then
  # Бэкап .zshrc один раз, перед первым изменением.
  [ -f "$HOME/.zshrc.iterm-config.bak" ] || cp "$ZSHRC" "$HOME/.zshrc.iterm-config.bak"
  {
    echo ""
    echo "$MARKER_START"
    echo "source \"$REPO_DIR/shell/iterm2.zsh\""
    echo "$MARKER_END"
  } >>"$ZSHRC"
fi

done_msg "промпт настроен - откройте новую вкладку/окно терминала, чтобы увидеть ❯"
