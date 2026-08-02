#!/usr/bin/env bash
# Обвязка cron для sentinel.sh: TG-алерт если сторож УПАЛ (краш скрипта).
# Алерты об отклонениях шлёт сам sentinel.sh — здесь только "сторож не работает".
FLAG=/var/lib/sentinel/crash_alerted
if /usr/local/bin/sentinel.sh "$1" >/dev/null 2>&1; then
  rm -f "$FLAG"
else
  rc=$?
  [[ -f "$FLAG" ]] && exit 0
  touch "$FLAG"
  . /root/.secrets/sentinel.env 2>/dev/null || true
  [[ -n "${SENTINEL_TG_TOKEN:-}" && -n "${SENTINEL_CHAT_ID:-}" ]] && curl -sS -m 10 \
    --data-urlencode "chat_id=$SENTINEL_CHAT_ID" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=🔴 <b>Сторож · ${SENTINEL_HOST:-$(hostname)}</b>
УПАЛ: <code>sentinel.sh $1</code> завершился ошибкой (exit $rc).
Сервер сейчас БЕЗ присмотра — проверь <code>/var/log/sentinel.log</code> и cron." \
    "https://api.telegram.org/bot$SENTINEL_TG_TOKEN/sendMessage" >/dev/null 2>&1
fi
