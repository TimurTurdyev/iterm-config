# Подключается из ~/.zshrc маркерным блоком (ставит scripts/install-shell.sh).
# Rc-фрагмент обязан загружаться беззвучно: никакого вывода в stdout/stderr.

# Starship устанавливается в ~/.local/bin (scripts/install-shell.sh).
if [[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# $0 при source в zsh указывает на этот файл; :A:h - абсолютный путь к каталогу.
export STARSHIP_CONFIG="${0:A:h}/starship.toml"
# Профиль timcode.ru живёт с промптом сайта (user@host dir %), остальные - с ❯.
if [[ "$ITERM_PROFILE" == "timcode.ru" ]]; then
  export STARSHIP_CONFIG="${0:A:h}/starship-timcode.toml"
fi

# bat сам определяет светлый/тёмный фон терминала (--theme=auto по умолчанию);
# задаём пару в тон профилю Auto (Catppuccin).
export BAT_THEME_DARK="Catppuccin Mocha"
export BAT_THEME_LIGHT="Catppuccin Latte"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  # Fallback без зависимостей: тот же минимальный символ.
  PROMPT='❯ '
fi
