#!/bin/bash -e

# Copyright 2018 Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -x

function print_help() {
    echo 'Usage: test.sh [--skip-setup] [--skip-cleanup] <istio-directory>'
    exit 1
}

export WAIT_TIMEOUT=${WAIT_TIMEOUT:-5m}
SKIP_CLEANUP=0
SKIP_SETUP=0
while [ $# -gt 0 ]
do
    case $1 in
        --skip-cleanup)
            SKIP_CLEANUP=1
            ;;
        --skip-setup) 
            SKIP_SETUP=1
            ;;
        *)
            if [ ! -z "$ISTIO_PATH" ]; then
                echo "to many arguments"
                print_help
            fi
            ISTIO_PATH=$1
        ;;
    esac
    shift 1
done

if [ -z "$ISTIO_PATH" ]; then
    echo "istio-directory not set"
    print_help
fi
if [ ! -d "$ISTIO_PATH" ]; then
    echo "$ISTIO_PATH is not a directory"
    print_help
fi

cd $ISTIO_PATH

if [ "$SKIP_SETUP" -eq 0 ]; then
    kubectl label namespace default istio-env=istio-control --overwrite
fi

if [ -z $SKIP_CLEANUP ] ; then

kubectl delete -f samples/bookinfo/platform/kube/bookinfo.yaml --ignore-not-found
kubectl delete -f samples/bookinfo/networking/destination-rule-all-mtls.yaml --ignore-not-found
kubectl delete -f samples/bookinfo/networking/bookinfo-gateway.yaml --ignore-not-found

    kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
    kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
    kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
    kubectl wait --all --for=condition=Ready pods --timeout=$WAIT_TIMEOUT
    for depl in details-v1 productpage-v1 ratings-v1 reviews-v1 reviews-v2 reviews-v3; do
        kubectl patch deployment $depl --patch '{"spec": {"strategy": {"rollingUpdate": {"maxSurge": 1,"maxUnavailable": 0},"type": "RollingUpdate"}}}'
    done
fi

kubectl rollout status deployments productpage-v1 --timeout=$WAIT_TIMEOUT
kubectl get pod

export INGRESS_HOST=$(kubectl -n istio-ingress get service ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z $INGRESS_HOST ]; then
    export INGRESS_HOST=$(kubectl -n istio-ingress get service ingressgateway -o jsonpath='{.spec.clusterIP}')
fi
export INGRESS_PORT=$(kubectl -n istio-ingress get service ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n istio-ingress get service ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
set +e
n=1
while true
do
    RESULT=$(curl -s -o /dev/null -w "%{http_code}" http://${GATEWAY_URL}/productpage)
    if [ $RESULT -eq "200"  ]; then
        break
    fi
    if [ $n -ge 5 ]; then
        exit 1
    fi
    n=$((n+1))
    echo "Retrying in 10s..."
    sleep 10
done
set -e

if [ -z $SKIP_CLEANUP ] ; then
echo "Cleaning up..."
kubectl delete -f samples/bookinfo/platform/kube/bookinfo.yaml --ignore-not-found
kubectl delete -f samples/bookinfo/networking/destination-rule-all-mtls.yaml --ignore-not-found
kubectl delete -f samples/bookinfo/networking/bookinfo-gateway.yaml --ignore-not-found
fi
