#!/bin/bash

set -exu
cd "$(dirname "$0")"

# check to ensure dependencies are met.
for cmd in wait-for-it dig rsync sshfs incus; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "This script requires \"${cmd}\" to be installed. Please run 'install.sh'."
        exit 1
    fi
done

# do a spot check; if we are on production warn.
if incus remote get-default | grep -q "production"; then
    echo "WARNING: You are running command against a production system!"
    echo ""

    # check if there are any uncommited changes. It's dangerous to 
    # alter production systems when you have commits to make or changes to stash.
    if git update-index --refresh | grep -q "needs update"; then
        echo "ERROR: You have uncommited changes! You MUST commit or stash all changes to continue."
        exit 1
    fi

    RESPONSE=
    read -r -p "         Are you sure you want to continue (y)  ": RESPONSE
    if [ "$RESPONSE" != "y" ]; then
        echo "STOPPING."
        exit 1
    fi

fi

OTHER_SITES_LIST=
PRIMARY_DOMAIN=
RUN_CERT_RENEWAL=true
SKIP_BASE_IMAGE_CREATION=false
RESTORE_WWW=false
RESTORE_CERTS=false
BACKUP_CERTS=true
BACKUP_BTCPAY=true
SKIP_BTCPAY_SERVER=false
SKIP_WWW_SERVER=false
SKIP_LNPLAY_SERVER=false
BACKUP_BTCPAY_ARCHIVE_PATH= 
RESTORE_BTCPAY=false
UPDATE_BTCPAY=false
REMOTE_NAME="$(incus remote get-default)"
USER_SAYS_YES=false

WWW_SERVER_MAC_ADDRESS=
BTCPAY_SERVER_MAC_ADDRESS=
LNPLAY_SERVER_MAC_ADDRESS=
LNPLAY_ENV_PATH=
LNPLAY_VM_EXPIRATION_DATE=
LNPLAY_ORDER_ID=

# grab any modifications from the command line.
for i in "$@"; do
    case $i in
        --restore-certs)
            RESTORE_CERTS=true
            shift
        ;;
        --restore-wwwserver)
            RESTORE_WWW=true
            shift
        ;;
        --restore-btcpay)
            RESTORE_BTCPAY=true
            shift
        ;;
        --skip-btcpayserver)
            SKIP_BTCPAY_SERVER=true
            shift
        ;;
        --skip-wwwserver)
            SKIP_WWW_SERVER=true
            shift
        ;;
        --skip-lnplayserver)
            SKIP_LNPLAY_SERVER=true
            shift
        ;;
        --backup-btcpayserver)
            BACKUP_BTCPAY=true
            shift
        ;;
        --backup-archive-path=*)
            BACKUP_BTCPAY_ARCHIVE_PATH="${i#*=}"
            shift
        ;;
        --update-btcpay)
            UPDATE_BTCPAY=true
            shift
        ;;
        --skip-base-image)
            SKIP_BASE_IMAGE_CREATION=true
            shift
        ;;
        --no-cert-renew)
            RUN_CERT_RENEWAL=false
            shift
        ;;
        --lnplay-env-path=*)
            LNPLAY_ENV_PATH="${i#*=}"
            shift
        ;;
        --vm-expiration-date=*)
            LNPLAY_VM_EXPIRATION_DATE="${i#*=}"
            shift
        ;;
        --order-id=*)
            LNPLAY_ORDER_ID="${i#*=}"
            shift
        ;;
        -y)
            USER_SAYS_YES=true
            shift
        ;;
        *)
        echo "Unexpected option: $1"
        exit 1
        ;;
    esac
done


if [ "$RESTORE_BTCPAY" = true ] && [ -z "$BACKUP_BTCPAY_ARCHIVE_PATH" ]; then
    echo "ERROR: Use the '--backup-archive-path=/path/to/btcpay/archive.tar.gz' option when restoring btcpay server."
    exit 1
fi

