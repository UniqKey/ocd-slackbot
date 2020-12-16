#!/bin/bash
set -Eeuo pipefail

oc() { 
    bin/oc_wrapper.sh "$@"
    if [[ "$?" != 0 ]]; then
        >&2 echo "ERROR oc wrapper returned none zero status"
    fi
}

IMAGE_STREAM="$1"

if [ -z "$IMAGE_STREAM" ]; then
    >&2 echo "ERROR Please provide image stream as first parameter (e.g., php-71-rhel7)"
fi

if [ -z "$BUILD_PROJECT" ]; then
    >&2 echo "ERROR Please provide BUILD_PROJECT as an environment variable (e.g., 'your-eng')"
fi

REDHAT_REGISTRY_API="https://registry.redhat.io/v2/rhscl/$IMAGE_STREAM"
REDHAT_REGISTRY_URL="registry.access.redhat.com/rhscl/$IMAGE_STREAM"

#echo REDHAT_REGISTRY_URL=$REDHAT_REGISTRY_URL
#echo IMAGE_STREAM=$IMAGE_STREAM

# Step1: What do we actually have locally? 
oc export is -o json -n $BUILD_PROJECT | /opt/app-root/jq -r '."items"[] | select(.metadata.name=="'$IMAGE_STREAM'") | .spec.tags[].name'  | grep -v latest > /tmp/local.$$

# ( echo "local tags are: " && cat /tmp/local.$$  ) || true

if [[ ! -s /tmp/local.$$ ]]; then
     (>&2 echo "ERROR could not get the local tags using oc export is -o json -n $BUILD_PROJECT")
fi

# Step 2.0: Get an oAuth token based on a service account username and password https://access.redhat.com/articles/3560571
TOKEN=$(curl --silent -u "$REGISTRY_USER":"$REGISTRY_PASSWORD" "https://sso.redhat.com/auth/realms/rhcc/protocol/redhat-docker-v2/auth?service=docker-registry&client_id=curl&scope=repository:rhel:pull" |  /opt/app-root/jq --raw-output '.token')

# Step 2.1: What are the tags that match the upstream “latest” version?
wget -q --header="Accept: application/json" --header="Authorization: Bearer $TOKEN" -O - "$REDHAT_REGISTRY_API/tags/list" | /opt/app-root/jq -r '."tags"[]' | while read -r TAG ; do echo "$TAG" ; wget --header="Authorization: Bearer $TOKEN" --header="Accept: application/vnd.docker.distribution.manifest.v2+json" -q  -O - "$REDHAT_REGISTRY_API/manifests/$TAG" | /opt/app-root/jq '.config.digest // "null"' ; done | paste -d, - - | awk 'BEGIN{FS=OFS=","}{map[$1] = $2;rmap[$2][$1] = $1;}END{for (key in rmap[map["latest"]]) {print key}}' | grep -v latest > /tmp/upstream.$$

# (echo "upstream tags are: " && cat /tmp/upstream.$$) || true

# Step3: What is upstream that isn’t local?
awk 'NR==FNR{a[$1];next} {delete a[$1] } END{for (key in a) print key }' /tmp/upstream.$$ /tmp/local.$$ > /tmp/missing.$$
#echo "missing tags are:"
#cat /tmp/missing.$$

# Step4: Whats the command to replace them? 
cat /tmp/missing.$$ | \
while read TAG; do \
    echo "# Run the following to import the missing image $TAG:"
    echo '```'
    echo "oc -n $BUILD_PROJECT import-image $IMAGE_STREAM:$TAG --from='$REDHAT_REGISTRY_URL:$TAG' --confirm"
    echo '```'
    echo "# Run the following set the imported image as the latest to trigger a build:"
    echo '```'
    echo "oc tag $BUILD_PROJECT/$IMAGE_STREAM:$TAG $BUILD_PROJECT/$IMAGE_STREAM:latest"
    echo '```'
done > /tmp/import.$$

if [ -s /tmp/missing.$$ ]
then
    echo "# The image stream $IMAGE_STREAM is missing one or more images marked as 'latest' upstream."
    cat /tmp/import.$$
else
    UPSTREAM=$(cat /tmp/upstream.$$ | paste -sd "," -)
    echo "The image stream $IMAGE_STREAM is up to date with latest upstream tags $UPSTREAM"
fi

rm /tmp/local.$$ /tmp/upstream.$$ /tmp/missing.$$ /tmp/import.$$