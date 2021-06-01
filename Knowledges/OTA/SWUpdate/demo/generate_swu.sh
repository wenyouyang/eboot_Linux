#!/bin/bash

CONTAINER_VER="1.0.1"
PRODUCT_NAME="nitrogen6x"
FILES="sw-description sw-description.sig rootfs.ext2.gz update.sh"

openssl dgst -sha256 -sign swupdate-priv.pem sw-description > sw-description.sig

for i in $FILES;do
        echo $i;done | cpio -ov -H crc >  ${PRODUCT_NAME}_${CONTAINER_VER}.swu
