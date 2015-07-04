#!/bin/bash

SAMBA_DC_IP=${SAMBA_DC_IP:-192.168.168.20}
SAMBA_DC_NAME=${SAMBA_DC_NAME:-bring.out.ba}

echo ip: $SAMBA_DC_IP, domain $SAMBA_DC_NAME

docker exec dc1-samba \
   samba-tool dns query $SAMBA_DC_IP  $SAMBA_DC_NAME $SAMBA_DC_NAME A | grep $SAMBA_DC_IP

[ $? -eq 0 ] && echo domain dns ok


