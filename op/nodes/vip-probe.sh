#!/bin/bash

TOP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." &> /dev/null && pwd )"
CONFIG_FILE="$TOP_DIR/config.yaml"
VIP=$(yq e '.vip' "$CONFIG_FILE")

TIMEOUT=5
MAX_RETRIES=10

# --- First ping (baseline, not counted in retries) ---
echo "Probing VIP $VIP..."
start_time=$(date +%s%N)
ping -c 1 "$VIP" > /dev/null 2>&1
first_exit=$?
elapsed_ns=$(( $(date +%s%N) - start_time ))
elapsed_s=$(( elapsed_ns / 1000000000 ))

if [ $first_exit -ne 0 ]; then
    echo "ERROR: VIP $VIP is unreachable (first ping failed, exit code: $first_exit)"
    exit 1
fi

echo "First ping OK (${elapsed_s}s). Running ${MAX_RETRIES} timed retries..."

# --- Retry loop ---
unstable=0
for (( i=1; i<=MAX_RETRIES; i++ )); do
    echo "  Retry $i/${MAX_RETRIES}..."
    start_time=$(date +%s%N)
    timeout --preserve-status "$TIMEOUT" ping -c 1 "$VIP" > /dev/null 2>&1
    ping_exit=$?
    elapsed_ns=$(( $(date +%s%N) - start_time ))
    elapsed_s=$(( elapsed_ns / 1000000000 ))

    if [ $ping_exit -ne 0 ]; then
        echo "  Retry $i: FAILED (exit code: $ping_exit)"
        unstable=1
    elif [ "$elapsed_s" -gt "$TIMEOUT" ]; then
        echo "  Retry $i: SLOW (${elapsed_s}s, exceeded ${TIMEOUT}s threshold)"
        unstable=1
    else
        echo "  Retry $i: OK (${elapsed_s}s)"
    fi

    sleep 1
done

if [ $unstable -ne 0 ]; then
    echo "ERROR: VIP $VIP is unstable (slow/unreachable pings detected in retry loop)"
    exit 1
fi

echo "OK: VIP $VIP is stable (${MAX_RETRIES} retries all within ${TIMEOUT}s)"
