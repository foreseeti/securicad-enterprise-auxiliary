#!/bin/bash

# foreseeti securiCAD Enterprise for Azure VM instance configuration script.
#
# You should only need to modify the parameter section.
#
# If you run into problems please contact support@foreseeti.com

set -eu

###############################
# Parameter section
# Please enter your environment configuration.
#

### Subscription [necessary]

# e.g. 00000000-0000-0000-0000-000000000000
subscription_id=""

### Managed identity [necessary]

# Set this if you want user managed identity, if empty it's assumed to be system managed
# Specifying credentials in text is not supported.
user_assigned_identity_id=""

### Admin account setup [necessary]

# The Managed Identity will require "secret read" permission under the key vault access policy (or corresponding RBAC role if the key vault permissions control is set to RBAC)
# e.g. https://<KeyVaultName>.vault.azure.net/secrets/admin-username/xxxxxxxxxxxxxxxxxxxx
admin_username_secret_id=""
admin_password_secret_id=""

### Backup [optional]

# The Managed Identity will require "storage blob data contributor" rights to this storage blob container
storage_account_name=""
blob_container_name=""

# Backup schedule in cron format. Please see https://crontab.guru/ for help
backup_schedule="2 2 * * *"

# Set this to a backup blob name if you want to restore a backup
# e.g. enterprise-backup-20210602-122205
backup_blob_name=""

### Security [necessary]

# set this to either http or https
#   http: you probably want to put a load balancer or proxy with https unwrapping in front
#   https: use the self signed https, for quick and easy testing
web_security_mode="https"

###############################
# Script section
# You should not need to modify anything below this line
#

validate_parameters() {

  echo "Validating parameters"

  if [[ -z "$subscription_id" ]]; then
    echo "Please specify subscription_id"
    exit 1
  fi

  if [[ ! "$web_security_mode" =~ ^(http|https)$ ]]; then
    echo "web_security_mode: only 'http' or 'https' are allowed values"
    exit 1
  fi

  if [[ -n "$storage_account_name" ]]; then
    if [[ -z "$blob_container_name" ]]; then
      echo "You need to specify both storage_account_name and blob_container_name for backup to work"
    fi
  fi

  if [[ -n "$blob_container_name" ]]; then
    if [[ -z "$storage_account_name" ]]; then
      echo "You need to specify both storage_account_name and blob_container_name for backup to work"
    fi
  fi
}

setup_azure_cli() {
  if [[ -n "$subscription_id" ]]; then
    echo "Setting up Azure CLI"
    if [[ -n "$user_assigned_identity_id" ]]; then
      az login --identity -u "$user_assigned_identity_id"
    else
      az login --identity
    fi
    az account set -s "$subscription_id"
  fi
}

setup_rabbitmq() {
  echo "Setting up RabbitMQ"

  declare -a arr=("guest" "esWorker" "esAPI")
  for user in "${arr[@]}"
  do
    if rabbitmqctl list_users | grep -q "$user"; then
      rabbitmqctl delete_user "$user"
    fi
  done
  rabbitmqctl add_user esWorker calcESWorker
  rabbitmqctl set_permissions -p / esWorker ".*" ".*" ".*"

  cleanPw=$(head /dev/urandom | tr -dc 'A-Za-z0-9_' | head -c 32  ; echo)
  confpath="/home/es/bin/enterprise_suite/backend/apps/es/configs/config.json"
  # shellcheck disable=SC2005
  echo "$(jq --arg cleanPw "$cleanPw" '
    .rabbit.api.password = $cleanPw
  ' "$confpath")"> "$confpath"

  rabbitmqctl add_user esAPI "$cleanPw"

  # Allow only user to monitor
  rabbitmqctl set_user_tags esAPI monitoring
}

set_credentials() {
  echo "Setting up securiCAD initial admin user"

  admin_name_data=$(az keyvault secret show --id $admin_username_secret_id || echo RETRIEVAL_FAILURE)
  if [[ "$admin_name_data" == "RETRIEVAL_FAILURE" ]]; then
     admin_name="admin"
     echo "Failed to retrieve admin username from keyvault"
  else
     admin_name=$(echo "$admin_name_data" | jq -r .value)
     echo "Retrieved admin username from keyvault"
  fi
  admin_pass_data=$(az keyvault secret show --id $admin_password_secret_id || echo RETRIEVAL_FAILURE)
  if [[ "$admin_pass_data" == "RETRIEVAL_FAILURE" ]]; then
     admin_pass="admin"
     echo "Failed to retrieve admin password from keyvault"
  else
     admin_pass=$(echo "$admin_pass_data" | jq -r .value)
     echo "Retrieved admin password from keyvault"
  fi
  python3 /home/es/bin/enterprise_suite/tools/troubleshooting.py addadmin --username "$admin_name" --password "$admin_pass"
}

setup_webserver() {
  echo "Configuring NGINX"

  metadata=$(curl -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01")
  public_ip=$(echo "$metadata" | jq -r '.network.interface[].ipv4.ipAddress[].publicIpAddress')
  if [[ $web_security_mode == "http" ]]; then
    sed "s/#replaceme#/$public_ip/g" /home/es/bin/enterprise_suite/installer/nginxUbuntuHttpConf > /etc/nginx/sites-available/default
  else
    sed "s/#replaceme#/$public_ip/g" /home/es/bin/enterprise_suite/installer/nginxUbuntuConf > /etc/nginx/sites-available/default
  fi
  systemctl restart nginx
}

setup_backup_cronjob() {
  echo "Configuring backup cronjob"

  backuplogdir="/root/backuplogs"
  mkdir -p "$backuplogdir"
  (crontab -l 2>/dev/null; echo "$backup_schedule /root/esbackup.cronjob.sh $storage_account_name $blob_container_name >> $backuplogdir/esbackup.cronlog 2>&1") | crontab -
}

restore_backup() {
  echo "Restoring from backup blob: $backup_blob_name"

  /root/esrestore.sh "$storage_account_name" "$blob_container_name" "$backup_blob_name"
}

restart_services() {
  echo "Restarting services"

  systemctl restart foreseeti-backend foreseeti-worker foreseeti-modelbuilder foreseeti-modelmerger foreseeti-coordinator
}


validate_parameters

setup_azure_cli
setup_rabbitmq
set_credentials
setup_webserver
restart_services

if [[ -n "$storage_account_name" ]]; then
  setup_backup_cronjob
else
  echo "storage_account_name not specified, backup not configured"
fi

if [[ -n "$backup_blob_name" ]]; then
  restore_backup
else
  echo "backup_blob_name not specified, backup not restored"
fi
