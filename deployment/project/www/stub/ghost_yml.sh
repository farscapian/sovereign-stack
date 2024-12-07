#!/bin/bash

set -eu
cd "$(dirname "$0")"

if ! docker image inspect "$GHOST_IMAGE" &> /dev/null; then
    docker pull "$GHOST_IMAGE"
fi

DEPLOY_STACK=false
for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # source the site path so we know what features it has.
    source ../../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../../domain_env.sh

    if [ "$DEPLOY_GHOST" = true ]; then
        DEPLOY_STACK=true
    fi

    # for each language specified in the site.conf, we spawn a separate ghost container
    # at https://www.domain.com/$LANGUAGE_CODE
    for LANGUAGE_CODE in ${SITE_LANGUAGE_CODES//,/ }; do

        STACK_NAME="$DOMAIN_IDENTIFIER-$LANGUAGE_CODE"

        # ensure directories on remote host exist so we can mount them into the containers.
        ssh "$PRIMARY_WWW_FQDN" mkdir -p "$REMOTE_GHOST_PATH/$DOMAIN_NAME"
        ssh "$PRIMARY_WWW_FQDN" mkdir -p "$REMOTE_GHOST_PATH/$DOMAIN_NAME/$LANGUAGE_CODE/ghost" "$REMOTE_GHOST_PATH/$DOMAIN_NAME/$LANGUAGE_CODE/db"

        export GHOST_STACK_TAG="ghost-$STACK_NAME"
        export GHOST_DB_STACK_TAG="ghostdb-$STACK_NAME"

        # todo append domain number or port number.
        WEBSTACK_PATH="$SITE_PATH/webstack"
        mkdir -p "$WEBSTACK_PATH"
        export DOCKER_YAML_PATH="$WEBSTACK_PATH/ghost-$LANGUAGE_CODE.yml"

        # here's the NGINX config. We support ghost and nextcloud.
        cat > "$DOCKER_YAML_PATH" <<EOL
version: "3.8"
services:

EOL
    # This is the ghost for HTTPS (not over Tor)
        cat >>"$DOCKER_YAML_PATH" <<EOL
  ${GHOST_STACK_TAG}:
    image: ${GHOST_IMAGE}
    networks:
      - ghostnet-${DOMAIN_IDENTIFIER}-${LANGUAGE_CODE}
      - ghostdbnet-${DOMAIN_IDENTIFIER}-${LANGUAGE_CODE}
    volumes:
      - ${REMOTE_GHOST_PATH}/${DOMAIN_NAME}/${LANGUAGE_CODE}/ghost:/var/lib/ghost/content
    environment:
EOL
            if [ "$LANGUAGE_CODE" = "en" ]; then
                cat >>"$DOCKER_YAML_PATH" <<EOL
      - url=https://${WWW_FQDN}
EOL
            else
                cat >>"$DOCKER_YAML_PATH" <<EOL
      - url=https://${WWW_FQDN}/${LANGUAGE_CODE}
EOL
            fi
            
            cat >>"$DOCKER_YAML_PATH" <<EOL
      - database__client=mysql
      - database__connection__host=${GHOST_DB_STACK_TAG}
      - database__connection__user=ghost
      - database__connection__password=\${GHOST_MYSQL_PASSWORD}
      - database__connection__database=ghost
      - database__pool__min=0
      - privacy__useStructuredData=true
EOL

            # INSERT EMAIL OPTIONS HERE
            if [ "$GHOST_DEPLOY_SMTP" = true ]; then
                cat >>"$DOCKER_YAML_PATH" <<EOL
      - mail__transport=SMTP
      - mail__from=${MAILGUN_FROM_ADDRESS}
      - mail__options__auth__user=${MAILGUN_SMTP_USERNAME}
      - mail__options__auth__pass=${MAILGUN_SMTP_PASSWORD}
      - mail__options__host=smtp.mailgun.org
      - mail__options__port=587
EOL
            fi

            cat >>"$DOCKER_YAML_PATH" <<EOL
    deploy:
      restart_policy:
        condition: on-failure

  ${GHOST_DB_STACK_TAG}:
    image: ${GHOST_DB_IMAGE}
    networks:
      - ghostdbnet-${DOMAIN_IDENTIFIER}-${LANGUAGE_CODE}
    volumes:
      - ${REMOTE_GHOST_PATH}/${DOMAIN_NAME}/${LANGUAGE_CODE}/db:/var/lib/mysql
    environment:
       - MYSQL_ROOT_PASSWORD=\${GHOST_MYSQL_ROOT_PASSWORD}
       - MYSQL_DATABASE=ghost
       - MYSQL_USER=ghost
       - MYSQL_PASSWORD=\${GHOST_MYSQL_PASSWORD}
    deploy:
      restart_policy:
        condition: on-failure

EOL

        cat >>"$DOCKER_YAML_PATH" <<EOL
networks:
EOL

            if [ "$DEPLOY_GHOST" = true ]; then
                GHOSTNET_NAME="ghostnet-$DOMAIN_IDENTIFIER-$LANGUAGE_CODE"
                GHOSTDBNET_NAME="ghostdbnet-$DOMAIN_IDENTIFIER-$LANGUAGE_CODE"

                cat >>"$DOCKER_YAML_PATH" <<EOL
    ${GHOSTNET_NAME}:
      name: "reverse-proxy_ghostnet-$DOMAIN_IDENTIFIER-$LANGUAGE_CODE"
      external: true

    ${GHOSTDBNET_NAME}:
EOL
            fi

        if [ "$DEPLOY_STACK" = true ]; then
            docker stack deploy -c "$DOCKER_YAML_PATH" "$DOMAIN_IDENTIFIER-ghost-$LANGUAGE_CODE"
            sleep 2
        fi

    done # language code

done # domain list