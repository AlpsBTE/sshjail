#!/bin/bash
#
# Setup SSH jail for karmcraft

JAIL_ROOT='/home/jail'
WORLD_ROOT='/srv/daemon-data/terra/world'
JAIL_USER='karmcraft'
declare -a PUBKEYS=(
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCoPiZwf0ElC9HhIGnyO+LhUF6Ms1HShsREIgyTecARHqdLTVW3BUAaF90OjJ45fKbx34gvhjDoaKdilClYmkNx8sYkbnmCpOwF4RXQNhHdDAk46QTn35UHHCWRrltdi2NHPG4kx8KGdY4OXcReg7KeiI+WZ08bth8ldDalZpdIQrHCZTOgI+0ab2s96Hr1rTryjsF9KxLbXbWlemuiwM8vJGrYqG3NYjrEJOkPnx9UhH6kveVgdRzylT4xPGkE7djImGCC1v5NJOTq25tndMixOTRk9n5ipu8Yv8w3iJw9H2M3XwGa9YkmEFdmEOCe8FrlW36hXIVQpKKgxdOUOVUEuWJYqgrbwag9668HwqlVnSWskHsG6yc4LyD5uaissfcyzRK/bmAU2WvLVZ40ehk9YaNQpJJD/LlT4hMhD67FRFknRxHEjJf91GQ3AAr8KgDjBYpdrQGa3hIxQAtabJkPwdwav4zbV0drsqTfcKsmKs7wDURVDCXKBH8LTqNNcQ0= kami"
    "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAskTfNE5uYMwhRNkwRWQniWZ+fpMCo1UboXVibkb+AuUnE4SlbXCWxMl2PjHqUNe5w/IdbYvwX+6sN7CfbMbF+mFDpo5t2fYQVthjYb0cxZJB3m5Luw75RXUQ7jKVoRG6r6PXkmcsNz1vndLrqeaEyeF/zTGggDvF52Sid5/Q3tGFlcliO640oslvPZq+0zQwKDLyluXwpmg2TRrMrhkYmWGkqVf+Cc5L7AHUmZCkqRDTx9QsekF7NpGzgdlE92iXb0rCpSLA8KPU85RR2uiuCeo87y42Hh7eFYXaMlrq7+CNuuxrd0gQmu60Yf0WlgT/Um+6HJ0haa280jG2ITSYpw== karmcraft"
)


set -euo pipefail
IFS=$'\n\t'

msg(){ echo -e "\033[32m ==>\033[m\033[1m $1\033[m" ;}
msg2(){ echo -e "\033[34m   ->\033[m\033[1m $1\033[m" ;}
warning(){ echo -e "\033[33m ==>\033[m\033[1m $1\033[m" >&2 ;}
error(){ echo -e "\033[31m ==>\033[m\033[1m $1\033[m" >&2 ;}


msg "Will create user \"${JAIL_USER}\" and a jail home directory at \"${JAIL_ROOT}\", with a folder mounting \"${WORLD_ROOT}\" and adapt SSH server configs as well as /etc/fstab."
msg2 "Jail: ${JAIL_ROOT}"
msg2 "  ${JAIL_ROOT}/world -> ${WORLD_ROOT}"
msg2 "Username: ${JAIL_USER}"
msg2 "Setup SSH config: /etc/ssh/"
msg2 "SSH public keys:"
for pubkey in ${PUBKEYS[@]}; do
    msg2 "  $pubkey"
done
read -p "Hit enter to continue: "

#################################################
#                     JAIL                      #
#################################################
msg "Set up jail"

if [ ! -d "$JAIL_ROOT" ]; then
    msg2 "Create jail"
    sudo mkdir -p "$JAIL_ROOT"

    msg2 "Create nodes"
    sudo mkdir -p "${JAIL_ROOT}/dev/"
    sudo mknod -m 666 "${JAIL_ROOT}/dev/null" c 1 3
    sudo mknod -m 666 "${JAIL_ROOT}/dev/tty" c 5 0
    sudo mknod -m 666 "${JAIL_ROOT}/dev/zero" c 1 5
    sudo mknod -m 666 "${JAIL_ROOT}/dev/random" c 1 8

    msg2 "Set permissions"
    sudo chown root:root "$JAIL_ROOT"
    sudo chmod 0755 "$JAIL_ROOT"
else
    msg2 "Jail dir already exists. Assuming finished setup. Skipping..."
fi

read -p "Hit enter to continue: "

