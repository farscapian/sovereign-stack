#!/bin/bash -e

set -o pipefail -o errexit

# Please be aware of these important issues:
#
# - Old channel state is toxic and you can loose all your funds, if you or someone
#   else closes a channel based on the backup with old state - and the state changes
#   often! If you publish an old state (say from yesterday's backup) on chain, you
#   WILL LOSE ALL YOUR FUNDS IN A CHANNEL, because the counterparty will publish a
#   revocation key!

if [ "$(id -u)" != "0" ]; then
  echo "INFO: This script must be run as root."
  echo "      Use the command 'sudo su -' (include the trailing hypen) and try again."
  exit 1
fi

# preparation
docker_dir=$(docker volume inspect generated_btcpay_datadir --format="{{.Mountpoint}}" | sed -e "s%/volumes/.*%%g")
dbdump_name=postgres.sql.gz
btcpay_dir="$BTCPAY_BASE_DIRECTORY/btcpayserver-docker"
backup_dir="$docker_dir/volumes/backup_datadir/_data"
dbdump_path="$docker_dir/$dbdump_name"
backup_path="$backup_dir/backup.tar.gz"

# ensure backup dir exists
if [ ! -d "$backup_dir" ]; then
  mkdir -p "$backup_dir"
fi

cd "$btcpay_dir"
. helpers.sh

dbcontainer=$(docker ps -a -q -f "name=postgres_1")
if [ -z "$dbcontainer" ]; then
  printf "\n"
  echo "INFO: Database container is not up and running. Starting BTCPay Server."
  docker volume create generated_postgres_datadir
  docker-compose -f "$BTCPAY_DOCKER_COMPOSE" up -d postgres

  printf "\n"
  dbcontainer=$(docker ps -a -q -f "name=postgres_1")
  if [ -z "$dbcontainer" ]; then
    echo "INFO: Database container could not be started or found."
    exit 1
  fi
fi

printf "\n"
echo "INFO: Dumping database."
{
  docker exec "$dbcontainer" pg_dumpall -c -U postgres | gzip > "$dbdump_path"
  echo "INFO: Database dump done."
} || {
  echo "ERROR: Dumping failed. Please check the error message above."
  exit 1
}

echo "Stopping BTCPay Server..."
btcpay_down

printf "\n"
cd "$docker_dir"
echo "Archiving files in $(pwd)."

{
  tar \
    --exclude="volumes/backup_datadir" \
    --exclude="volumes/generated_bitcoin_datadir/_data/blocks" \
    --exclude="volumes/generated_bitcoin_datadir/_data/chainstate" \
    --exclude="volumes/generated_bitcoin_datadir/_data/debug.log" \
    --exclude="volumes/generated_bitcoin_datadir/_data/testnet3/blocks" \
    --exclude="volumes/generated_bitcoin_datadir/_data/testnet3/chainstate" \
    --exclude="volumes/generated_bitcoin_datadir/_data/testnet3/debug.log" \
    --exclude="volumes/generated_bitcoin_datadir/_data/regtest/blocks" \
    --exclude="volumes/generated_bitcoin_datadir/_data/regtest/chainstate" \
    --exclude="volumes/generated_bitcoin_datadir/_data/regtest/debug.log" \
    --exclude="volumes/generated_postgres_datadir" \
    --exclude="volumes/generated_tor_relay_datadir" \
    --exclude="volumes/generated_clightning_bitcoin_datadir/_data/lightning-rpc" \
    --exclude="**/logs/*" \
    -cvzf "$backup_path" "$dbdump_name" volumes/generated_*
  echo "INFO: Archive done."

  if [ -n "$BTCPAY_BACKUP_PASSPHRASE" ]; then
    printf "\n"
    echo "INFO: BTCPAY_BACKUP_PASSPHRASE is set, the backup will be encrypted."
    {
      gpg -o "$backup_path.gpg" --batch --yes -c --passphrase "$BTCPAY_BACKUP_PASSPHRASE" "$backup_path"
      rm "$backup_path"
      backup_path="$backup_path.gpg"
      echo "INFO: Encryption done."
    } || {
      echo "INFO: Encrypting failed. Please check the error message above."
      echo "INFO: Restarting BTCPay Server."
      cd "$btcpay_dir"

      exit 1
    }
  fi
} || {
  echo "INFO: Archiving failed. Please check the error message above."
  echo "Restarting BTCPay Server"
  cd "$btcpay_dir"

  exit 1
}

printf "Restarting BTCPay Server."
cd "$btcpay_dir"

echo "Cleaning up."
rm "$dbdump_path"

echo "INFO: Backup done => $backup_path."
