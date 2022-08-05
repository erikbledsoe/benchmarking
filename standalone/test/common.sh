#!/bin/bash

function prom_snapshot() {
    if curl -XPOST "${PROM_URL}/api/v1/admin/tsdb/snapshot"; then
        pushd "$MONITORING_STACK_DIR" || exit 1
            docker compose exec -T "$PROM_SERVICE_NAME" /bin/sh -c "tar -czvf /tmp/prom-data.tgz -C /prometheus/snapshots/ ."
            PROM_CONTAINER_ID=$(docker compose ps -q prometheus)
            if [[ -n "$PROM_CONTAINER_ID" ]]; then
                docker cp "$PROM_CONTAINER_ID":/tmp/prom-data.tgz "$OUTPUT_DIR"/
                echo "Copied snapshot to $OUTPUT_DIR/prom-data.tgz"
            fi
        popd || true
    else
        echo "WARNING: unable to trigger snapshot on Prometheus"
    fi
}

function prom_query() {
    # Our list of metrics to dump out explicitly
    declare -a QUERY_METRICS=("fluentbit_input_records_total"
                            "fluentbit_input_bytes_total"
                            "fluentbit_filter_add_records_total"
                            "fluentbit_filter_drop_records_total"
                            "fluentbit_output_dropped_records_total"
                            "fluentbit_output_errors_total"
                            "fluentbit_output_proc_bytes_total"
                            "fluentbit_output_proc_records_total"
                            "fluentbit_output_retried_records_total"
                            "fluentbit_output_retries_failed_total"
                            "fluentbit_output_retries_total"
                            "container_cpu_system_seconds_total"
                            "container_cpu_usage_seconds_total"
                            "container_cpu_user_seconds_total"
                            "container_fs_writes_bytes_total"
                            "container_fs_write_seconds_total"
                            "container_fs_writes_total"
                            "container_memory_usage_bytes"
                            "container_memory_rss"
                            "container_network_transmit_bytes_total"
                            "container_network_receive_packets_total"
                            'namedprocess_namegroup_cpu_seconds_total'
                            "namedprocess_namegroup_memory_bytes"
    )

    for METRIC in "${QUERY_METRICS[@]}"; do
        curl --fail --silent "${PROM_URL}/api/v1/query?query=$METRIC" | jq > "$OUTPUT_DIR/$METRIC.json"
        if command -v promplot; then
            promplot -query "$METRIC" -title "$METRIC" -range "${RUN_TIMEOUT_MINUTES}m" -url "$PROM_URL" -file "$OUTPUT_DIR/$METRIC.png"
        fi
    done
}

function run_monitoring_stack() {
    stop_monitoring_stack
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"

    pushd "$MONITORING_STACK_DIR" || exit 1
        docker compose pull --include-deps --quiet
        docker compose up --force-recreate --always-recreate-deps -d
    popd || true
}

function stop_monitoring_stack() {
    mkdir -p "$OUTPUT_DIR"
    pushd "$MONITORING_STACK_DIR" || exit 1
        # List what is running
        docker compose ps > "$OUTPUT_DIR"/monitoring.log
        docker compose stop
        # Grab logs before down removes them
        docker compose logs >> "$OUTPUT_DIR"/monitoring.log
        docker compose down --remove-orphans --volumes
    popd || true
}

