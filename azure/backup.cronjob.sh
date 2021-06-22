#!/bin/bash

# Copyright 2020-2021 Foreseeti AB <https://foreseeti.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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
