#!/usr/bin/env bash

export PREFIX=vetrov-09
export ZONE=ru-central1-d
export CIDR=10.19.1.0/24
export DISK_SIZE=25

yc iam service-account get --name "$PREFIX-sa" >/dev/null 2>&1 || \
  yc iam service-account create --name "$PREFIX-sa"
export FOLDER_ID=$(yc config get folder-id)
export SA_ID=$(yc iam service-account get --name "$PREFIX-sa" --format json | jq -r .id)
echo "$FOLDER_ID $SA_ID"
yc resource-manager folder add-access-binding "$FOLDER_ID" \
  --role editor \
  --subject "serviceAccount:$SA_ID"
mkdir -p ~/.yc-keys
if [ ! -s ~/.yc-keys/$PREFIX-key.json ]; then
  yc iam key create --service-account-name "$PREFIX-sa" \
    --output ~/.yc-keys/$PREFIX-key.json
fi

yc vpc network create --name "$PREFIX-net"
yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR"


yc compute instance create \
  --name "$PREFIX-web-1" \
  --zone "$ZONE" \
  --platform standard-v3 \
  --cores=2 \
  --core-fraction=20 \
  --memory=2 \
  --preemptible \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size="$DISK_SIZE" \
  --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
  --hostname "$PREFIX-web-1" \
  --ssh-key ~/.ssh/id_ed25519.pub \
  --labels created-by=cli


yc compute instance list --format json | jq -r '.[] | select(.status != "RUNNING") | .name'

yc compute instance delete "$PREFIX-web-1"
yc compute instance delete "$PREFIX-web-manual"
yc vpc subnet delete "$PREFIX-subnet"
yc vpc network delete "$PREFIX-net"
