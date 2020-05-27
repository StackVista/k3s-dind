#!/bin/bash

KUBE_CONFIG=/kubeconfig
if [ ! -z "${K3S_KUBECONFIG_OUTPUT_DIR}" ]; then
    KUBE_CONFIG=${K3S_KUBECONFIG_OUTPUT_DIR}/kubeconfig
fi

export KUBECONFIG=${KUBE_CONFIG}

while [ ! -f ${KUBE_CONFIG} ]; do
    sleep 1
done

if [ "$1" = "-json" ]; then
    cfg=$(kubectl config view -o json --merge=true --flatten=true)
else
    cfg=$(kubectl config view -o yaml --merge=true --flatten=true)
fi

if [ -z "$2" ]; then
    hostname="localhost"
else
    hostname="$2"
fi

echo "$cfg" | sed -e "s/0\.0\.0\.0/$hostname/g"
