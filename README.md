
# GitOps Workshop - Deploy Infra

1. [GitOps Workshop - Deploy Infra](#gitops-workshop---deploy-infra)
   1. [Prerequisites](#prerequisites)
      1. [Install CLI tools](#install-cli-tools)
      2. [AWS account](#aws-account)
      3. [Pull secret](#pull-secret)
      4. [Environment variables](#environment-variables)
   2. [Creating OCP IPI on AWS](#creating-ocp-ipi-on-aws)
      1. [Deploying the Hub cluster](#deploying-the-hub-cluster)
      2. [Deploying Managed Clusters (SNO)](#deploying-managed-clusters-sno)
   3. [Postinstall configuration](#postinstall-configuration)
      1. [1. Deploy and configure ArgoCD declaratively](#1-deploy-and-configure-argocd-declaratively)
      2. [2. Deploy keycloak](#2-deploy-keycloak)
   4. [Deploy FreeIPA](#deploy-freeipa)
      1. [Create FreeIPA users](#create-freeipa-users)
   5. [Deploy vault server](#deploy-vault-server)
   6. [Destroy cluster](#destroy-cluster)


> [!IMPORTANT]
> This repository builds upon the original workshop developed by Coral, as documented in her repository: https://github.com/romerobu/workshop-gitops-infra-deploy.

This repo is part of the [ArgoCD Managing Infrastructure workshop](https://alvarolop.github.io/manual-workshop-infra/manual-workshop-infra/index.html) and is intended to deploy the clusters (hub and managed) plus the infra setup required to complete the activities.

In order to deploy all the infra you will need to cover the following steps:

1. Deploy the hub cluster named `argo-hub`. This will create a VPC on AWS.
2. Deploy all the managed clusters named `sno-X` reusing the same VPC.
3. Deploy ArgoCD to manage those clusters.
4. Configure FreeIPA and Keycloak on the hub to provide credentials.
5. Configure Hashicorp Vault on the hub to store secrets.
6. [Optional] Configure the cluster certificates and LightSpeed operator.


## Prerequisites

### Install CLI tools

This workshop deployment requires the following **cli** tools:

* `oc`. [Installation guide](https://docs.openshift.com/container-platform/4.17/cli_reference/openshift_cli/getting-started-cli.html).
* `aws`. [Installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
* `helm`. [Installation guide](https://helm.sh/docs/intro/install/). 
<!-- * `argocd`. [Installation guide](https://argo-cd.readthedocs.io/en/stable/cli_installation/). -->
<!-- * `yq`. [Installation guide](https://www.cyberithub.com/how-to-install-yq-command-line-tool-on-linux-in-5-easy-steps/). -->


### AWS account

In order to install OpenShift on AWS using IPI (Installer-Provisioned Infrastructure), you need the following configuration:

* An AWS account.
* A domain name registered with a registrar. You can register a domain directly through Route 53 or use another domain registrar.
* To configure the top-level domain in AWS Route 53, create a hosted zone for your domain, update the registrar with the provided NS records, and then add the necessary DNS records like A or CNAME to point to your infrastructure. This setup links your domain to Route 53, allowing you to manage DNS for your website or services.

> [!TIP]
> If you are a Red Hatter, you can order a lab environment on the [Red Hat Demo Platform](https://demo.redhat.com). Request environment `Red Hat Open Environments` > `AWS Blank Open Environment`.

### Pull secret

Retrieve the Pull Secret given from RedHat OpenShift Cluster Manager [site](https://console.redhat.com/openshift/create) for an AWS IPI installation. You should create a `./pullsecret.txt` file containing the pull secret to be used.



### Environment variables

Create a file with the environment variables that will be consistent during all the deployment. I suggest the following process:

1. Copy the contents of the example file: `cp aws-ocp4-config.example aws-ocp4-config`.
2. Edit the file with the values received from [Red Hat Demo Platform](https://demo.redhat.com).



## Creating OCP IPI on AWS

All the clusters (Hub and managed) for this workshop will be deployed using the same script: `ocp4-install.sh`. The way to execute this script is with the following parameters:

```bash
sh ocp4-install.sh <cluster_name> <region_aws> <base_domain> <replicas_master> <replicas_worker> <vpc_id|false> <aws_id> <aws_secret> <instance_type> <amount_of_users>
```

As most of the configuration is similar depending on the cluster type, I've created two sections to see how to deploy them. 

Note that `<vpc_id|false>` is the parameter that allows to configure the VPC where the node will be deployed:

* If this is the first cluster of the account (Hub), you need to set it to false, so that it creates a new VPC.
* If you are installing a managed cluster, the Hub should be already present, so that you can reuse the same VPC. In such case, you will select the vpc-id created by the initial install.

Also, note that `<amount_of_users>` refers to the users created in the htpasswd of the Hub Cluster. This parameter does not take effect on the Managed Clusters.

Regarding the `<cluster_name>`, remember that it is mandatory to keep the same cluster names:
* `argo-hub` for the Hub cluster.
* `sno-X` for the managed clusters.



### Deploying the Hub cluster

```bash
source aws-ocp4-config

sh ocp4-install.sh argo-hub $AWS_DEFAULT_REGION $BASE_DOMAIN 3 3 false $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY $INSTANCE_TYPE $AMOUNT_OF_USERS
```


### Deploying Managed Clusters (SNO)

First, you need to wait until the Hub cluster is installed. Then, you can parallelize the installation of all the Managed Clusters with the following commands in different terminal tabs:

```bash
source aws-ocp4-config

sh ocp4-install.sh sno-1 $AWS_DEFAULT_REGION $BASE_DOMAIN 1 0 $(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text) $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY $INSTANCE_TYPE

sh ocp4-install.sh sno-2 $AWS_DEFAULT_REGION $BASE_DOMAIN 1 0 $(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text) $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY $INSTANCE_TYPE

# Continue until you create all the required clusters
```

Feel free to use the following commands to check the VPCs on your AWS account:
* Count number of VPCs: `aws ec2 describe-vpcs --query "length(Vpcs)" --output text`.
* Get the first VPC ID: `aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text`.
* Get Subnets from first VPC: `aws ec2 describe-subnets --filters Name=vpc-id,Values=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)  --output text`


At this point, you should have the hub cluster and also one managed cluster for each workshop user.




## Postinstall configuration

> [!WARNING]
> All this process has been automated so that you don't have to execute it manually. Please execute the following script:
> ```bash
> sh postinstall.sh aws-ocp4-config
> ```

### 1. Deploy and configure ArgoCD declaratively

If you didn't run the previous command that automates everything, follow these steps:

1. Install the OpenShift GitOps operator: `oc apply -f gitops-operator`.
2. Create a branch `setup-sno` from the repo [workshop-gitops-content-deploy](https://github.com/alvarolop/workshop-gitops-content-deploy.git).
3. Adapt the ArgoCD application to your credentials and apply it `oc apply -f application-hub-setup.yaml`.




### 2. Deploy keycloak

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
