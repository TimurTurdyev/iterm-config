#!/usr/bin/env bash
# Проверка zsh-модулей: синтаксис каждого файла и тесты разбора.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

for f in "$REPO_DIR"/shell/*.zsh "$REPO_DIR"/shell/tools.d/*.zsh; do
  zsh -n "$f" || fail "синтаксис: $f"
done

zsh "$REPO_DIR/shell/tests/run.zsh" || fail "тесты не прошли"
done_msg "модули и тесты в порядке"
