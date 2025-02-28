#!/bin/bash

# Vault configuration
VAULT_ADDR="$(oc get route hashicorp-vault-server -n vault --template='https://{{.spec.host}}')"
VAULT_TOKEN="root"                  # Default token in dev mode

# Inline JSON definition of secrets
SECRETS_JSON='[
    {
        "path": "secret/data/demo",
        "data": {
            "password": "password123"
        }
    }
]'

# Parse JSON and upload secrets
echo -e "\nCreating dummy Secrets..."
for row in $(echo "$SECRETS_JSON" | jq -c '.[]'); do
    path=$(echo "$row" | jq -r '.path')
    data=$(echo "$row" | jq -c '.data')

    echo "Writing secret to $path"
    curl -k -s \
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
curl -k -s \
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
curl -k -s \
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
curl -k -s \
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
curl -k -s \
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



# Enable AppRole authentication
echo -e "\nEnabling AppRole authentication..."
curl -k -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"type": "approle"}' \
    "$VAULT_ADDR/v1/sys/auth/approle" > /dev/null

if [ $? -eq 0 ]; then
    echo "AppRole authentication enabled"
else
    echo "Failed to enable AppRole authentication"
fi

# Create an AppRole named argocd
echo -e "\nCreating AppRole argocd..."
curl -k -s \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{
        "secret_id_ttl": "120h",
        "token_num_uses": 1000,
        "token_ttl": "120h",
        "token_max_ttl": "120h",
        "secret_id_num_uses": 4000,
        "policies": ["demo"]
    }' \
    "$VAULT_ADDR/v1/auth/approle/role/argocd" > /dev/null

if [ $? -eq 0 ]; then
    echo "AppRole argocd created"
else
    echo "Failed to create AppRole argocd"
fi

# Retrieve the role_id for argocd
echo -e "\nRetrieving role_id for AppRole argocd..."
ROLE_ID=$(curl -k -s \
            --header "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/auth/approle/role/argocd/role-id" | jq -r '.data.role_id')

if [ $? -eq 0 ] && [ ! -z "$ROLE_ID" ]; then
    echo "Retrieved role_id for argocd: $ROLE_ID"
else
    echo "Failed to retrieve role_id for argocd"
fi

# Generate a secret_id for argocd
echo -e "\nGenerating secret_id for AppRole argocd..."
SECRET_ID=$(curl -k -s \
              --header "X-Vault-Token: $VAULT_TOKEN" \
              --request POST \
              "$VAULT_ADDR/v1/auth/approle/role/argocd/secret-id" | jq -r '.data.secret_id')

if [ $? -eq 0 ] && [ ! -z "$SECRET_ID" ]; then
    echo "Generated secret_id for argocd: $SECRET_ID"
else
    echo "Failed to generate secret_id for argocd"
fi

