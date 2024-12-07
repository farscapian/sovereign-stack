#!/bin/bash

set -eu
cd "$(dirname "$0")"

if ! docker image inspect "$NEXTCLOUD_IMAGE" &> /dev/null; then
    docker pull "$NEXTCLOUD_IMAGE"
fi

for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # source the site path so we know what features it has.
    source ../../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../../domain_env.sh

    # ensure remote directories exist
    if [ "$DEPLOY_NEXTCLOUD" = true ]; then

        ssh "$PRIMARY_WWW_FQDN" "mkdir -p $REMOTE_NEXTCLOUD_PATH/$DOMAIN_NAME/en/db"
        ssh "$PRIMARY_WWW_FQDN" "mkdir -p $REMOTE_NEXTCLOUD_PATH/$DOMAIN_NAME/en/html"

        sleep 2

        WEBSTACK_PATH="$SITE_PATH/webstack"
        mkdir -p "$WEBSTACK_PATH"
        export DOCKER_YAML_PATH="$WEBSTACK_PATH/nextcloud-en.yml"

        # here's the NGINX config. We support ghost and nextcloud.
        cat > "$DOCKER_YAML_PATH" <<EOL
version: "3.8"
services:

  ${NEXTCLOUD_STACK_TAG}:
    image: ${NEXTCLOUD_IMAGE}
    networks:
      - nextcloud-${DOMAIN_IDENTIFIER}-en
      - nextclouddb-${DOMAIN_IDENTIFIER}-en
    volumes:
      - ${REMOTE_DATA_PATH}/nextcloud/${DOMAIN_NAME}/en/html:/var/www/html
    environment:
      - MYSQL_PASSWORD=\${NEXTCLOUD_MYSQL_PASSWORD}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_HOST=${NEXTCLOUD_DB_STACK_TAG}
      - NEXTCLOUD_TRUSTED_DOMAINS=${DOMAIN_NAME}
      - OVERWRITEHOST=${NEXTCLOUD_FQDN}
      - OVERWRITEPROTOCOL=https
      - SERVERNAME=${NEXTCLOUD_FQDN}
    deploy:
      restart_policy:
        condition: on-failure

  ${NEXTCLOUD_DB_STACK_TAG}:
    image: ${NEXTCLOUD_DB_IMAGE}
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW --innodb_read_only_compressed=OFF
    networks:
      - nextclouddb-${DOMAIN_IDENTIFIER}-en
    volumes:
      - ${REMOTE_DATA_PATH}/nextcloud/${DOMAIN_NAME}/en/db:/var/lib/mysql
    environment:
       - MARIADB_ROOT_PASSWORD=\${NEXTCLOUD_MYSQL_ROOT_PASSWORD}
       - MYSQL_PASSWORD=\${NEXTCLOUD_MYSQL_PASSWORD}
       - MYSQL_DATABASE=nextcloud
       - MYSQL_USER=nextcloud
    deploy:
      restart_policy:
        condition: on-failure

networks:
    nextcloud-${DOMAIN_IDENTIFIER}-en:
      name: "reverse-proxy_nextcloudnet-$DOMAIN_IDENTIFIER-$LANGUAGE_CODE"
      external: true

    nextclouddb-${DOMAIN_IDENTIFIER}-en:

EOL

        docker stack deploy -c "$DOCKER_YAML_PATH" "$DOMAIN_IDENTIFIER-nextcloud-en"
        sleep 1
    fi
done