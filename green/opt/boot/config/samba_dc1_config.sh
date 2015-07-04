#!/bin/sh

C_NAME=dc1-samba

dc1_exec() {

   echo  docker exec $C_NAME $CMD
   docker exec $C_NAME $CMD
}

CMD="samba-tool domain passwordsettings set --complexity=off"
dc1_exec

CMD="samba-tool domain passwordsettings set --history-length=0"
dc1_exec

CMD="samba-tool domain passwordsettings set --min-pwd-age=0"
dc1_exec

CMD="samba-tool domain passwordsettings set --max-pwd-age=0"
dc1_exec

CMD="samba-tool domain passwordsettings set --min-pwd-length=3"
dc1_exec
