# ============================================================
# Quick Menu 2.8.1
# macOS · zsh · fzf
# ============================================================

# Configuration
typeset -g _LAUNCHER_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quick-menu"
typeset -g _LAUNCHER_BREW_CACHE="$_LAUNCHER_CACHE_DIR/brew-outdated.txt"
typeset -g _LAUNCHER_LOG="$_LAUNCHER_CACHE_DIR/events.log"
typeset -g _LAUNCHER_VPN_UDP="$HOME/ya_vpn/udpstart.sh"
typeset -g _LAUNCHER_VPN_TCP="$HOME/ya_vpn/tcpstart.sh"

# ============================================================
# Safety helpers
# ============================================================

# Log only action names and lifecycle events; never log typed values,
# passwords, clipboard data or command output.
_launcher_log() {
  [[ -d "$_LAUNCHER_CACHE_DIR" ]] || mkdir -p -- "$_LAUNCHER_CACHE_DIR" 2>/dev/null || return 0
  # Limit log growth without external background workers.
  if [[ -f "$_LAUNCHER_LOG" ]]; then
    local bytes
    bytes=$(stat -f %z "$_LAUNCHER_LOG" 2>/dev/null)
    if [[ "$bytes" == <-> ]] && (( bytes > 262144 )); then
      mv -f -- "$_LAUNCHER_LOG" "${_LAUNCHER_LOG}.old" 2>/dev/null
    fi
  fi
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') pid=$$ $*" >> "$_LAUNCHER_LOG" 2>/dev/null
  return 0
}

# stderr remains attached to the terminal inside pipelines and $(...).
# stdin/stdout are intentionally redirected when piping choices into fzf.
_launcher_tty_ok() {
  [[ -t 2 ]]
}

# Timeout used ONLY for short status checks, not interactive tools.
# macOS includes Perl; alarm survives exec, so it also bounds a hung CLI.
_launcher_status_with_timeout() {
  local seconds="$1"
  shift
  /usr/bin/perl -e 'my $s = shift @ARGV; alarm($s); exec @ARGV or exit 127;' "$seconds" "$@"
}

# ============================================================
# UI helpers
# ============================================================

_launcher_select() {
  _launcher_tty_ok || return 130
  # fzf reads choices from a pipe, and communicates with the terminal itself.
  fzf \
    --height=80% \
    --layout=reverse \
    --border=rounded \
    --no-sort \
    --delimiter='|' \
    --with-nth=2 \
    --prompt='❯ ' \
    --header="$1 · Enter: выбрать · Esc: назад" \
    --info=inline
}

