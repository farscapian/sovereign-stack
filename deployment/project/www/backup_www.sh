#!/bin/bash

set -exu
cd "$(dirname "$0")"

APP=

# grab any modifications from the command line.
for i in "$@"; do
    case $i in
        --app=*)
            APP="${i#*=}"
            shift
        ;;

        *)
        echo "Unexpected option: $1"
        exit 1
        ;;
    esac
done

if [ -z "$APP" ]; then
    echo "ERROR: You must specify the --app= paramater."
    exit 1
fi

for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # source the site path so we know what features it has.
    source ../../deployment_defaults.sh
    source ../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../domain_env.sh

    # these variable are used by both backup/restore scripts.
    export REMOTE_BACKUP_PATH="$REMOTE_BACKUP_PATH/www/$APP/$DOMAIN_IDENTIFIER"
    export REMOTE_SOURCE_BACKUP_PATH="$REMOTE_DATA_PATH/$APP/$DOMAIN_NAME"

    # ensure our local backup path exists so we can pull down the duplicity archive to the management machine.
    export LOCAL_BACKUP_PATH="$SITE_PATH/backups/www/$APP"
    mkdir -p "$LOCAL_BACKUP_PATH"

    ./backup_path.sh
done
