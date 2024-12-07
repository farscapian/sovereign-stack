#!/bin/bash

set -exu
cd "$(dirname "$0")"

# Create the nginx config file which covers all domainys.
bash -c ./stub/nginx_config.sh

for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # source the site path so we know what features it has.
    source ../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../domain_env.sh
    
    ### Let's check to ensure all the requiredsettings are set.
    if [ "$DEPLOY_GHOST" = true ]; then
        if [ -z "$GHOST_MYSQL_PASSWORD" ]; then
            echo "ERROR: Ensure GHOST_MYSQL_PASSWORD is configured in your site.conf."
            exit 1
        fi

        if [ -z "$GHOST_MYSQL_ROOT_PASSWORD" ]; then
            echo "ERROR: Ensure GHOST_MYSQL_ROOT_PASSWORD is configured in your site.conf."
            exit 1
        fi
    fi

    if [ "$DEPLOY_GITEA" = true ]; then
        if [ -z "$GITEA_MYSQL_PASSWORD" ]; then
            echo "ERROR: Ensure GITEA_MYSQL_PASSWORD is configured in your site.conf."
            exit 1
        fi
        if [ -z "$GITEA_MYSQL_ROOT_PASSWORD" ]; then
            echo "ERROR: Ensure GITEA_MYSQL_ROOT_PASSWORD is configured in your site.conf."
            exit 1
        fi
    fi

    if [ "$DEPLOY_NEXTCLOUD" = true ]; then
        if [ -z "$NEXTCLOUD_MYSQL_ROOT_PASSWORD" ]; then
            echo "ERROR: Ensure NEXTCLOUD_MYSQL_ROOT_PASSWORD is configured in your site.conf."
            exit 1
        fi

        if [ -z "$NEXTCLOUD_MYSQL_PASSWORD" ]; then
            echo "ERROR: Ensure NEXTCLOUD_MYSQL_PASSWORD is configured in your site.conf."
            exit 1
        fi
    fi


    if [ "$DEPLOY_NOSTR" = true ]; then
        if [ -z "$NOSTR_ACCOUNT_PUBKEY" ]; then
            echo "ERROR: When deploying nostr, you MUST specify NOSTR_ACCOUNT_PUBKEY."
            exit 1
        fi
    fi


    if [ -z "$DUPLICITY_BACKUP_PASSPHRASE" ]; then
        echo "ERROR: Ensure DUPLICITY_BACKUP_PASSPHRASE is configured in your site.conf."
        exit 1
    fi

    if [ -z "$DOMAIN_NAME" ]; then
        echo "ERROR: Ensure DOMAIN_NAME is configured in your site.conf."
        exit 1
    fi

done

# TODO check if there are any other stacks that are left running (other than reverse proxy)
# if so, this may mean the user has disabled one or more domains and that existing sites/services
# are still running. We should prompt the user of this and quit. They have to go manually docker stack remove these.
STACKS_STILL_RUNNING=false
if [[ $(docker stack list | wc -l) -gt 2 ]]; then
    echo "WARNING! You still have stacks running. If you have modified the SITES list,"
    echo "         you may need to go remove the docker stacks running the remote machine."
    STACKS_STILL_RUNNING=true
fi

# generate the certs and grab a backup
if [ "$RUN_CERT_RENEWAL" = true ] && [ "$RESTORE_CERTS" = false ] && [ "$STACKS_STILL_RUNNING" = false ]; then
    ./generate_certs.sh
fi

# nginx gets deployed first since it "owns" the docker networks of downstream services.
./stub/nginx_yml.sh

# next run our application stub logic. These deploy the apps too if configured to do so.
./stub/ghost_yml.sh
./stub/nextcloud_yml.sh
./stub/gitea_yml.sh
./stub/nostr_yml.sh
