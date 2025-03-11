#!/bin/bash

# Retrieve all folders that start with 'install-dir-sno'
sno_folders=()
for d in workdir/install/install-dir-sno*/; do
  sno_folders+=("$(basename "$d" | cut -d '-' -f 3-)")
done

for cluster_name in "${sno_folders[@]}"; do
  export KUBECONFIG=workdir/install/install-dir-$cluster_name/auth/kubeconfig
  echo -e "\nCluster: $(oc whoami --show-server)"
  echo -e "Console: $(oc whoami --show-console)"
  oc get nodes
done

ARGOCD_URL=$(oc get routes argocd-server -n openshift-operators -o jsonpath='{.status.ingress[0].host}')
ARGOCD_PASSWD=$(oc get secret argocd-cluster -n openshift-operators -o jsonpath='{.data.admin\.password}' | base64 -d)
argocd login --grpc-web --username admin --password $ARGOCD_PASSWD $ARGOCD_URL

echo -e "\nArgoCD clusters status:"
argocd cluster list
