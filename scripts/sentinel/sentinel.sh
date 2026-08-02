#!/usr/bin/env bash
# sentinel.sh — сторож целостности сервера. Ловит то, что произошло 02.07.2026:
# чужой ключ в authorized_keys, новый UID0-юзер, sudoers, новый публичный порт, чужой cron.
# Команды:
#   check     — сверка с эталоном (cron */10 мин); молчит пока чисто, TG-алерт при отклонении
#   baseline  — зафиксировать текущее состояние как эталон (только по команде Саши!)
#   heartbeat — суточный пульс: «чисто» или «висит незакрытое отклонение»
#   test      — тестовый TG-алерт (проверка канала)
set -euo pipefail

ENV_FILE="${SENTINEL_ENV:-/root/.secrets/sentinel.env}"
BASE_DIR="${SENTINEL_BASE:-/var/lib/sentinel}"
LOG="${SENTINEL_LOG:-/var/log/sentinel.log}"
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && . "$ENV_FILE"
: "${SENTINEL_HOST:=$(hostname)}"
: "${SENTINEL_TG_TOKEN:=}"
: "${SENTINEL_CHAT_ID:=}"

BASELINE="$BASE_DIR/baseline.txt"
LAST_ALERT="$BASE_DIR/last_alert.sha"
KNOWN_IPS="${SENTINEL_KNOWN_IPS:-$BASE_DIR/known_ips}"
KNOWN_KEYS="${SENTINEL_KNOWN_KEYS:-$BASE_DIR/known_keys}"   # строки: «SHA256:… человекочитаемое имя ключа»
AUTH_LOG="${SENTINEL_AUTH_LOG:-/var/log/auth.log}"

logline() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# Экранирование данных, вставляемых в HTML-сообщение (&, <, >).
html_esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<<"$1"; }

# tg_send TEXT [REPLY_MARKUP_JSON] — второй аргумент = inline-клавиатура (кнопки одобрить/блок).
# Текст — HTML (parse_mode=HTML); если Telegram отверг разметку — повтор как plain text (алерт важнее красоты).
tg_send() {
  local text="$1" kb="${2:-}"
  if [[ -z "$SENTINEL_TG_TOKEN" || -z "$SENTINEL_CHAT_ID" ]]; then
    logline "TG не настроен, сообщение только в лог: $text"
    return 0
  fi
  local args=(-sS -m 10
    --data-urlencode "chat_id=$SENTINEL_CHAT_ID"
    --data-urlencode "text=$text")
  [[ -n "$kb" ]] && args+=(--data-urlencode "reply_markup=$kb")
  local resp
  resp="$(curl "${args[@]}" --data-urlencode "parse_mode=HTML" \
    "https://api.telegram.org/bot$SENTINEL_TG_TOKEN/sendMessage" 2>/dev/null)" || true
  if ! grep -q '"ok":true' <<<"$resp"; then
    curl "${args[@]}" \
      "https://api.telegram.org/bot$SENTINEL_TG_TOKEN/sendMessage" >/dev/null \
      || logline "TG send FAILED"
  fi
}

# Уникальные IP успешных SSH-логинов из auth.log.
accepted_ips() {
  grep -haE "Accepted (publickey|password) for" "$AUTH_LOG" 2>/dev/null \
    | grep -haoE 'from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}' | sort -u
}

# Новый успешный SSH-вход (IP не в known_ips) → алерт со всей инфой + кнопки [Это я][Заблокировать].
check_ssh_logins() {
  [[ -r "$AUTH_LOG" ]] || return 0
  touch "$KNOWN_IPS"
  local ip line user method keyfp keyname keymark
  while read -r ip; do
    [[ -z "$ip" ]] && continue
    grep -qxF "$ip" "$KNOWN_IPS" && continue
    line="$(grep -haF " from $ip " "$AUTH_LOG" | grep -aE 'Accepted (publickey|password)' | tail -1)"
    user="$(sed -nE 's/.*Accepted (publickey|password) for ([^ ]+) .*/\2/p' <<<"$line")"
    method="$(grep -aoE 'Accepted (publickey|password)' <<<"$line" | awk '{print $2}')"
    keyfp="$(grep -aoE 'SHA256:[A-Za-z0-9+/]+' <<<"$line" || true)"
    keyname=""
    [[ -n "$keyfp" && -r "$KNOWN_KEYS" ]] && keyname="$(awk -v fp="$keyfp" '$1==fp{$1="";sub(/^ +/,"");print;exit}' "$KNOWN_KEYS")"
    if [[ -n "$keyname" ]]; then
      keymark="    ✅ Ключ НАШ: <b>$(html_esc "$keyname")</b> — IP просто новый (мобильный пул)."
    elif [[ "$method" == "password" ]]; then
      keymark="    🚨 Вход ПО ПАРОЛЮ — у нас key-only, это ТРЕВОГА."
    else
      keymark="    🚨 Ключ НЕ из списка наших ($KNOWN_KEYS) — если это не ты, ТРЕВОГА."
    fi
    echo "$ip" >> "$KNOWN_IPS"   # запоминаем, чтобы алертить один раз
    logline "НОВЫЙ SSH-вход ip=$ip user=$user method=$method key=${keyfp:-—} known=${keyname:-нет}"
    local kb='{"inline_keyboard":[[{"text":"✅ Это я","callback_data":"sec|trust|'"$ip"'"},{"text":"⛔ Заблокировать IP","callback_data":"sec|ban|'"$ip"'"}]]}'
    tg_send "🔐 <b>Новый SSH-вход · $SENTINEL_HOST</b>

    👤 Пользователь: <code>$(html_esc "${user:-?}")</code>
    🌍 IP: <code>$ip</code>
    🗝 Метод: ${method:-?} · ключ <code>$(html_esc "${keyfp:-—}")</code>
$keymark
    🕒 $(date '+%F %T %Z')

<b>Это был ты?</b>
    ✅ Да — жми «Это я».
    ⛔ Нет — жми «Заблокировать IP» и срочно проверь <code>authorized_keys</code>." "$kb"
  done < <(accepted_ips)
}

