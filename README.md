:warning: **Repo added to this [organization](https://github.com/WorkshopGitOpsInfra)**, this is view-only.

# workshop-gitops-infra-deploy

This repo is part of the [ArgoCD Managing Infrastructure workshop](https://romerobu.github.io/manual-workshop-infra/manual-workshop-infra/index.html) and is intended to deploy clusters (hub and managed) for this purpose plus the infra setup required to complete the activities. 

## Create cluster

:warning: First of all, create a **./pullsecret.txt** containing the pull secret to be used.

This script deploy OCP both hub and SNO managed on AWS. You must specify the following params:

```bash
sh ocp4-install.sh <cluster_name> <region_aws> <base_domain> <replicas_master> <replicas_worker> <vpc_id|false> <aws_id> <aws_secret> <instance_type> <amount_of_users>
```
VPC id is required only if you are deploying on an existing VPC, otherwise specify "false". 
Amount of users means users for the amount of managed cluster, in case you are not installing hub cluster it is not required.

```bash
sh ocp4-install.sh argo-hub <region_aws> <base_domain> 3 3 false <aws_id> <aws_secret> m6i.xlarge <amount_of_users> 
```
For deploying a SNO managed cluster:

```bash
sh ocp4-install.sh sno-1 <region_aws> <base_domain> 1 0 <vpc_id> <aws_id> <aws_secret> m6i.4xlarge
```
:warning: It is mandatory to name hub and sno clusters as *argo-hub* and *sno-x*

You can check your VPC id on AWS console or by running this command:

```bash
aws ec2 describe-vpcs 
```

## Deploy and configure ArgoCD

:warning: You need to install argocd [CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) and [yq](https://www.cyberithub.com/how-to-install-yq-command-line-tool-on-linux-in-5-easy-steps/).

:warning: It's higly recommended to fllow de Declarative setup approach as it has the last updates.

This script installs GitOps operator, deploy ArgoCD instance and add managed clusters. You must specify the amount of deployed SNO clusters to be managed by argocd:

```bash
sh deploy-gitops.sh <amount_of_sno_clusters>
```

For example, if you want to add 3 sno cluster (sno-1, sno-2 and sno-3):

```bash
sh deploy-gitops.sh 3
```

This script configures argo RBAC so users created in hub cluster for sno managed cluster (user-1, user-2...) can only view project-sno-x and destination sno-x clusters hence only deploying to the allowed destination within the allowed project.

### Declarative setup

You can also deploy and configure GitOps using a declarative approach as defined in this [repo](https://github.com/romerobu/workshop-gitops-content-deploy.git).

First install Openshift GitOps operator. Then create a setup-sno branch, add your clusters token to [hub-setup/charts/gitops-setup/values.yaml](https://github.com/romerobu/workshop-gitops-content-deploy/blob/main/hub-setup/charts/gitops-setup/values.yaml) file, then set subdomain and sharding replicas values and then create global-config/bootstrap-a/hub-setup-a.yaml Application on your default instance.

```bash
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hub-setup
  namespace: openshift-gitops
spec:
  destination:
    namespace: openshift-gitops
    server: https://kubernetes.default.svc
  project: default
  source:
    repoURL: https://github.com/romerobu/workshop-gitops-content-deploy.git
    targetRevision: setup-sno
    path: hub-setup/charts/gitops-setup 
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Deploy keycloak

To deploy an instance of keycloak and create the corresponding realms, client and users, run this script:

```bash
sh set-up-keycloak.sh <number_of_clusters> <subdomain | sandoboxXXX.opentlc.com>
```
Beware you need to update your [certificate](https://github.com/romerobu/helm-infra-gitops-workshop/blob/main/charts/oauth/files/ca.crt) on your helm charts repo:

```bash
oc -n openshift-ingress-operator get secret router-ca -o jsonpath="{ .data.tls\.crt }" | base64 -d -i 
```
## Deploy FreeIPA

Follow the instructions [here](https://github.com/redhat-cop/helm-charts/tree/master/charts/ipa) to deploy FreeIPA server.

```bash
git clone https://github.com/redhat-cop/helm-charts.git

cd helm-charts/charts
helm dep up ipa
cd ipa/
helm upgrade --install ipa . --namespace=ipa --create-namespace --set app_domain=apps.<domain>
```
You have to wait for IPA to be fully deployed to run this commands, verify ipa-1-deploy pod is completed.

Then, expose ipa service as NodePort and allow external traffic on AWS by configuring the security groups.

```bash
oc expose service ipa  --type=NodePort --name=ipa-nodeport --generator="service/v2" -n ipa
```
Make sure you have enabled a security group for allowing incoming traffic to port 389 (nodeport) and origin 10.0.0.0/16. You can test connectivity running this command from your managed cluster node:

```bash
nc -vz <hub_worker_node_ip> <ldap_nodeport>
```

### Create FreeIPA users

To create FreeIPA users, run these commands:

```bash
# Login to kerberos
oc exec -it dc/ipa -n ipa -- \
    sh -c "echo Passw0rd123 | /usr/bin/kinit admin && \
    echo Passw0rd | \
    ipa user-add ldap_admin --first=ldap \
    --last=admin --email=ldap_admin@redhatlabs.dev --password"
    
# Create groups if they dont exist

oc exec -it dc/ipa -n ipa -- \
    sh -c "ipa group-add student --desc 'wrapper group' || true && \
    ipa group-add ocp_admins --desc 'admin openshift group' || true && \
    ipa group-add ocp_devs --desc 'edit openshift group' || true && \
    ipa group-add ocp_viewers --desc 'view openshift group' || true && \
    ipa group-add-member student --groups=ocp_admins --groups=ocp_devs --groups=ocp_viewers || true"

# Add demo users

oc exec -it dc/ipa -n ipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add paul --first=paul \
    --last=ipa --email=paulipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_admins --users=paul"

oc exec -it dc/ipa -n ipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add henry --first=henry \
    --last=ipa --email=henryipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_devs --users=henry"

oc exec -it dc/ipa -n ipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add mark --first=mark \
    --last=ipa --email=markipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_viewers --users=mark"
```

## Deploy vault server

To deploy an instance of vault server:

```bash
git clone https://github.com/hashicorp/vault-helm.git

helm repo add hashicorp https://helm.releases.hashicorp.com

oc new-project vault

helm install vault hashicorp/vault \
    --set "global.openshift=true" \
    --set "server.dev.enabled=true" --values values.openshift.yaml
    
oc expose svc vault -n vault -n vault
```

Then you must expose vault server so it can be reached from SNO clusters.

Once server is deployed and argo-vault-plugin working on SNO, you must configure vault server auth so argo can authenticate against it.

Follow this instructions [here](https://luafanti.medium.com/injecting-secrets-from-vault-into-helm-charts-with-argocd-43fc1df57e74).

```bash
# enable kv-v2 engine in Vault
oc exec vault-0 -- vault secrets enable kv-v2

# create kv-v2 secret with two keys # Put your secrets here
oc exec vault-0 -- vault kv put kv-v2/demo password="password123"

oc exec vault-0 -- vault kv get kv-v2/demo

oc rsh vault-0 # Then run these commands

# create policy to enable reading above secret
vault policy write demo - <<EOF # Replace with your app name
path "kv-v2/data/demo" {
  capabilities = ["read"]
}
EOF

vault auth enable approle

vault write auth/approle/role/argocd secret_id_ttl=120h token_num_uses=1000 token_ttl=120h token_max_ttl=120h secret_id_num_uses=4000  token_policies=demo

vault read auth/approle/role/argocd/role-id

vault write -f auth/approle/role/argocd/secret-id
```
Bear in mind you need to update this secret on [main](https://github.com/romerobu/workshop-gitops-content-deploy/blob/main/cluster-addons/charts/bootstrap/templates/vault/secret-vault.yaml) and [main-day2](https://github.com/romerobu/workshop-gitops-content-deploy/blob/main-day2/cluster-addons/charts/bootstrap/templates/vault/secret-vault.yaml) branch to so users will clone and pull the right credentials.

## Destroy cluster

If you want to delete a cluster, first run this command to destroy it from AWS:

```bash
CLUSTER_NAME=<cluster_name>
openshift-install destroy cluster --dir install/install-dir-$CLUSTER_NAME --log-level info
```
Then remove it from ArgoCD instance:

```bash
# Make sure you are logged in cluster hub, unless you are trying to delete this cluster that this section is not required
export KUBECONFIG=./install/install-dir-argo-hub/auth/kubeconfig
# Login to argo server
ARGO_SERVER=$(oc get route -n openshift-operators argocd-server  -o jsonpath='{.spec.host}')
ADMIN_PASSWORD=$(oc get secret argocd-cluster -n openshift-operators  -o jsonpath='{.data.admin\.password}' | base64 -d)
# Remove managed cluster
argocd login $ARGO_SERVER --username admin --password $ADMIN_PASSWORD --insecure
argocd cluster rm $CLUSTER_NAME
# Then remove installation directories
rm -rf ./backup/backup-$CLUSTER_NAME
rm -rf ./install/install-dir-$CLUSTER_NAME
```
