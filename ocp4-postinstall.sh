#!/bin/bash

# set -x

source $(pwd)/$1

# Check if the user is logged in 
if ! oc whoami &> /dev/null; then
    echo -e "Check. You are not logged in. Please log in and run the script again."
    exit 1
else
    echo -e "Check. You are correctly logged in. Continue..."
    # Check if the server URL contains the BASE_DOMAIN
    if [[ "$(oc whoami --show-server)" != *"$BASE_DOMAIN"* ]]; then
        echo "The server URL does not contain the BASE_DOMAIN. You are not logged in the correct cluster."
        exit 1
    fi
    if ! oc project &> /dev/null; then
        echo -e "Current project does not exist, moving to project Default."
        oc project default 
    fi
fi


echo -e "\n==============================="
echo -e "=      INSTALL OCP GITOPS     ="
echo -e "===============================\n"

GITOPS_NS=openshift-gitops

echo -e "\n[1/2]Install the GitOps operator"
oc apply -f 01-gitops-operator

sleep 30

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l control-plane=gitops-operator -n openshift-gitops-operator -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

echo -e "\n[2/2]Configure ArgoCD using GitOps"
cat 02-application-gitops-setup.yaml | CLUSTER_DOMAIN=$BASE_DOMAIN envsubst | oc apply -f -

APP=gitops-setup
echo -n "Waiting for Argo CD application to be synced and healthy..."
while [[ $(oc get application $APP -n $GITOPS_NS -o jsonpath='{.status.sync.status}') != "Synced" || $(oc get application $APP -n $GITOPS_NS -o jsonpath='{.status.health.status}') != "Healthy" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n" 

echo -e "\n============================="
echo -e "=      INSTALL KEYCLOAK     ="
echo -e "=============================\n"

cat 03-application-keycloak.yaml | CLUSTER_DOMAIN=$BASE_DOMAIN NUM_CLUSTERS=20 envsubst | oc apply -f -

APP=keycloak
echo -n "Waiting for Argo CD application to be synced and healthy..."
while [[ $(oc get application $APP -n $GITOPS_NS -o jsonpath='{.status.sync.status}') != "Synced" || $(oc get application $APP -n $GITOPS_NS -o jsonpath='{.status.health.status}') != "Healthy" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

echo -e "\n============================="
echo -e "=   INSTALL HASHICORP VAULT  ="
echo -e "=============================\n"

oc apply -f 04-application-hashicorp-vault-server.yaml

APP=hashicorp-vault-server
echo -n "Waiting for Argo CD application to be synced and healthy..."
while [[ $(oc get application $APP -n $GITOPS_NS -o jsonpath='{.status.sync.status}') != "Synced" || $(oc get application $APP -n $GITOPS_NS -o jsonpath='{.status.health.status}') != "Healthy" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

echo "Vault has been deployed and exposed in the 'vault' namespace."

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l app.kubernetes.io/instance=hashicorp-vault-server -n vault -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

echo "Initializing Hashicorp Vault..."

./04-create_vault_secrets.sh


echo -e "\n============================"
echo -e "=      INSTALL FREEIPA     ="
echo -e "============================\n"

cat 05-application-freeipa.yaml | CLUSTER_DOMAIN=$BASE_DOMAIN envsubst | oc apply -f -

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l app=freeipa -n ipa -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

# Expose it using NodePort and use 389 for LDAP on the node port 
oc patch service freeipa -n ipa -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {
        "name": "ldap",
        "protocol": "TCP",
        "port": 389,
        "targetPort": 389,
        "nodePort": 30389
      }
    ]
  }
}'

echo -e "\tConfiguring groups and users..."

./05-init-freeipa.sh

echo -e "\tFreeIPA is ready to use!"
