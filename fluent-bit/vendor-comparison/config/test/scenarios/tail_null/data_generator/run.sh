#!/bin/bash
set -eu
echo "Starting data generation"

LOG_RATE=${LOG_RATE:-20}
LOG_SIZE=${LOG_SIZE:-1000}
CONTAINER_NAME=${CONTAINER_NAME:-data-generator}

TEST_SCENARIO_DATA_DIR=${TEST_SCENARIO_DATA_DIR:-/test/data}

# We want to wipe our data for this run
rm -rf "${TEST_SCENARIO_DATA_DIR:?}"/*
mkdir -p "${TEST_SCENARIO_DATA_DIR}"

# Remove any existing container
docker rm -f "$CONTAINER_NAME" &> /dev/null || true

docker pull --quiet fluentbitdev/fluent-bit-ci:benchmark
docker run --rm -d --name="$CONTAINER_NAME" -v "$TEST_SCENARIO_DATA_DIR":/logs/:rw \
    fluentbitdev/fluent-bit-ci:benchmark \
    /run_log_generator.py \
    --log-size-in-bytes "$LOG_SIZE" \
    --log-rate "$LOG_RATE" \
    --log-agent-input-type tail \
    --tail-file-path "/logs/input.log"
