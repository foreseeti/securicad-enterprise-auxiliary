#!/bin/bash

# Copyright 2021 Foreseeti AB <https://foreseeti.com>
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
                       --account-name "$storage_account_name" \
                       --container-name "$container_name" \
                       --file "$filepath" \
                       --name "$blobname"

mkdir "$blobname"
tar -xvzf "$filepath" -C "$blobname"

# shutdown backend to finalize backend writes
systemctl stop foreseeti-backend

cp "$blobname/config.json" "$confpath"
dburi=$(jq -r .flask.sqlalchemy.database "$confpath")
dbpath=${dburi#sqlite:///}
cp "$blobname/data.db" "$dbpath"

systemctl start foreseeti-backend