# Menu items are specified as key|title|description.
# Column width follows the longest title automatically.
_launcher_format_items() {
  local entry key rest title description
  local max_width=0
  local -a entries=("$@")

  for entry in "${entries[@]}"; do
    rest="${entry#*|}"
    title="${rest%%|*}"
    (( ${#title} > max_width )) && max_width=${#title}
  done
  (( max_width += 2 ))

  for entry in "${entries[@]}"; do
    key="${entry%%|*}"
    rest="${entry#*|}"
    title="${rest%%|*}"
    description="${rest#*|}"
    printf '%s|%-*s· %s\n' "$key" "$max_width" "$title" "$description"
  done
}

# ============================================================
# Dynamic statuses
# ============================================================

_launcher_git_status() {
  local root branch
  root=$(_launcher_status_with_timeout 3 git rev-parse --show-toplevel 2>/dev/null) || {
    print -r -- "не в репозитории"
    return
  }
  branch=$(_launcher_status_with_timeout 3 git symbolic-ref --quiet --short HEAD 2>/dev/null)
  [[ -n "$branch" ]] || branch="detached HEAD"
  print -r -- "${root:t} · $branch"
}

_launcher_ollama_status() {
  if ! command -v ollama >/dev/null 2>&1; then
    print -r -- "не установлена"
    return
  fi

  local output
  output=$(_launcher_status_with_timeout 4 ollama ps 2>/dev/null) || {
    print -r -- "сервис недоступен"
    return
  }

  print -r -- "$output" | awk '
    NR > 1 && NF {
      count++
      if (count <= 2) names = names (names ? ", " : "") $1
    }
    END {
      if (count == 0) print "нет загруженных моделей"
      else {
        printf "%s", names
        if (count > 2) printf " … (%d)", count
        printf "\n"
      }
    }
  '
}

# Homebrew updates are cached for six hours to avoid slowing down startup.
_launcher_brew_status() {
  if ! command -v brew >/dev/null 2>&1; then
    print -r -- "не установлен"
    return
  fi

  mkdir -p -- "$_LAUNCHER_CACHE_DIR" 2>/dev/null || {
    print -r -- "кэш недоступен"
    return
  }
  local now mtime count tmp_file
  now=$(date +%s)
  mtime=$(stat -f %m "$_LAUNCHER_BREW_CACHE" 2>/dev/null)

  if [[ -z "$mtime" ]] || (( now - mtime >= 21600 )); then
    # Unique temporary file: multiple Terminal tabs cannot clobber one another.
    tmp_file="${_LAUNCHER_BREW_CACHE}.$$.tmp"
    if HOMEBREW_NO_AUTO_UPDATE=1 _launcher_status_with_timeout 15 brew outdated --quiet > "$tmp_file" 2>/dev/null; then
      mv -f -- "$tmp_file" "$_LAUNCHER_BREW_CACHE"
    else
      _launcher_log "brew status timeout/error"
      rm -f -- "$tmp_file"
    fi
  fi

  if [[ ! -f "$_LAUNCHER_BREW_CACHE" ]]; then
    print -r -- "не удалось проверить"
    return
  fi

  count=$(wc -l < "$_LAUNCHER_BREW_CACHE")
  count=${count//[[:space:]]/}
  if (( count == 0 )); then
    print -r -- "всё обновлено"
  else
    print -r -- "$count обновлений"
  fi
}

# ============================================================
# Corporate VPN
# ============================================================

_launcher_vpn_start() {
  local protocol="$1" script
  case "$protocol" in
    udp) script="$_LAUNCHER_VPN_UDP" ;;
    tcp) script="$_LAUNCHER_VPN_TCP" ;;
    *) print -r -- "Неизвестный протокол VPN"; return 1 ;;
  esac

  if [[ ! -f "$script" ]]; then
    print -r -- "VPN-скрипт не найден: $script"
    return 1
  fi

  print -r -- "Yandex VPN · ${protocol:u}"
  print -r -- "Запуск: $script"
  print
  _launcher_log "vpn ${protocol} start"
  bash "$script"
}

# ============================================================
# Network Tools
# ============================================================

# Required terminal input. Empty Enter repeats the prompt.
# Ctrl+C aborts the current action; EOF also aborts (no infinite loop).
# Result is returned via REPLY, following the zsh convention.
_launcher_prompt() {
  local label="$1" kind="${2:-text}" value

  while true; do
    # A detached terminal must cancel instead of retrying input.
    _launcher_tty_ok || { _launcher_log "prompt no tty"; return 130; }
    read -r "value?$label: " || { _launcher_log "prompt interrupted/eof"; return 130; }

    # Reject empty or whitespace-only answers.
    if [[ -z "${value//[[:space:]]/}" ]]; then
      print -r -- "Введите значение (Ctrl+C — отмена)."
      continue
    fi

    case "$kind" in
      port)
        if [[ "$value" != <-> ]] || (( value < 1 || value > 65535 )); then
          print -r -- "Введите TCP-порт от 1 до 65535."
          continue
        fi
        ;;
      url)
        if [[ "$value" != http://* && "$value" != https://* ]]; then
          print -r -- "Укажите полный URL с http:// или https://."
          continue
        fi
        ;;
      passwordlen|tokenbytes|httpcode)
        if [[ "$value" != <-> ]]; then
          print -r -- "Введите целое число."
          continue
        fi
        local minimum=8 maximum=256
        [[ "$kind" == tokenbytes ]] && maximum=128
        if [[ "$kind" == httpcode ]]; then
          minimum=100
          maximum=599
        fi
        if (( value < minimum || value > maximum )); then
          print -r -- "Допустимый диапазон: $minimum–$maximum."
          continue
        fi
        ;;
      timestamp)
        if [[ "$value" != <-> && "$value" != -<-> ]]; then
          print -r -- "Введите целое число секунд Unix timestamp."
          continue
        fi
        ;;
      chmod)
        if [[ "$value" != [0-7][0-7][0-7] ]]; then
          print -r -- "Введите три цифры от 0 до 7, например 755."
          continue
        fi
        ;;
      yesno)
        case "${value:l}" in
          y|yes|д|да) REPLY="yes"; return 0 ;;
          n|no|н|нет) REPLY="no"; return 0 ;;
          *)
            print -r -- "Ответьте y или n (Ctrl+C — отмена)."
            continue
            ;;
        esac
        ;;
    esac

    REPLY="$value"
    return 0
  done
}

