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

# Личные списки tools заводятся из шаблонов один раз и в git не попадают.
for name in tools.hosts tools.projects tools.conf; do
  [ -f "$REPO_DIR/shell/$name" ] || cp "$REPO_DIR/shell/$name.example" "$REPO_DIR/shell/$name"
done

done_msg "промпт и tools настроены - откройте новую вкладку терминала; списки tools: shell/tools.hosts, shell/tools.projects"
