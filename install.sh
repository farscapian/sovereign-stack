#!/bin/bash

set -exu
cd "$(dirname "$0")"

# https://www.sovereign-stack.org/install/

# this script is not meant to be executed from the SSME; Let's let's check and abort if so.
if [ "$(hostname)" = ss-mgmt ]; then
    echo "ERROR: This command is meant to be executed from the bare metal management machine -- not the SSME."
    exit 1
fi

# ensure the iptables forward policy is set to ACCEPT so your host can act as a router
# Note this is necessary if docker is running (or has been previuosly installed) on the
# same host running incus.
sudo iptables -F FORWARD
sudo iptables -P FORWARD ACCEPT

# run the incus install script.
sudo bash -c ./install_incus.sh

# run incus init
cat <<EOF | sudo incus admin init --preseed
config: {}
networks:
- config:
    ipv4.address: auto
    ipv4.dhcp: true
    ipv6.address: none
  description: "Default network bridge for ss-mgmt outbound network access."
  name: incusbr0
  type: bridge
  project: default
storage_pools:
- config:
    size: 30GiB
  description: ""
  name: sovereign-stack
  driver: zfs
profiles:
- config: {}
  description: "Default profile for ss-mgmt."
  devices:
    enp5s0:
      name: enp5s0
      network: incusbr0
      type: nic
    root:
      path: /
      pool: sovereign-stack
      type: disk
  name: default
projects: []
cluster: null

EOF


. ./deployment/deployment_defaults.sh

. ./deployment/base.sh


# we need to get the base image. IMport it if it's cached, else download it then cache it.
if ! incus image list | grep -q "$UBUNTU_BASE_IMAGE_NAME"; then
        # if the image if cached locally, import it from disk, otherwise download it from ubuntu
    IMAGE_PATH="$HOME/ss/cache/ss-ubuntu-jammy"
    IMAGE_IDENTIFIER=$(find "$IMAGE_PATH" | grep ".qcow2" | head -n1 | cut -d "." -f1)
    METADATA_FILE="$IMAGE_PATH/meta-$IMAGE_IDENTIFIER.tar.xz"
    IMAGE_FILE="$IMAGE_PATH/$IMAGE_IDENTIFIER.qcow2"
    if [ -d "$IMAGE_PATH" ] && [ -f "$METADATA_FILE" ] && [ -f "$IMAGE_FILE" ]; then
        incus image import "$METADATA_FILE" "$IMAGE_FILE" --alias "$UBUNTU_BASE_IMAGE_NAME"
    else
        incus image copy "images:$BASE_INCUS_IMAGE" local: --alias "$UBUNTU_BASE_IMAGE_NAME" --vm --auto-update
        mkdir -p "$IMAGE_PATH"
        incus image export "$UBUNTU_BASE_IMAGE_NAME" "$IMAGE_PATH" --vm
    fi
fi

# if the ss-mgmt doesn't exist, create it.
SSH_PATH="$HOME/.ssh"
SSH_PRIVKEY_PATH="$SSH_PATH/id_rsa"
SSH_PUBKEY_PATH="$SSH_PRIVKEY_PATH.pub"

if [ ! -f "$SSH_PRIVKEY_PATH" ]; then
    ssh-keygen -f "$SSH_PRIVKEY_PATH" -t rsa -b 4096
fi

# add SSH_PUBKEY_PATH to authorized_keys
grep -qxF "$(cat "$SSH_PUBKEY_PATH")" "$SSH_PATH/authorized_keys" || cat "$SSH_PUBKEY_PATH" >> "$SSH_PATH/authorized_keys"

FROM_BUILT_IMAGE=false
if ! incus list --format csv | grep -q ss-mgmt; then

    # TODO check to see if there's an existing ss-mgmt image to spawn from, otherwise do this.
    if incus image list | grep -q ss-mgmt; then
        FROM_BUILT_IMAGE=true
        incus init ss-mgmt ss-mgmt --vm -c limits.cpu=4 -c limits.memory=4GiB --profile=default
    else
        incus init "images:$BASE_INCUS_IMAGE" ss-mgmt --vm -c limits.cpu=4 -c limits.memory=4GiB --profile=default
    fi

fi

# mount the pre-verified sovereign stack git repo into the new vm
if ! incus config device show ss-mgmt | grep -q ss-code; then
    incus config device add ss-mgmt ss-code disk source="$(pwd)" path=/home/ubuntu/sovereign-stack
fi

# create the ~/ss path and mount it into the vm.
source ./deployment/deployment_defaults.sh
source ./deployment/base.sh

mkdir -p "$SS_ROOT_PATH"

if ! incus config device show ss-mgmt | grep -q ss-root; then
    incus config device add ss-mgmt ss-root disk source="$SS_ROOT_PATH" path=/home/ubuntu/ss
fi