_launcher_network_input() {
  _launcher_prompt "$@"
}

_launcher_network() {
  local selected action target record server port url

  selected=$(printf '%s\n' \
    'ping|Ping — доступность узла' \
    'dns|DNS — dig / nslookup' \
    'trace|Traceroute — маршрут' \
    'http|HTTP / HTTPS — диагностика' \
    'port|TCP — проверить порт' \
    'info|macOS — сетевые параметры' \
    'quality|Network Quality — тест соединения' |
    _launcher_select "Сетевые утилиты") || return 0

  action="${selected%%|*}"
  case "$action" in
    ping)
      selected=$(printf '%s\n' \
        '4|4 пакета' \
        '10|10 пакетов' \
        'continuous|Непрерывно (Ctrl+C — остановить)' \
        'ipv6|IPv6 — 4 пакета' |
        _launcher_select "Ping") || return 0
      action="${selected%%|*}"
      _launcher_network_input "IP или домен" || return 0
      target="$REPLY"
      case "$action" in
        4) ping -c 4 "$target" ;;
        10) ping -c 10 "$target" ;;
        continuous) ping "$target" ;;
        ipv6) ping6 -c 4 "$target" ;;
      esac
      ;;

    dns)
      selected=$(printf '%s\n' \
        'dig|dig — полный ответ' \
        'short|dig — краткий ответ' \
        'type|Выбрать тип записи' \
        'cloudflare|Cloudflare · 1.1.1.1' \
        'google|Google · 8.8.8.8' \
        'custom|Указать DNS-сервер' \
        'trace|dig +trace — делегирование' \
        'nslookup|nslookup — стандартный запрос' \
        'reverse|Обратный DNS — PTR' |
        _launcher_select "DNS Lookup") || return 0
      action="${selected%%|*}"
      _launcher_network_input "Домен или IP" || return 0
      target="$REPLY"
      case "$action" in
        dig) dig "$target" ;;
        short) dig +short "$target" ;;
        type)
          selected=$(printf '%s\n' A AAAA MX TXT NS CNAME SOA CAA SRV |
            _launcher_select "Тип DNS-записи") || return 0
          record="$selected"
          dig "$target" "$record"
          ;;
        cloudflare) dig @1.1.1.1 "$target" ;;
        google) dig @8.8.8.8 "$target" ;;
        custom)
          _launcher_network_input "DNS-сервер" || return 0
          server="$REPLY"
          dig @"$server" "$target"
          ;;
        trace) dig +trace "$target" ;;
        nslookup) nslookup "$target" ;;
        reverse) dig -x "$target" ;;
      esac
      ;;

    trace)
      selected=$(printf '%s\n' \
        'default|Стандартный traceroute' \
        'fast|До 12 переходов, короткий тайм-аут' \
        'icmp|ICMP traceroute' \
        'ipv6|IPv6 traceroute' |
        _launcher_select "Traceroute") || return 0
      action="${selected%%|*}"
      _launcher_network_input "IP или домен" || return 0
      target="$REPLY"
      case "$action" in
        default) traceroute "$target" ;;
        fast) traceroute -m 12 -w 1 "$target" ;;
        icmp) traceroute -I "$target" ;;
        ipv6) traceroute6 "$target" ;;
      esac
      ;;

    http)
      selected=$(printf '%s\n' \
        'headers|HTTP-заголовки' \
        'verbose|Подробный HTTP / TLS' \
        'timing|Время DNS / TCP / TLS / HTTP' \
        'status|HTTP-код ответа' \
        'redirect|Цепочка редиректов' |
        _launcher_select "HTTP / HTTPS") || return 0
      action="${selected%%|*}"
      _launcher_network_input "URL (https://...)" url || return 0
      url="$REPLY"
      case "$action" in
        headers) curl -I -L --max-time 20 -- "$url" ;;
        verbose) curl -v -o /dev/null --max-time 20 -- "$url" ;;
        timing)
          curl -L -sS -o /dev/null --max-time 20 \
            -w $'DNS: %{time_namelookup}s\nTCP: %{time_connect}s\nTLS: %{time_appconnect}s\nFirst byte: %{time_starttransfer}s\nTotal: %{time_total}s\nHTTP: %{http_code}\n' -- "$url"
          ;;
        status) curl -L -sS -o /dev/null --max-time 20 -w 'HTTP %{http_code}\n' -- "$url" ;;
        redirect) curl -IL --max-time 20 -- "$url" ;;
      esac
      ;;

    port)
      _launcher_network_input "IP или домен" || return 0
      target="$REPLY"
      _launcher_network_input "TCP-порт (1–65535)" port || return 0
      port="$REPLY"
      nc -G 5 -vz "$target" "$port"
      ;;

    info)
      selected=$(printf '%s\n' \
        'interfaces|Сетевые интерфейсы' \
        'hardware|Аппаратные сетевые порты' \
        'dns|DNS-конфигурация' \
        'proxy|Системные прокси' \
        'gateway|Основной шлюз' \
        'routes|Таблица маршрутизации' \
        'arp|ARP-таблица' \
        'services|Сетевые службы macOS' |
        _launcher_select "Network Info") || return 0
      action="${selected%%|*}"
      case "$action" in
        interfaces) ifconfig -a ;;
        hardware) networksetup -listallhardwareports ;;
        dns) scutil --dns ;;
        proxy) scutil --proxy ;;
        gateway) route -n get default ;;
        routes) netstat -rn ;;
        arp) arp -an ;;
        services) networksetup -listallnetworkservices ;;
      esac
      ;;

    quality)
      if command -v networkQuality >/dev/null 2>&1; then
        networkQuality
      else
        print -r -- "networkQuality недоступна"
        return 1
      fi
      ;;
  esac
}

