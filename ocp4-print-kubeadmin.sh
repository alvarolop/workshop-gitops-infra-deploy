#!/bin/bash

# Retrieve all folders that start with 'install-dir-sno'
sno_folders=()
for d in workdir/install/install-dir-sno*/; do
  sno_folders+=("$(basename "$d" | cut -d '-' -f 3-)")
done

for cluster_name in "${sno_folders[@]}"; do
  file_path="workdir/install/install-dir-$cluster_name/auth/kubeadmin-password"
  
  if [ -f "$file_path" ]; then
    password=$(cat "$file_path")
    echo -e "$cluster_name\t$password"
  else
    echo -e "$cluster_name\tFile not found"
  fi
done

echo -e "\nYAML Structure:\n"
echo "          sno:"
for cluster_name in "${sno_folders[@]}"; do
  export KUBECONFIG="workdir/install/install-dir-$cluster_name/auth/kubeconfig"
  # oc apply -k auth/overlays/sno
  cluster_id=${cluster_name#"sno-"} # Remove the sno- part
  token=$(oc create token argocd-admin -n openshift-config)
  echo "            \"$cluster_id\":"
  echo "              token: $token"
done
