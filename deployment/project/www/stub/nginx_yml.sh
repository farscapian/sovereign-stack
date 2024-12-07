#!/bin/bash

set -e
cd "$(dirname "$0")"

if ! docker image inspect "$NEXTCLOUD_IMAGE" &> /dev/null; then
    docker pull "$NGINX_IMAGE"
fi

#https://github.com/fiatjaf/expensive-relay
# NOSTR RELAY WHICH REQUIRES PAYMENTS.
DOCKER_YAML_PATH="$PROJECT_PATH/nginx.yml"
cat > "$DOCKER_YAML_PATH" <<EOL
version: "3.8"
services:

  nginx:
    image: ${NGINX_IMAGE}
    ports:
      - 0.0.0.0:443:443
      - 0.0.0.0:80:80
    networks:
EOL

for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # source the site path so we know what features it has.
    source ../../../deployment_defaults.sh
    source ../../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../../domain_env.sh

    for LANGUAGE_CODE in ${SITE_LANGUAGE_CODES//,/ }; do
        # We create another ghost instance under /

        if [ "$DEPLOY_GHOST" = true ]; then 
            cat >> "$DOCKER_YAML_PATH" <<EOL
      - ghostnet-$DOMAIN_IDENTIFIER-$LANGUAGE_CODE
EOL
        fi
    
        if [ "$LANGUAGE_CODE" = en ]; then
            if [ "$DEPLOY_GITEA" = "true" ]; then
                cat >> "$DOCKER_YAML_PATH" <<EOL
      - giteanet-$DOMAIN_IDENTIFIER-en
EOL
            fi

            if [ "$DEPLOY_NEXTCLOUD" = "true" ]; then
                cat >> "$DOCKER_YAML_PATH" <<EOL
      - nextcloudnet-$DOMAIN_IDENTIFIER-en
EOL
            fi

            if [ "$DEPLOY_NOSTR" = true ]; then
                cat >> "$DOCKER_YAML_PATH" <<EOL
      - nostrnet-$DOMAIN_IDENTIFIER-en
EOL
            fi
        fi

    done

done

cat >> "$DOCKER_YAML_PATH" <<EOL
    volumes:
      - ${REMOTE_DATA_PATH_LETSENCRYPT}:/etc/letsencrypt:ro
EOL

cat >> "$DOCKER_YAML_PATH" <<EOL
    configs:
      - source: nginx-config
        target: /etc/nginx/nginx.conf
    deploy:
      restart_policy:
        condition: on-failure

configs:
  nginx-config:
    file: ${PROJECT_PATH}/nginx.conf

EOL

################ NETWORKS SECTION
cat >> "$DOCKER_YAML_PATH" <<EOL
networks:
EOL

for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # source the site path so we know what features it has.
    source ../../../deployment_defaults.sh
    source ../../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../../domain_env.sh

    # for each language specified in the site.conf, we spawn a separate ghost container
    # at https://www.domain.com/$LANGUAGE_CODE
    for LANGUAGE_CODE in ${SITE_LANGUAGE_CODES//,/ }; do
        if [ "$DEPLOY_GHOST" = true ]; then 
            cat >> "$DOCKER_YAML_PATH" <<EOL
  ghostnet-$DOMAIN_IDENTIFIER-$LANGUAGE_CODE:
    attachable: true
EOL
        fi
        
        if [ "$LANGUAGE_CODE" = en ]; then
            if [ "$DEPLOY_GITEA" = true ]; then
                cat >> "$DOCKER_YAML_PATH" <<EOL
  giteanet-$DOMAIN_IDENTIFIER-en:
    attachable: true
EOL
            fi

            if [ "$DEPLOY_NEXTCLOUD" = true ]; then
                cat >> "$DOCKER_YAML_PATH" <<EOL
  nextcloudnet-$DOMAIN_IDENTIFIER-en:
    attachable: true
EOL
            fi

            if [ "$DEPLOY_NOSTR" = true ]; then
                cat >> "$DOCKER_YAML_PATH" <<EOL
  nostrnet-$DOMAIN_IDENTIFIER-en:
    attachable: true
EOL
    
            fi
        fi
    done
done

# for some reason we need to wait here. See if there's a fix; poll for service readiness?
sleep 5

docker stack deploy -c "$DOCKER_YAML_PATH" reverse-proxy
# iterate over all our domains and create the nginx config file.
sleep 3
