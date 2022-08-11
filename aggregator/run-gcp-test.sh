#!/bin/bash
set -eu

gcloud info

INPUT_IMAGE_FAMILY=${INPUT_IMAGE_FAMILY:-calyptia-vendor-comparison}
INPUT_MACHINE_TYPE=${INPUT_MACHINE_TYPE:-e2-highcpu-8}
INPUT_VM_COUNT=${INPUT_VM_COUNT:-3}
INPUT_LOG_RATE=${INPUT_LOG_RATE:-2000}
INPUT_LOG_SIZE=${INPUT_LOG_SIZE:-1000}

SSH_USERNAME=${SSH_USERNAME:-ubuntu}

CORE_VM_NAME=${CORE_VM_NAME:-benchmark-instance-core}
CORE_IMAGE_FAMILY=${CORE_IMAGE_FAMILY:-gold-calyptia-core}
CORE_MACHINE_TYPE=${CORE_MACHINE_TYPE:-e2-highcpu-32}
CORE_TCP_PORT=${CORE_TCP_PORT:-5000}
CALYPTIA_CLOUD_PROJECT_TOKEN=${CALYPTIA_CLOUD_PROJECT_TOKEN:?}
# Must be different each time or removed completely from Calyptia Cloud
CALYPTIA_CLOUD_AGGREGATOR_NAME=${CALYPTIA_CLOUD_AGGREGATOR_NAME:?}

function wait_for_ssh() {
    local VM_NAME=$1
    echo "Waiting for SSH access to $VM_NAME..."
    until gcloud compute ssh --force-key-file-overwrite "$SSH_USERNAME"@"$VM_NAME" -q --command="true" 2> /dev/null; do
        echo -n '.'
        sleep 1
    done
    echo
    echo "Successfully connected to $VM_NAME"
}

if [[ "${SKIP_VM_CREATION:-no}" == "no" ]]; then
    echo "Creating $INPUT_VM_COUNT input instances"
    for index in $(seq "$INPUT_VM_COUNT")
    do
        VM_NAME="benchmark-instance-input-$index"
        gcloud compute instances delete "$VM_NAME" -q &> /dev/null || true
        gcloud compute instances create "$VM_NAME" \
            --image-family="$INPUT_IMAGE_FAMILY" \
            --machine-type="$INPUT_MACHINE_TYPE"
    done

    echo "Creating Core instance"
    gcloud compute instances delete "$CORE_VM_NAME" -q &> /dev/null || true
    gcloud compute instances create "$CORE_VM_NAME" \
        --image-family="$CORE_IMAGE_FAMILY" \
        --machine-type="$CORE_MACHINE_TYPE" \
        --metadata=CALYPTIA_CLOUD_PROJECT_TOKEN="$CALYPTIA_CLOUD_PROJECT_TOKEN",CALYPTIA_CLOUD_AGGREGATOR_NAME="$CALYPTIA_CLOUD_AGGREGATOR_NAME"
    wait_for_ssh "$CORE_VM_NAME"
fi

echo "Setting up Core instance"
cat > coreconfig << EOF
[INPUT]
    Name tcp
    Tag  input
    Port $CORE_TCP_PORT
EOF

gcloud compute scp coreconfig "$SSH_USERNAME"@"$CORE_VM_NAME":~/coreconfig
gcloud compute ssh "$SSH_USERNAME"@"$CORE_VM_NAME" -q --command="curl -fsSL https://github.com/calyptia/cli/releases/download/v0.29.0/cli_0.29.0_linux_amd64.tar.gz| tar -xz && \
    ./calyptia delete pipeline --token \"$CALYPTIA_CLOUD_PROJECT_TOKEN\" benchmark-test --yes || true; \
    ./calyptia create pipeline --token \"$CALYPTIA_CLOUD_PROJECT_TOKEN\" \
        --aggregator \"$CALYPTIA_CLOUD_AGGREGATOR_NAME\" --name benchmark-test --config-file coreconfig"

# We need the IP address to add to the config files for inputs
CORE_IP_ADDRESS=$(gcloud compute instances describe "$CORE_VM_NAME" --format='get(networkInterfaces[0].networkIP)')

echo "Setting up input instances"

cat > benchmark-output.conf << EOF
[OUTPUT]
    Name tcp
    Host $CORE_IP_ADDRESS
    Port $CORE_TCP_PORT
    Match *
    Format json_lines
EOF
cat benchmark-output.conf

for index in $(seq "$INPUT_VM_COUNT")
do
    VM_NAME="benchmark-instance-input-$index"
    wait_for_ssh "$VM_NAME"

    gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" -q --command="export TEST_SCENARIO_DATA_DIR=/test; \
        export INPUT_LOG_RATE=$INPUT_LOG_RATE; export INPUT_LOG_SIZE=$INPUT_LOG_SIZE; \
        /test/scenarios/tail_null/data_generator/stop.sh; nohup /test/scenarios/tail_null/data_generator/run.sh &"
    gcloud compute scp "benchmark-output.conf" "$SSH_USERNAME"@"$VM_NAME":/etc/calyptia-fluent-bit/custom/
    gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" -q --command="rm -f /etc/calyptia-fluent-bit/custom/null.conf; \
        sudo systemctl restart calyptia-fluent-bit"

    if [[ "${RUN_INPUT_MONITORING_STACK:-no}" != "no" ]]; then
        echo "Running instance monitoring stack"
        gcloud compute ssh "$SSH_USERNAME"@"$VM_NAME" -q --command="cd /opt/fluent-bit-devtools/monitoring && docker compose up --force-recreate --always-recreate-deps -d"
        echo "To port-forward (e.g. Grafana and Prometheus): gcloud compute ssh $SSH_USERNAME@$VM_NAME -- -NL 3000:localhost:3000 -- -NL 9090:localhost:9090"
    fi
done

echo "Setup completed and running"
