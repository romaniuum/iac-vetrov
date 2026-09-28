#!/usr/bin/env bash
set -euo pipefail

PREFIX=vetrov-09
ZONE_A=ru-central1-d
ZONE_B=ru-central1-a
CIDR_A=10.19.1.0/24
CIDR_B=10.19.2.0/24
APP_PORT=8027
GREETING=cloudlab
VM_COUNT="${1:-2}"
DISK_SIZE="${2:-15}"
BOOT_SIZE=25
IMAGE_FAMILY=ubuntu-2404-lts

DIR="$(cd "$(dirname "$0")" && pwd)"

die() { echo "ошибка: $*" >&2; exit 1; }

[[ "$VM_COUNT" =~ ^[1-9][0-9]*$ ]] || die "число машин должно быть целым больше нуля, получено: $VM_COUNT"
[[ "$DISK_SIZE" =~ ^[1-9][0-9]*$ ]] || die "размер диска должен быть целым числом ГБ, получено: $DISK_SIZE"
for cmd in yc jq envsubst; do
  command -v "$cmd" >/dev/null 2>&1 || die "не найдена утилита $cmd"
done
[ -s ~/.ssh/id_ed25519.pub ] || die "нет публичного ключа ~/.ssh/id_ed25519.pub"
if [ -n "$(yc vpc network list --format json | jq -r --arg n "$PREFIX-net" '.[] | select(.name == $n) | .id')" ]; then
  die "сеть $PREFIX-net уже есть: сначала запустите destroy.sh"
fi

echo "==> стенд $PREFIX: машин $VM_COUNT, дополнительный диск $DISK_SIZE ГБ"

echo "==> сеть и подсети"
yc vpc network create --name "$PREFIX-net"
yc vpc subnet create --name "$PREFIX-subnet-a" --network-name "$PREFIX-net" \
  --zone "$ZONE_A" --range "$CIDR_A"
yc vpc subnet create --name "$PREFIX-subnet-b" --network-name "$PREFIX-net" \
  --zone "$ZONE_B" --range "$CIDR_B"

echo "==> файл настройки из шаблона"
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < "$DIR/cloud-init.tpl.yaml" > "$DIR/cloud-init.yaml"

echo "==> дополнительный диск"
yc compute disk create --name "$PREFIX-data" --zone "$ZONE_A" \
  --size "$DISK_SIZE" --type network-hdd

echo "==> машины"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")
for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  EXTRA=()
  if [ "$i" -eq 1 ]; then
    EXTRA=(--attach-disk disk-name="$PREFIX-data",device-name=data)
  fi
  yc compute instance create \
    --name "$PREFIX-app-$i" \
    --zone "${ZONES[$idx]}" \
    --platform standard-v3 \
    --cores=2 --core-fraction=20 --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
    --network-interface subnet-name="${SUBNETS[$idx]}",nat-ip-version=ipv4 \
    --hostname "$PREFIX-app-$i" \
    --metadata-from-file user-data="$DIR/cloud-init.yaml" \
    "${EXTRA[@]}"
done

echo "==> целевая группа"
TARGETS=()
for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  IP=$(yc compute instance get "$PREFIX-app-$i" --format json \
    | jq -r '.network_interfaces[0].primary_v4_address.address')
  TARGETS+=(--target "subnet-name=${SUBNETS[$idx]},address=$IP")
done
yc load-balancer target-group create --name "$PREFIX-tg" "${TARGETS[@]}"

echo "==> балансировщик"
TG_ID=$(yc load-balancer target-group get --name "$PREFIX-tg" --format json | jq -r .id)
yc load-balancer network-load-balancer create \
  --name "$PREFIX-lb" \
  --region-id ru-central1 \
  --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
  --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/

echo "==> ожидание готовности машин"
for attempt in $(seq 1 60); do
  HEALTHY=$(yc load-balancer network-load-balancer target-states \
    --name "$PREFIX-lb" --target-group-id "$TG_ID" --format json \
    | jq '[.[] | select(.status == "HEALTHY")] | length')
  echo "    попытка $attempt: HEALTHY $HEALTHY из $VM_COUNT"
  [ "$HEALTHY" -eq "$VM_COUNT" ] && break
  sleep 10
done

LB_IP=$(yc load-balancer network-load-balancer get --name "$PREFIX-lb" --format json \
  | jq -r '.listeners[0].address')
yc load-balancer network-load-balancer target-states \
  --name "$PREFIX-lb" --target-group-id "$TG_ID"
echo "==> готово: http://$LB_IP"
