







#     if [ "$DEPLOY_NEXTCLOUD" = true ]; then
#         cat >>"$DOCKER_YAML_PATH" <<EOL
#   nextcloud-db:
#     image: ${NEXTCLOUD_DB_IMAGE}
#     command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW --innodb_read_only_compressed=OFF
#     networks:
#       - nextclouddb-net
#     volumes:
#       - ${REMOTE_HOME}/nextcloud/db/data:/var/lib/mysql
#     environment:
#       - MARIADB_ROOT_PASSWORD=\${NEXTCLOUD_MYSQL_ROOT_PASSWORD}
#       - MYSQL_PASSWORD=\${NEXTCLOUD_MYSQL_PASSWORD}
#       - MYSQL_DATABASE=nextcloud
#       - MYSQL_USER=nextcloud
#     deploy:
#       restart_policy:
#         condition: on-failure

#   nextcloud:
#     image: ${NEXTCLOUD_IMAGE}
#     networks:
#       - nextclouddb-net
#       - nextcloud-net
#     volumes:
#       - ${REMOTE_HOME}/nextcloud/html:/var/www/html
#     environment:
#       - MYSQL_PASSWORD=\${NEXTCLOUD_MYSQL_PASSWORD}
#       - MYSQL_DATABASE=nextcloud
#       - MYSQL_USER=nextcloud
#       - MYSQL_HOST=nextcloud-db
#       - NEXTCLOUD_TRUSTED_DOMAINS=${DOMAIN_NAME}
#       - OVERWRITEHOST=${NEXTCLOUD_FQDN}
#       - OVERWRITEPROTOCOL=https
#       - SERVERNAME=${NEXTCLOUD_FQDN}
#     deploy:
#       restart_policy:
#         condition: on-failure

# EOL
#     fi



#     if [ "$DEPLOY_ONION_SITE" = true ]; then
#         cat >>"$DOCKER_YAML_PATH" <<EOL
#   # a hidden service that routes to the nginx container at http://onionurl.onion server block
#   tor-onion:
#     image: tor:latest
#     networks:
#       - tor-net
#     volumes:
#       - ${REMOTE_HOME}/tor:/var/lib/tor
#       - tor-logs:/var/log/tor
#     configs:
#       - source: tor-config
#         target: /etc/tor/torrc
#         mode: 0644
#     deploy:
#       mode: replicated
#       replicas: 1
#       restart_policy:
#         condition: on-failure

#   tor-ghost:
#     image: ${GHOST_IMAGE}
#     networks:
#       - ghostdb-net
#       - ghost-net
#     volumes:
#       - ${REMOTE_HOME}/tor_ghost:/var/lib/ghost/content
#     environment:
#       - url=https://${ONION_ADDRESS}
#       - database__client=mysql
#       - database__connection__host=ghostdb
#       - database__connection__user=ghost
#       - database__connection__password=\${GHOST_MYSQL_PASSWORD}
#       - database__connection__database=ghost
#     deploy:
#       restart_policy:
#         condition: on-failure

# EOL
#     fi


#     if [ "$DEPLOY_ONION_SITE" = true ]; then
# cat >>"$DOCKER_YAML_PATH" <<EOL
#       - torghost-net
# EOL
#     fi

#     if [ "$DEPLOY_NEXTCLOUD" = true ]; then
# cat >>"$DOCKER_YAML_PATH" <<EOL
#       - nextcloud-net
# EOL
#     fi


#     if [ "$DEPLOY_ONION_SITE" = true ]; then
# cat >>"$DOCKER_YAML_PATH" <<EOL
#       - tor-net
# EOL
#     fi

#     if [ "$DEPLOY_ONION_SITE" = true ]; then
#         cat >>"$DOCKER_YAML_PATH" <<EOL
  
# volumes:
#   tor-data:
#   tor-logs:

# EOL
#     fi
#     #-------------------------



#     if [ "$DEPLOY_NEXTCLOUD" = true ]; then
#         cat >>"$DOCKER_YAML_PATH" <<EOL
#   nextclouddb-net:
#   nextcloud-net:
# EOL
#     fi


#     if [ "$DEPLOY_ONION_SITE" = true ]; then
#         cat >>"$DOCKER_YAML_PATH" <<EOL
#   tor-net:
#   torghost-net:
# EOL
#     fi
#     # -------------------------------


#     if [ "$DEPLOY_ONION_SITE" = true ]; then
#         cat >>"$DOCKER_YAML_PATH" <<EOL
#   tor-config:
#     file: $(pwd)/tor/torrc
# EOL
#     fi
#     # -----------------------------
