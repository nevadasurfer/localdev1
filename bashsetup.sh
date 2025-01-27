#!/bin/bash

set -euo pipefail

# create cluster
cat <<EOF | kind create cluster --config=-
---
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: $(pwd)/mnt
    containerPath: /mnt
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

# Ingress IP
INGRESS_IP=$(docker inspect kind | jq -r '.. | .IPv4Address? | select(type != "null") | split("/")[0]')
INGRESS_DOMAIN="${INGRESS_IP}.nip.io"

# Install Ingress Nginx
echo
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
sleep 15
kubectl wait --namespace ingress-nginx  --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

# install MetalLB
echo
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml

# wait for MetalLB to be ready
sleep 15
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s

# setup MetalLB IP address pool
# Get the subnet from Docker
subnet=$(docker network inspect kind | jq -r '.[].IPAM.Config[].Subnet' | grep -P '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}/.*$')

# Split the subnet into the base IP and the CIDR suffix
IFS='/' read -r ip cidr <<< "$subnet"

# Convert the base IP to a 32-bit integer
IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
ip_dec=$(( (i1<<24) + (i2<<16) + (i3<<8) + i4 ))

# Calculate the number of hosts
num_hosts=$(( 2 ** (32 - cidr) ))

# Calculate the start and end IPs for the second half
start_ip_dec=$(( ip_dec + num_hosts / 2 ))
end_ip_dec=$(( ip_dec + num_hosts - 1 ))

# Convert the start and end IPs back to dotted decimal format
start_ip=$(printf "%d.%d.%d.%d" $(( (start_ip_dec & 0xFF000000) >> 24 )) $(( (start_ip_dec & 0x00FF0000) >> 16 )) $(( (start_ip_dec & 0x0000FF00) >> 8 )) $(( start_ip_dec & 0x000000FF )))
end_ip=$(printf "%d.%d.%d.%d" $(( (end_ip_dec & 0xFF000000) >> 24 )) $(( (end_ip_dec & 0x00FF0000) >> 16 )) $(( (end_ip_dec & 0x0000FF00) >> 8 )) $(( end_ip_dec & 0x000000FF )))

cat <<EOF| kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - "${start_ip}-${end_ip}"
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF
# add helm charts repos
echo
helm repo add gitea-charts https://dl.gitea.io/charts/
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
# install Gitea
GITEA_HOST="gitea.${INGRESS_DOMAIN}"
GITEA_USERNAME=gitea_admin
GITEA_PASSWORD=gitea_admin
echo
cat <<EOF | helm upgrade --install gitea gitea-charts/gitea --wait --create-namespace --namespace=gitea --values=-
ingress:
  enabled: true
  hosts:
  - host: "${GITEA_HOST}"
    paths:
      - path: /
        pathType: Prefix
gitea:
  admin:
    username: ${GITEA_USERNAME}
    password: ${GITEA_PASSWORD}
extraVolumes:
- name: host-mount
  hostPath:
    path: /mnt
extraContainerVolumeMounts:
- name: host-mount
  mountPath: /data/git/gitea-repositories/gitea_admin/local-repo.git
initPreScript: mkdir -p /data/git/gitea-repositories/gitea_admin/
EOF
## configure Gitea
## inspiration: https://cloudpirates.medium.com/local-prototyping-of-argocd-manifests-with-minikube-and-gitea-a8eb20a0f2d3
sleep 10
echo
curl -v -s -XPOST -H "Content-Type: application/json" -k -u "${GITEA_USERNAME}:${GITEA_PASSWORD}" \
  --url "http://${GITEA_HOST}/api/v1/admin/unadopted/gitea_admin/local-repo"
echo
curl -v -s -XPATCH -H "Content-Type: application/json" -k -d '{"private": false}' -u "${GITEA_USERNAME}:${GITEA_PASSWORD}" \
  --url "http://${GITEA_HOST}/api/v1/repos/gitea_admin/local-repo"
# setup ArgoCD
echo
ARGOCD_HOST="argocd.${INGRESS_DOMAIN}"
cat <<EOF | helm upgrade --install argocd argo/argo-cd --wait --create-namespace --namespace=argocd --values=-
configs:
  cm:
    admin.enabled: false
    timeout.reconciliation: 10s
  params:
    server.insecure: true
    server.disable.auth: true
  repositories:
    local:
      name: local
      url: http://gitea-http.gitea.svc.cluster.local:3000/gitea_admin/local-repo.git
server:
  ingress:
    enabled: true
    hosts:
    - "${ARGOCD_HOST}"
EOF
echo
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: default
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    path: apps
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/gitea_admin/local-repo.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: -1 # number of failed sync attempt retries; unlimited number of attempts if less than 0
      backoff:
        duration: 5s # the amount to back off. Default unit is seconds, but could also be a duration (e.g. "2m", "1h")
        factor: 2 # a factor to multiply the base duration after each failed retry
        maxDuration: 10m # the maximum amount of time allowed for the backoff strategy
EOF
echo
echo "Gitea address: http://${GITEA_HOST}"
echo "Gitea login:"
echo "U: ${GITEA_USERNAME}"
echo "P: ${GITEA_PASSWORD}"
echo
echo "ArgoCD address: http://${ARGOCD_HOST}"
