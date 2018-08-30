#!/usr/bin/env bash

if test -z "$1"; then
    MIRROR_URL="http://localhost:3000"
else
    MIRROR_URL="$1"
fi

if test -z "$2"; then
    ORIG_SETUP_YAML="stack-setup-2.yaml"
else
    ORIG_SETUP_YAML="$2"
fi

MIRROR_URL_ESC=\
$(echo "$MIRROR_URL" | sed -e 's/[\/&]/\\&/g')

sed "s/\\( \\+url\\: *\\)\"http.*\\/\\([^?]*\\).*\"\$`\
    `/\\1$MIRROR_URL_ESC\\/stack\\/\\2/" \
    "$ORIG_SETUP_YAML" \
    > "stack-setup-mirror.yaml"
