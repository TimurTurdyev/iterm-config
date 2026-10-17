# tools vpn: туннели, маршруты и обёртки над скриптами projects/vpn-help.

_tools_vpn_script() {
  local dir
  _tools_project vpn-help || { print -P "%F{red}проекта vpn-help нет в реестре%f" >&2; return 1 }
  dir="${TOOLS_DEV}/${reply[2]}"
  [[ -x "$dir/$1" ]] || { print -P "%F{red}скрипта ${dir}/$1 нет или он не исполняемый%f" >&2; return 1 }
  print "$dir/$1"
}

_tools_vpn_status() {
  local label dim warn bad info off; _tools_colors
  local i ip def device gw
  def=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')
  device=$(_tools_phys_iface); gw=$(_tools_iface_gateway "$device")
  print -P "${label}default${off}  ${def:-нет}${${(M)def:#utun*}:+  ${warn}(весь трафик в туннель)${off}}   ${label}физически${off} ${device:-?} via ${gw:-?}"
  for i in $(ifconfig -l); do
    [[ "$i" == utun* ]] || continue
    ip=$(ifconfig "$i" | awk '/inet /{print $2}')
    [[ -n "$ip" ]] && print -P "${label}tunnel${off}   ${i} ${ip}"
  done
  pgrep -xq openvpn && print -P "${dim}openvpn запущен${off}"
  pgrep -qf AmneziaVPN && print -P "${dim}AmneziaVPN запущен${off}"
  print -P "${dim}маршруты в обход: tools route${off}"
}

tools_vpn() {
  local cmd="${1:-status}"; (( $# > 0 )) && shift
  local script
  case "$cmd" in
    status|"") _tools_vpn_status ;;
    fix) script=$(_tools_vpn_script fix-vpn-conflict.sh) || return 1; _tools_run "sudo $script $*" ;;
    exclude) script=$(_tools_vpn_script vpn-exclude.sh) || return 1; _tools_run "$script $*" ;;
    shell) script=$(_tools_vpn_script vpn-shell.sh) || return 1; _tools_run "$script $*" ;;
    ssh) script=$(_tools_vpn_script vpn-ssh.sh) || return 1; _tools_run "$script $*" ;;
    *) print -P "%F{red}tools vpn [status|fix|exclude|shell|ssh]%f"; return 1 ;;
  esac
}

tools_help_add сеть "tools vpn" "туннели, маршрут по умолчанию, физический шлюз"
tools_help_add сеть "tools vpn fix|exclude|shell|ssh" "скрипты vpn-help: починка, приложение или ssh мимо VPN"
