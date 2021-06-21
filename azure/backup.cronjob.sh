#!/bin/bash

# This script is meant to be run at intervals and back up enterprise database and config to azure blob storage
# Currently only local database is supported.
#
# As written requires root, but you can add sudo before systemctl below.

set -eu

storage_account_name=$1
container_name=$2

confpath="/home/es/bin/enterprise_suite/backend/apps/es/configs/config.json"
dburi=$(jq -r .flask.sqlalchemy.database "$confpath")
dbpath=${dburi#sqlite:///}
timestamp=$(date -u +"%Y%m%d-%H%M%S")
blobname="enterprise-backup-$timestamp"
filename="$blobname.tar.gz"
filepath="./$filename"

backupdirname="backupdir"
if [[ -d $backupdirname ]]; then
    rm -rf $backupdirname
fi
mkdir -p $backupdirname

# shutdown backend to finalize backend writes
systemctl stop foreseeti-backend

cp "$confpath" "$backupdirname"
cp "$dbpath" "$backupdirname"

cd $backupdirname
systemctl start foreseeti-backend

tar -cvzf "$filepath" data.db config.json

az storage blob upload --auth-mode login \
                       --account-name "$storage_account_name" \
                       --container-name "$container_name" \
                       --file "$filepath" \
                       --name "$blobname"

rm -rf "$backupdirname"
