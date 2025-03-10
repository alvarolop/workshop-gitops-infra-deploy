#!/bin/bash

# set -x

# # Check if the user is logged in 
# if ! oc whoami &> /dev/null; then
#     echo -e "Check. You are not logged in. Please log in and run the script again."
#     exit 1
# else
#     echo -e "Check. You are correctly logged in. Continue..."
#     # Check if the server URL contains the BASE_DOMAIN
#     if [[ "$(oc whoami --show-server)" != *"$BASE_DOMAIN"* ]]; then
#         echo "The server URL does not contain the BASE_DOMAIN. You are not logged in the correct cluster."
#         exit 1
#     fi
#     if ! oc project &> /dev/null; then
#         echo -e "Current project does not exist, moving to project Default."
#         oc project default 
#     fi
# fi

CLUSTER_NAME=argo-hub
OCP_API=https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443
oc login -u admin -p redhat $OCP_API --insecure-skip-tls-verify=true 

echo -e "\n==============================="
echo -e "=      INSTALL OCP GITOPS     ="
echo -e "===============================\n"

GITOPS_NS=openshift-gitops

echo -e "\n[1/2]Install the GitOps operator"
oc apply -f 01-gitops-operator

# sleep 30

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l control-plane=gitops-operator -n openshift-gitops-operator -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

echo -e "\n[2/2]Configure ArgoCD using GitOps"
cat 02-application-hub-setup.yaml | CLUSTER_DOMAIN=$BASE_DOMAIN envsubst | oc apply -f -

APP=hub-setup
echo -n "Waiting for Argo CD application to be synced and healthy..."
while [[ $(oc get application $APP -n $GITOPS_NS -o jsonpath='{.status.sync.status}') != "Synced" || $(oc get application $APP -n $GITOPS_NS -o jsonpath='{.status.health.status}') != "Healthy" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n" 

oc patch argocd openshift-gitops -n openshift-gitops --type=json -p '[{"op": "add", "path": "/spec/rbac/defaultPolicy", "value": "role:readonly"}]'

echo -e "\n==============================="
echo -e "=     INSTALL CERTIFICATES    ="
echo -e "===============================\n"

# Install OpenShift cert-manager operator
oc apply -f https://raw.githubusercontent.com/alvarolop/ocp-secured-integration/refs/heads/main/application-02-cert-manager-operator.yaml

echo -n "Waiting for operator pods to be ready..."
while [[ $(oc get pods -l name=cert-manager-operator -n cert-manager-operator -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

echo -n "Waiting for cert-manager pods to be ready..."
while [[ $(oc get pods -l app.kubernetes.io/instance=cert-manager -n cert-manager -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True True True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

# Configure API and Ingress certificates (It user the $CLUSTER_DOMAIN defined previously)
# Retrieve the cluster domain
curl -s https://raw.githubusercontent.com/alvarolop/ocp-secured-integration/main/application-02-cert-manager-route53.yaml | CLUSTER_DOMAIN=$(oc get dns.config/cluster -o jsonpath='{.spec.baseDomain}') envsubst | oc apply -f -

sleep 10 # Wait for the Certificates to be created in the cluster

echo -ne "\nWaiting for ocp-api certificate to be ready..."
while [[ $(oc get certificate ocp-api -n openshift-config -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 5; done; echo -n -e "  [OK]\n"

echo -ne "\nWaiting for ocp-ingress certificate to be ready..."
while [[ $(oc get certificate ocp-ingress -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 5; done; echo -n -e "  [OK]\n"

sleep 10

# Check cluster operators status
set +e  # Disable exit on non-zero status to keep the script running even if commands fail. There is no HA when cluster is SNO
echo -e "\nCheck cluster operators..."
while true; do
    oc get clusteroperators
    STATUS_AUTHENTICATION=$(oc get clusteroperators authentication -o go-template='{{range .status.conditions}}{{ if eq .type "Progressing"}}{{.status}}{{end}}{{end}}')
    STATUS_CONSOLE=$(oc get clusteroperators console -o go-template='{{range .status.conditions}}{{ if eq .type "Progressing"}}{{.status}}{{end}}{{end}}')
    STATUS_KUBE_API_SERVER=$(oc get clusteroperators kube-apiserver -o go-template='{{range .status.conditions}}{{ if eq .type "Progressing"}}{{.status}}{{end}}{{end}}')
    STATUS_KUBE_SCHEDULER=$(oc get clusteroperators kube-scheduler -o go-template='{{range .status.conditions}}{{ if eq .type "Progressing"}}{{.status}}{{end}}{{end}}')
    STATUS_KUBE_CONTROLLER_MANAGER=$(oc get clusteroperators kube-controller-manager -o go-template='{{range .status.conditions}}{{ if eq .type "Progressing"}}{{.status}}{{end}}{{end}}')

    if [ $STATUS_AUTHENTICATION == "False" ] && [ $STATUS_CONSOLE == "False" ] && [ $STATUS_KUBE_API_SERVER == "False" ] && [ $STATUS_KUBE_SCHEDULER == "False" ] && [ $STATUS_KUBE_CONTROLLER_MANAGER == "False" ]; then
        echo -e "\n\tOperators updated!!\n"
        break
    fi

    echo -e "Cluster operators are still progressing...Sleep 60s...\n"
    sleep 60
done

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
