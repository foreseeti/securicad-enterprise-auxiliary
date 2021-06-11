#!/bin/bash

# This script can be run at machine setup or later to restore securiCAD Enterprise to a backup.
# As written requires root, but you can add sudo before systemctl below.

# A backup is expected to be on the same format as backup.cronjob.sh writes.
#

set -eu

storage_account_name=$1
container_name=$2
blobname=$3

confpath="/home/es/bin/enterprise_suite/backend/apps/es/configs/config.json"
filepath="$blobname.tar.gz"

az storage blob download --auth-mode login \
                       --account-name $storage_account_name \
                       --container-name $container_name \
                       --file $filepath \
                       --name $blobname

mkdir "$blobname"
tar -xvzf "$filepath" -C "$blobname"

# shutdown backend to finalize backend writes
systemctl stop foreseeti-backend

cp "$blobname/config.json" "$confpath"
dburi=$(jq -r .flask.sqlalchemy.database "$confpath")
dbpath=${dburi#sqlite:///}
cp "$blobname/data.db" "$dbpath"

systemctl start foreseeti-backend
