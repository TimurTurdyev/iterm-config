#!/usr/bin/env zsh
# Тесты разбора .env и реестра проектов. Запуск: zsh shell/tests/run.zsh
set -u
TESTS_DIR="${0:A:h}"
TOOLS_DEV=$(mktemp -d)
TOOLS_PROJECTS="$TOOLS_DEV/tools.projects"
export TOOLS_DEV TOOLS_PROJECTS
source "$TESTS_DIR/../tools.zsh"

failed=0
check() { # имя ожидание факт
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1: ожидалось [$2], получено [$3]"; failed=1; fi
}

# .env: кавычки, комментарии, export, CRLF, повтор ключа, пустое значение
env="$TOOLS_DEV/.env"
printf 'A=1\nB="two words" # c\nC='"'"'x # not comment'"'"'\nD=raw # comment\nE=\nexport F=yes\r\nA=2\nAPP_URL=http://localhost:8003\n' > "$env"
check "env: последнее вхождение" "2" "$(_tools_env_get "$env" A)"
check "env: двойные кавычки" "two words" "$(_tools_env_get "$env" B)"
check "env: одинарные кавычки с решёткой" "x # not comment" "$(_tools_env_get "$env" C)"
check "env: хвостовой комментарий" "raw" "$(_tools_env_get "$env" D)"
check "env: пустое значение" "" "$(_tools_env_get "$env" E)"
check "env: export и CRLF" "yes" "$(_tools_env_get "$env" F)"
check "env: нет ключа" "1" "$(_tools_env_get "$env" NOPE; print $?)"

# реестр: комментарии, короткие строки добиваются "-", проект по папке самый длинный
mkdir -p "$TOOLS_DEV/projects/a/app/handbook" "$TOOLS_DEV/projects/b/app"
printf '# comment\nshort\tprojects/b/app\n\na\tprojects/a/app\tssh-a\t/srv/a\tmake:deploy\t5180\tpg:a\na-handbook\tprojects/a/app/handbook\n' > "$TOOLS_PROJECTS"
check "registry: число строк" "3" "$(_tools_registry | wc -l | tr -d ' ')"
check "registry: короткая строка добита до 7 полей" "7" "$(_tools_registry | awk -F'\t' '$1 == "short" { print NF }')"
_tools_project a; check "project: поля" "a projects/a/app ssh-a /srv/a make:deploy 5180 pg:a" "${reply[*]}"
check "project: нет такого" "1" "$(_tools_project nope; print $?)"
check "here: вложенный проект длиннее" "a-handbook" "$(cd "$TOOLS_DEV/projects/a/app/handbook" && _tools_project_here)"
check "here: родительский проект" "a" "$(cd "$TOOLS_DEV/projects/a/app" && _tools_project_here)"
check "here: вне реестра" "" "$(cd /tmp && _tools_project_here)"
cp "$env" "$TOOLS_DEV/projects/b/app/.env"
check "port: из APP_URL когда в реестре нет" "8003" "$(_tools_project_port short "$TOOLS_DEV/projects/b/app")"
check "port: из реестра" "5180" "$(_tools_project_port a "$TOOLS_DEV/projects/a/app")"
check "port: по умолчанию" "8000" "$(_tools_project_port a-handbook "$TOOLS_DEV/projects/a/app/handbook")"

rm -rf "$TOOLS_DEV"
(( failed )) && { print "есть провалы"; exit 1 }
print "все тесты прошли"
