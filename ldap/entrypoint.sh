#!/bin/bash

# check if environment variables are set with -e option:
if [[ -z "$SLAPD_PASSWORD" ]]; then
        echo -n >&2 "Error: Container not configured and SLAPD_PASSWORD not set. "
        echo >&2 "Did you forget to add -e SLAPD_PASSWORD=... ?"
        exit 1
fi
if [[ -z "$SLAPD_DOMAIN0" ]]; then
        echo -n"SLAPD_DOMAIN0 not set."
        echo -n"I am using 'local'"
        SLAPD_DOMAIN0='local'
fi
if [[ -z "$SLAPD_DOMAIN1" ]]; then
        echo -n"SLAPD_DOMAIN1 not set."
        echo -n"I am using 'slapd'"
        SLAPD_DOMAIN1='slapd'
fi
if [[ -z "$SLAPD_ORGANIZATION" ]]; then
        echo -n"SLAPD_ORGANIZATION not set."
        echo -n"I am using 'My School'"
        SLAPD_ORGANIZATION='My School'
fi

# ------------------------------------
# Install the slapd (openLDAP) server:
# ------------------------------------

# set the environment variables for slapd:
sed -i "s|SLAPD_PASSWORD|$SLAPD_PASSWORD|g" /root/debconf_slapd
sed -i "s|SLAPD_DOMAIN0|$SLAPD_DOMAIN0|g" /root/debconf_slapd
sed -i "s|SLAPD_DOMAIN1|$SLAPD_DOMAIN1|g" /root/debconf_slapd
sed -i "s|SLAPD_ORGANIZATION|$SLAPD_ORGANIZATION|g" /root/debconf_slapd
debconf-set-selections /root/debconf_slapd

#dpkg-reconfigure -f noninteractive slapd >/dev/null 2>&1
dpkg-reconfigure slapd

chown -R openldap:openldap /var/lib/ldap/ /var/run/slapd/

# -----------------------------
# installation of samba-schema:
# -----------------------------
sed -i "s|SLAPD_DOMAIN0|$SLAPD_DOMAIN0|g" /root/add_user.ldif
sed -i "s|SLAPD_DOMAIN1|$SLAPD_DOMAIN1|g" /root/add_user.ldif

#cp /usr/share/doc/samba/examples/LDAP/samba.schema.gz /etc/ldap/schema
cp /root/samba.schema.gz /etc/ldap/schema
zcat /root/samba.schema.gz > /etc/ldap/schema/samba.schema
mkdir /tmp/ldif_output
#slapcat -f /root/schema_convert.conf -F /tmp/ldif_output -n 0 | grep samba,cn=schema
#slapcat -f /root/schema_convert.conf -F /tmp/ldif_output -n0 -H ldap:///cn={14}samba,cn=schema,cn=config -l cn=samba.ldif
slaptest -f /root/schema_convert.conf -F /tmp/ldif_output/
#mv -f /root/cn\=samba.ldif /tmp/ldif_output/
cp "/tmp/ldif_output/cn=config/cn=schema/cn={14}samba.ldif" "/etc/ldap/slapd.d/cn=config/cn=schema"

echo "installing .ldif-files..."
#service slapd start, we need it to listen to ldapi (unix command) as well:
/usr/sbin/slapd -h "ldap:/// ldapi:///"
ldapadd -x -D cn=admin,dc=$SLAPD_DOMAIN1,dc=$SLAPD_DOMAIN0 -w $SLAPD_PASSWORD -f /root/add_user.ldif
cd /tmp/ldif_output/
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /tmp/ldif_output/cn\=samba.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/limit.ldif
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /root/samba_indices.ldif
#service slapd stop
SLAPD_PID=$(cat /run/slapd/slapd.pid)
kill -15 $SLAPD_PID
#while true; do sleep 1; done # hang for debugging...
killall -15 slapd
while [ -e /proc/$SLAPD_PID ]; do sleep 0.1; done # wait until slapd is terminated

# ===============================================================


# Start slapd in foreground:
# --------------------------
echo "configuration finished, starting now..."
slapd -d 32768
#exec "$@"
