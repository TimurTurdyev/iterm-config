# Автодополнение tools: подкоманды, проекты из реестра, алиасы ssh, сервисы.
# Файл грузится последним (zz-), когда все модули уже объявлены.

_tools() {
  local -a cmds projects aliases services
  local cur="${words[CURRENT]}"
  cmds=(help motd ports services net repos procs versions route port dns ssl vpn
        proj go open serve env svc php db ssh deploy pull tunnel)
  case $CURRENT in
    2) _describe -t commands 'команда tools' cmds ;;
    3)
      case "${words[2]}" in
        route) compadd status check up down list table ;;
        proj) compadd list info scan here ;;
        svc) compadd status start stop restart logs ;;
        dns) compadd flush servers ;;
        vpn) compadd status fix exclude shell ssh ;;
        php) compadd ${${(f)"$(ls -d /opt/homebrew/opt/php@* 2>/dev/null)"}##*php@} ;;
        db) projects=(${(f)"$(_tools_project_names)"}); compadd dump restore "${projects[@]}" ;;
        ssh) aliases=(${(f)"$(_tools_ssh_aliases)"}); projects=(${(f)"$(_tools_project_names)"}); compadd list "${aliases[@]}" "${projects[@]}" ;;
        go|open|serve|env|deploy|pull|info) projects=(${(f)"$(_tools_project_names)"}); compadd "${projects[@]}" ;;
        help) compadd сводка проекты запуск базы удалённое туннели сеть маршруты ;;
        net) compadd public ;;
        tunnel) compadd status up down check shell run app system all port expose ;;
      esac ;;
    4)
      case "${words[2]}" in
        proj) projects=(${(f)"$(_tools_project_names)"}); compadd "${projects[@]}" ;;
        svc) services=("${TOOLS_BREW_SERVICES[@]}"); compadd "${services[@]}" ;;
        route) [[ "${words[3]}" == (up|down) ]] && compadd ${(f)"$(_tools_hosts | awk '{print $2}')"} ;;
        db) compadd dump restore ;;
        pull) compadd db storage ;;
        port) compadd kill ;;
        php) compadd --global ;;
        tunnel) case "${words[3]}" in app) compadd chrome firefox brave ;; system) compadd on off ;; all) compadd off ;; up|check|shell) compadd ${(f)"$(_tools_ssh_aliases)"} ;; esac ;;
      esac ;;
  esac
}

(( $+functions[compdef] )) && compdef _tools tools
