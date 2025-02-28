#!/bin/bash

# Vault configuration
VAULT_ADDR="$(oc get route hashicorp-vault-server -n vault --template='https://{{.spec.host}}')"
VAULT_TOKEN="root"                  # Default token in dev mode

# Inline JSON definition of secrets
SECRETS_JSON='[
    {
        "path": "secret/data/demo1",
        "data": {
            "key1": "value1",
            "key2": "value2"
        }
    },
    {
        "path": "secret/data/demo2",
        "data": {
            "key1": "value3",
            "key2": "value4"
        }
    },
    {
        "path": "secret/data/demo3",
        "data": {
            "key1": "value5",
            "key2": "value6"
        }
    }
]'

# Parse JSON and upload secrets
echo -e "\nCreating dummy Secrets..."
for row in $(echo "$SECRETS_JSON" | jq -c '.[]'); do
    path=$(echo "$row" | jq -r '.path')
    data=$(echo "$row" | jq -c '.data')

    echo "Writing secret to $path"
    curl -s \
        --header "X-Vault-Token: $VAULT_TOKEN" \
        --request POST \
        --data "{\"data\":$data}" \
        "$VAULT_ADDR/v1/$path" > /dev/null

    if [ $? -eq 0 ]; then
        echo "Successfully wrote secret to $path"
    else
        echo "Failed to write secret to $path"
    fi
done

# Enable Kubernetes authentication
echo -e "\nEnabling Kubernetes authentication..."
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type": "kubernetes"}' \
    "$VAULT_ADDR/v1/sys/auth/kubernetes" > /dev/null

if [ $? -eq 0 ]; then
    echo "Kubernetes authentication enabled"
else
    echo "Failed to enable Kubernetes authentication"
fi


# Configure the Kubernetes authentication method
echo -e "\nConfiguring Kubernetes authentication..."
KUBERNETES_SERVICE_HOST=172.30.0.1
KUBERNETES_SERVICE_PORT=443
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data "{
        \"kubernetes_host\": \"https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT\"
    }" \
    "$VAULT_ADDR/v1/auth/kubernetes/config" > /dev/null

if [ $? -eq 0 ]; then
    echo "Kubernetes authentication configured"
else
    echo "Failed to configure Kubernetes authentication"
fi


# Create a policy for the role
echo -e "\nCreating policy svc-policy..."
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data '{
        "policy": "path \"secret/data/*\" {\n  capabilities = [\"read\"]\n}"
    }' \
    "$VAULT_ADDR/v1/sys/policies/acl/svc-policy" > /dev/null

if [ $? -eq 0 ]; then
    echo "Policy svc-policy created"
else
    echo "Failed to create policy svc-policy"
fi

# Create a role binding Kubernetes service account to the policy
echo -e "\nCreating role webapp..."
curl -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{
        "bound_service_account_names": ["*"],
        "bound_service_account_namespaces": ["*"],
        "policies": ["svc-policy"],
        "ttl": "1h"
    }' \
    "$VAULT_ADDR/v1/auth/kubernetes/role/webapp" > /dev/null

if [ $? -eq 0 ]; then
    echo "Role webapp created"
else
    echo "Failed to create role webapp"
fi