# ============================================================
# Developer Tools — inspired by https://github.com/CorentinTh/it-tools
# All conversions are performed locally using Python standard library.
# Text transformations read from macOS clipboard (pbpaste), and copy the
# result back to clipboard (pbcopy) after successful completion.
# ============================================================

_launcher_devtools_python() {
  local operation="$1" value="${2:-}"
  if ! command -v python3 >/dev/null 2>&1; then
    print -r -- "Требуется python3."
    return 1
  fi

  python3 - "$operation" "$value" <<'PYTHON'
import base64
import hashlib
import html
import http
import json
import re
import secrets
import string
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from urllib.parse import quote, unquote

op, arg = sys.argv[1:3]

def clipboard():
    try:
        return subprocess.check_output(["pbpaste"], text=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(f"Не удалось прочитать буфер обмена: {exc}")

def result(text, copy=True):
    text = str(text)
    print(text)
    if copy:
        try:
            subprocess.run(["pbcopy"], input=text, text=True, check=True)
            print("\n[Результат скопирован в буфер обмена]", file=sys.stderr)
        except (OSError, subprocess.CalledProcessError):
            print("\n[Не удалось скопировать результат]", file=sys.stderr)

try:
    if op == "uuid":
        result(str(uuid.uuid4()))
    elif op == "password":
        size = int(arg)
        if not 8 <= size <= 256:
            raise ValueError("Длина пароля: от 8 до 256 символов")
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_"
        result("".join(secrets.choice(alphabet) for _ in range(size)))
    elif op == "token":
        size = int(arg)
        if not 8 <= size <= 128:
            raise ValueError("Количество байт: от 8 до 128")
        result(secrets.token_hex(size))
    elif op == "port":
        result(secrets.randbelow(65535 - 1024 + 1) + 1024)
        print("[Порт не проверялся на занятость]", file=sys.stderr)
    elif op == "sha256":
        result(hashlib.sha256(clipboard().encode("utf-8")).hexdigest())
    elif op == "sha512":
        result(hashlib.sha512(clipboard().encode("utf-8")).hexdigest())
    elif op == "base64_enc":
        result(base64.b64encode(clipboard().encode("utf-8")).decode("ascii"))
    elif op == "base64_dec":
        raw = base64.b64decode(clipboard().strip(), validate=True)
        result(raw.decode("utf-8"))
    elif op == "url_enc":
        result(quote(clipboard(), safe=""))
    elif op == "url_dec":
        result(unquote(clipboard()))
    elif op == "html_enc":
        result(html.escape(clipboard(), quote=True))
    elif op == "html_dec":
        result(html.unescape(clipboard()))
    elif op == "json_pretty":
        result(json.dumps(json.loads(clipboard()), ensure_ascii=False, indent=2))
    elif op == "json_min":
        result(json.dumps(json.loads(clipboard()), ensure_ascii=False, separators=(",", ":")))
    elif op == "json_check":
        json.loads(clipboard())
        print("JSON корректен. Буфер обмена не изменён.")
    elif op == "jwt":
        parts = clipboard().strip().split(".")
        if len(parts) != 3:
            raise ValueError("Ожидается JWT из трёх частей: header.payload.signature")
        def decode(part):
            raw = base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))
            return json.loads(raw.decode("utf-8"))
        print("JWT — только просмотр. Подпись НЕ проверена.\n")
        print("HEADER:")
        print(json.dumps(decode(parts[0]), ensure_ascii=False, indent=2))
        print("\nPAYLOAD:")
        print(json.dumps(decode(parts[1]), ensure_ascii=False, indent=2))
    elif op == "text_stats":
        data = clipboard()
        print(f"Символов: {len(data)}")
        print(f"Слов: {len(data.split())}")
        print(f"Строк: {len(data.splitlines())}")
        print(f"Байт UTF-8: {len(data.encode('utf-8'))}")
    elif op == "timestamp_now":
        now = datetime.now().astimezone()
        print(f"Unix timestamp: {int(now.timestamp())}")
        print(f"Локальное время: {now.isoformat(timespec='seconds')}")
        print(f"UTC: {now.astimezone(timezone.utc).isoformat(timespec='seconds')}")
    elif op == "timestamp_parse":
        ts = float(arg)
        dt = datetime.fromtimestamp(ts, timezone.utc)
        print(f"Локальное время: {dt.astimezone().isoformat(timespec='seconds')}")
        print(f"UTC: {dt.isoformat(timespec='seconds')}")
    elif op == "http_status":
        code = int(arg)
        try:
            status = http.HTTPStatus(code)
        except ValueError:
            raise ValueError(f"Неизвестный HTTP-код: {code}")
        print(f"{status.value} {status.phrase}\n{status.description}")
    elif op == "chmod":
        if not re.fullmatch(r"[0-7]{3}", arg):
            raise ValueError("Введите три восьмеричные цифры, например 755")
        mapping = ((4, "r"), (2, "w"), (1, "x"))
        symbolic = "".join("".join(c if int(digit) & bit else "-" for bit, c in mapping) for digit in arg)
        print(f"{arg}  ->  {symbolic}")
    else:
        raise ValueError("Неизвестный инструмент")