function get_logs() {
    if ! is_cribl_disabled; then
        mkdir -p "$OUTPUT_DIR"/cribl
        cp -rfv "$CRIBL_HOME"/log/ "$OUTPUT_DIR"/cribl/
    fi
    if ! is_stanza_disabled; then
        mkdir -p "$OUTPUT_DIR"/stanza
        cp -fv /opt/observiq/stanza/*.log "$OUTPUT_DIR"/stanza/
        journalctl --no-pager -u stanza > "$OUTPUT_DIR"/journal-stanza.log
    fi
    if ! is_logstash_disabled; then
        journalctl --no-pager -u logstash > "$OUTPUT_DIR"/journal-logstash.log
    fi
    if ! is_vector_disabled; then
        journalctl --no-pager -u vector > "$OUTPUT_DIR"/journal-vector.log
    fi
    if ! is_fluent_bit_disabled; then
        journalctl --no-pager -u fluent-bit > "$OUTPUT_DIR"/journal-fluent-bit.log
    fi
    if ! is_calyptia_lts_disabled; then
        journalctl --no-pager -u calyptia-fluent-bit > "$OUTPUT_DIR"/journal-calyptia-fluent-bit.log
    fi

    # Any containers set up to use journald will get output here
    journalctl --no-pager -g 'CONTAINER_NAME=' > "$OUTPUT_DIR"/journal-containers.log

    ps afx &> "$OUTPUT_DIR"/ps.log
    set &> "$OUTPUT_DIR"/env.log
}

# We check if the environment variable is set to disable it, if not we then check if there is a configuration directory
function is_cribl_disabled() {
	[ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_CRIBL:-no}" )" = "yes" ] || \
        [ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_CRIBL:-no}" )" = "true" ] || \
        [ ! -d "$TEST_SCENARIO_DIR"/cribl ]
}

function is_logstash_disabled() {
	[ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_LOGSTASH:-no}" )" = "yes" ] || \
        [ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_LOGSTASH:-no}" )" = "true" ] || \
        [ ! -d "$TEST_SCENARIO_DIR"/logstash ]
}

function is_stanza_disabled() {
	[ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_STANZA:-no}" )" = "yes" ] || \
        [ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_STANZA:-no}" )" = "true" ] || \
        [ ! -d "$TEST_SCENARIO_DIR"/stanza ]
}

function is_vector_disabled() {
	[ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_VECTOR:-no}" )" = "yes" ] || \
        [ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_VECTOR:-no}" )" = "true" ] || \
        [ ! -d "$TEST_SCENARIO_DIR"/vector ]
}

function is_fluent_bit_disabled() {
	[ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_FLUENT_BIT:-no}" )" = "yes" ] || \
        [ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_FLUENT_BIT:-no}" )" = "true" ] || \
        [ ! -d "$TEST_SCENARIO_DIR"/fluent-bit ]
}

function is_calyptia_lts_disabled() {
	[ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_CALYPTIA_LTS:-no}" )" = "yes" ] || \
        [ "$( tr '[:upper:]' '[:lower:]' <<<"${DISABLE_CALYPTIA_LTS:-no}" )" = "true" ] || \
        [ ! -d "$TEST_SCENARIO_DIR"/calyptia-fluent-bit ]
}

function is_cribl_running() {
    if ! is_cribl_disabled; then
        if ! "$CRIBL_HOME"/bin/cribl status &> /dev/null; then
            echo "ERROR: cribl not running"
            "$CRIBL_HOME"/bin/cribl status
        fi
    fi
}

function run_cribl() {
    if is_cribl_disabled; then
        echo "SKIP: cribl"
    else
        echo "Running cribl"
        "$CRIBL_HOME"/bin/cribl version
        "$CRIBL_HOME"/bin/cribl mode-single
        "$CRIBL_HOME"/bin/cribl start
    fi
}

function stop_cribl() {
    if ! is_cribl_disabled; then
        echo "Stop cribl"
        "$CRIBL_HOME"/bin/cribl status
        "$CRIBL_HOME"/bin/cribl stop
    fi
}

function is_logstash_running() {
    if ! is_logstash_disabled; then
        if ! systemctl --quiet is-active logstash &> /dev/null; then
            echo "ERROR: logstash not running"
            systemctl --no-pager status logstash
        fi
    fi
}

function run_logstash() {
    if is_logstash_disabled; then
        echo "SKIP: logstash"
    else
        echo "Running logstash"
        sudo systemctl start logstash
    fi
}

function stop_logstash() {
    if ! is_logstash_disabled; then
        echo "Stop logstash"
        systemctl --no-pager status logstash
        sudo systemctl stop logstash
    fi
}

function configure_stanza() {
    echo "Configuring Stanza for test $TEST_SCENARIO from directory: $TEST_SCENARIO_DIR"
    cp -fv "$TEST_SCENARIO_DIR"/stanza/* /opt/observiq/stanza/
    cat /opt/observiq/stanza/config.yaml
}

function is_stanza_running() {
    if ! is_stanza_disabled; then
        if ! systemctl --quiet is-active stanza &> /dev/null; then
            echo "ERROR: Stanza not running"
            systemctl --no-pager status stanza
        fi
    fi
}

function run_stanza() {
    if is_stanza_disabled; then
        echo "SKIP: Stanza"
    else
        configure_stanza
        echo "Running Stanza"
        stanza version
        sudo systemctl start stanza
    fi
}

function stop_stanza() {
    if ! is_stanza_disabled; then
        echo "Stop Stanza"
        systemctl --no-pager status stanza
        sudo systemctl stop stanza
    fi
}

function configure_vector() {
    echo "Configuring Vector for test $TEST_SCENARIO from directory: $TEST_SCENARIO_DIR"
    cp -fv "$TEST_SCENARIO_DIR"/vector/* /etc/vector/
    cat /etc/vector/vector.toml
}

function is_vector_running() {
    if ! is_vector_disabled; then
        if ! systemctl --quiet is-active vector &> /dev/null; then
            echo "ERROR: Vector not running"
            systemctl --no-pager status vector
        fi
    fi
}

function run_vector() {
    if is_vector_disabled; then
        echo "SKIP: Vector"
    else
        configure_vector
        echo "Running Vector"
        vector --version
        sudo systemctl start vector
    fi
}

function stop_vector() {
    if ! is_vector_disabled; then
        echo "Stop Vector"
        systemctl --no-pager status vector
        sudo systemctl stop vector
    fi
}

function configure_fluent_bit() {
    echo "Configuring Fluent Bit for test $TEST_SCENARIO from directory: $TEST_SCENARIO_DIR"
    cp -fv "$TEST_SCENARIO_DIR"/fluent-bit/* /etc/fluent-bit/
    cat /etc/fluent-bit/fluent-bit.conf
}

function is_fluent_bit_running() {
    if ! is_fluent_bit_disabled; then
        if ! systemctl --quiet is-active fluent-bit &> /dev/null; then
            echo "ERROR: Fluent Bit not running"
            systemctl --no-pager status fluent-bit
        fi
    fi
}

function run_fluent_bit() {
    if is_fluent_bit_disabled; then
        echo "SKIP: Fluent Bit"
    else
        configure_fluent_bit
        echo "Running Fluent Bit"
        /opt/fluent-bit/bin/fluent-bit --version
        sudo systemctl start fluent-bit
    fi
}

function stop_fluent_bit() {
    if ! is_fluent_bit_disabled; then
        echo "Stop Fluent Bit"
        systemctl --no-pager status fluent-bit
        sudo systemctl stop fluent-bit
    fi
}

function configure_calyptia_lts() {
    echo "Configuring Calyptia Fluent Bit LTS for test $TEST_SCENARIO from directory: $TEST_SCENARIO_DIR"
    cp -fv "$TEST_SCENARIO_DIR"/calyptia-fluent-bit/* /etc/calyptia-fluent-bit/
    cat /etc/calyptia-fluent-bit/fluent-bit.conf
}

function is_calyptia_lts_running() {
    if ! is_calyptia_lts_disabled; then
        if ! systemctl --quiet is-active calyptia-fluent-bit &> /dev/null; then
            echo "ERROR: Calyptia Fluent Bit LTS not running"
            systemctl --no-pager status calyptia-fluent-bit
        fi
    fi
}

function run_calyptia_lts() {
    if is_calyptia_lts_disabled; then
        echo "SKIP: Calyptia Fluent Bit LTS"
    else
        configure_calyptia_lts
        echo "Running Calyptia Fluent Bit LTS"
        /opt/calyptia-fluent-bit/bin/calyptia-fluent-bit --version
        sudo systemctl start calyptia-fluent-bit
    fi
}

function stop_calyptia_lts() {
    if ! is_calyptia_lts_disabled; then
        echo "Stop Calyptia Fluent Bit LTS"
        systemctl --no-pager status calyptia-fluent-bit
        sudo systemctl stop calyptia-fluent-bit
    fi
}

function is_data_generator_running() {
    if [[ -f "$TEST_SCENARIO_DIR"/data_generator/check_running.sh ]]; then
        /bin/bash "$TEST_SCENARIO_DIR"/data_generator/check_running.sh
    fi
}

function run_data_generator() {
    echo "Running data generator for test case $TEST_SCENARIO from $TEST_SCENARIO_DIR"
    if [[ -f "$TEST_SCENARIO_DIR"/data_generator/run.sh ]]; then
        /bin/bash "$TEST_SCENARIO_DIR"/data_generator/run.sh
    fi
}

function stop_data_generator() {
    echo "Stoping data generator for test case $TEST_SCENARIO from $TEST_SCENARIO_DIR"
    if [[ -f "$TEST_SCENARIO_DIR"/data_generator/stop.sh ]]; then
        /bin/bash "$TEST_SCENARIO_DIR"/data_generator/stop.sh
    fi
}

function run_cleanup() {
    # Clean up anything temporary
    sudo rm -rf /tmp/cribl/ /tmp/logstash/ /tmp/stanza/ /tmp/vector/ /tmp/fluent-bit/ /tmp/calyptia-fluent-bit /tmp/fluentd/
    mkdir -p /tmp/cribl/ /tmp/logstash/ /tmp/stanza/ /tmp/vector/ /tmp/fluent-bit/ /tmp/calyptia-fluent-bit /tmp/fluentd/
    chmod a+w /tmp/cribl/ /tmp/logstash/ /tmp/stanza/ /tmp/vector/ /tmp/fluent-bit/ /tmp/calyptia-fluent-bit /tmp/fluentd/
}

function run_comparison() {
    stop_comparison
    run_cleanup
    run_cribl
    run_logstash
    run_stanza
    run_vector
    run_fluent_bit
    run_calyptia_lts
    run_data_generator
}

function stop_comparison() {
    stop_data_generator
    stop_cribl
    stop_stanza
    stop_vector
    stop_logstash
    stop_fluent_bit
    stop_calyptia_lts
}

function check_running() {
    # Check all services that should be running are running
    is_cribl_running
    is_logstash_running
    is_stanza_running
    is_vector_running
    is_fluent_bit_running
    is_calyptia_lts_running
    is_data_generator_running
}

function check_expected() {
    # For some scenarios we may want to check what records have been received.
    # These metrics can also be pushed to Prometheus for scraping afterwards.
    if [[ -f "$TEST_SCENARIO_DIR"/data_generator/check_expected.sh ]]; then
        /bin/bash "$TEST_SCENARIO_DIR"/data_generator/check_expected.sh
    fi
}