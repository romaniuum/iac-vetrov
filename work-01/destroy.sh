#!/usr/bin/env bash

set -euo pipefail

# ===== Параметры варианта 09 (те же, что в create.sh) =====
PREFIX="vetrov-09"
VM_NAMES=("$PREFIX-app-1" "$PREFIX-app-2")
NET="$PREFIX-net"
SUBNET="$PREFIX-subnet"
SG="$PREFIX-sg"

command -v yc >/dev/null 2>&1 || { echo "ОШИБКА: не найдена утилита yc" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ОШИБКА: не найдена утилита jq" >&2; exit 1; }

# delete_if_exists <группа команд yc> <имя>
delete_if_exists() {
  local what="$1" name="$2"
  # shellcheck disable=SC2086
  if yc $what get --name "$name" >/dev/null 2>&1; then
    yc $what delete --name "$name"
    echo "Удалено: $what $name"
  else
    echo "Нет ресурса: $what $name — пропускаю"
  fi
}

# ===== Машины: сначала то, что использует сеть =====
for VM in "${VM_NAMES[@]}"; do
  delete_if_exists "compute instance" "$VM"
done

# ===== Сеть: группа безопасности, подсеть, сама сеть =====
delete_if_exists "vpc security-group" "$SG"
delete_if_exists "vpc subnet" "$SUBNET"
delete_if_exists "vpc network" "$NET"

# ===== Контроль: ничего с префиксом не осталось =====
echo
LEFT="$( {
  yc compute instance list --format json | jq -r '.[].name'
  yc vpc subnet list --format json | jq -r '.[].name'
  yc vpc network list --format json | jq -r '.[].name'
  yc vpc security-group list --format json | jq -r '.[].name'
} | grep "^$PREFIX-" || true )"

if [ -n "$LEFT" ]; then
  echo "Остались ресурсы с префиксом $PREFIX:"
  echo "$LEFT"
  exit 1
fi
echo "Ресурсов с префиксом $PREFIX не осталось."

DISKS="$(yc compute disk list --format json | jq 'length')"
if [ "$DISKS" -ne 0 ]; then
  echo "Внимание: в каталоге есть диски ($DISKS шт.), проверьте: yc compute disk list"
fi
