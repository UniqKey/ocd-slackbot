#!/bin/bash

set -euxo pipefail

s2i --copy \
    --incremental=false \
    build \
    $(git remote show origin | fgrep 'Fetch URL' | awk '{print $NF}') \
    --ref=master \
    registry.redhat.io/ubi8/nodejs-12:latest \
    ocd-openshiftbot


#s2i s2i build     .     registry.access.redhat.com/rhscl/nodejs-8-rhel7:latest     ocd-openshiftbot

docker run -it -p 8080:8080 -e PASSPHRASE=$(<passphrase)  ocd-openshiftbot