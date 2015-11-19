FROM ubuntu:trusty
MAINTAINER Ernad Husremovic <hernad@bring.out.ba> 
# Thank you: Martin Yrj√∂l√<martin.yrjola@gmail.com> & Tobias Kaatz <info@kaatz.io>

ENV DEBIAN_FRONTEND noninteractive

VOLUME ["/var/lib/samba", "/etc/samba"]

# Update Ubuntu and install dependencies:
# - expect, pwgen: utilities needed for setup
# - sssd: for UNIX logins to AD
RUN sed -e 's/archive./ba.archive./' /etc/apt/sources.list -i
RUN apt-get update && apt-get upgrade && apt-get install -y \
  ntp supervisor \
  krb5-user krb5-kdc bind9 psmisc dnsutils \
  attr acl python-dnspython python-xattr \
  samba smbclient winbind ldb-tools \
  expect pwgen \
  sssd sssd-tools

# Setup ssh
#RUN mkdir -p /var/run/sshd
#RUN sed -ri 's/PermitRootLogin without-password/PermitRootLogin Yes/g' /etc/ssh/sshd_config

RUN mkdir -p /var/log/supervisor

ADD named.conf.options /etc/bind/named.conf.options

ADD kdb5_util_create.expect kdb5_util_create.expect

# Install rsyslog to get better logging of ie. bind9 (NOTE: add to single RUN command above)
# RUN apt-get install -y rsyslog

# Create run directory for bind9
RUN mkdir -p /var/run/named
RUN chown -R bind:bind /var/run/named

# Setup sssd for UNIX logins to AD
ADD sssd.conf /etc/sssd/sssd.conf
RUN chmod 0600 /etc/sssd/sssd.conf

ADD supervisord.conf.ad /
ADD supervisord.conf.member / 

ADD ntp.conf /etc/ntp.conf

# https://wiki.samba.org/index.php/Samba_port_usage

EXPOSE 22 
EXPOSE 53
EXPOSE 53/udp
EXPOSE 135 137 138 139
EXPOSE 389
EXPOSE 389/udp 
EXPOSE 445
EXPOSE 445/udp
EXPOSE 464
EXPOSE 464/udp
# EXPOSE 3268 3269 - already in 1024-5000 range
EXPOSE 1024-5000
EXPOSE 5353
EXPOSE 5353/udp

ADD nsswitch.conf.ad /

# https://lists.samba.org/archive/samba/2014-January/178286.html
# Winbindd does the authentication against AD and retreival of the
# user and group infos from a AD domain the windows way, and
# tries to map the infos as closely and windows-like as possible,
# in particular with information about nested groups, etc.

# "sssd on the other hand side, I don't know well enough. But"
# "as far as I am aware, sssd coming from the FreeIPA/LDAP world"
# "uses ldap and direct kerberos auth where possible intead of"
# "windows native methods which leads to certain tradeoffs. Some"
# "info is simply not accessible that way, or presented incorrectly."

# https://lists.samba.org/archive/samba/2014-January/178307.html
# "Running Samba's smbd as a domain member server without winbindd is a"
# "very bad idea.  It forces Samba into a number of undesirable fallback modes"

ADD nsswitch.conf.member /

ADD net_join.expect /

# https://github.com/jelmer/samba.git

#ADD samba-tool-patch/netcmd/* /usr/lib/python2.7/dist-packages/samba/netcmd/
#ADD samba-tool-patch/provision/* /usr/lib/python2.7/dist-packages/samba/provision/
#ADD samba-tool-patch/*.py /usr/lib/python2.7/dist-packages/samba/
COPY samba-tool-patch.tar.gz /

# init.sh ce prebaciti u /etc/supervisor/conf.d/supervisord.conf
ADD init.sh /init.sh
RUN chmod 755 /init.sh

ENTRYPOINT ["/init.sh"]
CMD ["app:help"]
