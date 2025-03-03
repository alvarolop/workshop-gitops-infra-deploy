#!/bin/bash

set -x

## Env
CLUSTER_NAME=${1}
REPLICAS_CP=${2}
REPLICAS_WORKER=${3}
VPC=${4:-false}

# Check if the directory exists, and create it if it doesn't
if [ ! -d "$WORKDIR" ]; then
    mkdir -p "$WORKDIR"
fi

## Prerequisites
echo "This script installs ${OPENSHIFT_VERSION} version for OCP..."
echo "Downloading OCP 4 installer if not exists:"

if [ ! -f $WORKDIR/ocp4-installer.tar.gz ]; then
    curl -o $WORKDIR/ocp4-installer.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/openshift-install-linux-${OPENSHIFT_VERSION}.tar.gz && tar -xvzf $WORKDIR/ocp4-installer.tar.gz -C $WORKDIR openshift-install
else
    echo "Installer exists, using ./ocp4-installer.tar.gz. Unpacking..." ; echo " "
    tar -xvzf $WORKDIR/ocp4-installer.tar.gz -C $WORKDIR openshift-install
fi


if [ -f $WORKDIR/install/install-dir-$CLUSTER_NAME/terraform.cluster.tfstate ]; then

    echo "An OCP cluster exists. Skipping installation..."
    echo "Remove the install-dir folder and run the script."

    exit 0
fi


echo "Generating SSH key pair" ; echo " "
mkdir -p $WORKDIR/.ssh-keys
rm -f $WORKDIR/.ssh-keys/myocp_$CLUSTER_NAME ; ssh-keygen -t rsa -b 4096 -N '' -f $WORKDIR/.ssh-keys/myocp_$CLUSTER_NAME
eval "$(ssh-agent -s)"

ssh-add $WORKDIR/.ssh-keys/myocp_$CLUSTER_NAME
ssh-add -L

## Install config file
echo "Creating install config file" ; echo " "
rm -f $WORKDIR/install/install-dir-$CLUSTER_NAME/install-config.yaml && rm -f $WORKDIR/install/install-dir-$CLUSTER_NAME/.openshift_install* ; #$WORKDIR/openshift-install create install-config --dir=install-dir-$CLUSTER_NAME

mkdir -p $WORKDIR/backup && mkdir $WORKDIR/backup/backup-$CLUSTER_NAME/
mkdir -p $WORKDIR/install && mkdir $WORKDIR/install/install-dir-$CLUSTER_NAME/

SSH_KEY=$(cat $WORKDIR/.ssh-keys/myocp_$CLUSTER_NAME.pub)

if [ $VPC != false ]; then
    echo "Existing VPC is $VPC..."

    # Fetch the Subnet IDs associated with the specified VPC
    #?MapPublicIpOnLaunch==`false`
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters Name=vpc-id,Values="$VPC" \
        --query 'Subnets[*].SubnetId' \
        --output text)

    # Convert Subnet IDs into a single-line YAML array
    EXISTING_VPC="subnets: [$(echo $SUBNET_IDS | sed "s/ /', '/g" | sed "s/^/'/;s/$/'/")]"
    echo "Existing subnets are $EXISTING_VPC"
else
    EXISTING_VPC=""
    echo "No existing VPC..."
fi

cat << EOF > $WORKDIR/backup/backup-$CLUSTER_NAME/install-config.yaml
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: #{}
    aws:
     type: $INSTANCE_TYPE #m6i.4xlarge  
  replicas: $REPLICAS_WORKER
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: #{}
    aws:
     type: $INSTANCE_TYPE #m6i.4xlarge    
  replicas: $REPLICAS_CP
metadata:
  creationTimestamp: null
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $AWS_DEFAULT_REGION
    $EXISTING_VPC
pullSecret: '$RHOCM_PULL_SECRET'
sshKey: $SSH_KEY
EOF

cp $WORKDIR/backup/backup-$CLUSTER_NAME/install-config.yaml $WORKDIR/install/install-dir-$CLUSTER_NAME/install-config.yaml
cat $WORKDIR/install/install-dir-$CLUSTER_NAME/install-config.yaml

echo "Edit the installation file $WORKDIR/install/install-dir-$CLUSTER_NAME/install-config.yaml if you need."
echo "Confirm when you are ready:" ; echo " "


install_ocp() {
    $WORKDIR/openshift-install create cluster --dir=$WORKDIR/install/install-dir-$CLUSTER_NAME --log-level=info
}

configure_oauth() {
    echo "Set HTPasswd as Identity Provider" ; echo " "
    export KUBECONFIG=$WORKDIR/install/install-dir-$CLUSTER_NAME/auth/kubeconfig
    if [ $VPC == false ]; then
      oc apply -k auth/overlays/argo-hub
    else
      oc apply -k auth/overlays/sno
    fi
    ssh-add -D
}

cleanup() {
    rm -f $WORKDIR/openshift-install
    rm -f $WORKDIR/.ssh-keys/myocp_$CLUSTER_NAME
}

while true; do
    read -p "Proceed with OCP cluster installation: yY|nN -> " yn
    case $yn in
        [Yy]* ) echo "Installing OCP4 cluster... " ; install_ocp ; configure_oauth ; break;;
        [Nn]* ) echo "Aborting installation..." ; cleanup ; ssh-add -D ; exit;;
        * ) echo "Select yes or no";;
    esac
done