snapshot() {
  echo "## authorized_keys (sha256)"
  for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    [[ -f "$f" ]] && sha256sum "$f" 2>/dev/null || true
  done
  echo "## uid0-юзеры"
  awk -F: '$3==0{print $1}' /etc/passwd || true
  echo "## sudoers (sha256)"
  sha256sum /etc/sudoers 2>/dev/null || true
  find /etc/sudoers.d -type f -exec sha256sum {} \; 2>/dev/null | sort || true
  echo "## публичные LISTEN-порты"
  ss -Htln 2>/dev/null | awk '{print $4}' | grep -Ev '^(127\.|\[::1\])' | sort -u || true
  echo "## cron (sha256)"
  sha256sum /etc/crontab 2>/dev/null || true
  find /etc/cron.d /var/spool/cron -type f -exec sha256sum {} \; 2>/dev/null | sort || true
}

# --- Человеческий пересказ отклонений для TG (сырой diff остаётся в /var/log/sentinel.log) ---
_section() { awk -v s="## $1" 'BEGIN{f=0} $0==s{f=1;next} /^## /{if(f==1)exit} f==1' "$2" 2>/dev/null || true; }

_added_removed() {  # $1=старый текст $2=новый → _ADD/_DEL (построчно)
  _ADD="$(comm -13 <(sort -u <<<"$1") <(sort -u <<<"$2") 2>/dev/null | grep -v '^[[:space:]]*$' || true)"
  _DEL="$(comm -23 <(sort -u <<<"$1") <(sort -u <<<"$2") 2>/dev/null | grep -v '^[[:space:]]*$' || true)"
}

_human_hashes() {  # $1=секция $2=baseline $3=current $4=заголовок (для секций «sha256 путь»)
  local b c out="" ln pth
  b="$(_section "$1" "$2")"; c="$(_section "$1" "$3")"
  [[ "$b" == "$c" ]] && return 0
  _added_removed "$b" "$c"
  while IFS= read -r ln; do
    [[ -z "$ln" ]] && continue
    pth="$(awk '{print $2}' <<<"$ln")"; [[ -z "$pth" ]] && continue
    if grep -qF "$pth" <<<"$b"; then out+="    ✏️ изменился: <code>$(html_esc "$pth")</code>"$'\n'; else out+="    ➕ новый: <code>$(html_esc "$pth")</code>"$'\n'; fi
  done <<<"$_ADD"
  while IFS= read -r ln; do
    [[ -z "$ln" ]] && continue
    pth="$(awk '{print $2}' <<<"$ln")"; [[ -z "$pth" ]] && continue
    grep -qF "$pth" <<<"$c" || out+="    ➖ удалён: <code>$(html_esc "$pth")</code>"$'\n'
  done <<<"$_DEL"
  [[ -n "$out" ]] && printf '%s\n%s' "$4" "$out"
  return 0
}

_human_lines() {  # $1=секция $2=baseline $3=current $4=заголовок $5=метка➕ $6=метка➖
  local b c out=""
  b="$(_section "$1" "$2")"; c="$(_section "$1" "$3")"
  [[ "$b" == "$c" ]] && return 0
  _added_removed "$b" "$c"
  [[ -n "$_ADD" ]] && out+="$(html_esc "$_ADD" | sed "s|^|    $5 <code>|; s|\$|</code>|")"$'\n'
  [[ -n "$_DEL" ]] && out+="$(html_esc "$_DEL" | sed "s|^|    $6 <code>|; s|\$|</code>|")"$'\n'
  [[ -n "$out" ]] && printf '%s\n%s' "$4" "$out"
  return 0
}

