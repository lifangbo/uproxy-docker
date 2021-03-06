#!/bin/bash

set -e

PREBUILT=

function usage () {
  echo "$0 [-p] [-h] browser version"
  echo "  -p: path to uproxy repo"
  echo "  -h, -?: this help message"
  echo
  echo "If -p is not specified then -p must be passed to run_cloud.sh and run_pair.sh."
  exit 1;
}

while getopts p:h? opt; do
  case $opt in
    p) PREBUILT="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

if [ $# -lt 2 ]
then
  usage
fi

BROWSER=$1
VERSION=$2

TMP_DIR=`mktemp -d`

cp -R ${BASH_SOURCE%/*}/../integration/test $TMP_DIR/test

cat <<EOF > $TMP_DIR/Dockerfile
FROM phusion/baseimage:0.9.18

RUN apt-get -qq update
RUN apt-get -qq install wget unzip xvfb fvwm supervisor iptables x11vnc unattended-upgrades

RUN mkdir /test
COPY test /test

EXPOSE 9000
EXPOSE 9999
EXPOSE 5900
EOF

if [ -n "$PREBUILT" ]
then
  mkdir $TMP_DIR/zork
  cp -R $PREBUILT/build/dev/uproxy/lib/samples/zork-* $TMP_DIR/zork
  cat <<EOF >> $TMP_DIR/Dockerfile
COPY zork /test/zork/
EOF
fi

./gen_browser.sh "$@" >> $TMP_DIR/Dockerfile

docker build -t uproxy/$BROWSER-$VERSION $TMP_DIR
