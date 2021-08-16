#!/bin/bash

child=0
sig_handler() {
    sig_send=$1
    code=$2
    if [ $child -ne 0 ]; then
        kill -$sig_send $child
        wait $child
    fi
    exit $code
}
trap 'sig_handler HUP 129' HUP
trap 'sig_handler TERM 130' INT
trap 'sig_handler TERM 131' QUIT
trap 'sig_handler TERM 143' TERM

K3S_LOG="/var/log/k3s.log"

function dockerReady {
    docker info >& /dev/null
}

function runDocker {
    dockerd \
    --host=unix:///var/run/docker.sock \
    --host=tcp://0.0.0.0:2375 \
    > /var/log/docker.log 2>&1 < /dev/null &

    until dockerReady ; do
        sleep 1
    done
}

if [ -z "${K3S_NAME}" ]; then
    K3S_NAME=$(hostname)
fi

# Make sure we can run inside a Kubernetes cluster without breaking out of the container
unset KUBERNETES_PORT KUBERNETES_PORT_443_TCP KUBERNETES_PORT_443_TCP_ADDR KUBERNETES_PORT_443_TCP_PORT KUBERNETES_PORT_443_TCP_PROTO KUBERNETES_SERVICE_HOST KUBERNETES_SERVICE_PORT KUBERNETES_SERVICE_PORT_HTTPS

K3S_ARGS=( \
    --no-deploy=traefik \
    --docker \
    --https-listen-port=${K3S_API_PORT:-8443} \
    --node-name=${K3S_NAME} \
    --tls-san=${K3S_NAME} \
)

function runServer {
    k3s server "${K3S_ARGS[@]}" >> ${K3S_LOG} 2>&1 &
}

function getKubeconfig {
    local cfg=$(cat /etc/rancher/k3s/k3s.yaml)
    if [[ $cfg =~ client-certificate-data ]]; then
        echo "${cfg}" | sed 's/\/\/127.0.0.1:/\/\/'"${K3S_NAME}"':/'
    fi
}

function waitForKubeconfig {
    local cfg=""
    while [ -z "${cfg}" ]; do
        sleep 1
        cfg=$(getKubeconfig)
    done

    echo "${cfg}" > /tmp/kubeconfig
    KUBE_CONFIG=/build/kubeconfig
    if [ ! -z "${K3S_KUBECONFIG_OUTPUT_DIR}" ]; then
        if [ ! -d "${K3S_KUBECONFIG_OUTPUT_DIR}" ]; then
            mkdir -p ${K3S_KUBECONFIG_OUTPUT_DIR}
        fi
        KUBE_CONFIG=${K3S_KUBECONFIG_OUTPUT_DIR}/kubeconfig
    fi

    mv /tmp/kubeconfig ${KUBE_CONFIG}
}



echo > ${K3S_LOG}
tail -F ${K3S_LOG} &
child=$!

runDocker
runServer
waitForKubeconfig

touch /k3s_startup_complete
echo Kubeconfig is ready

# Put the tail of logs in the foreground to keep the container running
wait $child
