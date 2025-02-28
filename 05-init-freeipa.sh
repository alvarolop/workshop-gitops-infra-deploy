#!/bin/bash
# Login to kerberos
oc exec -n ipa -it deployment/freeipa -- \
    sh -c "echo Passw0rd123 | /usr/bin/kinit admin && \
    echo Passw0rd | \
    ipa user-add ldap_admin --first=ldap \
    --last=admin --email=ldap_admin@redhatlabs.dev --password"
    
# Create groups if they dont exist

oc exec -n ipa -it deployment/freeipa -- \
    sh -c "ipa group-add student --desc 'wrapper group' || true && \
    ipa group-add ocp_admins --desc 'admin openshift group' || true && \
    ipa group-add ocp_devs --desc 'edit openshift group' || true && \
    ipa group-add ocp_viewers --desc 'view openshift group' || true && \
    ipa group-add-member student --groups=ocp_admins --groups=ocp_devs --groups=ocp_viewers || true"

# Add demo users

oc exec -n ipa -it deployment/freeipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add paul --first=paul \
    --last=ipa --email=paulipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_admins --users=paul"

oc exec -n ipa -it deployment/freeipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add henry --first=henry \
    --last=ipa --email=henryipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_devs --users=henry"

oc exec -n ipa -it deployment/freeipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add mark --first=mark \
    --last=ipa --email=markipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_viewers --users=mark"