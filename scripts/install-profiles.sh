#!/usr/bin/env bash
# Валидация и установка Dynamic Profiles в iTerm2.
# Сначала проверяются ВСЕ файлы: один битый JSON блокирует обработку
# всего каталога DynamicProfiles на стороне iTerm2.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DP_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_iterm2

shopt -s nullglob
profiles=("$REPO_DIR"/profiles/*.json)
shopt -u nullglob
[ ${#profiles[@]} -gt 0 ] || fail "в $REPO_DIR/profiles нет ни одного .json"

# plutil -lint не понимает JSON-плисты, поэтому валидируем конвертацией в xml1.
for f in "${profiles[@]}"; do
  plutil -convert xml1 -o /dev/null "$f" || fail "битый JSON-плист: $f"
done

mkdir -p "$DP_DIR"
for f in "${profiles[@]}"; do
  cp "$f" "$DP_DIR/"
done

done_msg "профили установлены (${#profiles[@]} шт.) в $DP_DIR"
