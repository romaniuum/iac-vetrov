#!/usr/bin/env bash
# Убирает стенд ДЗ 1. Не полагается на список созданного: спрашивает облако,
# что в каталоге принадлежит стенду (метка owner или имя с префиксом), и удаляет найденное.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=params.sh
source "$DIR/params.sh"
load_params "$@"
need yc jq

# "id имя" всех своих ресурсов данного вида
mine() {
  # shellcheck disable=SC2086
  yc $1 list --format json | jq -r --arg p "$PREFIX" "$MINE_JQ"' | "\(.id) \(.name // "-")"'
}

remove() {
  local kind="$1" found id name
  found=$(mine "$kind")
  if [ -z "$found" ]; then
    echo "==> $kind: своего ничего нет"
    return
  fi
  while read -r id name; do
    echo "==> удаляю $kind $name"
    # shellcheck disable=SC2086
    yc $kind delete "$id" </dev/null >/dev/null
  done <<<"$found"
}

remove "load-balancer network-load-balancer"
remove "load-balancer target-group"
remove "compute instance"
remove "compute disk"

# подсеть ссылается на таблицу маршрутизации: сначала отвязать, потом удалять таблицу
linked=$(yc vpc subnet list --format json |
  jq -r --arg p "$PREFIX" "$MINE_JQ"' | select((.route_table_id // "") != "") | "\(.id) \(.name)"')
if [ -n "$linked" ]; then
  while read -r id name; do
    echo "==> отвязываю таблицу маршрутизации от $name"
    yc vpc subnet update "$id" --disassociate-route-table </dev/null >/dev/null
  done <<<"$linked"
fi

remove "vpc route-table"
remove "vpc gateway"
remove "vpc subnet"
remove "vpc network"

# уборка по факту: спрашиваем облако ещё раз
left=0
for kind in "compute instance" "compute disk" "vpc network" "vpc subnet" "vpc gateway" \
  "vpc route-table" "load-balancer target-group" "load-balancer network-load-balancer"; do
  n=$(mine "$kind" | grep -c . || true)
  if [ "$n" -gt 0 ]; then
    echo "!!! осталось: $kind — $n шт." >&2
    left=1
  fi
done
if [ "$left" -eq 0 ]; then
  echo "==> стенд $PREFIX убран, своих ресурсов в каталоге не осталось"
else
  exit 1
fi
