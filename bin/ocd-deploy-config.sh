#!/bin/bash

APP=$( echo $1 |  tr '-' '_')

if [[ -z "$APP" ]]; then
  >&2 echo "ERROR please define APP"
  exit 1
fi

# https://unix.stackexchange.com/a/251896/72040
if [[ -z "${!APP}" ]]; then
  >&2 echo "ERROR no git url defind with key ${APP}"
  exit 2
fi

TAG=$2

if [[ -z "$TAG" ]]; then
  >&2 echo "ERROR please supply TAG."
  exit 3
fi

ENVIRONMENT=$3

if [[ -z "$ENVIRONMENT" ]]; then
  >&2 echo "ERROR please define ENVIRONMENT"
  exit 1
fi

KEY=$( echo $ENVIRONMENT | tr '-' '_' )

source $APP_ROOT/src/bin/ocd-checkout.sh

ERRORTMPDIR=$(mktemp -d)
trap "rm -rf $ERRORTMPDIR" EXIT

MESSAGE="ocd-slackbot deploy $APP version $TAG"

if [ ! -f ./envvars ]; then
  >&2 echo "ERROR no envvars in $(pwd)" 
  exit 10
fi

if ! sed -i "s/^${APP}_version=.*/${APP}_version=${TAG}/g" ./envvars; then
  >&2 echo "ERROR unable to replace ${APP}_version in $(pwd)/envvars" 
  exit 11
fi

BRANCH=$(date +"%Y%m%d_%H%M%S")

if ! git checkout -b "$BRANCH" 1>"$ERRORTMPDIR/stdout" 2>"$ERRORTMPDIR/stderr"; then
  >&2 echo "WARNING failed to create branch $TAG it might exist. Continuing." 
  cat $ERRORTMPDIR/stdout
  cat $ERRORTMPDIR/stderr
fi

if ! git commit -am "$MESSAGE" 1>"$ERRORTMPDIR/stdout" 2>"$ERRORTMPDIR/stderr"; then
  >&2 echo "ERROR failed to commit modification to versions" 
  cat $ERRORTMPDIR/stdout
  cat $ERRORTMPDIR/stderr
  exit 12
fi

if ! git push origin "$BRANCH" 1>"$ERRORTMPDIR/stdout" 2>"$ERRORTMPDIR/stderr"; then
  >&2 echo "ERROR failed to git push origin $TAG"
  cat $ERRORTMPDIR/stdout
  cat $ERRORTMPDIR/stderr 
  exit 13
fi

if ! hub pull-request -m "$MESSAGE"; then
  >&2 echo "ERROR failed to hub pull-request -m $MESSAGE on branch $BRANCH"
  exit 14
fi
