#!/bin/bash

[ -z $1 ] && echo prvi argument je username && exit 1
[ -z $2 ] && echo drugi argument je user password && exit 1

USER_NAME=$1
USER_PWD=$2
docker exec -ti dc1-samba \
   expect -f /user.expect $USER_NAME $USER_PWD | grep "created successfully" 



[ $? -eq 0 ] && echo user $1 kreiran uspjesno
[ ! $? -eq 0 ] && echo user $1 nije kreiran - ERROR !


#docker exec dc1-samba \
#   samba-tool user list
