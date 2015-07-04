#!/bin/sh

VOLUME_BASE=/data/samba
VOLUME_QUOTA=5G

S_HOST="dc1"                                                                                           
S_DEV=eth0
S_DOMAIN="bring"                                                                                       
S_REALM="$S_DOMAIN.out.ba"                                                                             
S_HOST_IP="192.168.168.20"                                                                             

create_volume_dirs() 
{
  # /data/samba/bring.out.ba/dc1
  DATASET=green/samba/$S_REALM-$S_HOST
  echo kreiram $VOLUME_BASE/$S_REALM/$S_HOST $DATASET
  sudo zfs create -o acltype=posixacl -o quota=$VOLUME_QUOTA -o mountpoint=$VOLUME_BASE/$S_REALM/$S_HOST $DATASET
  echo pravim direktorije $VOLUME_BASE/$S_REALM/$S_HOST /etc /var
  # /data/samba/bring.out.ba/dc1/etc
  sudo mkdir $VOLUME_BASE/$S_REALM/$S_HOST/etc
  sudo chown docker $VOLUME_BASE/$S_REALM/$S_HOST/etc
  sudo mkdir $VOLUME_BASE/$S_REALM/$S_HOST/var
  sudo chown docker $VOLUME_BASE/$S_REALM/$S_HOST/var

}           

clean_data()
{

 sudo rm -r -f /data/samba/dc1-etc/.alreadysetup
 sudo rm -r -f /data/samba/dc1-etc/*
 sudo rm -r -f /data/samba/dc1-samba/*

}

RUN=-d
RUN_CMD=

if [ "$1" == "clean" ] ; then
  clean_data
fi

if [ "$2" == "bash" ] ; then                   
  RUN=-ti                                       
  RUN_CMD=/bin/bash                             
fi 


run_host_net() {

echo uklanjam container $S_HOST-samba
docker rm -f $S_HOST-samba

echo kreiram ip: ip addr add $S_HOST_IP/24 dev $S_DEV
sudo ip addr add $S_HOST_IP/24 dev eth0

SMB_OPTS="--option=interfaces=$S_HOST_IP/24"
#SMB_OPTS="$SMB_OPTS --option=\\\"bind interfaces only\\\"=yes"
docker run $RUN \
     --name $S_HOST-samba \
     --privileged \
     --net host \
     -p $S_HOST_IP:53:53 -p $S_HOST_IP:53:53/udp -p $S_HOST_IP:88:88 -p $S_HOST_IP:88:88/udp -p $S_HOST_IP:135:135 -p $S_HOST_IP:137:137/udp \
     -p $S_HOST_IP:138:138/udp -p $S_HOST_IP:139:139 -p $S_HOST_IP:389:389 -p $S_HOST_IP:389:389/udp \
     -p $S_HOST_IP:1024-5000:1024-5000 \
     -v $VOLUME_BASE/$S_REALM/$S_HOST/etc:/etc/samba \
     -v $VOLUME_BASE/$S_REALM/$S_HOST/var:/var/lib/samba \
     -v /opt/boot/config/samba-tool-user-add.expect:/user.expect \
     -e SAMBA_DOMAIN=$S_DOMAIN -e SAMBA_REALM=$S_REALM \
     -e SAMBA_HOST_IP=$S_HOST_IP \
     -e KERBEROS_PASSWORD=Lozinka01 \
     -e SAMBA_OPTIONS="$SMB_OPTS" \
     samba-ad-dc $RUN_CMD
}

[ !  -d $VOLUME_BASE/$S_REALM/$S_HOST ] && create_volume_dirs || \
[ !  -d $VOLUME_BASE/$S_REALM/$S_HOST/etc ] && create_volume_dirs 
run_host_net

echo pokreni:
echo docker logs $S_HOST-samba 2>&1 | head -3
