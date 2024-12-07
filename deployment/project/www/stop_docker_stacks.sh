#!/bin/bash

set -exu
cd "$(dirname "$0")"

# this scripts brings down the docker stacks on www

# bring down ghost instances.
for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # source the site path so we know what features it has.
    source ../../deployment_defaults.sh
    source ../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../domain_env.sh

    ### Stop all services.
    for APP in ghost nextcloud gitea nostr; do
        # backup each language for each app.
        for LANGUAGE_CODE in ${SITE_LANGUAGE_CODES//,/ }; do
            STACK_NAME="$DOMAIN_IDENTIFIER-$APP-$LANGUAGE_CODE"

            if docker stack list --format "{{.Name}}" | grep -q "$STACK_NAME"; then
                docker stack rm "$STACK_NAME"
                sleep 2
            fi

            # these variable are used by both backup/restore scripts.
            export APP="$APP"
            export REMOTE_BACKUP_PATH="$REMOTE_BACKUP_PATH/www/$APP/$DOMAIN_IDENTIFIER-$LANGUAGE_CODE"
            export REMOTE_SOURCE_BACKUP_PATH="$REMOTE_DATA_PATH/$APP/$DOMAIN_NAME"
  
            # ensure our local backup path exists so we can pull down the duplicity archive to the management machine.
            export LOCAL_BACKUP_PATH="$SITE_PATH/backups/www/$APP"

            # ensure our local backup path exists.
            if [ ! -d "$LOCAL_BACKUP_PATH" ]; then
                mkdir -p "$LOCAL_BACKUP_PATH"
            fi
        done
    done
done

# remove the nginx stack
if docker stack list --format "{{.Name}}" | grep -q reverse-proxy; then
    docker stack rm reverse-proxy

    sleep 10
fi
