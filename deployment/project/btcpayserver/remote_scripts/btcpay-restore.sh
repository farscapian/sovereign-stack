#!/bin/bash -e

set -o pipefail -o errexit

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: This script must be run as root."
  echo "➡️ Use the command 'sudo su -' (include the trailing hypen) and try again."
  exit 1
fi

backup_path="$1"
if [ -z "$backup_path" ]; then
  echo "ERROR: Usage: btcpay-restore.sh /path/to/backup.tar.gz"
  exit 1
fi

if [ ! -f "$backup_path" ]; then
  echo "ERROR: $backup_path does not exist."
  exit 1
fi

if [[ "$backup_path" == *.gpg && -z "$BTCPAY_BACKUP_PASSPHRASE" ]]; then
  echo "INFO: $backup_path is encrypted. Please provide the passphrase to decrypt it."
  echo "INFO: Usage: BTCPAY_BACKUP_PASSPHRASE=t0pSeCrEt btcpay-restore.sh /path/to/backup.tar.gz.gpg"
  exit 1
fi

# preparation
docker_dir=$(docker volume inspect generated_btcpay_datadir --format="{{.Mountpoint}}" | sed -e "s%/volumes/.*%%g")
restore_dir="$docker_dir/volumes/backup_datadir/_data/restore"
dbdump_name=postgres.sql.gz
btcpay_dir="$BTCPAY_BASE_DIRECTORY/btcpayserver-docker"

# ensure clean restore dir
echo "INFO: Cleaning restore directory $restore_dir."
rm -rf "$restore_dir"
mkdir -p "$restore_dir"

if [[ "$backup_path" == *.gpg ]]; then
  echo "INFO: Decrypting backup file."
  {
    gpg -o "${backup_path%.*}" --batch --yes --passphrase "$BTCPAY_BACKUP_PASSPHRASE" -d "$backup_path"
    backup_path="${backup_path%.*}"
    echo "SUCESS: Decryption done."
  } || {
    echo "INFO: Decryption failed. Please check the error message above."
    exit 1
  }
fi

cd "$restore_dir"

echo "INFO: Extracting files in $(pwd)."
tar -h -xvf "$backup_path" -C "$restore_dir"

# basic control checks
if [ ! -f "$dbdump_name" ]; then
  echo "ERROR: '$dbdump_name' does not exist."
  exit 1
fi

if [ ! -d "volumes" ]; then
  echo "ERROR: volumes directory does not exist."
  exit 1
fi

cd "$btcpay_dir"
. helpers.sh

cd "$restore_dir"

{
  echo "INFO: Restoring volumes."
  # ensure volumes dir exists
  if [ ! -d "$docker_dir/volumes" ]; then
    mkdir -p "$docker_dir/volumes"
  fi
  # copy volume directories over
  cp -r volumes/* "$docker_dir/volumes/"
  # ensure datadirs excluded in backup exist
  mkdir -p "$docker_dir/volumes/generated_postgres_datadir/_data"
  echo "INFO: Volume restore done."
} || {
  echo "INFO: Restoring volumes failed. Please check the error message above."
  exit 1
}

{
  echo "INFO: Starting database container"
  docker-compose -f "$BTCPAY_DOCKER_COMPOSE" up -d postgres
  dbcontainer=$(docker ps -a -q -f "name=postgres")
  if [ -z "$dbcontainer" ]; then
    echo "ERROR: Database container could not be started or found."
    exit 1
  fi
} || {
  echo "ERROR: Starting database container failed. Please check the error message above."
  exit 1
}

cd "$restore_dir"

{
  echo "INFO: Restoring database..."
  gunzip -c $dbdump_name | docker exec -i "$dbcontainer" psql -U postgres postgres -a
  echo "SUCCESS: Database restore done."
} || {
  echo "ERROR: Restoring database failed. Please check the error message above."
  exit 1
}

echo "INFO: Cleaning up."
rm -rf "$restore_dir"

echo "SUCCESS: Restore done"
