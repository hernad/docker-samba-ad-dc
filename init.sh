#!/bin/bash

set -e

SAMBA_DOMAIN=${SAMBA_DOMAIN:-samdom}
SAMBA_REALM=${SAMBA_REALM:-samdom.example.com}

if [[ $SAMBA_HOST_IP ]]; then
    SAMBA_HOST_IP_PARAM="--host-ip=${SAMBA_HOST_IP}"
fi

kerberosInit () {                                                                                          
    
    ln -sf /var/lib/samba/private/krb5.conf /etc/krb5.conf                                                 

    # Create Kerberos database                                                                             
    expect kdb5_util_create.expect                                                                         
    # Export kerberos keytab for use with sssd                                                             
    samba-tool domain exportkeytab /etc/krb5.keytab #hernad: ne trebamo ovo --principal ${HOSTNAME}\$      
    sed -i "s/SAMBA_REALM/${KERBEROS_REALM}/" /etc/sssd/sssd.conf                                       
                                                                                                     
}

appSetup () {
    touch /etc/samba/.alreadysetup

    # Generate passwords
    ROOT_PASSWORD=$SAMBA_PASSWORD
    SAMBA_ADMIN_PASSWORD=$SAMBA_PASSWORD
    export KERBEROS_PASSWORD=$SAMBA_PASSWORD
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo Root password: $ROOT_PASSWORD
    echo Samba administrator password: $SAMBA_ADMIN_PASSWORD
    echo Kerberos KDC database master key: $KERBEROS_PASSWORD

    # Provision Samba
    rm -f /etc/samba/smb.conf
    rm -rf /var/lib/samba/private/*
    echo "samba options:$SAMBA_OPTIONS:"
    samba-tool domain provision --use-rfc2307 --domain=$SAMBA_DOMAIN --realm=$KERBEROS_REALM --server-role=dc\
      --dns-backend=BIND9_DLZ --adminpass=$SAMBA_ADMIN_PASSWORD $SAMBA_HOST_IP_PARAM $SAMBA_OPTIONS \
      --option="bind interfaces only"=yes

}

appDomainStart () {

    [ -f /etc/samba/.alreadysetup ] && echo "Skipping setup..." || appSetup

    cp /nsswitch.conf.ad /etc/nsswitch.conf
    kerberosInit

    echo samba tool provision user add patched version
    tar -xf /samba-tool-patch.tar.gz -C /usr/lib/python2.7/dist-packages/samba/
    cp /supervisord.conf.ad /etc/supervisor/conf.d/supervisord.conf
    # Start the services
    /usr/bin/supervisord
}

appHelp () {
	echo "Available options:"
	echo " app:start          - Starts all services needed for Samba AD DC"
	echo " app:setup          - First time setupi AD DC."
	echo " app:member         - Member server."
	echo " app:help           - Displays the help"
	echo " [command]          - Execute the specified linux command eg. /bin/bash."
}


set_share_permissions() {


[ -z $SAMBA_SHARES ] && exit

shares=$(echo $SAMBA_SHARES | tr "," "\n")

for f in 1 2 3 4 5
do
   groups administrator | grep -q domain\ users || (echo clock $f &&  sleep 10)
done

for share in $shares
do
  echo set share permissions $share
  groups administrator | grep -q domain\ users && \
     chown "administrator":"domain users" /$share
done


}

appMemberSmb () {


sed -i "s/SAMBA_REALM/${KERBEROS_REALM}/" /etc/sssd/sssd.conf                                       

FILE=/etc/samba/smb.conf
FILE_SHARES=/etc/samba/shares.conf

if [ ! -f /etc/samba/.alreadysetup ]
then

cat > $FILE <<- EOM
[global]

  netbios name = $SAMBA_NETBIOS
  workgroup = $KERBEROS_DOMAIN
  realm = $KERBEROS_REALM
  security = ADS
  dedicated keytab file = /etc/krb5.keytab
  kerberos method = secrets and keytab
  template homedir = /home/%U
  template shell = /bin/bash
        
  idmap config $KERBEROS_DOMAIN:backend = ad
  idmap config $KERBEROS_DOMAIN:schema_mode = rfc2307
  idmap config $KERBEROS_DOMAIN:range = 5000-50000
  idmap config *:backend = tdb
  idmap config *:range = 2000-4999
  winbind nss info = rfc2307
  winbind enum users  = yes
  winbind enum groups = yes
  winbind use default domain = yes
  winbind refresh tickets = Yes

  idmap config * : backend = tdb
  idmap idmap config * : range = 20000-99999
  idmap idmap config * : schema_mode = rfc2307

  include = $FILE_SHARES
EOM



if [ ! -z $SAMBA_SHARES ] ; then

shares=$(echo $SAMBA_SHARES | tr "," "\n")

[ ! $SAMBA_SHARES ] && rm $FILE_SHARES

for share in $shares
do 
cat >> $FILE_SHARES <<- EOM
[$share]
  comment = member share $share
  path = /$share
  browseable = Yes
  read only = no
EOM
done

fi

touch /etc/samba/.alreadysetup

fi

KRB_FILE=/etc/krb5.conf

[ -f $KRB_FILE ] && rm $KRB_FILE

cat > $KRB_FILE <<- EOM
[libdefaults]
	default_realm = $KERBEROS_REALM
	dns_lookup_realm = false
	dns_lookup_kdc = true
EOM

cp /nsswitch.conf.member /etc/nsswitch.conf

[ ! -d /var/lib/samba/private ] && mkdir /var/lib/samba/private

expect net_join.expect $SAMBA_REALM $KERBEROS_PASSWORD

cp /supervisord.conf.member /etc/supervisor/conf.d/supervisord.conf                                        


# set_share_permissions treba sacekati da se supervisord daemoni aktiviraju
set_share_permissions &

echo samba tool provision user add patched version
tar -xf /samba-tool-patch.tar.gz -C /usr/lib/python2.7/dist-packages/samba/

# Start the services                                                                             
/usr/bin/supervisord


}

init() {

echo listen on given interface $SAMBA_HOST_IP
sed -ri "s/999999/$SAMBA_HOST_IP/g" /etc/ntp.conf
sed -ri "s/999999/$SAMBA_HOST_IP/g" /etc/bind/named.conf.options

}


init

case "$1" in
	app:start)
		appDomainStart
		;;
	app:setup)
		appSetup
		;;
	app:help)
		appHelp
		;;
        app:member)
                appMemberSmb
                ;;
	*)
		if [ -x $1 ]; then
			$1
		else
			prog=$(which $1)
			if [ -n "${prog}" ] ; then
				shift 1
				$prog $@
			else
				appHelp
			fi
		fi
		;;
	esac

exit 0