# if a ~/.bitcoin/testnet3/blocks direrectory exists, mount it in.
BITCOIN_DIR="$HOME/.bitcoin"
REMOTE_BITCOIN_CACHE_PATH="/home/ubuntu/ss/cache/bitcoin"
BITCOIN_TESTNET_BLOCKS_PATH="$BITCOIN_DIR/testnet3/blocks"
if [ -d "$BITCOIN_TESTNET_BLOCKS_PATH" ]; then
    if ! incus config device show ss-mgmt | grep -q ss-testnet-blocks; then
        incus config device add ss-mgmt ss-testnet-blocks disk source="$BITCOIN_TESTNET_BLOCKS_PATH" path=$REMOTE_BITCOIN_CACHE_PATH/testnet/blocks
    fi
fi

# if a ~/.bitcoin/testnet3/blocks direrectory exists, mount it in.
BITCOIN_TESTNET_CHAINSTATE_PATH="$BITCOIN_DIR/testnet3/chainstate"
if [ -d "$BITCOIN_TESTNET_CHAINSTATE_PATH" ]; then
    if ! incus config device show ss-mgmt | grep -q ss-testnet-chainstate; then
        incus config device add ss-mgmt ss-testnet-chainstate disk source="$BITCOIN_TESTNET_CHAINSTATE_PATH" path="$REMOTE_BITCOIN_CACHE_PATH/testnet/chainstate"
    fi
fi

# if a ~/.bitcoin/blocks dir exists, mount it in.
BITCOIN_MAINNET_BLOCKS_PATH="$BITCOIN_DIR/blocks"
if [ -d "$BITCOIN_MAINNET_BLOCKS_PATH" ]; then
    if ! incus config device show ss-mgmt | grep -q ss-mainnet-blocks; then
        incus config device add ss-mgmt ss-mainnet-blocks disk source="$BITCOIN_MAINNET_BLOCKS_PATH" path="$REMOTE_BITCOIN_CACHE_PATH/mainnet/blocks"
    fi
fi

    # if a ~/.bitcoin/testnet3/blocks direrectory exists, mount it in.
BITCOIN_MAINNET_CHAINSTATE_PATH="$BITCOIN_DIR/chainstate"
if [ -d "$BITCOIN_MAINNET_CHAINSTATE_PATH" ]; then
    if ! incus config device show ss-mgmt | grep -q ss-mainnet-blocks; then
        incus config device add ss-mgmt ss-mainnet-chainstate disk source="$BITCOIN_MAINNET_CHAINSTATE_PATH" path="$REMOTE_BITCOIN_CACHE_PATH/mainnet/chainstate"
    fi
fi

# mount the ssh directory in there.
if [ -f "$SSH_PUBKEY_PATH" ]; then
    if ! incus config device show ss-mgmt | grep -q ss-ssh; then
        incus config device add ss-mgmt ss-ssh disk source="$HOME/.ssh" path=/home/ubuntu/.ssh
    fi
fi

# start the vm if it's not already running
if incus list --format csv | grep -q "ss-mgmt,STOPPED"; then
    incus start ss-mgmt
    sleep 10
fi

# wait for the vm to have an IP address
. ./management/wait_for_ip.sh

# do some other preparations for user experience
incus file push ./management/bash_aliases ss-mgmt/home/ubuntu/.bash_aliases
incus file push ./management/bash_profile ss-mgmt/home/ubuntu/.bash_profile
incus file push ./management/bashrc ss-mgmt/home/ubuntu/.bashrc
incus file push ./management/motd ss-mgmt/etc/update-motd.d/sovereign-stack

# install SSH
incus exec ss-mgmt apt-get update
incus exec ss-mgmt -- apt-get install -y openssh-server
incus file push ./management/sshd_config ss-mgmt/etc/ssh/sshd_config
incus exec ss-mgmt -- sudo systemctl restart sshd

# add 'ss-manage' to the bare metal ~/.bashrc
ADDED_COMMAND=false
if ! < "$HOME/.bashrc" grep -q "ss-manage"; then
    echo "alias ss-manage='$(pwd)/manage.sh \$@'" >> "$HOME/.bashrc"
    ADDED_COMMAND=true
fi

# Let's remove any entry in our known_hosts, then add it back.
# we are using IP address here so we don't have to rely on external DNS 
# configuration for the base image preparataion.
ssh-keygen -R "$IP_V4_ADDRESS"

ssh-keyscan -H "$IP_V4_ADDRESS" >> "$SSH_HOME/known_hosts"

ssh "ubuntu@$IP_V4_ADDRESS" sudo chown -R ubuntu:ubuntu /home/ubuntu

if [ "$FROM_BUILT_IMAGE" = false ]; then
    ssh "ubuntu@$IP_V4_ADDRESS" /home/ubuntu/sovereign-stack/management/provision.sh

    incus stop ss-mgmt

    if ! incus image list | grep -q "ss-mgmt"; then
        echo "Publishing image. Please wait, this may take a while..."
        incus publish ss-mgmt --alias=ss-mgmt
    fi

    incus start ss-mgmt
fi

if [ "$ADDED_COMMAND" = true ]; then
    echo "NOTICE! You need to run 'source ~/.bashrc' before continuing. After that, type 'ss-manage' to enter your management environment."
fi
