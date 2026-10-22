# =============================================================
# CallFlow Pro - Monitoring Container
# Runs queue-monitor.sh / agent-dashboard.sh / auto-scaler.sh
# on a schedule inside a lightweight Alpine container.
# =============================================================
FROM alpine:3.20

RUN apk add --no-cache bash curl mysql-client netcat-openbsd tzdata dcron

WORKDIR /opt/callflowpro

COPY scripts/ ./scripts/
RUN chmod +x ./scripts/*.sh

# Schedule auto-scaler every minute, report generator daily at 23:59
RUN echo "* * * * * /opt/callflowpro/scripts/auto-scaler.sh >> /var/log/callflowpro/auto-scaler.log 2>&1" > /etc/crontabs/root \
 && echo "59 23 * * * /opt/callflowpro/scripts/report-generator.sh >> /var/log/callflowpro/report.log 2>&1" >> /etc/crontabs/root

CMD ["crond", "-f", "-l", "2"]
