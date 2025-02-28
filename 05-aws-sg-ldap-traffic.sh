#!/bin/bash

# Ensure the script is executed with a source file argument
if [ -z "$1" ]; then
    echo "Usage: $0 <source-file>"
    echo "Example: $0 aws-ocp4-config"
    exit 1
fi

source $(pwd)/$1

# Retrieve the VPC ID (assuming there is only one VPC in your account)
VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)
echo "Using VPC ID: $VPC_ID"

# Create a new security group for LDAP traffic (port 389)
SECURITY_GROUP=$(aws ec2 create-security-group \
    --group-name MySecurityGroup \
    --description "Security group for LDAP traffic" \
    --vpc-id $VPC_ID \
    --query "GroupId" \
    --output text)
echo "Created Security Group: $SECURITY_GROUP"

# Add an inbound rule to allow traffic on port 389 from CIDR range 10.0.0.0/16
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP \
    --protocol tcp \
    --port 389 \
    --cidr 10.0.0.0/16
echo "Inbound rule added to Security Group: $SECURITY_GROUP"

# Retrieve all EC2 instance IDs that are workers (Therefore, only argo-hub instances)
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=iam-instance-profile.arn,Values=*worker*" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

# Loop through each instance and update its security groups
for INSTANCE_ID in $INSTANCE_IDS; do
    echo "Processing instance: $INSTANCE_ID"

    # Get the current security groups attached to the instance
    CURRENT_SECURITY_GROUPS=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query "Reservations[0].Instances[0].SecurityGroups[*].GroupId" \
        --output text)

    # Combine current security groups with the new one
    UPDATED_SECURITY_GROUPS="$CURRENT_SECURITY_GROUPS $SECURITY_GROUP"

    # Apply the updated list of security groups to the instance
    aws ec2 modify-instance-attribute \
        --instance-id $INSTANCE_ID \
        --groups $UPDATED_SECURITY_GROUPS

    echo "Updated security groups for instance: $INSTANCE_ID"
done

echo "Script execution completed."