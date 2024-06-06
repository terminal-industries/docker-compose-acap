#!/bin/sh -e

echo "Starting script..."

if [ ! -e /usr/bin/containerd ]; then
    logger -p user.warn "$0: Container support required to install application."
    exit 77 # EX_NOPERM
fi

UID_DOT_GID="$(stat -c %u.%g localdata)"
USERID=$(id -u)
IS_ROOT=$([ "${USERID}" -eq 0 ] && echo true || echo false)
XDG_RUNTIME_DIR="/run/user/${USERID}"
PWD="$(pwd)"
DAEMON_JSON=localdata/daemon.json
CONTAINERD_TOML=localdata/containerd.toml
ENTRYPOINT_FILE=localdata/entrypoint.sh
XTABLES_LOCKFILE=localdata/xtables.lock
APP_NAME="$(basename "$(pwd)")"
SD_CARD_AREA=/var/spool/storage/SD_DISK/areas/"$APP_NAME"

#  log whatever the user is 
echo "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"

#  create Daemon.json
echo "Creating $DAEMON_JSON..."
if [ ! -e "$DAEMON_JSON" ]; then
    umask 077
cat << EOF >"$DAEMON_JSON"
{
  "group": "0",
  "hosts": ["unix://${XDG_RUNTIME_DIR}/docker.sock"],
  "data-root": "${SD_CARD_AREA}/data",
  "debug": true
}
EOF
    ! $IS_ROOT || chown "$UID_DOT_GID" "$DAEMON_JSON"
fi


# Check if the lock file already exists
if [ ! -e "$XTABLES_LOCKFILE" ]; then
    # Create the lock file with secure permissions
    umask 077
    touch $XTABLES_LOCKFILE
    ! $IS_ROOT || chown "$UID_DOT_GID" "$XTABLES_LOCKFILE"
fi

echo "${XTABLES_LOCKFILE} has been created and configured."
# Create entrypoint.sh
echo "Creating $ENTRYPOINT_FILE..."
umask 077
touch $ENTRYPOINT_FILE
cat << EOF >"$ENTRYPOINT_FILE"
#!/bin/sh

PATH="${PWD}:/bin:/usr/bin:%s:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

rm -rf /run/docker /run/containerd /run/xtables.lock

dockerd --rootless --config-file ${PWD}/${DAEMON_JSON}
EOF

chmod +x "$ENTRYPOINT_FILE"
chown "$UID_DOT_GID" "$ENTRYPOINT_FILE"

# ACAP framework does not handle ownership on SD card, which causes problem when
# the app user ID changes. If run as root, this script will repair the ownership.
if $IS_ROOT && [ -d "$SD_CARD_AREA" ]; then
    echo "Repairing ownership of $SD_CARD_AREA..."
    chown -R "$UID_DOT_GID" "$SD_CARD_AREA"
fi

echo "Script completed."