except (ValueError, UnicodeError, OverflowError, json.JSONDecodeError) as exc:
    print(f"Ошибка: {exc}", file=sys.stderr)
    sys.exit(1)
PYTHON
}

_launcher_devtools() {
  local section selected action value
  section=$(printf '%s\n' \
    'generators|Генераторы — UUID, пароли, токены' \
    'encoding|Кодирование и текст — Base64, URL, HTML, SHA' \
    'json|JSON и JWT — форматирование, проверка' \
    'reference|Дата, время и справочники' | \
    _launcher_select "Инструменты разработчика") || return 0
  section="${section%%|*}"

  case "$section" in
    generators)
      selected=$(printf '%s\n' \
        'uuid|UUID v4 — сгенерировать' \
        'password|Случайный пароль' \
        'token|Hex-токен для разработки' \
        'port|Случайный номер порта' | \
        _launcher_select "Генераторы") || return 0
      ;;
    encoding)
      selected=$(printf '%s\n' \
        'sha256|SHA-256 текста из буфера' \
        'sha512|SHA-512 текста из буфера' \
        'base64_enc|Base64 — кодировать текст' \
        'base64_dec|Base64 — декодировать UTF-8' \
        'url_enc|URL — кодировать текст' \
        'url_dec|URL — декодировать текст' \
        'html_enc|HTML — экранировать спецсимволы' \
        'html_dec|HTML — восстановить спецсимволы' \
        'text_stats|Статистика текста из буфера' | \
        _launcher_select "Кодирование и текст") || return 0
      ;;
    json)
      selected=$(printf '%s\n' \
        'json_pretty|JSON — красиво форматировать' \
        'json_min|JSON — минифицировать' \
        'json_check|JSON — проверить корректность' \
        'jwt|JWT — прочитать header/payload' | \
        _launcher_select "JSON и JWT") || return 0
      ;;
    reference)
      selected=$(printf '%s\n' \
        'timestamp_now|Текущее время Unix / ISO 8601' \
        'timestamp_parse|Unix timestamp → дата' \
        'http_status|Расшифровать HTTP-код' \
        'chmod|Права chmod: 755 → rwxr-xr-x' | \
        _launcher_select "Дата и справочники") || return 0
      ;;
  esac

  action="${selected%%|*}"
  case "$action" in
    password)
      _launcher_prompt "Длина пароля (8–256)" passwordlen || return 0
      value="$REPLY"
      ;;
    token)
      _launcher_prompt "Количество случайных байт (8–128)" tokenbytes || return 0
      value="$REPLY"
      ;;
    timestamp_parse)
      _launcher_prompt "Unix timestamp (секунды)" timestamp || return 0
      value="$REPLY"
      ;;
    http_status)
      _launcher_prompt "HTTP-код (например 404)" httpcode || return 0
      value="$REPLY"
      ;;
    chmod)
      _launcher_prompt "Права chmod (например 755)" chmod || return 0
      value="$REPLY"
      ;;
  esac

  case "$section" in
    encoding|json)
      print -r -- "Используется текст из буфера обмена macOS."
      ;;
  esac
  print
  _launcher_devtools_python "$action" "$value"
}

