#!/bin/bash

if [ -z "$DOMAIN_NAME" ]; then
    echo "ERROR: DOMAIN_NAME not defined.".
    exit 1
fi

/sovereign-stack/refresh.sh --domain="$DOMAIN_NAME"
