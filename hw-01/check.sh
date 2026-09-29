#!/usr/bin/env bash
# Проверяет стенд ДЗ 1. Код возврата: 0 — все проверки прошли, 1 — хотя бы одна нет.
# Написан для раннера: вывод — по строке на проверку, решение — по коду возврата.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=params.sh
source "$DIR/params.sh"
load_params "$@"
need yc jq curl ssh

SSH_USER="${SSH_USER:-student}"
TRIES=20 # запросов к балансировщику для проверки распределения
FAILED=0
ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAILED=1; }

vm_json() { yc compute instance get "$1" --format json 2>/dev/null; }

# 1-2. Балансировщик и распределение
LB_IP=$(yc load-balancer network-load-balancer get "$PREFIX-lb" --format json 2>/dev/null |
  jq -r '.listeners[0].address // empty')
if [ -z "$LB_IP" ]; then
  bad "балансировщика $PREFIX-lb нет"
  bad "распределение не проверить: нет балансировщика"
else
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$LB_IP/")
  if [ "$code" = 200 ]; then
    ok "балансировщик $LB_IP отвечает: $code"
  else
    bad "балансировщик $LB_IP отвечает: $code"
  fi
  hosts=$(for _ in $(seq 1 "$TRIES"); do curl -s --max-time 3 "http://$LB_IP/"; echo; done |
    sed -n "s/^$WORD on //p" | sort -u)
  count=$(grep -c . <<<"$hosts")
  list=$(paste -sd, <<<"$hosts" | sed 's/,/, /g')
  if [ "$count" -gt 1 ]; then
    ok "ответили машины: $list"
  elif [ "$count" -eq 1 ]; then
    bad "за $TRIES запросов ответила только $list: распределения нет"
  else
    bad "за $TRIES запросов не ответила ни одна машина"
  fi
fi

# 3-4. Сервер приложения: закрыт снаружи и доступен с веб-сервера
APP_JSON=$(vm_json "$PREFIX-app")
if [ -z "$APP_JSON" ]; then
  bad "сервера приложения $PREFIX-app нет"
  bad "публичный адрес сервера приложения не проверить: машины нет"
else
  APP_IP=$(jq -r '.network_interfaces[0].primary_v4_address.address' <<<"$APP_JSON")
  APP_NAT=$(jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address // empty' <<<"$APP_JSON")

  # заходим на первый веб-сервер, до которого есть ssh; nginx на нём может быть и остановлен
  answered=""
  for web in $(yc compute instance list --format json |
    jq -r --arg p "$PREFIX-web-" '.[] | select(.name | startswith($p)) | select(.status == "RUNNING") | .name' | sort -V); do
    WEB_IP=$(vm_json "$web" | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address // empty')
    [ -n "$WEB_IP" ] || continue
    if code=$(ssh -n -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      "$SSH_USER@$WEB_IP" \
      "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://$APP_IP:$APP_PORT/ || true"); then
      answered="$web"
      break
    fi
  done
  if [ -z "$answered" ]; then
    bad "ни на один веб-сервер не удалось зайти по ssh, сервер приложения не проверить"
  elif [ "$code" = 200 ]; then
    ok "сервер приложения $APP_IP:$APP_PORT отвечает с ${answered#"$PREFIX"-}: $code"
  else
    bad "сервер приложения $APP_IP:$APP_PORT недоступен с ${answered#"$PREFIX"-}: $code"
  fi

  if [ -z "$APP_NAT" ]; then
    ok "у сервера приложения нет публичного адреса"
  else
    bad "у сервера приложения есть публичный адрес $APP_NAT"
  fi
fi

exit "$FAILED"