if [ "$RESTORE_BTCPAY" = true ] && [ ! -f "$BACKUP_BTCPAY_ARCHIVE_PATH" ]; then
    echo "ERROR: The backup archive path you specified DOES NOT exist!"
    exit 1
fi

. ./remote_env.sh

export REGISTRY_DOCKER_IMAGE="registry:2"
export BACKUP_CERTS="$BACKUP_CERTS"
export RESTORE_BTCPAY="$RESTORE_BTCPAY"
export RESTORE_WWW="$RESTORE_WWW"
export BACKUP_BTCPAY="$BACKUP_BTCPAY"
export RUN_CERT_RENEWAL="$RUN_CERT_RENEWAL"
export REMOTE_NAME="$REMOTE_NAME"
export REMOTE_PATH="$REMOTES_PATH/$REMOTE_NAME"
export USER_SAYS_YES="$USER_SAYS_YES"
export BACKUP_BTCPAY_ARCHIVE_PATH="$BACKUP_BTCPAY_ARCHIVE_PATH"
export RESTORE_CERTS="$RESTORE_CERTS"

# todo convert this to Trezor-T
SSH_PUBKEY_PATH="$SSH_HOME/id_rsa.pub"
export SSH_PUBKEY_PATH="$SSH_PUBKEY_PATH"

# ensure our remote path is created.
mkdir -p "$REMOTE_PATH"

REMOTE_DEFINITION="$REMOTE_PATH/remote.conf"
if [ ! -f "$REMOTE_DEFINITION" ]; then
    echo "ERROR: The remote definition could not be found. You may need to re-run 'ss-remote'."
    exit 1
fi

export REMOTE_DEFINITION="$REMOTE_DEFINITION"
source "$REMOTE_DEFINITION"


# this is our password generation mechanism. Relying on GPG for secure password generation
# TODO see if this is a secure way to do it.
function new_pass {
    gpg --gen-random --armor 1 25
}

function stub_site_definition {
    mkdir -p "$SITE_PATH" "$PROJECT_PATH/sites"

    # create a symlink from the PROJECT_PATH/sites/DOMAIN_NAME to the ss-sites/domain name
    DOMAIN_SYMLINK_PATH="$PROJECT_PATH/sites/$DOMAIN_NAME"
    if [ ! -L "$DOMAIN_SYMLINK_PATH" ]; then
        ln -r -s "$SITE_PATH" "$DOMAIN_SYMLINK_PATH"
    fi

    if [ ! -f "$SITE_PATH/site.conf" ]; then
        # check to see if the enf file exists. exist if not.
        SITE_DEFINITION_PATH="$SITE_PATH/site.conf"
        if [ ! -f "$SITE_DEFINITION_PATH" ]; then

            # stub out a site.conf with new passwords.
            cat >"$SITE_DEFINITION_PATH" <<EOL
# https://www.sovereign-stack.org/ss-up/#siteconf

DOMAIN_NAME="${DOMAIN_NAME}"
# BTCPAY_ALT_NAMES="tip,store,pay,send"
SITE_LANGUAGE_CODES="en"
DUPLICITY_BACKUP_PASSPHRASE="$(new_pass)"
DEPLOY_GHOST=true

DEPLOY_NEXTCLOUD=false
DEPLOY_NOSTR=false
NOSTR_ACCOUNT_PUBKEY=
DEPLOY_GITEA=false
GHOST_MYSQL_PASSWORD="$(new_pass)"
GHOST_MYSQL_ROOT_PASSWORD="$(new_pass)"
NEXTCLOUD_MYSQL_PASSWORD="$(new_pass)"
NEXTCLOUD_MYSQL_ROOT_PASSWORD="$(new_pass)"
GITEA_MYSQL_PASSWORD="$(new_pass)"
GITEA_MYSQL_ROOT_PASSWORD="$(new_pass)"


#GHOST_DEPLOY_SMTP=true
#MAILGUN_FROM_ADDRESS=false
#MAILGUN_SMTP_USERNAME=
#MAILGUN_SMTP_PASSWORD=

EOL

            chmod 0744 "$SITE_DEFINITION_PATH"
            echo "INFO: we stubbed a new site.conf for you at '$SITE_DEFINITION_PATH'. Go update it!"
            exit 1

        fi
    fi

}

