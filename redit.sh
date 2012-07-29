#!/bin/bash
#
# Licence: GPL
# Created: 2012-07-29 14:56:23+02:00
# Main authors:
#     - Jérôme Pouiller <jezz@sysmic.org>
#

# Local = host where editor (and X server) run
# Remote = host where this script run and file to be edited is located
#
# To work, you need:
#  - inotify-tools on local
#  - ssh server on local
#  - a network connectivity between remote and local
#  - A ssh key and a ssh-agent
#  - Recommended: ssh server on remote. I suggest to connect remote using "ssh -A -R 1022:localhost:22"
#  - I also recommand to place ths script in your $PATH and set accordingly $EDITOR
# 
# Limitations and TODO:
#   Poor handling of abnormal cases (Race conditions, Ctrl+C on remote, retc...)
#   Each user on remote have to choose a different port 
#   Need between 0.2s and 1s to start. It's a quite a lot.
#   No option to disable ControlMaster (even if it should work with warnings)
#   Not tested with other editors
#   Need network connectivity (sometime I only have a serial connection)
#   Need ssh and scp on remote
#   No support for line jumping (like "edit.sh file +15")
#   Written in bash


PORT=10022
HOST=jezz@localhost
LDIR=\~/remote/$(hostname)
LEDITOR="DISPLAY=:0 kate -b"
SSH="ssh -o ControlPath=~/.ssh/%r@%h:%p -o ControlPersist=5 -p $PORT"
SCP="scp -o ControlPath=~/.ssh/%r@%h:%p -o ControlPersist=5 -P $PORT"

[ -e ~/.ssh/$HOST:$PORT ] || $SSH -Mn $HOST true

$SSH $HOST "mkdir -p $LDIR; cat > $LDIR/local-edit.sh; chmod +x $LDIR/local-edit.sh" << EOF &
#! /bin/bash
LDIR=$LDIR
LOCK=$LDIR/\$\$.lock
echo \$@ > \$LOCK
( $LEDITOR \$@; rm $LDIR/\$\$.lock ) &
while [ -e \$LOCK ]; do
  inotifywait -q -e close_write -e modify -e delete_self --format "%w" \$LOCK \$@ | sed  -e "\\,\$LOCK,d" -e "s,\$LDIR,,"
done
EOF
echo "local-edit.sh succesfully uploaded"

LIST=( )
for i in $@; do 
    FILE=$(readlink -f $i)
    $SSH $HOST "mkdir -p $LDIR/$(dirname $FILE)"
    $SCP $FILE $HOST:$LDIR/$FILE &
    LIST+=$LDIR/$FILE
    echo "$LDIR/$FILE succesfully uploaded"
done 

wait

$SSH -n $HOST "bash $LDIR/local-edit.sh $LIST" | while read LINE; do
    sleep 0.2
    $SCP $HOST:$LDIR/$LINE $LINE
    echo "Downloaded $HOST:$LDIR/$LINE to $LINE (returned: $?)"
done



