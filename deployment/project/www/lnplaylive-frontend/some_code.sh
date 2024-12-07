# this code was found in layers above the current dir;
# need to incorporate all this into sovereign-stack

# if we are deploying the lnplaylive frontend, we can rebuild at this point
# because it required build-time info from the deployed backend. The build script below
# will stub out those envs and rebuild the output from the app.
if [ "$DEPLOY_LNPLAYLIVE_FRONTEND" = true ]; then
    env LNPLAYLIVE_FRONTEND_ENV="$LNPLAYLIVE_FRONTEND_ENV" ./lnplay/lnplaylive-frontend/build.sh
fi



if [ "$DEPLOY_LNPLAYLIVE_FRONTEND" = true ]; then
    if ! docker image inspect "$NODE_BASE_DOCKER_IMAGE_NAME" &> /dev/null; then
        # pull bitcoind down
        docker pull -q "$NODE_BASE_DOCKER_IMAGE_NAME" >> /dev/null
    fi

    if ! docker volume list | grep -q "lnplay-live"; then
        docker volume create lnplay-live
    fi
fi









# if [ "$DEPLOY_LNPLAYLIVE_FRONTEND" = true ]; then
#     cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
#       - lnplaylive-appnet
# EOF
# fi


if [ "$DEPLOY_LNPLAYLIVE_FRONTEND" = true ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
      - lnplaylive:/lnplaylive:ro
EOF
fi



# if [ "$DEPLOY_LNPLAYLIVE_FRONTEND" = true ]; then
# cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
#   lnplaylive-appnet:
# EOF
# fi


if [ "$DEPLOY_LNPLAYLIVE_FRONTEND" = true ]; then

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
  lnplaylive:
    external: true
    name: lnplay-live

EOF
fi








# this was in stub_nginx.conf
elif [ "$DEPLOY_LNPLAYLIVE_FRONTEND" = true ]; then
    cat >> "$NGINX_CONFIG_PATH" <<EOF

    # https server block for lnplaylive
    server {
        listen ${SERVICE_INTERNAL_PORT}${SSL_TAG};

        server_name ${DOMAIN_NAME};

        location ~ ^/order/(?<order_id>.+)$ {
            autoindex off;
            server_tokens off;
            gzip_static on;
            root /lnplaylive/build;
            index 404.html;
        }

        location / {
            autoindex off;
            server_tokens off;
            gzip_static on;
            root /lnplaylive/build;
            index index.html;
        }
    }
EOF

el
