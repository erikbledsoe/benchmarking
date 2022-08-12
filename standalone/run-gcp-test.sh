#!/bin/bash
set -eu

VM_NAME=${VM_NAME:-vendor-comparison-test}
IMAGE_NAME=${IMAGE_NAME:-https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-vendor-comparison-ubuntu-2004}
MACHINE_TYPE=${MACHINE_TYPE:-e2-highcpu-32}
SSH_USERNAME=${SSH_USERNAME:-ubuntu}

# Test options
OUTPUT_DIR=${OUTPUT_DIR:-$PWD/output}
RUN_TIMEOUT_MINUTES=${RUN_TIMEOUT_MINUTES:-5}
TEST_SCENARIO=${TEST_SCENARIO:-tail_null}

gcloud compute instances delete "$VM_NAME" -q &> /dev/null || true

gcloud compute instances create "$VM_NAME" \
    --image="$IMAGE_NAME" \
    --machine-type="$MACHINE_TYPE"

rm -rf "${OUTPUT_DIR:?}"/
mkdir -p "$OUTPUT_DIR"

# You must sleep for some initial VM deployment to appear otherwise terrible failures occur!
sleep 30

echo "Waiting for SSH access to $VM_NAME..."
until gcloud compute ssh --force-key-file-overwrite "$SSH_USERNAME"@"$VM_NAME" -q --command="true" 2> /dev/null; do
    echo -n '.'
    sleep 1
done
echo
echo "Successfully connected to $VM_NAME"

echo "To port-forward (e.g. Grafana and Prometheus): gcloud compute ssh $SSH_USERNAME@$VM_NAME -- -NL 3000:localhost:3000 -- -NL 9090:localhost:9090"

if [[ "${TRANSFER_UPDATED_FRAMEWORK:-no}" != "no" ]]; then
    echo "Updating remote test framework with local files"
    gcloud compute scp --recurse ./config/test/* "$SSH_USERNAME"@"$VM_NAME":/test
fi

echo "Running test"
gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" --command "export TEST_SCENARIO=$TEST_SCENARIO;export RUN_TIMEOUT_MINUTES=$RUN_TIMEOUT_MINUTES;export OUTPUT_DIR=/tmp/output;/test/run-test.sh"

if [[ $RUN_TIMEOUT_MINUTES -gt 0 ]]; then
    echo "Transferring output files to $OUTPUT_DIR"
    gcloud compute scp --recurse "$SSH_USERNAME"@"$VM_NAME":/tmp/output/* "$OUTPUT_DIR"

    if [[ "${SKIP_TEARDOWN:-no}" != "no" ]]; then
        echo "Leaving instance running"
    else
        echo "Destroying instance"
        gcloud compute instances delete "$VM_NAME" -q
    fi
else
    echo "Left $VM_NAME running for continuous test"
fi

echo "Run completed"
