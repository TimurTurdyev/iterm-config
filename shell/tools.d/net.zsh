# tools port, dns, ssl: сеть и процессы.

# Кто слушает порт; tools port <n> kill завершает процесс.
tools_port() {
  local label dim warn bad info off; _tools_colors
  local port="$1" rows
  [[ -n "$port" ]] || { print -P "${bad}укажи порт: tools port 8000 [kill]${off}"; return 1 }
  rows=$(lsof +c 0 -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $2, $1 }' | sort -u)
  if [[ -z "$rows" ]]; then
    print -P "${dim}порт ${port} свободен${off}"
    return 0
  fi
  local pid proc
  while read -r pid proc; do
    print -P "${label}${port}${off}  pid ${pid}  ${proc}"
    if [[ "$2" == kill ]]; then
      kill "$pid" 2>/dev/null && print -P "  ${warn}завершён${off}" || print -P "  ${bad}не удалось завершить, попробуй sudo kill ${pid}${off}"
    fi
  done <<< "$rows"
}

# Сброс DNS-кэша macOS.
tools_dns() {
  local label dim warn bad info off; _tools_colors
  case "${1:-flush}" in
    flush)
      sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder && print -P "${label}DNS-кэш сброшен${off}" ;;
    servers)
      scutil --dns | awk '/nameserver\[/ { print $3 }' | sort -u ;;
    *) print -P "${bad}tools dns flush|servers${off}"; return 1 ;;
  esac
}

# Срок действия сертификата домена.
tools_ssl() {
  local label dim warn bad info off; _tools_colors
  local host="$1" dates not_after days
  [[ -n "$host" ]] || { print -P "${bad}укажи домен: tools ssl timcode.ru${off}"; return 1 }
  dates=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)
  [[ -n "$dates" ]] || { print -P "${bad}${host}: сертификат не получен${off}"; return 1 }
  not_after=$(print "$dates" | awk -F= '/notAfter/ { print $2 }')
  # Дата от openssl на английском, под русской локалью %b её не разберёт.
  days=$(( ($(LC_ALL=C date -j -f '%b %d %T %Y %Z' "$not_after" +%s 2>/dev/null || print 0) - $(date +%s)) / 86400 ))
  print -P "${label}${host}${off}  $(print "$dates" | awk -F= '/issuer/ { print $NF }' | sed 's/^ *//')"
  if (( days < 14 )); then
    print -P "  ${bad}истекает через ${days} дн.${off} ${dim}${not_after}${off}"
  else
    print -P "  ${label}действует ещё ${days} дн.${off} ${dim}${not_after}${off}"
  fi
}

tools_help_add сеть "tools port <n> [kill]" "кто слушает порт, при kill завершить"
tools_help_add сеть "tools dns flush|servers" "сбросить DNS-кэш (sudo) или показать серверы"
tools_help_add сеть "tools ssl <домен>" "срок действия сертификата"
