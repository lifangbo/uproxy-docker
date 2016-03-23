#!/bin/bash

# Tests if a Zork instance can handle N number of connections.

source "${BASH_SOURCE%/*}/utils.sh" || (echo "cannot find utils.sh" && exit 1)

CONTAINER_PREFIX=stress
PREBUILT=

function usage () {
  echo "$0 [-p] [-h] browser-version giver_ip giver_port num_attempts parallelism"
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

if [ $# -lt 5 ]
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

seq $4 | parallel -j $5 --linebuffer -k 'echo -n "{}: " && ./connect-pair.sh '$GETTER_IP' 9000 '$GIVER_IP' '$GIVER_PORT'; echo'