PROJECT_NAME="$(incus info | grep "project:" | awk '{print $2}')"
export PROJECT_NAME="$PROJECT_NAME"
export PROJECT_PATH="$PROJECTS_PATH/$PROJECT_NAME"
export SKIP_BTCPAY_SERVER="$SKIP_BTCPAY_SERVER"
export SKIP_WWW_SERVER="$SKIP_WWW_SERVER"
export SKIP_LNPLAY_SERVER="$SKIP_LNPLAY_SERVER"


mkdir -p "$PROJECT_PATH" "$REMOTE_PATH/projects"

# create a symlink from ./remotepath/projects/project
PROJECT_SYMLINK="$REMOTE_PATH/projects/$PROJECT_NAME"
if [ ! -L "$PROJECT_SYMLINK" ]; then
    ln -r -s "$PROJECT_PATH" "$PROJECT_SYMLINK"
fi

# check to see if the enf file exists. exist if not.
PROJECT_DEFINITION_PATH="$PROJECT_PATH/project.conf"
if [ ! -f "$PROJECT_DEFINITION_PATH" ]; then

        # stub out a project.conf
    cat >"$PROJECT_DEFINITION_PATH" <<EOL
# see https://www.sovereign-stack.org/ss-up/#projectconf for more info.

PRIMARY_DOMAIN="domain0.tld"
# OTHER_SITES_LIST="domain1.tld,domain2.tld,domain3.tld"

WWW_SERVER_MAC_ADDRESS=
# WWW_SSDATA_DISK_SIZE_GB=100
# WWW_SERVER_CPU_COUNT="6"
# WWW_SERVER_MEMORY_MB="4096"

BTCPAY_SERVER_MAC_ADDRESS=
# BTCPAY_SERVER_CPU_COUNT="4"
# BTCPAY_SERVER_MEMORY_MB="4096"

LNPLAY_SERVER_MAC_ADDRESS=
# LNPLAY_SERVER_CPU_COUNT="4"
# LNPLAY_SERVER_MEMORY_MB="4096"

# BITCOIN_CHAIN=mainnet

EOL

    chmod 0744 "$PROJECT_DEFINITION_PATH"
    echo "INFO: we stubbed a new project.conf for you at '$PROJECT_DEFINITION_PATH'. Go update it!"
    echo "INFO: Learn more at https://www.sovereign-stack.org/ss-up/"

    exit 1
fi

. ./project_env.sh

if [ -z "$PRIMARY_DOMAIN" ]; then
    echo "ERROR: The PRIMARY_DOMAIN is not specified. Check your project.conf."
    exit 1
fi

source ./domain_list.sh

# let's provision our primary domain first.
export DOMAIN_NAME="$PRIMARY_DOMAIN"
export PRIMARY_DOMAIN="$PRIMARY_DOMAIN"
export BITCOIN_CHAIN="$BITCOIN_CHAIN"
export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"
export PRIMARY_SITE_PATH="$SITES_PATH/$PRIMARY_DOMAIN"

stub_site_definition

# bring the VMs up under the primary domain name.

export UPDATE_BTCPAY="$UPDATE_BTCPAY"

# iterate over all our server endpoints and provision them if needed.
# www
VPS_HOSTNAME=

. ./base.sh
if ! incus image list --format csv | grep -q "$DOCKER_BASE_IMAGE_NAME"; then
    # create the incus base image.
    if [ "$SKIP_BASE_IMAGE_CREATION" = false ]; then
        ./create_base.sh
    fi
fi


VMS_TO_PROVISION=""
if [ -n "$WWW_SERVER_MAC_ADDRESS" ] && [ "$SKIP_WWW_SERVER" = false ]; then
    VMS_TO_PROVISION="www"
