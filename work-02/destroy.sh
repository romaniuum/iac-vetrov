#!/usr/bin/env bash
set -euo pipefail

PREFIX=vetrov-09
VM_COUNT=2

yc load-balancer network-load-balancer delete "$PREFIX-lb"
yc load-balancer target-group delete "$PREFIX-tg"
for i in $(seq 1 "$VM_COUNT"); do
  yc compute instance delete "$PREFIX-app-$i"
done
yc compute disk delete "$PREFIX-data"
yc vpc subnet delete "$PREFIX-subnet-a"
yc vpc subnet delete "$PREFIX-subnet-b"
yc vpc network delete "$PREFIX-net"