# ============================================================
# Tool submenus
# ============================================================

_launcher_action() {
  local category="$1"
  local selected action model answer

  case "$category" in
    ollama)
      selected=$(printf '%s\n' \
        'list|Установленные модели' \
        'ps|Загруженные модели' \
        'run|Запустить модель' \
        'show|Информация о модели' \
        'version|Версия Ollama' |
        _launcher_select "Ollama") || return 0
      ;;
    opencode)
      selected=$(printf '%s\n' \
        'ai|Универсальный агент — Qwen3.8 MLX' \
        'code|Агент-разработчик — Qwen3-Coder' \
        'models|Доступные модели' \
        'agents|Список агентов' |
        _launcher_select "OpenCode") || return 0
      ;;
    codex)
      selected=$(printf '%s\n' \
        'start|Запустить Codex CLI' \
        'resume|Продолжить сессию Codex' |
        _launcher_select "Codex") || return 0
      ;;
    vpn)
      selected=$(printf '%s\n' \
        'udp|Подключиться через UDP' \
        'tcp|Подключиться через TCP' |
        _launcher_select "Yandex VPN") || return 0
      ;;
    homebrew)
      selected=$(printf '%s\n' \
        'list|Установленные пакеты' \
        'outdated|Доступные обновления' \
        'update|Обновить индексы Homebrew' \
        'upgrade|Обновить пакеты' \
        'doctor|Диагностика Homebrew' |
        _launcher_select "Homebrew") || return 0
      ;;
    git)
      selected=$(printf '%s\n' \
        'status|Статус репозитория' \
        'log|Последние 10 коммитов' \
        'branch|Локальные ветки' \
        'diff|Незакоммиченные изменения' |
        _launcher_select "Git") || return 0
      ;;
    python)
      selected=$(printf '%s\n' \
        'version|Версия Python' \
        'repl|Интерактивный Python' \
        'venv|Создать .venv в текущей папке' \
        'packages|Установленные Python-пакеты' |
        _launcher_select "Python") || return 0
      ;;
    sublime|vscode)
      selected=$(printf '%s\n' \
        'app|Открыть приложение' \
        'folder|Открыть текущую папку' |
        _launcher_select "Editor") || return 0
      ;;
    adb)
      selected=$(printf '%s\n' \
        'devices|Подключённые устройства' \
        'shell|ADB shell' \
        'restart|Перезапустить ADB server' \
        'info|Информация об устройстве' |
        _launcher_select "Android ADB") || return 0
      ;;
    *) return 1 ;;
  esac

  action="${selected%%|*}"
  print

  case "$category:$action" in
    ollama:list) ollama list ;;
    ollama:ps) ollama ps ;;
    ollama:version) ollama --version ;;
    ollama:run)
      ollama list
      _launcher_prompt "Модель" || return 0
      model="$REPLY"
      ollama run "$model"
      ;;
    ollama:show)
      _launcher_prompt "Модель" || return 0
      model="$REPLY"
      ollama show "$model"
      ;;

    opencode:ai) ai ;;
    opencode:code) code ;;
    opencode:models) opencode models ;;
    opencode:agents) opencode debug agents ;;

    codex:start) codex ;;
    codex:resume) codex resume ;;

    vpn:udp) _launcher_vpn_start udp ;;
    vpn:tcp) _launcher_vpn_start tcp ;;

    homebrew:list) brew list ;;
    homebrew:outdated) brew outdated ;;
    homebrew:update) brew update ;;
    homebrew:doctor) brew doctor ;;
    homebrew:upgrade)
      _launcher_prompt "Обновить установленные пакеты? [y/n]" yesno || return 0
      [[ "$REPLY" == yes ]] && brew upgrade
      ;;

    git:status) git status ;;
    git:log) git log -10 --oneline --decorate ;;
    git:branch) git branch ;;
    git:diff) git diff ;;

    python:version) python3 --version ;;
    python:repl) python3 ;;
    python:packages) python3 -m pip list ;;
    python:venv)
      if [[ -e .venv ]]; then
        print -r -- ".venv уже существует"
      else
        python3 -m venv .venv
      fi
      ;;

    sublime:app) open -a "Sublime Text" ;;
    sublime:folder) open -a "Sublime Text" "$PWD" ;;
    vscode:app) open -a "Visual Studio Code" ;;
    vscode:folder) open -a "Visual Studio Code" "$PWD" ;;

    adb:devices) adb devices -l ;;
    adb:shell) adb shell ;;
    adb:restart) adb kill-server && adb start-server ;;
    adb:info)
      adb shell getprop ro.product.model
      adb shell getprop ro.build.version.release
      ;;
  esac
}

