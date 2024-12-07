#!/bin/bash

set -e

# let's do a refresh of the certificates. Let's Encrypt will not run if it's not time.
CERTBOT_IMAGE_NAME="certbot/certbot:latest"
if ! docker image inspect "$CERTBOT_IMAGE_NAME" &> /dev/null; then
    docker pull "$CERTBOT_IMAGE_NAME"
fi

# iterate over each domain and call certbot
for DOMAIN_NAME in ${DOMAIN_LIST//,/ }; do
    export DOMAIN_NAME="$DOMAIN_NAME"
    export SITE_PATH="$SITES_PATH/$DOMAIN_NAME"

    # source the site path so we know what features it has.
    source ../project_defaults.sh
    source "$SITE_PATH/site.conf"
    source ../domain_env.sh

    # with the incus side, we are trying to expose ALL OUR services from one IP address, which terminates
    # at a cachehing reverse proxy that runs nginx.

    ssh "$PRIMARY_WWW_FQDN" sudo mkdir -p "$REMOTE_DATA_PATH_LETSENCRYPT/$DOMAIN_NAME/_logs"

    # this is minimum required; www and btcpay.
    DOMAIN_STRING="-d $DOMAIN_NAME -d $WWW_FQDN -d $BTCPAY_USER_FQDN"
    if [ "$DEPLOY_NEXTCLOUD" = true ]; then DOMAIN_STRING="$DOMAIN_STRING -d $NEXTCLOUD_FQDN"; fi
    if [ "$DEPLOY_GITEA" = true ]; then DOMAIN_STRING="$DOMAIN_STRING -d $GITEA_FQDN"; fi
    if [ "$DEPLOY_NOSTR" = true ]; then DOMAIN_STRING="$DOMAIN_STRING -d $NOSTR_FQDN"; fi

    
    # if BTCPAY_ALT_NAMES has been set by the admin, iterate over the list
    # and append the domain names to the certbot request
    if [ -n "$BTCPAY_ALT_NAMES" ]; then
        # let's stub out the rest of our site definitions, if any.
        for ALT_NAME in ${BTCPAY_ALT_NAMES//,/ }; do
            DOMAIN_STRING="$DOMAIN_STRING -d $ALT_NAME.$DOMAIN_NAME"
        done
    fi
    
    GENERATE_CERT_STRING="docker run -t --rm --name certbot -p 80:80 -p 443:443 -v $REMOTE_DATA_PATH_LETSENCRYPT/$DOMAIN_NAME:/etc/letsencrypt -v /var/lib/letsencrypt:/var/lib/letsencrypt -v $REMOTE_DATA_PATH_LETSENCRYPT/$DOMAIN_NAME/_logs:/var/log/letsencrypt certbot/certbot certonly -v --noninteractive --agree-tos --key-type ecdsa --standalone --expand ${DOMAIN_STRING} --email $CERTIFICATE_EMAIL_ADDRESS"

    # execute the certbot command that we dynamically generated.
    eval "$GENERATE_CERT_STRING"
done
