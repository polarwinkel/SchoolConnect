#!/bin/bash

# Function for a clean shutdown of the container
function shutdown {
    kill -TERM "$MANAGER_PROCESS" 2>/dev/null
    exit
}
trap shutdown SIGTERM

sleep 60

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
        echo -n"I am using 'ldap'"
        SLAPD_DOMAIN1='ldap'
fi
if [[ -z "$SLAPD_ORGANIZATION" ]]; then
        echo -n"SLAPD_ORGANIZATION not set."
        echo -n"I am using 'My School'"
        SLAPD_ORGANIZATION='My School'
fi

# Wait til ldap is up and running
while ! ping -c 1 -n -w 1 ldap &> /dev/null; do
    sleep 1
done

# -------------------------------
# setup the connection to sldapd:
# -------------------------------

echo "setting up connection to slapd..."
# TODO: Besser machen: nur Anfang der Zeile mit sed parsen, dann ganze Zeile ersetzen
sed -i "s|passwd:         files|passwd:         compat ldap|g" /etc/nsswitch.conf
sed -i "s|group:          files|group:          compat ldap|g" /etc/nsswitch.conf
sed -i "s|shadow:         files|shadow:         compat ldap|g" /etc/nsswitch.conf

sed -i "s/password\t\[success=1 user_unknown=ignore default=die\]\tpam_ldap\.so use_authtok try_first_pass/password\t\[success=1 user_unknown=ignore default=die\]\tpam_ldap\.so try_first_pass/g" /etc/pam.d/common-password

# ----------------------------------
# configure smbldap and libnss-ldap:
# ----------------------------------

echo "configuring slapd and libnss-ldap..."
sed -i "s|SLAPD_PASSWORD|$SLAPD_PASSWORD|g" /root/debconf_libnss-ldap
sed -i "s|SLAPD_DOMAIN0|$SLAPD_DOMAIN0|g" /root/debconf_libnss-ldap
sed -i "s|SLAPD_DOMAIN1|$SLAPD_DOMAIN1|g" /root/debconf_libnss-ldap
debconf-set-selections /root/debconf_libnss-ldap
dpkg-reconfigure libnss-ldap
# TODO: for some reason the debconf-settings don't get into this file, so we need to place the settings and copy it there manually:
sed -i "s|SLAPD_PASSWORD|$SLAPD_PASSWORD|g" /root/libnss-ldap.conf
sed -i "s|SLAPD_DOMAIN0|$SLAPD_DOMAIN0|g" /root/libnss-ldap.conf
sed -i "s|SLAPD_DOMAIN1|$SLAPD_DOMAIN1|g" /root/libnss-ldap.conf
cp -f /root/libnss-ldap.conf /etc/

sed -i "s|SLAPD_PASSWORD|$SLAPD_PASSWORD|g" /etc/smbldap-tools/smbldap_bind.conf
sed -i "s|SLAPD_DOMAIN0|$SLAPD_DOMAIN0|g" /etc/smbldap-tools/smbldap_bind.conf
sed -i "s|SLAPD_DOMAIN1|$SLAPD_DOMAIN1|g" /etc/smbldap-tools/smbldap_bind.conf

sed -i "s|SLAPD_PASSWORD|$SLAPD_PASSWORD|g" /etc/smbldap-tools/smbldap.conf
sed -i "s|SLAPD_DOMAIN0|$SLAPD_DOMAIN0|g" /etc/smbldap-tools/smbldap.conf
sed -i "s|SLAPD_DOMAIN1|$SLAPD_DOMAIN1|g" /etc/smbldap-tools/smbldap.conf

smbldap-populate -u 10000 -g 10000

# ----------------
# configure samba:
# ----------------

echo "configuring smb.conf..."
sed -i "s/SLAPD_DOMAIN0/$SLAPD_DOMAIN0/g" /root/smbconfadd
sed -i "s/SLAPD_DOMAIN1/$SLAPD_DOMAIN1/g" /root/smbconfadd

cp -f /root/smb.conf.tpl /etc/samba/smb.conf
sed -i '/\[global\]/a security = user' /etc/samba/smb.conf
sed -i '/server role = standalone server/a # EDITED: ldap connection setup for samba:/g' /etc/samba/smb.conf
sed -i '/# EDITED: ldap connection setup for samba:/ r /root/smbconfadd' /etc/samba/smb.conf
sed -i 's/   read only = yes/   read only = no/g' /etc/samba/smb.conf
sed -i 's/   create mask = 0700/   create mask = 0777/g' /etc/samba/smb.conf
sed -i 's/   directory mask = 0700/   directory mask = 0777/g' /etc/samba/smb.conf

smbpasswd -w $SLAPD_PASSWORD

# --------------------------------
# Getting it up and insert groups:
# --------------------------------
echo "adding groups to samba..."
service nmbd start
service smbd start
smbldap-groupadd -a scsystem

#=======================================================

echo "configuration finished, starting now..."
python3 /root/smbFoldersChanger.py &
MANAGER_PROCESS=$!
wait $MANAGER_PROCESS
