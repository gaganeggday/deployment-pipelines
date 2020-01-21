#!/bin/sh
QUAYIO_USERNAME=$1
GITHUB_REPO=$2
DEPLOYMENT_PATH=${3:-deploy}

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     SED_OPTIONS="-i";;
    Darwin*)    SED_OPTIONS="-i \"\"";;
    *)          echo "unknown OS ${unameOut}"; exit 1;;
esac

if [[ $# -lt 2 ]]; then
    echo 'usage: ./setup.sh <quayio-username> <github repo>'
    exit 1
fi

IFS='/' # assumes orgname/repo
read -ra seg <<< "${GITHUB_REPO}"

if [[ ${#seg[@]} -ne 2 ]]; then
    echo 'github repo must be of the form orgname/repo'
    exit 1
fi

ORGNAME=${seg[0]}
APP_NAME=${seg[1]}
PULL_SECRET_NAME="${QUAYIO_USERNAME}-pull-secret"
IMAGE_REPO="quay.io/${QUAYIO_USERNAME}/${APP_NAME}"
GITHUB_REPO="${ORGNAME}/${APP_NAME}"
GITHUB_STAGE_REPO="${ORGNAME}/${APP_NAME}-stage-config"

FILENAME="$HOME/Downloads/${QUAYIO_USERNAME}-auth.json"
if [ ! -f "${FILENAME}" ]; then
    echo "${FILENAME} does not exist"
    exit 1
fi

FILENAME="$HOME/Downloads/${QUAYIO_USERNAME}-secret.yml"
if [ ! -f "${FILENAME}" ]; then
    echo "${FILENAME} does not exist"
    exit 1
fi

sed $SED_OPTIONS "s|REPLACE_IMAGE|${IMAGE_REPO}|g" **/*.yaml
sed $SED_OPTIONS "s|PULL_SECRET_NAME|${PULL_SECRET_NAME}|g" 02-serviceaccount/serviceaccount.yaml
sed $SED_OPTIONS "s|GITHUB_REPO|${GITHUB_REPO}|g" 08-eventlisteners/cicd-event-listener.yaml
sed $SED_OPTIONS "s|GITHUB_STAGE_REPO|${GITHUB_STAGE_REPO}|g" 08-eventlisteners/cicd-event-listener.yaml argocd/argo-app.yaml
sed $SED_OPTIONS "s|APP_NAME|${APP_NAME}|g" argocd/argo-app.yaml
sed $SED_OPTIONS "s|DEPLOYMENT_PATH|${DEPLOYMENT_PATH}|g" 07-cd/*.yaml

oc apply -f https://github.com/tektoncd/pipeline/releases/download/v0.9.1/release.yaml
oc apply -f https://github.com/tektoncd/triggers/releases/download/v0.2.0/release.yaml
oc new-project dev-environment
oc new-project stage-environment
oc new-project cicd-environment
oc apply -f "$HOME/Downloads/${QUAYIO_USERNAME}-secret.yml"
oc create secret generic regcred --from-file=.dockerconfigjson="$HOME/Downloads/${QUAYIO_USERNAME}-auth.json" --type=kubernetes.io/dockerconfigjson
oc apply -f 02-serviceaccount
oc adm policy add-scc-to-user privileged -z demo-sa
oc adm policy add-role-to-user edit -z demo-sa
oc create rolebinding demo-sa-admin-dev --clusterrole=admin --serviceaccount=cicd-environment:demo-sa --namespace=dev-environment
oc create rolebinding demo-sa-admin-stage --clusterrole=admin --serviceaccount=cicd-environment:demo-sa --namespace=stage-environment
oc apply -f 03-tasks
oc apply -f 04-templatesandbindings
oc apply -f 06-ci
oc apply -f 07-cd
oc apply -f 08-eventlisteners
oc apply -f 09-routes
oc create secret generic github-auth --from-file="$HOME/Downloads/token"
