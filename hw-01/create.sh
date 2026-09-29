#!/usr/bin/env bash
# Поднимает стенд ДЗ 1: сеть, две подсети, NAT-шлюз с таблицей маршрутизации,
# веб-серверы в двух зонах, сервер приложения без публичного адреса, балансировщик.
# Повторный запуск не падает и не создаёт дубликатов: перед каждым созданием проверка.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=params.sh
source "$DIR/params.sh"
load_params "$@"
show_params

need yc jq envsubst curl ssh
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
[ -s "$SSH_PUBKEY" ] || die "нет публичного ключа $SSH_PUBKEY (можно указать через SSH_PUBKEY)"

LABELS="env=$ENV_NAME,owner=$PREFIX"
NET="$PREFIX-net"
SUB_A="$PREFIX-subnet-a"
SUB_B="$PREFIX-subnet-b"
NAT="$PREFIX-nat"
RT="$PREFIX-rt"
APP="$PREFIX-app"
TG="$PREFIX-tg"
LB="$PREFIX-lb"

step() { echo "==> $*"; }

# 0 — ресурс есть, 1 — ресурса нет. Любая другая ошибка (сеть, токен, квота)
# не выдаётся за «нет ресурса»: печатаем её и останавливаемся.
exists() {
  local err
  # shellcheck disable=SC2086
  if err=$(yc $1 get "$2" 2>&1 >/dev/null); then return 0; fi
  if grep -Eqi 'not[ _]?found' <<<"$err"; then return 1; fi
  printf '%s\n' "$err" >&2
  die "не удалось проверить $1 $2, и это не «не найдено»"
}

# ensure "вид ресурса" ИМЯ команда создания...
ensure() {
  local kind="$1" name="$2"
  shift 2
  if exists "$kind" "$name"; then
    echo "    = $name уже есть, пропускаю"
  else
    "$@" >/dev/null
    echo "    + $name создан"
  fi
}

# Машина: создать, если нет; запустить, если прерываемую машину остановило облако.
ensure_vm() {
  local name="$1" zone="$2" subnet="$3" public="$4" nic status
  nic="subnet-name=$subnet"
  [ "$public" = yes ] && nic="$nic,nat-ip-version=ipv4"
  if exists "compute instance" "$name"; then
    status=$(yc compute instance get "$name" --format json | jq -r .status)
    if [ "$status" = STOPPED ]; then
      yc compute instance start "$name" >/dev/null
      echo "    ~ $name была остановлена, запустил"
    else
      echo "    = $name уже есть ($status), пропускаю"
    fi
    return
  fi
  yc compute instance create \
    --name "$name" --hostname "$name" \
    --zone "$zone" \
    --platform standard-v3 --cores 2 --core-fraction 20 --memory 2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size=20 \
    --network-interface "$nic" \
    --metadata-from-file user-data="$CLOUD_INIT" \
    --labels "$LABELS" >/dev/null
  echo "    + $name создан ($zone, публичный адрес: $([ "$public" = yes ] && echo есть || echo нет))"
}

step "сеть и подсети"
ensure "vpc network" "$NET" yc vpc network create --name "$NET" --labels "$LABELS"
ensure "vpc subnet" "$SUB_A" yc vpc subnet create --name "$SUB_A" --network-name "$NET" \
  --zone "$ZONE_A" --range "$CIDR_A" --labels "$LABELS"
ensure "vpc subnet" "$SUB_B" yc vpc subnet create --name "$SUB_B" --network-name "$NET" \
  --zone "$ZONE_B" --range "$CIDR_B" --labels "$LABELS"

step "NAT-шлюз и таблица маршрутизации для подсети A"
ensure "vpc gateway" "$NAT" yc vpc gateway create --name "$NAT" --labels "$LABELS"
GW_ID=$(yc vpc gateway get "$NAT" --format json | jq -r .id)
ensure "vpc route-table" "$RT" yc vpc route-table create --name "$RT" --network-name "$NET" \
  --route "destination=0.0.0.0/0,gateway-id=$GW_ID" --labels "$LABELS"
RT_ID=$(yc vpc route-table get "$RT" --format json | jq -r .id)
if [ "$(yc vpc subnet get "$SUB_A" --format json | jq -r '.route_table_id // ""')" = "$RT_ID" ]; then
  echo "    = $SUB_A уже ходит через $RT, пропускаю"
