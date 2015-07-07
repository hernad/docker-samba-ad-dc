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
    samba-tool domain provision --use-rfc2307 --domain=$SAMBA_DOMAIN --realm=$SAMBA_REALM --server-role=dc\
      --dns-backend=BIND9_DLZ --adminpass=$SAMBA_ADMIN_PASSWORD $SAMBA_HOST_IP_PARAM $SAMBA_OPTIONS \
      --option="bind interfaces only"=yes

}

appStart () {
    [ -f /etc/samba/.alreadysetup ] && echo "Skipping setup..." || appSetup

    kerberosInit

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

appMemberSmb () {

FILE=/etc/samba/smb.conf

if [ ! -f /etc/samba/.alreadysetup ]
then

cat > $FILE <<- EOM
[global]

  netbios name = $SAMBA_NETBIOS
  workgroup = $KERBEROS_DOMAIN
  security = ADS
  realm = $KERBEROS_REALM
  dedicated keytab file = /etc/krb5.keytab
  kerberos method = secrets and keytab
  password server = $SAMBA_REALM

  idmap config * : backend = tdb
  idmap idmap config * : range = 2000-9999
  idmap idmap config * : schema_mode = rfc2307

  idmap config $KERBEROS_DOMAIN:backend = ad
  idmap config $KERBEROS_DOMAIN:schema_mode = rfc2307
  idmap config $KERBEROS_DOMAIN:range = 10000-49999

  winbind nss info = rfc2307
  winbind trusted domains only = no
  winbind use default domain = yes
  winbind enum users  = yes
  winbind enum groups = yes
  winbind refresh tickets = Yes

  template homedir = /home/%U
  template shell = /bin/bash

EOM


if [ ! -z $SAMBA_SHARE ] ; then

cat >> $FILE <<- EOM
[$SAMBA_SHARE]
  path = /$SAMBA_SHARE
  read only = no
  force group = "Domain Users"
  directory mask = 0770
  force directory mode = 0770
  create mask = 0660
  force create mode = 0660

EOM

expect net_join.expect $KERBEROS_PASSWORD

chown "administrator":"domain users" /$SAMBA_SHARE || echo nakon sto se podesi domena pokrenuti chown \"administrator\":\"domain users\" /$SAMBA_SHARE 

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

[ ! -d /var/lib/samba/private ] && mkdir /var/lib/samba/private

cp /supervisord.conf.member /etc/supervisor/conf.d/supervisord.conf                                        

# Start the services                                                                             

/usr/bin/supervisord


}

case "$1" in
	app:start)
		appStart
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
