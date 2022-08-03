#!/bin/bash

set -eux
cd "$(dirname "$0")"


# let's make sure we have an ssh keypair. We just use ~/.ssh/id_rsa
# TODO convert this to SSH private key held on Trezor. THus trezor-T required for 
# login operations. This should be configurable of course.
if [ ! -f "$SSH_HOME/id_rsa" ]; then
    # generate a new SSH key for the base vm image.
    ssh-keygen -f "$SSH_HOME/id_rsa" -t ecdsa -b 521 -N ""
fi

## This is a weird if clause since we need to LEFT-ALIGN the statement below.
SSH_STRING="Host ${FQDN}"
if ! grep -q "$SSH_STRING" "$SSH_HOME/config"; then

########## BEGIN
cat >> "$SSH_HOME/config" <<-EOF

${SSH_STRING}
    HostName ${FQDN}
    User ubuntu
EOF
###

fi

function prepare_host {
    # scan the remote machine and install it's identity in our SSH known_hosts file.
    ssh-keyscan -H -t ecdsa "$FQDN" >> "$SSH_HOME/known_hosts"

    # create a directory to store backup archives. This is on all new vms.
    ssh "$FQDN" mkdir -p "$REMOTE_HOME/backups"

    if [ "$VIRTUAL_MACHINE" = btcpayserver ]; then
        echo "INFO: new machine detected. Provisioning BTCPay server scripts."
        ./btcpayserver/stub_btcpay_setup.sh
    fi

}

# when set to true, this flag indicates that a new VPS was created during THIS script run.
if [ "$VPS_HOSTING_TARGET" = aws ]; then
    # let's create the remote VPS if needed.
    if ! docker-machine ls -q --filter name="$FQDN" | grep -q "$FQDN"; then
        RUN_BACKUP=false

        ./provision_vps.sh

        prepare_host
    fi
elif [ "$VPS_HOSTING_TARGET" = lxd ]; then
    ssh-keygen -f "$SSH_HOME/known_hosts" -R "$FQDN"

    # if the machine doesn't exist, we create it.
    if ! lxc list --format csv | grep -q "$LXD_VM_NAME"; then
        export RUN_BACKUP=false

        # create a base image if needed and instantiate a VM.
        if [ -z "$MAC_ADDRESS_TO_PROVISION" ]; then
            echo "ERROR: You MUST define a MAC Address for all your machines by setting WWW_MAC_ADDRESS, BTCPAY_MAC_ADDRESS in your site defintion."
            echo "INFO: IMPORTANT! You MUST have DHCP Reservations for these MAC addresses. You also need static DNS entries."
            exit 1
        fi

        ./provision_lxc.sh
    fi

    prepare_host
fi

# if the local docker client isn't logged in, do so;
# this helps prevent docker pull errors since they throttle.
if [ ! -f "$HOME/.docker/config.json" ]; then
    echo "$REGISTRY_PASSWORD" | docker login --username "$REGISTRY_USERNAME" --password-stdin
fi

# this tells our local docker client to target the remote endpoint via SSH
export DOCKER_HOST="ssh://ubuntu@$FQDN"

# the following scripts take responsibility for the rest of the provisioning depending on the app you're deploying.
bash -c "./$VIRTUAL_MACHINE/go.sh"

echo "Successfull deployed '$DOMAIN_NAME' with git commit '$(cat ./.git/refs/heads/master)' VPS_HOSTING_TARGET=$VPS_HOSTING_TARGET;"