else
  yc vpc subnet update "$SUB_A" --route-table-name "$RT" >/dev/null
  echo "    + $SUB_A привязана к $RT"
fi

step "файл настройки из шаблона"
CLOUD_INIT=$(mktemp)
trap 'rm -f "$CLOUD_INIT"' EXIT
SSH_KEY=$(cat "$SSH_PUBKEY")
export SSH_KEY
# shellcheck disable=SC2016 # имена для envsubst, раскрывать их здесь не нужно
envsubst '${APP_PORT} ${WORD} ${SSH_KEY}' <"$DIR/cloud-init.tpl.yaml" >"$CLOUD_INIT"
echo "    готов, порт $APP_PORT, слово $WORD"

step "веб-серверы: $WEB_COUNT шт. в зонах $ZONE_A и $ZONE_B"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$SUB_A" "$SUB_B")
for i in $(seq 1 "$WEB_COUNT"); do
  idx=$(((i - 1) % 2))
  ensure_vm "$PREFIX-web-$i" "${ZONES[$idx]}" "${SUBNETS[$idx]}" yes
done

step "сервер приложения без публичного адреса"
ensure_vm "$APP" "$ZONE_A" "$SUB_A" no

step "целевая группа"
TARGETS=()
for i in $(seq 1 "$WEB_COUNT"); do
  idx=$(((i - 1) % 2))
  ip=$(yc compute instance get "$PREFIX-web-$i" --format json |
    jq -r '.network_interfaces[0].primary_v4_address.address')
  TARGETS+=("subnet-name=${SUBNETS[$idx]},address=$ip")
done
if exists "load-balancer target-group" "$TG"; then
  have=$(yc load-balancer target-group get "$TG" --format json | jq -r '.targets[]?.address')
  added=0
  for t in "${TARGETS[@]}"; do
    ip="${t##*address=}"
    if ! grep -qxF "$ip" <<<"$have"; then
      yc load-balancer target-group add-targets "$TG" --target "$t" >/dev/null
      echo "    + в $TG добавлен $ip"
      added=1
    fi
  done
  [ "$added" -eq 1 ] || echo "    = $TG уже есть, все веб-серверы в ней, пропускаю"
else
  TG_ARGS=()
  for t in "${TARGETS[@]}"; do TG_ARGS+=(--target "$t"); done
  yc load-balancer target-group create --name "$TG" "${TG_ARGS[@]}" --labels "$LABELS" >/dev/null
  echo "    + $TG создан, целей: ${#TARGETS[@]}"
fi
TG_ID=$(yc load-balancer target-group get "$TG" --format json | jq -r .id)

step "балансировщик"
ensure "load-balancer network-load-balancer" "$LB" \
  yc load-balancer network-load-balancer create --name "$LB" --region-id ru-central1 \
  --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
  --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/ \
  --labels "$LABELS"

step "ожидание: все веб-серверы HEALTHY"
for attempt in $(seq 1 60); do
  healthy=$(yc load-balancer network-load-balancer target-states --name "$LB" --target-group-id "$TG_ID" --format json |
    jq '[.[] | select(.status == "HEALTHY")] | length')
  echo "    попытка $attempt: HEALTHY $healthy из $WEB_COUNT"
  [ "$healthy" -ge "$WEB_COUNT" ] && break
  [ "$attempt" -eq 60 ] && die "за 10 минут веб-серверы так и не стали HEALTHY"
  sleep 10
done

step "ожидание: check.sh проходит целиком (сервер приложения настраивается дольше)"
for attempt in $(seq 1 30); do
  if "$DIR/check.sh" >/dev/null 2>&1; then break; fi
  echo "    попытка $attempt: check.sh ещё не проходит"
  if [ "$attempt" -eq 30 ]; then
    "$DIR/check.sh" || true
    die "стенд поднят, но проверка не проходит"
  fi
  sleep 10
done
"$DIR/check.sh"

LB_IP=$(yc load-balancer network-load-balancer get "$LB" --format json | jq -r '.listeners[0].address')
echo "==> готово: http://$LB_IP"