fi

if [ -n "$BTCPAY_SERVER_MAC_ADDRESS" ] && [ "$SKIP_BTCPAY_SERVER" = false ]; then
    VMS_TO_PROVISION="$VMS_TO_PROVISION btcpayserver"
fi

if [ -n "$LNPLAY_SERVER_MAC_ADDRESS" ] || [ "$SKIP_LNPLAY_SERVER" = false ]; then
    VMS_TO_PROVISION="$VMS_TO_PROVISION lnplayserver"
fi

for VIRTUAL_MACHINE in $VMS_TO_PROVISION; do

    export VIRTUAL_MACHINE="$VIRTUAL_MACHINE"
    FQDN=

    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    source "$SITE_PATH/site.conf"
    source ./project/domain_env.sh

    # VALIDATE THE INPUT from the ENVFILE
    if [ -z "$DOMAIN_NAME" ]; then
        echo "ERROR: DOMAIN_NAME not specified in your site.conf."
        exit 1
    fi

    # Goal is to get the macvlan interface.
    INCUS_SS_CONFIG_LINE=
    if incus network list --format csv --project default | grep incusbr0 | grep -q "ss-config"; then
        INCUS_SS_CONFIG_LINE="$(incus network list --format csv --project default | grep incusbr0 | grep ss-config)"
    fi

    if [ -z "$INCUS_SS_CONFIG_LINE" ]; then
        echo "ERROR: the MACVLAN interface has not been specified. You may need to run 'ss-remote' again."
        exit 1
    fi

    CONFIG_ITEMS="$(echo "$INCUS_SS_CONFIG_LINE" | awk -F'"' '{print $2}')"
    DATA_PLANE_MACVLAN_INTERFACE="$(echo "$CONFIG_ITEMS" | cut -d ',' -f2)"
    export DATA_PLANE_MACVLAN_INTERFACE="$DATA_PLANE_MACVLAN_INTERFACE"


    # Now let's switch to the new project to ensure new resources are created under the project scope.
    if ! incus info | grep "project:" | grep -q "$PROJECT_NAME"; then
        incus project switch "$PROJECT_NAME"
    fi

    # check if the OVN network exists in this project.
    if ! incus network list | grep -q "ss-ovn"; then
        incus network create ss-ovn --type=ovn network=incusbr1 ipv6.address=none
    fi

    export MAC_ADDRESS_TO_PROVISION=
    export VPS_HOSTNAME="$VPS_HOSTNAME"
    export FQDN="$VPS_HOSTNAME.$DOMAIN_NAME"

    if [ "$VIRTUAL_MACHINE" = www ] && [ -n "$WWW_SERVER_MAC_ADDRESS" ]; then
        FQDN="$WWW_HOSTNAME.$DOMAIN_NAME"
        VPS_HOSTNAME="$WWW_HOSTNAME"
        MAC_ADDRESS_TO_PROVISION="$WWW_SERVER_MAC_ADDRESS"

    elif [ "$VIRTUAL_MACHINE" = btcpayserver ] && [ -n "$BTCPAY_SERVER_MAC_ADDRESS" ]; then
        FQDN="$BTCPAY_SERVER_HOSTNAME.$DOMAIN_NAME"
        VPS_HOSTNAME="$BTCPAY_SERVER_HOSTNAME"
        MAC_ADDRESS_TO_PROVISION="$BTCPAY_SERVER_MAC_ADDRESS"
    
    elif [ "$VIRTUAL_MACHINE" = lnplayserver ] && [ -n "$LNPLAY_SERVER_MAC_ADDRESS" ]; then
        FQDN="$LNPLAY_SERVER_HOSTNAME.$DOMAIN_NAME"
        VPS_HOSTNAME="$LNPLAY_SERVER_HOSTNAME"
        MAC_ADDRESS_TO_PROVISION="$LNPLAY_SERVER_MAC_ADDRESS"

    elif [ "$VIRTUAL_MACHINE" = "$BASE_IMAGE_VM_NAME" ]; then
        FQDN="$BASE_IMAGE_VM_NAME"
    fi

    export FQDN="$FQDN"
    export INCUS_VM_NAME="${FQDN//./-}"
    export MAC_ADDRESS_TO_PROVISION="$MAC_ADDRESS_TO_PROVISION"
    export PROJECT_PATH="$PROJECT_PATH"

    ./deploy_vm.sh