#################################################
#                     USER                      #
#################################################
msg "Set up jail user $JAIL_USER"
if ! id "$JAIL_USER" >& /dev/null; then
    msg2 "Creating user $JAIL_USER"
    sudo useradd -m "$JAIL_USER"
else
    msg2 "User already exists. Skipping..."
fi

msg2 "Adding passwd and groups to jail"
sudo mkdir -p "${JAIL_ROOT}/etc"
{
    IFS=$' \n\t'
    for grp in $(groups "$JAIL_USER" | cut -d':' -f2); do
        grep "$grp" /etc/group
    done
} | sort | uniq | sed 's/[^:]*$//g' | sudo tee "${JAIL_ROOT}/etc/group"

msg2 "Adding SSH public keys"
sudo mkdir -p "/home/${JAIL_USER}/.ssh"
{
    for key in "${PUBKEYS[@]}"; do
        echo "$key"
    done
} | sudo tee "/home/${JAIL_USER}/.ssh/authorized_keys"


#################################################
#                     FSTAB                     #
#################################################
msg "Configuring FStab"
if ! egrep "^${WORLD_ROOT}\s+${JAIL_ROOT}/world\s.*?$" /etc/fstab >& /dev/null; then
    msg2 "Adding mount entry ($WORLD_ROOT -> $JAIL_ROOT) to table"
    {
        echo
        echo "# SFTP $JAIL_USER"
        echo "${WORLD_ROOT}    ${JAIL_ROOT}/world    none    defaults,bind,ro    0    0"
    } | sudo tee -a "/etc/fstab"
else
    msg2 "Entry already present. Skipping..."
fi

if ! mountpoint "${JAIL_ROOT}/world" &> /dev/null; then
    msg2 "Mounting world folder read-only"
    sudo mount --read-only --bind /srv/daemon-data/terra/world /home/jail/world
else
    msg2 "Folder already mounted. Skipping..."
fi

read -p "Hit enter to continue: "

#################################################
#               SSH SERVER CONFIG               #
#################################################
msg "Configuring SSH server"
SSHD_CONFIG_ROOT='/etc/ssh'
SSHD_CONFIG_PATH="${SSHD_CONFIG_ROOT}/sshd_config"
SSHD_CONFIG_D_PATH="${SSHD_CONFIG_ROOT}/sshd_config.d"
KARMCRAFT_SSHD_CONFIG_PATH="${SSHD_CONFIG_D_PATH}/10-${JAIL_USER}.conf"
INCLUDE_SUPPORT="$(sshd -V 2>&1 | egrep "OpenSSH_8\.[2-9]" &> /dev/null && 1 || true)"
MATCH_BLOCK="
# Jail ${JAIL_USER} into ${JAIL_ROOT} and only allow SFTP
Match User ${JAIL_USER}
    ChrootDirectory ${JAIL_ROOT}
    PasswordAuthentication no
    PubkeyAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    GatewayPorts no
    AllowAgentForwarding no
    ForceCommand internal-sftp
"

if [ "$INCLUDE_SUPPORT" ]; then
    if [ ! -d "$SSHD_CONFIG_D_PATH" ]; then
        msg2 "Creating SSH config directory"
        sudo mkdir -p "$SSHD_CONFIG_D_PATH"
    fi
    if ! egrep "^Include ${SSHD_CONFIG_D_PATH}/\*\.conf$" "$SSHD_CONFIG_PATH" &> /dev/null; then
        msg2 "Adding include statement to main SSH config"
        {
            echo
            echo "Include ${SSHD_CONFIG_D_PATH}/*.conf"
        } | sudo tee -a "$SSHD_CONFIG_PATH"
    fi

    msg2 "Adding SSH config ("$KARMCRAFT_SSHD_CONFIG_PATH")"
    echo "$MATCH_BLOCK" | sudo tee "$KARMCRAFT_SSHD_CONFIG_PATH"
else
    msg2 "OpenSSH is too old to support Include statements (>=8.2)."
    if ! egrep "^Match User ${JAIL_USER}$" "$SSHD_CONFIG_PATH" &> /dev/null; then
        msg2 "Adding Match block to $SSHD_CONFIG_PATH"
        echo "$MATCH_BLOCK" | sudo tee -a "$SSHD_CONFIG_PATH"
    else
        msg2 "Match block already present. Skipping..."
    fi
fi

msg "!!! Please remember to check the configs and reload your SSH daemon !!!"
