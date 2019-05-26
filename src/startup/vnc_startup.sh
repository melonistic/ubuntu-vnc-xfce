#!/bin/bash
### every exit != 0 fails the script
set -e
#set -u     # do not use

## print out help
help (){
echo "
USAGE:
docker run <run-options> accetto/<image>:<tag> <option> <optional-command>

IMAGES:
accetto/ubuntu-vnc-xfce

TAGS:
latest      based on 'latest' Ubuntu
rolling     based on 'rolling' Ubuntu

OPTIONS:
-w, --wait      (default) Keeps the UI and the vnc server up until SIGINT or SIGTERM are received.
                An optional command can be executed after the vnc starts up.
                example: docker run -d -P accetto/ubuntu-vnc-xfce
                example: docker run -it -P accetto/ubuntu-vnc-xfce /bin/bash

-s, --skip      Skips the vnc startup and just executes the provided command.
                example: docker run -it -P accetto/ubuntu-vnc-xfce --skip /bin/bash

-d, --debug     Executes the vnc startup and tails the vnc/noVNC logs.
                Any parameters after '--debug' are ignored. CTRL-C stops the container.
                example: docker run -it -P accetto/ubuntu-vnc-xfce --debug

-t, --tail-log  same as '--debug'

-h, --help      Prints out this help.
                example: docker run --rm accetto/ubuntu-vnc-xfce

Fore more information see: https://github.com/accetto/ubuntu-vnc-xfce
"
}
if [[ $1 =~ -h|--help ]]; then
    help
    exit 0
fi

### '.bashrc' will also source '$STARTUPDIR/generate_container_user'
### (see 'stage-final' in Dockerfile)
source "$HOME"/.bashrc

### add `--skip` to startup args, to skip the VNC startup procedure
if [[ $1 =~ -s|--skip ]]; then
    echo -e "\n\n------------------ SKIP VNC STARTUP -----------------"
    echo -e "\n\n------------------ EXECUTE COMMAND ------------------"
    echo "Executing command: '${@:2}'"
    exec "${@:2}"
fi

if [[ $1 =~ -d|--debug ]]; then
    echo -e "\n\n------------------ DEBUG VNC STARTUP -----------------"
    export DEBUG=true
fi

### correct forwarding of shutdown signal
cleanup () {
    kill -s SIGTERM $!
    exit 0
}
trap cleanup SIGINT SIGTERM

### resolve_vnc_connection
VNC_IP=$(hostname -i)

### DEV
if [[ $DEBUG ]] ; then
    echo "DEBUG:"
    id
    echo "DEBUG: ls -la /"
    ls -la /
    echo "DEBUG: ls -la ."
    ls -la .
fi

### change vnc password
echo -e "\n------------------ change VNC password  ------------------"
### first entry is control, second is view (if only one is valid for both)
mkdir -p "$HOME"/.vnc
PASSWD_PATH="$HOME/.vnc/passwd"

if [[ "$VNC_VIEW_ONLY" == "true" ]]; then
    echo "start VNC server in VIEW ONLY mode!"
    ### create random pw to prevent access
    echo $(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20) | vncpasswd -f > "$PASSWD_PATH"
fi

echo "$VNC_PW" | vncpasswd -f >> "$PASSWD_PATH"
chmod 600 "$PASSWD_PATH"

### start vncserver and noVNC webclient
echo -e "\n------------------ start noVNC  ----------------------------"
if [[ $DEBUG == true ]]; then 
    echo "$NO_VNC_HOME/utils/launch.sh --vnc localhost:$VNC_PORT --listen $NO_VNC_PORT"
fi

"$NO_VNC_HOME"/utils/launch.sh --vnc localhost:$VNC_PORT --listen $NO_VNC_PORT &> "$STARTUPDIR"/no_vnc_startup.log &
PID_SUB=$!

echo -e "\n------------------ start VNC server ------------------------"
echo "remove old vnc locks to be a reattachable container"
vncserver -kill $DISPLAY &> "$STARTUPDIR"/vnc_startup.log \
    || rm -rfv /tmp/.X*-lock /tmp/.X11-unix &> "$STARTUPDIR"/vnc_startup.log \
    || echo "no locks present"

echo -e "start vncserver with param: VNC_COL_DEPTH=$VNC_COL_DEPTH, VNC_RESOLUTION=$VNC_RESOLUTION\n..."
if [[ $DEBUG == true ]]; then 
    echo "vncserver $DISPLAY -depth $VNC_COL_DEPTH -geometry $VNC_RESOLUTION"
fi

vncserver $DISPLAY -depth $VNC_COL_DEPTH -geometry $VNC_RESOLUTION -BlacklistTimeout $VNC_BLACKLIST_TIMEOUT -BlacklistThreshold $VNC_BLACKLIST_THRESHOLD &> "$STARTUPDIR"/no_vnc_startup.log
echo -e "start window manager\n..."

### log connect options
echo -e "\n\n------------------ VNC environment started ------------------"
echo -e "\nVNCSERVER started on DISPLAY= $DISPLAY \n\t=> connect via VNC viewer with $VNC_IP:$VNC_PORT"
echo -e "\nnoVNC HTML client started:\n\t=> connect via http://$VNC_IP:$NO_VNC_PORT/?password=...\n"

if [[ $DEBUG == true ]] || [[ $1 =~ -t|--tail-log ]]; then
    echo -e "\n------------------ $HOME/.vnc/*$DISPLAY.log ------------------"
    ### if option `-t` or `--tail-log` block the execution and tail the VNC log
    tail -f "$STARTUPDIR"/*.log "$HOME"/.vnc/*$DISPLAY.log
fi

if [ -z "$1" ] || [[ $1 =~ -w|--wait ]]; then
    wait $PID_SUB
else
    ### unknown option ==> call command
    echo -e "\n\n------------------ EXECUTE COMMAND ------------------"
    echo "Executing command: '$@'"
    exec "$@"
fi
