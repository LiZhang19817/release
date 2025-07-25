#!/bin/bash
set -o errexit

echo "kubeconfig loc $$KUBECONFIG"
echo "Using the flattened version of kubeconfig"
oc config view --flatten > /tmp/config
export KUBECONFIG=/tmp/config
export KRKN_KUBE_CONFIG=$KUBECONFIG

ES_PASSWORD=$(cat "/secret/es/password" || "")
ES_USERNAME=$(cat "/secret/es/username" || "")

export ES_PASSWORD
export ES_USERNAME

export ES_SERVER="https://search-ocp-qe-perf-scale-test-elk-hcm7wtsqpxy7xogbu72bor4uve.us-east-1.es.amazonaws.com"

# # read passwords from vault
telemetry_password=$(cat "/secret/telemetry/telemetry_password")

# set the secrets from the vault as env vars
export TELEMETRY_PASSWORD=$telemetry_password

console_url=$(oc get routes -n openshift-console console -o jsonpath='{.spec.host}')
export HEALTH_CHECK_URL=https://$console_url

NODE_NAME=$(oc get nodes --no-headers | head -n 1 | awk '{print $1}')
rc=$?

set -o nounset
set -o pipefail
set -x

echo "Node name return code: $rc"
platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}') 
if [ "$platform" = "AWS" ]; then
    mkdir -p $HOME/.aws
    cat "/secret/telemetry/.awscred" > $HOME/.aws/config
    cat ${CLUSTER_PROFILE_DIR}/.awscred > $HOME/.aws/config
    export AWS_DEFAULT_REGION="${LEASED_RESOURCE}"
    VPC_ID=$(aws ec2 describe-instances --filter Name=private-dns-name,Values=$NODE_NAME  --query 'Reservations[*].Instances[*].NetworkInterfaces[*].VpcId' --output text)
    rc=$?
    echo "VPC return code: $rc"
    export VPC_ID

    SUBNET_ID=$(aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID --query 'Subnets[*].SubnetId' --max-items 2) 
    rc=$?
    echo "Subnet return code: $rc"
    export SUBNET_ID
elif [ "$platform" = "GCP" ]; then
    export CLOUD_TYPE="gcp"
    export GCP_SHARED_CREDENTIALS_FILE=${CLUSTER_PROFILE_DIR}/gce.json
    export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SHARED_CREDENTIALS_FILE}"
    # topology.kubernetes.io/zone=us-central1-b

    ZONE=$(set +o pipefail; oc get node $NODE_NAME -o json | \
    jq -r '.metadata.labels' | \
    sed 's/,//g' | grep  "topology.kubernetes.io/zone" | awk '{ print $2 }' )
    export ZONE
fi

./zone-outages/prow_run.sh
rc=$?

if [[ $TELEMETRY_EVENTS_BACKUP == "True" ]]; then
    cp /tmp/events.json ${ARTIFACT_DIR}/events.json
fi

echo "Finished running zone outages"
echo "Return code: $rc"
