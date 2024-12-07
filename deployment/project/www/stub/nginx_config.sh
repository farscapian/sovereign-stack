#!/bin/bash

set -eu
cd "$(dirname "$0")"

# here's the NGINX config. We support ghost and nextcloud.
NGINX_CONF_PATH="$PROJECT_PATH/nginx.conf"

# clear the existing nginx config.
echo "" > "$NGINX_CONF_PATH"

# iterate over all our domains and create the nginx config file.
iteration=0

for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"
    export CONTAINER_TLS_PATH="/etc/letsencrypt/${DOMAIN_NAME}/live/${DOMAIN_NAME}"
    
    # source the site path so we know what features it has.
    source ../../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../../domain_env.sh

    if [ $iteration = 0 ]; then
        cat >>"$NGINX_CONF_PATH" <<EOL
events {
    worker_connections  1024;
}

http {
    client_max_body_size 100m;
    server_tokens off;
    sendfile on;
    include mime.types;
    
    # next two sets commands and connection_upgrade block come from https://docs.btcpayserver.org/FAQ/Deployment/#can-i-use-an-existing-nginx-server-as-a-reverse-proxy-with-ssl-termination
    # Needed to allow very long URLs to prevent issues while signing PSBTs
    server_names_hash_bucket_size   128;
    proxy_buffer_size               128k;
    proxy_buffers                   4 256k;
    proxy_busy_buffers_size         256k;
    client_header_buffer_size       500k;
    large_client_header_buffers     4 500k;

    # Needed websocket support (used by Ledger hardware wallets)
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
    }

    # return 403 for all non-explicit hostnames
    server {
        listen 80 default_server;
        return 301 https://${WWW_FQDN}\$request_uri;
    }

EOL
    fi

    # ghost http to https redirects.
    cat >>"$NGINX_CONF_PATH" <<EOL
    # http://${DOMAIN_NAME} redirect to https://${WWW_FQDN}
    server {
        listen 80;
        
        server_name ${DOMAIN_NAME};

        location / {
            # request MAY get another redirect at https://domain.tld for www.
            return 301 https://${DOMAIN_NAME}\$request_uri;
        }
    }

EOL

    cat >>"$NGINX_CONF_PATH" <<EOL
    # http://${WWW_FQDN} redirect to https://${WWW_FQDN}
    server {
        listen 80;
        server_name ${WWW_FQDN};
        return 301 https://${WWW_FQDN}\$request_uri;
    }

EOL

    # nextcloud http-to-https redirect
    if [ "$DEPLOY_NEXTCLOUD" = true ]; then
        cat >>"$NGINX_CONF_PATH" <<EOL
    # http://${NEXTCLOUD_FQDN} redirect to https://${NEXTCLOUD_FQDN}
    server {
        listen 80;
        server_name ${NEXTCLOUD_FQDN};
        return 301 https://${NEXTCLOUD_FQDN}\$request_uri;
    }

EOL
    fi

    # gitea http to https redirect.
    if [ "$DEPLOY_GITEA" = true ]; then
        cat >>"$NGINX_CONF_PATH" <<EOL
    # http://${GITEA_FQDN} redirect to https://${GITEA_FQDN}
    server {
        listen 80;
        server_name ${GITEA_FQDN};
        return 301 https://${GITEA_FQDN}\$request_uri;
    }

