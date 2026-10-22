#!/usr/bin/env bash
# =============================================================
# CallFlow Pro - Daily CDR Report Generator
# Generates a daily call summary report from the CDR database
# and emails it to management. Intended to run via cron at 23:59.
#
# Cron example:
#   59 23 * * * /opt/callflowpro/scripts/report-generator.sh
# =============================================================
set -euo pipefail

# ---- Configuration ----
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_NAME="${DB_NAME:-callflow_db}"
DB_USER="${DB_USER:-callflow_user}"
DB_PASS="${DB_PASS:-CHANGE_ME}"
REPORT_DATE="${1:-$(date +%Y-%m-%d)}"
REPORT_DIR="/opt/callflowpro/reports"
REPORT_FILE="${REPORT_DIR}/cdr-report-${REPORT_DATE}.csv"
SUMMARY_FILE="${REPORT_DIR}/cdr-summary-${REPORT_DATE}.txt"
MAIL_TO="${MAIL_TO:-management@callflowpro.com}"

mkdir -p "$REPORT_DIR"

command -v mysql >/dev/null 2>&1 || { echo "ERROR: mysql client not found."; exit 1; }

echo "Generating CDR report for ${REPORT_DATE}..."

# ---- Export raw CDR rows for the day ----
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    --batch --silent -e "
    SELECT calldate, src, dst, duration, billsec, disposition, queue_name, agent_id
    FROM cdr_records
    WHERE DATE(calldate) = '${REPORT_DATE}';
" > "$REPORT_FILE" 2>/tmp/callflowpro_report_err.log || {
    echo "ERROR: Failed to export CDR data. See /tmp/callflowpro_report_err.log"
    exit 1
}

TOTAL_CALLS=$(wc -l < "$REPORT_FILE" | tr -d ' ')

# ---- Summary metrics ----
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    --batch --silent -e "
    SELECT
        COUNT(*) AS total_calls,
        SUM(CASE WHEN disposition='ANSWERED' THEN 1 ELSE 0 END) AS answered,
        SUM(CASE WHEN disposition='NO ANSWER' THEN 1 ELSE 0 END) AS missed,
        ROUND(AVG(billsec),1) AS avg_talk_time_sec,
        ROUND(SUM(billsec)/3600,2) AS total_talk_hours
    FROM cdr_records
    WHERE DATE(calldate) = '${REPORT_DATE}';
" > "$SUMMARY_FILE"

{
    echo "=============================================================="
    echo " CallFlow Pro - Daily Report for ${REPORT_DATE}"
    echo "=============================================================="
    echo "Total logged rows: ${TOTAL_CALLS}"
    echo ""
    echo "Summary metrics (total_calls, answered, missed, avg_talk_sec, total_hours):"
    cat "$SUMMARY_FILE"
    echo "=============================================================="
} > "${REPORT_DIR}/final-report-${REPORT_DATE}.txt"

echo "Report generated: ${REPORT_DIR}/final-report-${REPORT_DATE}.txt"

# ---- Email report (requires mailutils / sendmail configured) ----
if command -v mail >/dev/null 2>&1; then
    mail -s "CallFlow Pro Daily Report - ${REPORT_DATE}" \
         -a "$REPORT_FILE" \
         "$MAIL_TO" < "${REPORT_DIR}/final-report-${REPORT_DATE}.txt" \
         && echo "Report emailed to ${MAIL_TO}"
else
    echo "NOTE: 'mail' command not available - report saved locally only."
fi
