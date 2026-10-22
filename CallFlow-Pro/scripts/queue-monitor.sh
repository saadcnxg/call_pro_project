#!/usr/bin/env bash
# =============================================================
# CallFlow Pro - Real-Time Queue Monitor
# Uses `asterisk -rx` CLI commands (must run on the Asterisk box,
# or via SSH to it) to show live queue depth, wait time, SLA.
# Usage: ./queue-monitor.sh [queue_name]
# =============================================================
set -euo pipefail

QUEUE_FILTER="${1:-}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-5}"
ASTERISK_BIN="${ASTERISK_BIN:-asterisk}"
ALERT_WAIT_THRESHOLD="${ALERT_WAIT_THRESHOLD:-120}"   # seconds
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"                    # optional Slack/Teams webhook

command -v "$ASTERISK_BIN" >/dev/null 2>&1 || {
    echo "ERROR: '$ASTERISK_BIN' CLI not found. Run this on the Asterisk server."
    exit 1
}

send_alert() {
    local message="$1"
    [ -z "$ALERT_WEBHOOK" ] && return 0
    curl -s -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"🚨 CallFlow Pro Alert: ${message}\"}" \
        "$ALERT_WEBHOOK" >/dev/null 2>&1 || true
}

trap 'echo; echo "Queue monitor stopped."; exit 0' INT TERM

while true; do
    clear
    echo "=============================================================="
    echo "  CallFlow Pro - Queue Monitor    $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================================================="

    RAW="$("$ASTERISK_BIN" -rx "queue show ${QUEUE_FILTER}" 2>/dev/null || true)"

    if [ -z "$RAW" ]; then
        echo "No queue data returned. Is Asterisk running?"
    else
        echo "$RAW"

        # Extract longest wait time in seconds if present and alert if over threshold
        LONGEST_WAIT=$(echo "$RAW" | grep -oE "Callers:[[:space:]]*[0-9]+" | head -1 | grep -oE "[0-9]+" || echo 0)
        if [ "${LONGEST_WAIT:-0}" -gt 0 ]; then
            echo ""
            echo "--- Active callers waiting: ${LONGEST_WAIT} ---"
        fi

        # Basic SLA breach detection (looks for "holdtime" over threshold pattern)
        if echo "$RAW" | grep -qE "wait: [0-9]{3,}"; then
            send_alert "A queue has calls waiting longer than ${ALERT_WAIT_THRESHOLD}s"
        fi
    fi

    echo "=============================================================="
    echo "Refreshing every ${REFRESH_INTERVAL}s. Ctrl+C to exit."
    sleep "$REFRESH_INTERVAL"
done
