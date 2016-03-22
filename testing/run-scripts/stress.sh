#!/bin/bash

# Tests if a Zork instance can handle N number of connections.

source "${BASH_SOURCE%/*}/utils.sh" || (echo "cannot find utils.sh" && exit 1)

CONTAINER_PREFIX=stress
PREBUILT=

function usage () {
  echo "$0 [-p] [-h] browser-version giver_ip giver_port num_connections"
  echo "  -p: use a pre-built uproxy-lib (conflicts with -g)"
  echo "  -h, -?: this help message."
  exit 1
}

while getopts p:h? opt; do
  case $opt in
    p) PREBUILT="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

if [ $# -lt 4 ]
then
  usage
fi

function make_image () {
  if [ "X$(docker images | tail -n +2 | awk '{print $1}' | grep uproxy/$1 )" == "Xuproxy/$1" ]
  then
    echo "Reusing existing image uproxy/$1"
  else
    BROWSER=$(echo $1 | cut -d - -f 1)
    VERSION=$(echo $1 | cut -d - -f 2)
    IMAGEARGS=
    if [ -n "$PREBUILT" ]
    then
      IMAGEARGS="-p"
    fi
    ./image_make.sh $IMAGEARGS $BROWSER $VERSION
  fi
}

if ! make_image $1
then
  echo "FAILED: Could not make docker image for $1."
  exit 1
fi

# $1 is the name of the resulting container.
# $2 is the image to run, and the rest are flags.
# TODO: Take a -b BRANCH arg and pass it to load-zork.sh
function run_docker () {
  local NAME=$1
  local IMAGE=$2
  shift; shift
  IMAGENAME=uproxy/$IMAGE
  local HOSTARGS=
  if $KEEP
  then
    HOSTARGS="$HOSTARGS --rm=false"
  fi
  if [ ! -z "$PREBUILT" ]
  then
    HOSTARGS="$HOSTARGS -v $PREBUILT:/test/src/uproxy-lib"
  fi
  docker run $HOSTARGS $@ --name $NAME -d $IMAGENAME /test/bin/load-zork.sh $RUNARGS
}

# ping giver.
# this is the server under test.
GIVER_IP=$2
GIVER_PORT=$3

# start the getter.
# this is just used to generate load.
docker rm -f $CONTAINER_PREFIX-getter > /dev/null || echo
run_docker $CONTAINER_PREFIX-getter $1 -p :9000 -p $PROXY_PORT:9999
GETTER_IP=`docker inspect --format '{{ .NetworkSettings.IPAddress }}' stress-getter`
GETTER_PORT=`docker port $CONTAINER_PREFIX-getter 9000|cut -d':' -f2`

echo -n "Waiting for getter to come up (port $GETTER_PORT)"
while ! ((echo ping ; sleep 0.5) | nc -w 1 localhost $GETTER_PORT | grep ping) > /dev/null; do echo -n .; done
echo


for i in `seq 1 $4`
do
  echo "$i..."

  TMP_DIR=`mktemp -d`

  # the exec stuff helps make the pipes non-blocking

  mkfifo $TMP_DIR/togiver
  exec 5<>$TMP_DIR/togiver
  mkfifo $TMP_DIR/fromgiver
  exec 6<>$TMP_DIR/fromgiver
  (nc -q 0 -w 5 $GIVER_IP $GIVER_PORT <&5 >&6; echo "giver disconnected") &
  GIVER_NC_PID=$!

  mkfifo $TMP_DIR/togetter
  exec 7<>$TMP_DIR/togetter
  mkfifo $TMP_DIR/fromgetter
  exec 8<>$TMP_DIR/fromgetter
  (nc -q 0 -w 5 localhost $GETTER_PORT <&7 >&8; echo "getter disconnected") &
  GETTER_NC_PID=$!

  # -r disables newline escaping
  (while true; do if read -r a <&6; then echo "from giver: $a"; echo $a >&7; fi; done) &

  echo give >&5
  echo get >&7

  while true
  do
    if read -r b <&8
    then
      echo "from getter: $b"
      if echo $b|grep ^connected
      then
        SOCKS_PORT=`echo $b|cut -d' ' -f2`
        echo "connected on port $SOCKS_PORT!"
        echo curl -x socks5h://$GETTER_IP:$SOCKS_PORT www.example.com >/dev/null
        curl -x socks5h://$GETTER_IP:$SOCKS_PORT www.example.com >/dev/null

        # TODO: is this all the cleanup we need to do?
        echo stop >&5
        echo stop >&7

        kill $GETTER_NC_PID
        kill $GIVER_NC_PID

        break
      else
        echo $b >&5
      fi
    fi
  done
done
