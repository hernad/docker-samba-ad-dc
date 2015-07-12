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


sed -i "s/SAMBA_REALM/${KERBEROS_REALM}/" /etc/sssd/sssd.conf                                       

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

  idmap config * : backend = tdb
  idmap idmap config * : range = 20000-99999
  idmap idmap config * : schema_mode = rfc2307

  idmap config $KERBEROS_DOMAIN:backend = ad
  idmap config $KERBEROS_DOMAIN:schema_mode = rfc2307
  idmap config $KERBEROS_DOMAIN:range = 100000-499999

  winbind nss info = rfc2307
  winbind trusted domains only = no
  winbind use default domain = yes
  winbind enum users  = yes
  winbind enum groups = yes
  winbind refresh tickets = Yes

  template homedir = /home/%U
  template shell = /bin/bash
  include = /etc/samba/shares.conf 

EOM


FILE_SHARES=/etc/samba/shares.conf

if [ ! -z $SAMBA_SHARES ] ; then

shares=$(echo $SAMBA_SHARES | tr "," "\n")

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
id Administrator | grep -q domain || echo --- net ads join ERROR ---- ?! 
chown "administrator":"domain users" /$SAMBA_SHARE || echo nakon sto se podesi domena pokrenuti chown \"administrator\":\"domain users\" /$SAMBA_SHARE 

cp /supervisord.conf.member /etc/supervisor/conf.d/supervisord.conf                                        

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
