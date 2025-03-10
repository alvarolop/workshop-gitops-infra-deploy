
# GitOps Workshop - Deploy Infra

1. [GitOps Workshop - Deploy Infra](#gitops-workshop---deploy-infra)
   1. [Prerequisites](#prerequisites)
      1. [Install CLI tools](#install-cli-tools)
      2. [AWS account](#aws-account)
      3. [Environment variables](#environment-variables)
   2. [Creating OCP IPI on AWS](#creating-ocp-ipi-on-aws)
      1. [Deploying the Hub cluster](#deploying-the-hub-cluster)
      2. [Deploying Managed Clusters (SNO)](#deploying-managed-clusters-sno)
   3. [Postinstall configuration](#postinstall-configuration)
      1. [1. Deploy and configure ArgoCD declaratively](#1-deploy-and-configure-argocd-declaratively)
      2. [2. Deploy keycloak](#2-deploy-keycloak)
      3. [3. Deploy vault server](#3-deploy-vault-server)
      4. [4. Deploy FreeIPA](#4-deploy-freeipa)
      5. [Create FreeIPA users](#create-freeipa-users)
   4. [Destroy cluster](#destroy-cluster)


> [!IMPORTANT]
> This repository builds upon the original workshop developed by Coral, as documented in her repository: https://github.com/romerobu/workshop-gitops-infra-deploy.

This repo is part of the [ArgoCD Managing Infrastructure workshop](https://alvarolop.github.io/manual-workshop-infra/manual-workshop-infra/index.html) and is intended to deploy the clusters (hub and managed) plus the infra setup required to complete the activities.

In order to deploy all the infra you will need to cover the following steps:

1. Deploy the hub cluster named `argo-hub`. This will create a VPC on AWS.
2. Deploy all the managed clusters named `sno-XX` reusing the same VPC.
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
> If you are a Red Hatter, you can order a lab environment on the [Red Hat Demo Platform](https://catalog.demo.redhat.com/catalog?item=babylon-catalog-prod/sandboxes-gpte.sandbox-open.prod&utm_source=webapp&utm_medium=share-link). Request environment `Red Hat Open Environments` > `AWS Blank Open Environment`.



> [!CAUTION]
> `AWS Blank Open Environment` accounts have a default Service Quota of **Classic Load Balancers per Region = 20**. This means that you can only deploy this exercise for 15 users by default. Rise the Quota to 40 to ensure that you can at least deploy 20 clusters. For that, just follow these steps:
> 1. Sign in to the AWS Management Console.
> 2. Open the Service Quotas console.
> 3. In the navigation pane, choose AWS services and select Elastic Load Balancing.
> 4. Find the quota for `Application-` or `Classic Load Balancers per region` (e.g., 50 for Application Load Balancers per region) and request an increase.



### Environment variables

Create a file with the environment variables that will be consistent during all the deployment. I suggest the following process:

1. Copy the contents of the example file: `cp aws-ocp4-config.example aws-ocp4-config`.
2. Retrieve the Pull Secret given from RedHat OpenShift Cluster Manager [site](https://console.redhat.com/openshift/create) for an AWS IPI installation. Add it to the `aws-ocp4-config` file.
3. Edit the file with the values received from [Red Hat Demo Platform](https://demo.redhat.com).



## Creating OCP IPI on AWS

All the clusters (Hub and managed) for this workshop will be deployed using the same script: `ocp4-install.sh`. The way to execute this script is with the following parameters:

```bash
sh ocp4-install.sh <cluster_name> <replicas_master> <replicas_worker> <vpc_id|false>
```

As most of the configuration is similar depending on the cluster type, I've created two sections to see how to deploy them. 

Note that `<vpc_id|false>` is the parameter that allows to configure the VPC where the node will be deployed:

* If this is the first cluster of the account (Hub), you need to set it to false, so that it creates a new VPC.
* If you are installing a managed cluster, the Hub should be already present, so that you can reuse the same VPC. In such case, you will select the vpc-id created by the initial install.

Regarding the `<cluster_name>`, remember that it is mandatory to keep the same cluster names:
* `argo-hub` for the Hub cluster.
* `sno-X` for the managed clusters.



### Deploying the Hub cluster

```bash
source aws-ocp4-config; sh ocp4-install.sh argo-hub 3 3 false
```


### Deploying Managed Clusters (SNO)

First, you need to wait until the Hub cluster is installed. Then, you can parallelize the installation of all the Managed Clusters with the following commands in different terminal tabs:

```bash
source aws-ocp4-config; sh ocp4-install.sh sno-01 1 0 $(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)

source aws-ocp4-config; sh ocp4-install.sh sno-02 1 0 $(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)

source aws-ocp4-config; sh ocp4-install.sh sno-03 1 0 $(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)


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
> source aws-ocp4-config; bash ocp4-postinstall.sh
> ```



### 1. Deploy and configure ArgoCD declaratively

If you didn't run the previous command that automates everything, follow these steps:

1. Install the OpenShift GitOps operator: `oc apply -f 01-gitops-operator`.
2. Create a branch `setup-sno` from the repo [workshop-gitops-content-deploy](https://github.com/alvarolop/workshop-gitops-content-deploy.git).
3. Adapt the ArgoCD application to your credentials and apply it `oc apply -f 02-application-gitops-setup.yaml`.




### 2. Deploy keycloak

If you didn't run the previous command that automates everything, follow these steps:

```bash
source aws-ocp4-config
# Using the app
cat 03-application-keycloak.yaml | CLUSTER_DOMAIN=$BASE_DOMAIN NUM_CLUSTERS=3 envsubst | oc apply -f -
# or
# using the Helm Chart directly
helm template keycloak --set global.clusterDomain=$BASE_DOMAIN --set numberOfClusters=3 | oc apply -f -
```


> [!WARNING]
> Check if this is relevant anymore:
> Beware you need to update your [certificate](https://github.com/romerobu/helm-infra-gitops-workshop/blob/main/charts/oauth/files/ca.crt) on your helm charts repo:
> ```bash
> oc -n openshift-ingress-operator get secret router-ca -o jsonpath="{ .data.tls\.crt }" | base64 -d -i 
> ```

### 3. Deploy vault server

If you didn't run the previous command that automates everything, follow these steps:

```bash
oc apply -f 04-application-hashicorp-vault-server.yaml
```

After Vault is ready, you have to populate it with the following script:

```bash
./04-create_vault_secrets.sh
```

<!-- Bear in mind you need to update this secret on [main](https://github.com/romerobu/workshop-gitops-content-deploy/blob/main/cluster-addons/charts/bootstrap/templates/vault/secret-vault.yaml) and [main-day2](https://github.com/romerobu/workshop-gitops-content-deploy/blob/main-day2/cluster-addons/charts/bootstrap/templates/vault/secret-vault.yaml) branch to so users will clone and pull the right credentials. -->






### 4. Deploy FreeIPA

Follow the instructions [here](https://github.com/redhat-cop/helm-charts/tree/master/charts/ipa) to deploy FreeIPA server.

```bash
source aws-ocp4-config
# Using the app
cat 05-application-freeipa.yaml | CLUSTER_DOMAIN=$BASE_DOMAIN envsubst | oc apply -f -
# or
# using the Helm Chart directly
helm template keycloak --set global.clusterDomain=$BASE_DOMAIN --set numberOfClusters=3 | oc apply -f -

```

Then, expose ipa service as NodePort and allow external traffic on AWS by configuring the security groups.

```bash
while [[ $(oc get pods -l app=freeipa -n ipa -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"
oc patch service freeipa -n ipa -p '{"spec":{"type":"NodePort","ports":[{"name":"ldap","protocol":"TCP","port":389,"targetPort":389,"nodePort":30389}]}}'
```

<!-- 
Then, enable a security group to allow incoming traffic to port 389 (NodePort) and origin 10.0.0.0/16.

```bash
sh 05-aws-sg-ldap-traffic.sh aws-ocp4-config
``` 
-->

You can test connectivity running this command from your managed cluster node:

```bash
@ Retrieve the node IP
oc get nodes --selector='node-role.kubernetes.io/worker' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
nc -vz $WORKER_IP 30389 # Important, as we are exposing it in nodePort, we need to use 30389 instead of 389
```

### Create FreeIPA users

To create FreeIPA users, run these commands:

```bash
./05-init-freeipa.sh
```





## Destroy cluster

If you want to delete a cluster, first run this command to destroy it from AWS:

```bash
CLUSTER_NAME=sno-XX
source aws-ocp4-config; ./workdir/openshift-install destroy cluster --dir workdir/install/install-dir-$CLUSTER_NAME --log-level info
```

Then remove it from ArgoCD instance:

```bash
# Make sure you are logged in cluster hub, unless you are trying to delete this cluster that this section is not required
export KUBECONFIG=./workdir/install/install-dir-argo-hub/auth/kubeconfig
# Login to argo server
ARGO_SERVER=$(oc get route -n openshift-operators argocd-server  -o jsonpath='{.spec.host}')
ADMIN_PASSWORD=$(oc get secret argocd-cluster -n openshift-operators  -o jsonpath='{.data.admin\.password}' | base64 -d)
# Remove managed cluster
argocd login $ARGO_SERVER --username admin --password $ADMIN_PASSWORD --insecure
argocd cluster rm $CLUSTER_NAME
# Then remove installation directories
rm -rf ./workdir/backup/backup-$CLUSTER_NAME
rm -rf ./workdir/install/install-dir-$CLUSTER_NAME
```
