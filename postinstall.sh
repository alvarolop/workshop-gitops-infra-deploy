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

echo -e "\n[1/2]Install the GitOps operator"
oc apply -f gitops-operator

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l control-plane=gitops-operator -n openshift-gitops-operator -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

echo -e "\n[2/2]Configure ArgoCD using GitOps"
cat application-hub-setup.yaml | CLUSTER_DOMAIN=$BASE_DOMAIN envsubst | oc apply -f -


echo -e "\n============================="
echo -e "=      INSTALL KEYCLOAK     ="
echo -e "=============================\n"

sh set-up-keycloak.sh 20 $BASE_DOMAIN


# echo -e "\n============================"
# echo -e "=      INSTALL FREEIPA     ="
# echo -e "============================\n"

# # Add Red Hat COP Helm repository and update
# helm repo add redhat-cop https://redhat-cop.github.io/helm-charts
# helm repo update

# # Install or upgrade the IPA Helm chart
# helm upgrade --install ipa redhat-cop/ipa --namespace=ipa --create-namespace --set app_domain=apps.${BASE_DOMAIN}

# # Wait for the ipa-1-deploy pod to complete deployment
# echo "Waiting for ipa-1-deploy pod to complete..."
# while [[ $(kubectl get pods -n ipa -l app.kubernetes.io/name=ipa -o jsonpath='{.items[0].status.phase}') != "Running" ]]; do
#     sleep 10
#     echo "Still waiting..."
# done

# # Expose the IPA service as NodePort
# oc expose service ipa --type=NodePort --name=ipa-nodeport --generator="service/v2" -n ipa

# # Login to kerberos
# oc exec -it dc/ipa -n ipa -- \
#     sh -c "echo Passw0rd123 | /usr/bin/kinit admin && \
#     echo Passw0rd | \
#     ipa user-add ldap_admin --first=ldap \
#     --last=admin --email=ldap_admin@redhatlabs.dev --password"
    
# # Create groups if they dont exist

# oc exec -it dc/ipa -n ipa -- \
#     sh -c "ipa group-add student --desc 'wrapper group' || true && \
#     ipa group-add ocp_admins --desc 'admin openshift group' || true && \
#     ipa group-add ocp_devs --desc 'edit openshift group' || true && \
#     ipa group-add ocp_viewers --desc 'view openshift group' || true && \
#     ipa group-add-member student --groups=ocp_admins --groups=ocp_devs --groups=ocp_viewers || true"

# # Add demo users

# oc exec -it dc/ipa -n ipa -- \
#     sh -c "echo Passw0rd | \
#     ipa user-add paul --first=paul \
#     --last=ipa --email=paulipa@redhatlabs.dev --password || true && \
#     ipa group-add-member ocp_admins --users=paul"

# oc exec -it dc/ipa -n ipa -- \
#     sh -c "echo Passw0rd | \
#     ipa user-add henry --first=henry \
#     --last=ipa --email=henryipa@redhatlabs.dev --password || true && \
#     ipa group-add-member ocp_devs --users=henry"

# oc exec -it dc/ipa -n ipa -- \
#     sh -c "echo Passw0rd | \
#     ipa user-add mark --first=mark \
#     --last=ipa --email=markipa@redhatlabs.dev --password || true && \
#     ipa group-add-member ocp_viewers --users=mark"


# echo -e "\n============================="
# echo -e "=   INSTALL HASHICORP VAULT  ="
# echo -e "=============================\n"

# # Add the HashiCorp Helm repository and update it
# helm repo add hashicorp https://helm.releases.hashicorp.com
# helm repo update

# # Create a new OpenShift project for Vault
# oc new-project vault

# # Install Vault using Helm in development mode with OpenShift-specific settings
# helm install vault hashicorp/vault \
#     --namespace=vault \
#     --set "global.openshift=true" \
#     --set "server.dev.enabled=true" \
#     --values values.openshift.yaml

# # Expose the Vault service to create an OpenShift route
# oc expose svc vault -n vault

# echo "Vault has been deployed and exposed in the 'vault' namespace."



