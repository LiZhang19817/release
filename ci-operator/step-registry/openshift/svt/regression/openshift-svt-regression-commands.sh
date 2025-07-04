#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
set -x

cat /etc/os-release
oc config view
oc projects
python --version

ES_HOST=${ES_HOST:-"search-ocp-qe-perf-scale-test-elk-hcm7wtsqpxy7xogbu72bor4uve.us-east-1.es.amazonaws.com"}
ES_PASSWORD=$(cat "/secret/password")
export ES_PASSWORD
ES_USERNAME=$(cat "/secret/username")
export ES_USERNAME
export ES_SERVER="https://$ES_USERNAME:$ES_PASSWORD@$ES_HOST"

# If running from the one folder, will reset SCRIPT and PARAMETERS variables
export SCRIPT=${SCRIPT_1:-$SCRIPT}

export PARAMETERS=${PARAMETERS_1:-${PARAMETERS:-""}}

pushd /tmp

git clone https://github.com/openshift/svt --depth=1
pushd svt

echo "========Start Regression test for $SCRIPT========"
set +e

# Do not change, for these custom tests we need to specify this specific version
export KUBE_BURNER_VERSION=${KUBE_BURNER_VERSION:-"1.7.6'"}

# If SCRIPT is not specified, find the script by the TEST_CASE.
if [[ $SCRIPT == "" ]]
then
    echo "$SCRIPT is not found under svt repo perfscale_regression_ci/scripts folder. Please check."
    exit 1

fi
export folder=${SCRIPT%/*}
export script=${SCRIPT##*/}
cd ${folder}

chmod +x ${script}
set -o pipefail
./${script} $PARAMETERS |& tee output.out

result=$?
set -e
# copy the reliability test result

cp output.out ${ARTIFACT_DIR}/
if [[ $result -ne 0 ]]; then
    exit 1
fi 