#!/bin/bash
#
# Licence: GPL
# Created: 2012-07-29 14:56:23+02:00
# Main authors:
#     - Jérôme Pouiller <jezz@sysmic.org>
#

# Local = host where editor (and X server) run
# Remote = host where this script run and file to be edited is located. Remote
#          can also be a different user.
#
# To work, you need:
#  - inotify-tools on local
#  - ssh server on local
#  - a network connectivity between remote and local
#  - A ssh key and a ssh-agent
#  - Recommended: ssh server on remote. I suggest to connect remote using
#    "ssh -A -R 1022:localhost:22" or better:
#       [[ -n "$SSH_TTY" ]] && FWDPORT=22 || FWDPORT=1022
#       alias ssh="ssh -A -R 1022:localhost:$FWDPORT"
#  - Recommended: alias "sudo" to "sudo SSH_AUTH_SOCK=$SSH_AUTH_SOCK" to be able
#    to edit files as root without password prompt
#  - export EDITOR=Path_to_this_script
#  - export REDITOR_FALLBACK=Your_favorite_editor
#  - export REDITOR_LOCAL=Your_local_editor (Should be set by ssh.Mjst be a graphical editor)
#  - export REDITOR_USERNAME=Local_username (Should be set by ssh)
#
# Autoinstall draft: 
#   ssh -p 81 root@192.168.1.4 'mkdir -p ~/.bin; cat > ~/.bin/redit.sh; echo "export EDITOR=~/.bin/redit.sh" >> ~/.bashrc; echo "alias e=~/.bin/redit.sh" >> ~/.bashrc' < conf/bin/redit.sh


# Limitations and TODO:
#   Poor handling of abnormal cases (Race conditions, Ctrl+C on remote, retc...)
#   May does not keep permissions and proprietary
#   Each user on remote have to choose a different port 
#   Need between 0.2s and 1s to start. It's a quite a lot.
#   No option to disable ControlMaster (even if it should work with warnings)
#   Not tested with other editors
#   Need network connectivity (sometime I only have a serial connection)
#   Need ssh and scp on remote
#   No support for line jumping (like "edit.sh file +15")
#   Written in bash

# Detect case we are called from sudo
if [[ -z "$SSH_TTY" ]]; then
  PORT=22
else
  PORT=10022
fi
if [[ -z ${REDITOR_USERNAME} ]]; then
  HOST=localhost
else
  HOST=$REDITOR_USERNAME@localhost
fi
LDIR=\$HOME/remote/$(hostname)
CTRLP="-o ControlPath=~/.ssh/%r@%h:%p -o ControlPersist=5 "
SSH="ssh -p $PORT "
SCP="scp -qP $PORT "
EDITOR_FALLBACK="${EDITOR_FALLBACK:-vim}"

# Detect if we are running on local session
# Use local editor in this case
if  [[ -z "$SSH_AUTH_SOCK" || -z "$SSH_TTY" && -n "$DISPLAY" && -z "$SUDO_USER" ]]; then
  exec ${EDITOR_FALLBACK} "$@"
  echo "Cannot execute ${EDITOR_FALLBACK}"
  exit 1
fi

# Use ControlMaster if supported
if [ -e ~/.ssh/$HOST:$PORT ] || $SSH $CTRLP -Mn $HOST true 2> /dev/null; then
  SSH="$SSH $CTRLP"
  SCP="$SCP $CTRLP"
elif ! $SSH $HOST true; then
  echo " $SSH $HOST true"
  echo "Falling back to ${EDITOR_FALLBACK}"
  exec ${EDITOR_FALLBACK} "$@"
  echo "Cannot execute ${EDITOR_FALLBACK}"
  exit 1
fi

$SSH $HOST "mkdir -p $LDIR; cat > $LDIR/local-edit.sh; chmod +x $LDIR/local-edit.sh" << EOF &
#! /bin/bash
LOCK=$LDIR/\$\$.lock
if ! which inotifywait > /dev/null; then 
  echo "Please install inotify-tools on Local host" >&2 
  exit 1
fi
EDITOR_LOCAL=( \${EDITOR_LOCAL:-gvim} )
if ! which \${EDITOR_LOCAL[0]} > /dev/null; then 
  echo "Please install ${EDITOR_LOCAL[0]} on Local host" >&2 
  exit 1
fi
echo \$LOCK > \$LOCK
for FILE in \$@; do 
    [[ \$FILE == +* ]] || echo \$FILE >> \$LOCK
done
( DISPLAY=:0 \$EDITOR_LOCAL \$@; rm \$LOCK ) &
echo "Launched \$EDITOR_LOCAL \$@" >&2
while [ -e \$LOCK ]; do
  inotifywait -q -e move_self -e close_write -e modify -e delete_self --format "%w" --fromfile \$LOCK | sed  -e "\\,\$LOCK,d" -e "s,$LDIR,,"
done
EOF
echo "Uploaded $LDIR/local-edit.sh"

LIST=
for i in $@; do 
    if [[ ! $i == +* ]]; then 
        [ -e $i ] || touch $i
        FILE=$(readlink -f $i)
        $SSH $HOST "mkdir -p $LDIR$(dirname $FILE)"
        $SCP $FILE $HOST:$LDIR$FILE &
        LIST="$LIST $LDIR$FILE"
        echo "Uploaded $LDIR$FILE"
     else 
        LIST="$LIST $i"
     fi
done 

wait

$SSH -n $HOST "$LDIR/local-edit.sh $LIST" | while read LINE; do
    sleep 0.2
    CONNECTION_SUCCESS=1
    $SCP $HOST:$LDIR/$LINE $LINE
    echo "Downloaded $HOST:$LDIR/$LINE to $LINE (returned: $?)"
done
if [[ ${PIPESTATUS[0]} -ne 0 && $CONNECTION_SUCCESS -ne 1 ]]; then
    echo "Falling back to ${EDITOR_FALLBACK}"
    exec ${EDITOR_FALLBACK} "$@"
    echo "Cannot execute ${EDITOR_FALLBACK}"
    exit 1
fi

$SSH -n $HOST "rm $LIST"



