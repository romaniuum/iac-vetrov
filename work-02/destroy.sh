#!/usr/bin/env bash
set -euo pipefail

PREFIX=vetrov-09

ids() {
  # shellcheck disable=SC2086
  yc $1 list --format json \
    | jq -r --arg p "$PREFIX-" '.[] | select(.name | startswith($p)) | "\(.id) \(.name)"'
}

remove() {
  local what="$1" found
  found=$(ids "$what")
  if [ -z "$found" ]; then
    echo "==> $what: с префиксом $PREFIX ничего нет"
    return
  fi
  while read -r id name; do
    echo "==> удаляю $what $name"
    # shellcheck disable=SC2086
    yc $what delete "$id" </dev/null
  done <<< "$found"
}

remove "load-balancer network-load-balancer"
remove "load-balancer target-group"
remove "compute instance"
remove "compute disk"
remove "vpc subnet"
remove "vpc network"
echo "==> стенд $PREFIX убран"