EOL
    fi

    # let's iterate over BTCPAY_ALT_NAMES and generate our SERVER_NAMES for btcpay server.
    BTCPAY_SERVER_NAMES="$BTCPAY_USER_FQDN"
    if [ -n "$BTCPAY_ALT_NAMES" ]; then
        # let's stub out the rest of our site definitions, if any.
        for ALT_NAME in ${BTCPAY_ALT_NAMES//,/ }; do
            BTCPAY_SERVER_NAMES="$BTCPAY_SERVER_NAMES $ALT_NAME.$DOMAIN_NAME"
        done
    fi

    # BTCPAY server http->https redirect
    cat >>"$NGINX_CONF_PATH" <<EOL
    # http://${BTCPAY_USER_FQDN} redirect to https://${BTCPAY_USER_FQDN}
    server {
        listen 80;
        server_name ${BTCPAY_SERVER_NAMES};
        return 301 https://\$host\$request_uri;
    }

EOL

    if [ $iteration = 0 ]; then
        # TLS config for ghost.
        cat >>"$NGINX_CONF_PATH" <<EOL
    # global TLS settings
    ssl_prefer_server_ciphers on;
    ssl_protocols TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;  # about 40000 sessions
    ssl_session_tickets off;
    add_header Strict-Transport-Security "max-age=63072000" always;
    ssl_stapling on;
    ssl_stapling_verify on;

    # default server if hostname not specified.
    server {
        listen 443 default_server;

        ssl_certificate $CONTAINER_TLS_PATH/fullchain.pem;
        ssl_certificate_key $CONTAINER_TLS_PATH/privkey.pem;
        ssl_trusted_certificate $CONTAINER_TLS_PATH/fullchain.pem;

        return 403;
    }

    # maybe helps with Twitter cards.
    #map \$http_user_agent \$og_prefix {
    #    ~*(googlebot|twitterbot)/  /open-graph;
    #}

    # this map allows us to route the clients request to the correct Ghost instance
    # based on the clients browser language setting.
    map \$http_accept_language \$lang {
        default "";
        ~es es;
    }

EOL
    fi

        cat >>"$NGINX_CONF_PATH" <<EOL
    # https://${DOMAIN_NAME} redirect to https://${WWW_FQDN}
    server {
        listen 443 ssl;

        ssl_certificate $CONTAINER_TLS_PATH/fullchain.pem;
        ssl_certificate_key $CONTAINER_TLS_PATH/privkey.pem;
        ssl_trusted_certificate $CONTAINER_TLS_PATH/fullchain.pem;
        
        server_name ${DOMAIN_NAME};
        
EOL

    if [ "$DEPLOY_NOSTR" = true ]; then
        cat >>"$NGINX_CONF_PATH" <<EOL
        # We return a JSON object with name/pubkey mapping per NIP05.
        # https://www.reddit.com/r/nostr/comments/rrzk76/nip05_mapping_usernames_to_dns_domains_by_fiatjaf/sssss
        # TODO I'm not sure about the security of this Access-Control-Allow-Origin. Read up and restrict it if possible.
        location = /.well-known/nostr.json {
            add_header Content-Type application/json;
            add_header Access-Control-Allow-Origin *;
            return 200 '{ "names": { "_": "${NOSTR_ACCOUNT_PUBKEY}" }, "relays": { "${NOSTR_ACCOUNT_PUBKEY}": [ "wss://${NOSTR_FQDN}" ] } }';
        }
        
EOL
    fi

    cat >>"$NGINX_CONF_PATH" <<EOL
        
        # catch all; send request to ${WWW_FQDN}
        location / {
            return 301 https://${WWW_FQDN}\$request_uri;
        }
    }

    #access_log /var/log/nginx/ghost-access.log;
    #error_log /var/log/nginx/ghost-error.log;

EOL

    if [ "$DEPLOY_NOSTR" = true ]; then
        cat >>"$NGINX_CONF_PATH" <<EOL
    # wss://$NOSTR_FQDN server block
    server {
        listen 443 ssl;
        
        server_name ${NOSTR_FQDN};

        ssl_certificate $CONTAINER_TLS_PATH/fullchain.pem;
        ssl_certificate_key $CONTAINER_TLS_PATH/privkey.pem;
        ssl_trusted_certificate $CONTAINER_TLS_PATH/fullchain.pem;

        keepalive_timeout 70;

        location / {
            # redirect all HTTP traffic to btcpay server
            proxy_pass http://nostr-${DOMAIN_IDENTIFIER}:8080;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host \$host;
        }
    }

EOL
    fi



    cat >>"$NGINX_CONF_PATH" <<EOL
    # https server block for https://${BTCPAY_SERVER_NAMES}
    server {
        listen 443 ssl;

        ssl_certificate $CONTAINER_TLS_PATH/fullchain.pem;
        ssl_certificate_key $CONTAINER_TLS_PATH/privkey.pem;
        ssl_trusted_certificate $CONTAINER_TLS_PATH/fullchain.pem;

        server_name ${BTCPAY_SERVER_NAMES};

        # Route everything to the real BTCPay server
        location / {
            proxy_pass http://10.10.10.66:80;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

            # For websockets (used by Ledger hardware wallets)
            proxy_set_header Upgrade \$http_upgrade;
        }
    }

EOL


    if [ "$DEPLOY_GHOST" = true ]; then
        echo "    # set up cache paths for nginx caching" >>"$NGINX_CONF_PATH"
        for LANGUAGE_CODE in ${SITE_LANGUAGE_CODES//,/ }; do
            STACK_NAME="$DOMAIN_IDENTIFIER-$LANGUAGE_CODE"
            cat >>"$NGINX_CONF_PATH" <<EOL
    proxy_cache_path /tmp/${STACK_NAME} levels=1:2 keys_zone=${STACK_NAME}:600m max_size=100m inactive=24h;
EOL
        done


        # the open server block for the HTTPS listener for ghost
        cat >>"$NGINX_CONF_PATH" <<EOL
    
    # Main HTTPS listener for https://${WWW_FQDN}
    server {
        listen 443 ssl;

        ssl_certificate $CONTAINER_TLS_PATH/fullchain.pem;
        ssl_certificate_key $CONTAINER_TLS_PATH/privkey.pem;
        ssl_trusted_certificate $CONTAINER_TLS_PATH/fullchain.pem;

        server_name ${WWW_FQDN};

        # Set the crawler policy.
        location = /robots.txt { 
            add_header Content-Type text/plain;
            return 200 "User-Agent: *\\nAllow: /\\n";
        }
        
EOL

        for LANGUAGE_CODE in ${SITE_LANGUAGE_CODES//,/ }; do
            STACK_NAME="$DOMAIN_IDENTIFIER-$LANGUAGE_CODE"

            if [ "$LANGUAGE_CODE" = en ]; then
                cat >>"$NGINX_CONF_PATH" <<EOL
        location ~ ^/(ghost/|p/|private/) {
EOL
            else
            cat >>"$NGINX_CONF_PATH" <<EOL
        location ~ ^/${LANGUAGE_CODE}/(ghost/|p/|private/) {
EOL
            fi

            cat >>"$NGINX_CONF_PATH" <<EOL
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto  \$scheme;
            proxy_intercept_errors  on;
            proxy_pass http://ghost-${STACK_NAME}:2368;
        }

EOL

        done

        ROOT_SITE_LANGUAGE_CODES="$SITE_LANGUAGE_CODES"
        for LANGUAGE_CODE in ${ROOT_SITE_LANGUAGE_CODES//,/ }; do

            cat >>"$NGINX_CONF_PATH" <<EOL
        # Location block to back https://${WWW_FQDN}/${LANGUAGE_CODE} or https://${WWW_FQDN}/ if english.
EOL

            if [ "$LANGUAGE_CODE" = en ]; then
                cat >>"$NGINX_CONF_PATH" <<EOL
        location / {
EOL
                if (( "$LANGUAGE_CODE_COUNT" > 1 )); then 
                    # we only need this clause if we know there is more than once lanuage being rendered.
                    cat >>"$NGINX_CONF_PATH" <<EOL
            # Redirect the user to the correct language using the map above.
            if ( \$http_accept_language !~* '^en(.*)\$' ) {
                #rewrite (.*) \$1/\$lang;
                return 302 https://${WWW_FQDN}/\$lang;
            }

EOL
                fi

            else
                cat >>"$NGINX_CONF_PATH" <<EOL
        location /${LANGUAGE_CODE} {
EOL
            fi

            cat >>"$NGINX_CONF_PATH" <<EOL
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header Host \$host;

            proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto  \$scheme;
            proxy_intercept_errors  on;
            proxy_pass http://ghost-${DOMAIN_IDENTIFIER}-${LANGUAGE_CODE}:2368;

            # https://stanislas.blog/2019/08/ghost-nginx-cache/ for nginx caching instructions
            # Remove cookies which are useless for anonymous visitor and prevent caching
            proxy_ignore_headers Set-Cookie Cache-Control;
            proxy_hide_header Set-Cookie;

            # Add header for cache status (miss or hit)
            add_header X-Cache-Status \$upstream_cache_status;
            proxy_cache ${DOMAIN_IDENTIFIER}-${LANGUAGE_CODE};

            # Default TTL: 1 day
            proxy_cache_valid 5s;

            # Cache 404 pages for 1h
            proxy_cache_valid 404 1h;

            # use conditional GET requests to refresh the content from origin servers
            proxy_cache_revalidate on;
            proxy_buffering on;

            # Allows starting a background subrequest to update an expired cache item,
            # while a stale cached response is returned to the client.
            proxy_cache_background_update on;

            # Bypass cache for errors
            proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
        }

EOL

        done

    # this is the closing server block for the ghost HTTPS segment
    cat >>"$NGINX_CONF_PATH" <<EOL
    
    }

EOL
fi

    if [ "$DEPLOY_NEXTCLOUD" = true ]; then
        cat >>"$NGINX_CONF_PATH" <<EOL
    # TLS listener for ${NEXTCLOUD_FQDN}
    server {
        listen 443 ssl;

        ssl_certificate $CONTAINER_TLS_PATH/fullchain.pem;
        ssl_certificate_key $CONTAINER_TLS_PATH/privkey.pem;
        ssl_trusted_certificate $CONTAINER_TLS_PATH/fullchain.pem;

        server_name ${NEXTCLOUD_FQDN};
        
        location / {
            proxy_headers_hash_max_size 512;
            proxy_headers_hash_bucket_size 64;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-NginX-Proxy true;
            
            proxy_pass http://${NEXTCLOUD_STACK_TAG}:80;
        }
                    
        # https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html
        location /.well-known/carddav {
            return 301 \$scheme://\$host/remote.php/dav;
        }

        location /.well-known/caldav {
            return 301 \$scheme://\$host/remote.php/dav;
        }
    }
EOL

    fi

    if [ "$DEPLOY_GITEA" = true ]; then
        cat >>"$NGINX_CONF_PATH" <<EOL
    # TLS listener for ${GITEA_FQDN}
    server {
        listen 443 ssl;

        ssl_certificate $CONTAINER_TLS_PATH/fullchain.pem;
        ssl_certificate_key $CONTAINER_TLS_PATH/privkey.pem;
        ssl_trusted_certificate $CONTAINER_TLS_PATH/fullchain.pem;
    
        server_name ${GITEA_FQDN};
        
        location / {
            proxy_headers_hash_max_size 512;
            proxy_headers_hash_bucket_size 64;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-NginX-Proxy true;
            
            proxy_pass http://gitea-${DOMAIN_IDENTIFIER}-en:3000;
        }
    }

EOL
    fi

    iteration=$((iteration+1))
done

# add the closing brace.
cat >>"$NGINX_CONF_PATH" <<EOL
}
EOL
