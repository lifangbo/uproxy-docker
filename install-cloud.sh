#!/bin/sh

# Quick and easy install via curl and wget.
# 
# All of the heavy lifting is done by run_cloud.sh: this
# script just clones the uproxy-docker repo and executes
# run_cloud.sh from there.
#
# Heavily based on Docker's installer at:
#   https://get.docker.com/.

set -e

if [ -f /etc/centos-release ]
then 
  yum update -y
  yum install -y git bind-utils nmap-ncat
  if [ ! -f /usr/bin/docker ]
  then
    curl -fsSL https://get.docker.com/ | sh
    service docker start
  fi
fi

do_install() {
    cd /root
    git clone --depth 1 https://github.com/uProxy/uproxy-docker.git
    cd uproxy-docker/testing/run-scripts

    # TODO: pass arguments, e.g. banner
    ./run_cloud.sh firefox-stable

    # Set up cron to auto-update every Sunday at midnight
    # TODO - try to figure out timezone to pick consistent time
    echo "0 0 * * 0 root /root/uproxy-docker/testing/run-scripts/run_cloud.sh -u firefox-stable" >> /etc/crontab
}

# Wrapped in a function for some protection against half-downloads.
do_install
