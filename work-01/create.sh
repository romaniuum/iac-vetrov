#!/usr/bin/env bash

set -euo pipefail

PREFIX="vetrov-09"
ZONE="ru-central1-d"
CIDR="10.19.1.0/24"
APP_PORT=8027
DISK_SIZE=25                   
IMAGE_FAMILY="debian-12"
WORD="cloudlab"                 
# ===== Параметры машин =====
PLATFORM="standard-v3"          
CORES=2
CORE_FRACTION=20
MEMORY=2                       
SSH_KEY="$HOME/.ssh/id_ed25519.pub"
VM_NAMES=("$PREFIX-app-1" "$PREFIX-app-2")

# ===== Производные имена =====
NET="$PREFIX-net"
SUBNET="$PREFIX-subnet"
SG="$PREFIX-sg"
LABELS="created-by=script,stand=$PREFIX"

# ===== Проверки окружения =====
die() { echo "ОШИБКА: $*" >&2; exit 1; }

for cmd in yc jq; do
  command -v "$cmd" >/dev/null 2>&1 || die "не найдена утилита $cmd"
done
[ -s "$SSH_KEY" ] ||  die "нет публичного ключа $SSH_KEY"

FOLDER_ID="$(yc config get folder-id 2>/dev/null || true)"
[ -n "$FOLDER_ID" ] || die "в профиле yc не задан folder-id, выполните yc init"
echo "Каталог: $FOLDER_ID, зона: $ZONE, префикс: $PREFIX"

MIN_DISK_BYTES="$(yc compute image get-latest-from-family "$IMAGE_FAMILY" \
  --folder-id standard-images --format json | jq -r '.min_disk_size // 0')"
[ "$MIN_DISK_BYTES" -le $((DISK_SIZE * 1024 * 1024 * 1024)) ] \
   || die "образу $IMAGE_FAMILY нужно больше $DISK_SIZE ГБ"

# ===== Сеть =====
if yc vpc network get --name "$NET" >/dev/null 2>&1; then
  echo "Сеть $NET уже есть"
else
  yc vpc network create --name "$NET" --labels "$LABELS"
fi

# ===== Подсеть =====
if yc vpc subnet get --name "$SUBNET" >/dev/null 2>&1; then
  echo "Подсеть $SUBNET уже есть"
else
  yc vpc subnet create \
    --name "$SUBNET" \
    --network-name "$NET" \
    --zone "$ZONE" \
    --range "$CIDR" \
    --labels "$LABELS"
fi

# ===== Группа безопасности: SSH и порт приложения снаружи, исходящий — весь =====
if yc vpc security-group get --name "$SG" >/dev/null 2>&1; then
  echo "Группа безопасности $SG уже есть"
else
  yc vpc security-group create \
    --name "$SG" \
    --network-name "$NET" \
    --rule "direction=ingress,port=22,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
    --rule "direction=ingress,port=$APP_PORT,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
    --rule "direction=egress,port=any,protocol=any,v4-cidrs=[0.0.0.0/0]" \
    --labels "$LABELS"
fi
SG_ID="$(yc vpc security-group get --name "$SG" --format json | jq -r .id)"
[ -n "$SG_ID" ] && [ "$SG_ID" != "null" ] || die "не удалось получить id группы $SG"

# ===== Машины =====
for VM in "${VM_NAMES[@]}"; do
  if yc compute instance get --name "$VM" >/dev/null 2>&1; then
    echo "Машина $VM уже есть"
    continue
  fi
  yc compute instance create \
    --name "$VM" \
    --hostname "$VM" \
    --zone "$ZONE" \
    --platform "$PLATFORM" \
    --cores "$CORES" \
    --core-fraction "$CORE_FRACTION" \
    --memory "$MEMORY" \
    --preemptible \
    --create-boot-disk "image-folder-id=standard-images,image-family=$IMAGE_FAMILY,type=network-hdd,size=$DISK_SIZE" \
    --network-interface "subnet-name=$SUBNET,nat-ip-version=ipv4,security-group-ids=$SG_ID" \
    --ssh-key "$SSH_KEY" \
    --labels "$LABELS" >/dev/null
  echo "Машина $VM создана"
done

# ===== Итог =====
echo
echo "Стенд $PREFIX:"
yc compute instance list --format json | jq -r --arg p "$PREFIX-app-" '
  .[] | select(.name | startswith($p))
  | "\(.name)\t\(.status)\t\(.network_interfaces[0].primary_v4_address.one_to_one_nat.address // "нет")"'

cat <<HINT

Дальше руками на каждой машине (ssh yc-user@<IP>):
  sudo apt update && sudo apt install -y nginx
  sudo sed -i 's/listen 80 default_server;/listen $APP_PORT default_server;/; s/listen \[::\]:80 default_server;/listen [::]:$APP_PORT default_server;/' /etc/nginx/sites-enabled/default
  sudo nginx -t && sudo systemctl reload nginx
  set +H
  sudo sed -i "s|Welcome to nginx!|$WORD on \$(hostname)|g" /var/www/html/index.nginx-debian.html
Проверка из браузера: http://<IP>:$APP_PORT
HINT
