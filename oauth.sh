#!/bin/bash

CLUSTER_NAME=$1
ADMIN=$2
USERS=$3

WORKDIR=$(pwd)/workdir

echo "Exporting admin TLS credentials..."
export KUBECONFIG=$WORKDIR/install/install-dir-$CLUSTER_NAME/auth/kubeconfig

echo "Creating htpasswd file"

rm -f $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd
mkdir -p $WORKDIR/oauth
mkdir -p $WORKDIR/oauth/oauth-$CLUSTER_NAME

echo "--------------------------> $ADMIN"

if [ $ADMIN == false ]; then

    echo "Creating users for cluster hub..."
    htpasswd -c -b -B $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd admin redhat
    for i in $(seq 1 $USERS);do
    htpasswd -b -B $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd user-$i redhat
    done

else

    echo "Creating users for SNO cluster"
    htpasswd -c -b -B $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd admin redhat
    htpasswd -b -B $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd user01 redhat
    htpasswd -b -B $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd user02 redhat
    htpasswd -b -B $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd user03 redhat
    htpasswd -b -B $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd user04 redhat
    htpasswd -b -B $WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd apimanager01 redhat
  
fi

echo "Creating HTPasswd Secret"
oc create secret generic htpass-secret --from-file=htpasswd=$WORKDIR/oauth/oauth-$CLUSTER_NAME/htpasswd -n openshift-config --dry-run=client -o yaml | oc apply -f -

echo "Configuring HTPassw identity provider"
cat > $WORKDIR/oauth/oauth-$CLUSTER_NAME/cluster-oauth.yaml << EOF_IP
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider 
    mappingMethod: claim 
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF_IP
oc apply -f $WORKDIR/oauth/oauth-$CLUSTER_NAME/cluster-oauth.yaml

echo "Giving cluster-admin role to admin user"
oc adm policy add-cluster-role-to-user cluster-admin admin

#echo "Remove kubeadmin user"
#oc delete secrets kubeadmin -n kube-system --ignore-not-found=true
