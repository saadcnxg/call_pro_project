#!/usr/bin/env bash
# =============================================================
# CallFlow Pro - Live Agent Status Dashboard
# Displays real-time agent status via Asterisk AMI
# Usage: ./agent-dashboard.sh
# =============================================================
set -euo pipefail

# ---- Configuration (override via environment or .env file) ----
AMI_HOST="${AMI_HOST:-127.0.0.1}"
AMI_PORT="${AMI_PORT:-5038}"
AMI_USER="${AMI_USER:-callflow_admin}"
AMI_SECRET="${AMI_SECRET:-CHANGE_ME}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-5}"
LOGFILE="/var/log/callflowpro/agent-dashboard.log"

mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOGFILE" 2>/dev/null || true
}

# ---- Check dependencies ----
command -v nc >/dev/null 2>&1 || { echo "ERROR: 'nc' (netcat) is required."; exit 1; }

# ---- Query AMI for agent status ----
query_ami() {
    {
        printf "Action: Login\r\nUsername: %s\r\nSecret: %s\r\n\r\n" "$AMI_USER" "$AMI_SECRET"
        sleep 0.3
        printf "Action: Command\r\nCommand: sip show peers\r\n\r\n"
        sleep 0.5
        printf "Action: QueueStatus\r\n\r\n"
        sleep 0.5
        printf "Action: Logoff\r\n\r\n"
        sleep 0.2
    } | nc -w 3 "$AMI_HOST" "$AMI_PORT"
}

parse_and_render() {
    local raw="$1"
    clear
    echo "=============================================================="
    echo "  CallFlow Pro - Live Agent Dashboard   $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================================================="
    printf "%-10s %-15s %-15s %-10s\n" "AGENT" "HOST" "STATUS" "PORT"
    echo "--------------------------------------------------------------"

    # 'sip show peers' output looks like:
    # 6001/6001   192.168.1.50    D  N  A  5060     OK (12 ms)
    # Columns: Name/Username  Host  Dyn Nat ACL Port Status
    echo "$raw" | awk '
        /^[0-9]+\// {
            name=$1; sub(/\/.*/,"",name)
            host=$2; status=""
            for (i=3; i<=NF; i++) status = status" "$i
            printf "%-10s %-15s %-25s\n", name, host, status
        }
    ' 2>/dev/null || echo "(no live data - is Asterisk AMI reachable?)"

    echo "--------------------------------------------------------------"
    echo "$raw" | grep -E "^Queue:|Calls:|Completed:|Abandoned:" | \
        sed 's/^/  /' || true
    echo "=============================================================="
    echo "Press Ctrl+C to exit. Refreshing every ${REFRESH_INTERVAL}s..."
}

trap 'echo; echo "Dashboard stopped."; exit 0' INT TERM

log "Dashboard started"
while true; do
    RAW_OUTPUT="$(query_ami || true)"
    if [ -z "$RAW_OUTPUT" ]; then
        echo "WARNING: Could not connect to AMI at ${AMI_HOST}:${AMI_PORT}"
        log "AMI connection failed"
    else
        parse_and_render "$RAW_OUTPUT"
    fi
    sleep "$REFRESH_INTERVAL"
done
