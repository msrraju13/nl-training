#!/bin/sh
set -e

JENKINS_USER_ID=admin
JENKINS_SECRET=$(docker exec -it --user root jenkins-blueocean cat /var/jenkins_home/secrets/initialAdminPassword | tr -d '\r')

if [ -z "$JENKINS_SECRET" ]; then
  echo "Jenkins secret token could not be found"
  exit 1
fi

if [ "$JENKINS_SECRET" == *\:* ]; then
  echo "Jenkins secret token was not valid!!! '$JENKINS_SECRET'"
  exit 2
fi