# ============================================================
# Main launcher
# ============================================================

launcher() {
  local selected category git_info ollama_info brew_info
  local -a menu_items

  # Do not run nested menus in the same shell.
  [[ "${_LAUNCHER_ACTIVE:-0}" != 1 ]] || return 0
  [[ -t 0 && -t 1 ]] || return 0
  _launcher_tty_ok || return 0

  # Scoped traps: do not overwrite the user's normal terminal handlers.
  # HUP/TERM can arrive when Terminal.app/tab closes; never retry fzf/read.
  emulate -L zsh
  setopt localtraps
  local _LAUNCHER_ACTIVE=1
  trap '_launcher_log "received SIGHUP"; return 129' HUP
  trap '_launcher_log "received SIGTERM"; return 143' TERM
  # The shell receives SIGINT for interactive commands itself. We deliberately
  # do not catch it globally: Ctrl+C must still stop ping/ollama normally.
  _launcher_log "launcher start"

  if ! command -v fzf >/dev/null 2>&1; then
    print -r -- "Не найден fzf. Установи: brew install fzf"
    return 1
  fi

  # If Terminal.app closes or stdin/stdout loses its TTY, stop immediately.
  while _launcher_tty_ok; do
    git_info=$(_launcher_git_status)
    ollama_info=$(_launcher_ollama_status)
    brew_info=$(_launcher_brew_status)

    menu_items=(
      "vpn|Yandex VPN|UDP / TCP"
      "ollama|Ollama|$ollama_info"
      "opencode|OpenCode|AI-агенты"
      "codex|Codex|CLI"
      "chatgpt|ChatGPT|Desktop"
      "network|Сетевые утилиты|Ping / DNS / HTTP / TCP"
      "devtools|Инструменты разработчика|UUID / JSON / Base64 / JWT"
      "homebrew|Homebrew|$brew_info"
      "git|Git|$git_info"
      "python|Python|Окружение"
      "sublime|Sublime Text|Редактор"
      "vscode|VS Code|Редактор"
      "adb|Android ADB|Устройства"
      "refresh|Обновить статусы Homebrew|Перепроверить пакеты"
      "exit|Терминал|Вернуться в shell"
    )

    # Do not hand fzf a new menu if the terminal disappeared while
    # collecting dynamic statuses. Empty/failed selections leave cleanly.
    _launcher_tty_ok || { _launcher_log "tty lost during statuses"; break; }
    selected=$(
      _launcher_format_items "${menu_items[@]}" |
        _launcher_select "Quick Menu"
    ) || { _launcher_log "fzf cancelled/closed"; break; }
    [[ -n "$selected" ]] || break
    _launcher_tty_ok || { _launcher_log "tty lost after fzf"; break; }

    category="${selected%%|*}"
    _launcher_log "selected $category"
    case "$category" in
      chatgpt) open -a "ChatGPT"; return ;;
      network) _launcher_network; return ;;
      devtools) _launcher_devtools; return ;;
      refresh) rm -f -- "$_LAUNCHER_BREW_CACHE"; continue ;;
      exit) return ;;
      *) _launcher_action "$category"; return ;;
    esac
  done
  _launcher_log "launcher exit"
  return 0
}
