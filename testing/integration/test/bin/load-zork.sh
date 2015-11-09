#!/bin/bash

RUNVNC=false
FOREVER=false
LISTEN=false
CLONEARGS=
CLONESRC=https://github.com/uProxy/uproxy-lib.git
PREBUILT=false
while getopts b:r:lpvwh? opt; do
    case $opt in
        b)
            CLONEARGS="$CLONEARGS -b $OPTARG"
            ;;
        r)
            CLONESRC=$OPTARG
            ;;
        p)
            PREBUILT=true
            ;;
        v)
            RUNVNC=true
            ;;
        w)
            FOREVER=true
            ;;
        l)
            LISTEN=true
            ;;
        *)
            echo "$0 [-v] [-w] [-l] [-b branch] [-r repo]"
            echo "  -b: BRANCH is the branch to checkout instead of HEAD's referant."
            echo "  -r: REPO is the repository to clone instead of github.com/uProxy/uproxy-lib."
            echo "  -p: use a pre-built uproxy-lib repo (overrides -b and -r)."
            echo "  -v: run a vncserver (port 5900 in the instance)"
            echo "  -w: after doing everything else, wait forever."
            echo "  -l: wait until the extension is listening."
            exit 1;
            ;;
    esac
done


# Overlap X startup with our download and build.
export DISPLAY=:10
Xvfb :10 -screen 0 1280x1024x24 &
fvwm &

if $RUNVNC; then
    x11vnc -display :10 -forever &
fi

if ! $PREBUILT; then
    mkdir -p /test/src
    cd /test/src
    npm install -g bower grunt-cli
    echo git clone $CLONEARGS $CLONESRC
    git clone $CLONEARGS $CLONESRC
    cd uproxy-lib
    ./setup.sh install
    grunt zork
fi
/test/bin/browser.sh /test/src/uproxy-lib/build/dev/uproxy-lib/samples/zork

while $FOREVER; do
    sleep 1
done