humanize() {  # $1=baseline файл, $2=файл текущего снапшота
  local out="" h
  h="$(_human_lines "публичные LISTEN-порты" "$1" "$2" "🌐 <b>Порты, открытые в интернет</b>" "ОТКРЫЛСЯ:" "закрылся:")" || true
  [[ -n "$h" ]] && out+="$h"$'\n'
  h="$(_human_hashes "authorized_keys (sha256)" "$1" "$2" "🔑 <b>SSH-ключи доступа</b> (кто может входить на сервер)")" || true
  [[ -n "$h" ]] && out+="$h"$'\n'
  h="$(_human_lines "uid0-юзеры" "$1" "$2" "👑 <b>Пользователи с правами root</b>" "НОВЫЙ:" "убран:")" || true
  [[ -n "$h" ]] && out+="$h"$'\n'
  h="$(_human_hashes "sudoers (sha256)" "$1" "$2" "📜 <b>Права sudo</b>")" || true
  [[ -n "$h" ]] && out+="$h"$'\n'
  h="$(_human_hashes "cron (sha256)" "$1" "$2" "⏰ <b>Планировщик задач (cron)</b>")" || true
  [[ -n "$h" ]] && out+="$h"$'\n'
  printf '%s' "$out"
  return 0
}

cmd="${1:-check}"
mkdir -p "$BASE_DIR"

case "$cmd" in
  baseline)
    snapshot > "$BASELINE"
    rm -f "$LAST_ALERT"
    # Засеять известные SSH-IP, чтобы первый прогон не завалил алертами по историческим входам.
    touch "$KNOWN_IPS"
    while read -r ip; do
      [[ -n "$ip" ]] && ! grep -qxF "$ip" "$KNOWN_IPS" && echo "$ip" >> "$KNOWN_IPS"
    done < <(accepted_ips)
    logline "baseline зафиксирован ($(wc -l < "$BASELINE") строк, known_ips=$(wc -l < "$KNOWN_IPS"))"
    echo "✅ Эталон зафиксирован: $BASELINE (+ known SSH IP: $(wc -l < "$KNOWN_IPS"))"
    ;;

  check)
    check_ssh_logins   # новые SSH-входы — независимо от структурного baseline
    if [[ ! -f "$BASELINE" ]]; then
      logline "check: baseline отсутствует — запусти 'sentinel.sh baseline'"
      exit 0
    fi
    current="$(snapshot)"
    d="$(diff "$BASELINE" <(printf '%s\n' "$current") || true)"
    if [[ -z "$d" ]]; then
      rm -f "$LAST_ALERT"
      exit 0
    fi
    dhash="$(printf '%s' "$d" | sha256sum | cut -d' ' -f1)"
    if [[ -f "$LAST_ALERT" && "$(cat "$LAST_ALERT")" == "$dhash" ]]; then
      exit 0   # то же отклонение уже отправлено — не спамим (heartbeat напомнит)
    fi
    echo "$dhash" > "$LAST_ALERT"
    logline "ОТКЛОНЕНИЕ: $d"
    curf="$(mktemp)"; printf '%s\n' "$current" > "$curf"
    human="$(humanize "$BASELINE" "$curf")" || true
    rm -f "$curf"
    [[ -z "$human" ]] && human="${d:0:1500}"
    kb='{"inline_keyboard":[[{"text":"✅ Это я — зафиксировать норму","callback_data":"sec|baseline"}]]}'
    tg_send "🚨 <b>Сторож · $SENTINEL_HOST</b>
Изменилось критичное состояние сервера.

${human:0:3300}
<b>Это менял ты</b> (или Алиса по твоей команде)?
    ✅ Да — жми «Это я», новое состояние станет нормой.
    ⛔ Нет — кнопку НЕ жми: сервер трогают чужие.
Тогда срочно проверь <code>authorized_keys</code> и открытые порты.

📄 Полный diff: <code>/var/log/sentinel.log</code>" "$kb"
    ;;

  humantest)
    if [[ ! -f "$BASELINE" ]]; then echo "нет baseline"; exit 0; fi
    current="$(snapshot)"
    curf="$(mktemp)"; printf '%s\n' "$current" > "$curf"
    humanize "$BASELINE" "$curf" || true
    rm -f "$curf"
    ;;

  heartbeat)
    if [[ ! -f "$BASELINE" ]]; then
      tg_send "⚠️ <b>Сторож · $SENTINEL_HOST</b>
Жив, но эталон не зафиксирован — сравнивать не с чем.
Зафиксируй: <code>sentinel.sh baseline</code>"
      exit 0
    fi
    current="$(snapshot)"
    d="$(diff "$BASELINE" <(printf '%s\n' "$current") || true)"
    if [[ -z "$d" ]]; then
      logline "heartbeat: чисто (TG не шлём — только отклонения)"
    else
      tg_send "⚠️ <b>Сторож · $SENTINEL_HOST</b> — суточное напоминание

Отклонение от эталона висит незакрытым.
    ✅ Твоё изменение — зафиксируй норму (кнопка «Это я» на алерте).
    ⛔ Не твоё — тревога, проверь сервер.

📄 Детали: <code>/var/log/sentinel.log</code>"
    fi
    ;;

  test)
    tg_send "🔐 <b>Сторож · $SENTINEL_HOST</b>
Тест канала алертов — всё настроено, я на связи."
    echo "Отправлено (или в лог, если TG не настроен)."
    ;;

  *)
    echo "Использование: $0 check|baseline|heartbeat|test|humantest" >&2
    exit 1
    ;;
esac