done

# let's stub out the rest of our site definitions, if any.
for DOMAIN_NAME in ${OTHER_SITES_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # stub out the site_defition if it's doesn't exist.
    stub_site_definition
done

if [ "$SKIP_BTCPAY_SERVER" = false ]; then
    if [ -n "$BTCPAY_SERVER_MAC_ADDRESS" ]; then
        export DOCKER_HOST="ssh://ubuntu@$BTCPAY_SERVER_FQDN"
        ./project/btcpayserver/go.sh
    fi
fi

if [ "$SKIP_WWW_SERVER" = false ]; then
    # now let's run the www and btcpay-specific provisioning scripts.
    if [ -n "$WWW_SERVER_MAC_ADDRESS" ]; then
        export DOCKER_HOST="ssh://ubuntu@$WWW_FQDN"

        # enable docker swarm mode so we can support docker stacks.
        if docker info | grep -q "Swarm: inactive"; then
            docker swarm init --advertise-addr enp6s0
        fi

        ./project/www/go.sh
    fi
fi

# don't run lnplay stuff if user specifies --skip-lnplay
if [ "$SKIP_LNPLAY_SERVER" = false ]; then
    # now let's run the www and btcpay-specific provisioning scripts.
    if [ -n "$LNPLAY_SERVER_MAC_ADDRESS" ]; then
        export DOCKER_HOST="ssh://ubuntu@$LNPLAY_SERVER_FQDN"

        LNPLAY_ENV_FILE="$PRIMARY_SITE_PATH/$LNPLAY_SERVER_FQDN/lnplay.conf"
        if [ ! -f "$LNPLAY_ENV_FILE" ]; then
            # and we have to set our environment file as well.
            cat > "$LNPLAY_ENV_FILE" <<EOL
DOCKER_HOST=ssh://ubuntu@${LNPLAY_SERVER_FQDN}
BACKEND_FQDN=lnplay.${PRIMARY_DOMAIN}
FRONTEND_FQDN=remote.${PRIMARY_DOMAIN}
ENABLE_TLS=true
BTC_CHAIN=${BITCOIN_CHAIN}
CHANNEL_SETUP=none
LNPLAY_SERVER_PATH=${SITES_PATH}/${PRIMARY_DOMAIN}/lnplayserver
DEPLOY_PRISM_PLUGIN=true
EOL

        fi

        INCUS_LNPLAYSERVER_IMAGE_NAME="lnplayserver-$DOMAIN_NAME"
        if ! incus image list -q --format csv | grep -q "$INCUS_LNPLAYSERVER_IMAGE_NAME"; then

            # do all the docker image creation steps, but don't run services.
            bash -c "./project/lnplay/up.sh -y --no-services  --lnplay-conf-path=$LNPLAY_ENV_FILE"

            # stop the instance so we can get an image yo
            INCUS_VM_NAME="${LNPLAY_SERVER_FQDN//./-}"

            incus stop "$INCUS_VM_NAME"

            # create the incus image.
            incus publish -q --public "$INCUS_VM_NAME" --alias="$INCUS_LNPLAYSERVER_IMAGE_NAME" --compression none

            incus start "$INCUS_VM_NAME"
            sleep 10

            bash -c "./wait_for_ip.sh --incus-name=$INCUS_VM_NAME"
            sleep 3
        fi

        # bring up lnplay services.
        bash -c "./project/lnplay/up.sh -y --lnplay-conf-path=$LNPLAY_ENV_FILE"
    fi
fi
