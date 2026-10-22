#!/usr/bin/env bash
# =============================================================
# CallFlow Pro - Dynamic Queue Auto-Scaler
# Monitors queue load and moves "floating" agents between
# queues, or pages on-call backup agents, when load is high.
#
# Run as a systemd service or via cron every minute.
# =============================================================
set -euo pipefail

ASTERISK_BIN="${ASTERISK_BIN:-asterisk}"
HIGH_LOAD_THRESHOLD="${HIGH_LOAD_THRESHOLD:-10}"     # callers waiting
CRITICAL_LOAD_THRESHOLD="${CRITICAL_LOAD_THRESHOLD:-20}"
FLOATING_AGENTS=("6301" "6302" "6303" "6304" "6305")  # cross-trained pool
LOG_FILE="/var/log/callflowpro/auto-scaler.log"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

send_alert() {
    local message="$1"
    log "ALERT: ${message}"
    [ -z "$ALERT_WEBHOOK" ] && return 0
    curl -s -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"⚠️ CallFlow Pro Auto-Scaler: ${message}\"}" \
        "$ALERT_WEBHOOK" >/dev/null 2>&1 || true
}

get_queue_waiting_count() {
    local queue_name="$1"
    "$ASTERISK_BIN" -rx "queue show ${queue_name}" 2>/dev/null | \
        grep -oE "Callers:[[:space:]]*[0-9]+" | grep -oE "[0-9]+" | head -1 || echo 0
}

move_agent_to_queue() {
    local agent="$1"
    local target_queue="$2"
    log "Moving floating agent SIP/${agent} into ${target_queue}"
    "$ASTERISK_BIN" -rx "queue add member SIP/${agent} to ${target_queue}" \
        >>"$LOG_FILE" 2>&1 || log "WARNING: failed to add ${agent} to ${target_queue}"
}

remove_agent_from_queue() {
    local agent="$1"
    local queue="$2"
    "$ASTERISK_BIN" -rx "queue remove member SIP/${agent} from ${queue}" \
        >>"$LOG_FILE" 2>&1 || true
}

QUEUES=("sales_queue" "support_queue" "billing_queue")

log "Auto-scaler check starting..."

for queue in "${QUEUES[@]}"; do
    waiting="$(get_queue_waiting_count "$queue")"
    log "Queue [${queue}] waiting callers: ${waiting}"

    if [ "${waiting:-0}" -ge "$CRITICAL_LOAD_THRESHOLD" ]; then
        send_alert "Queue ${queue} is CRITICAL (${waiting} waiting). Paging all floating agents."
        for agent in "${FLOATING_AGENTS[@]}"; do
            move_agent_to_queue "$agent" "$queue"
        done
    elif [ "${waiting:-0}" -ge "$HIGH_LOAD_THRESHOLD" ]; then
        send_alert "Queue ${queue} load is HIGH (${waiting} waiting). Adding 1 floating agent."
        move_agent_to_queue "${FLOATING_AGENTS[0]}" "$queue"
    fi
done

log "Auto-scaler check complete."
