#!/bin/bash

CONTAINER_PREFIX=stress
PREBUILT=

function usage () {
  echo "$0 getter_ip getter_port giver_ip giver_port"
  echo "  -h, -?: this help message."
  exit 1
}

if [ $# -lt 4 ]
then
  usage
fi

GETTER_IP=$1
GETTER_PORT=$2
GIVER_IP=$3
GIVER_PORT=$4

TMP_DIR=`mktemp -d`

# the exec stuff helps make the pipes non-blocking

mkfifo $TMP_DIR/togiver
exec 5<>$TMP_DIR/togiver
mkfifo $TMP_DIR/fromgiver
exec 6<>$TMP_DIR/fromgiver
(nc -q 0 -w 5 $GIVER_IP $GIVER_PORT <&5 >&6) &
GIVER_NC_PID=$!

mkfifo $TMP_DIR/togetter
exec 7<>$TMP_DIR/togetter
mkfifo $TMP_DIR/fromgetter
exec 8<>$TMP_DIR/fromgetter
(nc -q 0 -w 5 $GETTER_IP $GETTER_PORT <&7 >&8) &
GETTER_NC_PID=$!

# -r disables newline escaping
(while true; do if read -r a <&6; then echo $a >&7; fi; done) &

echo give >&5
echo get >&7

while true
do
  if read -r b <&8
  then
    if echo $b|grep ^connected > /dev/null
    then
      SOCKS_PORT=`echo $b|cut -d' ' -f2`
      echo -n "connected on port $SOCKS_PORT..."
      # URL=http://mirror.pnl.gov/releases/15.10/ubuntu-15.10-server-i386.template
      URL=www.example.com
      if curl -s -x socks5h://$GETTER_IP:$SOCKS_PORT $URL >/dev/null
      then
        echo -n "YES!"
      else
        echo -n "FAILED"
      fi

      # TODO: is this all the cleanup we need to do?
      echo stop >&5
      echo stop >&7

      kill $GETTER_NC_PID &>/dev/null
      kill $GIVER_NC_PID &>/dev/null

      exit 0
    else
      echo $b >&5
    fi
  fi
done

exit 1
