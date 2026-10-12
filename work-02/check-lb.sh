#!/usr/bin/env bash
# Ждёт, пока балансировщик начнёт отдавать ответы обеих машин,
# и печатает десять ответов подряд.
set -euo pipefail

PREFIX=${PREFIX:-vetrov-09}
GREETING=${GREETING:-cloudlab}
WAIT=${WAIT:-300} # сколько ждать, секунд

LB_IP=$(yc load-balancer network-load-balancer get --name "$PREFIX-lb" --format json \
  | jq -r '.listeners[0].address')
if [[ -z "$LB_IP" || "$LB_IP" == "null" ]]; then
  echo "у балансировщика $PREFIX-lb нет внешнего адреса" >&2
  exit 1
fi

echo "==> жду ответов обеих машин от http://$LB_IP, не дольше $WAIT с"
seen_1=no
seen_2=no
while (( SECONDS < WAIT )); do
  # пока проверки состояния не прошли, балансировщик не отвечает вовсе:
  # это не ошибка, а ожидание, поэтому код curl здесь не проверяем
  answer=$(curl -s --max-time 3 "http://$LB_IP" || true)
  case "$answer" in
    "$GREETING on $PREFIX-app-1") seen_1=yes ;;
    "$GREETING on $PREFIX-app-2") seen_2=yes ;;
  esac
  if [[ $seen_1 == yes && $seen_2 == yes ]]; then
    break
  fi
  sleep 2
done

if [[ $seen_1 != yes || $seen_2 != yes ]]; then
  echo "за $WAIT с ответили не обе машины: app-1 — $seen_1, app-2 — $seen_2" >&2
  exit 1
fi

echo "==> обе машины отвечают, прошло $SECONDS с; десять запросов подряд"
for _ in $(seq 1 10); do
  curl -s --max-time 3 "http://$LB_IP" || echo "нет ответа"
done
