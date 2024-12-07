#!/bin/bash

set -e

export MAILGUN_SMTP_PASSWORD=

export DEPLOY_GHOST=true
export DEPLOY_CLBOSS_PLUGIN=false
export DEPLOY_NOSTR=false
export DEPLOY_NEXTCLOUD=false
export DEPLOY_GITEA=false
export GHOST_DEPLOY_SMTP=false
export MAILGUN_FROM_ADDRESS=
export MAILGUN_SMTP_USERNAME=
export SITE_LANGUAGE_CODES="en"
export LANGUAGE_CODE="en"
export NOSTR_ACCOUNT_PUBKEY=


# this is where the html is sourced from.
export SITE_HTML_PATH=

export GHOST_MYSQL_PASSWORD=
export GHOST_MYSQL_ROOT_PASSWORD=
export NEXTCLOUD_MYSQL_PASSWORD=
export GITEA_MYSQL_PASSWORD=
export NEXTCLOUD_MYSQL_ROOT_PASSWORD=
export GITEA_MYSQL_ROOT_PASSWORD=
export DUPLICITY_BACKUP_PASSPHRASE=



DEFAULT_DB_IMAGE="mariadb:10.11.2-jammy"



# run the docker stack.
export GHOST_IMAGE="ghost:5.103.0"

# TODO switch to mysql. May require intricate export work for existing sites. 
# THIS MUST BE COMPLETED BEFORE v1 RELEASE
#https://forum.ghost.org/t/how-to-migrate-from-mariadb-10-to-mysql-8/29575
export GHOST_DB_IMAGE="mysql:8.0.32"


export NGINX_IMAGE="nginx:1.27.3"

# version of backup is 24.0.3
export NEXTCLOUD_IMAGE="nextcloud:25.0.4"
export NEXTCLOUD_DB_IMAGE="$DEFAULT_DB_IMAGE"

# TODO PIN the gitea version number.
export GITEA_IMAGE="gitea/gitea:latest"
export GITEA_DB_IMAGE="$DEFAULT_DB_IMAGE"

export NOSTR_RELAY_IMAGE="scsibug/nostr-rs-relay:0.9.0"


export OTHER_SITES_LIST=
export BTCPAY_ALT_NAMES=
