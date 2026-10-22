# CallFlow Pro — System Architecture

## Overview
CallFlow Pro is a production-grade PBX built on **Asterisk** designed to support
a 200-agent call center with intelligent routing, high availability, and
real-time monitoring.

## High-Level Diagram (text form)

```
                         ┌─────────────────────┐
                         │   PSTN / SIP Trunks   │
                         │  (Primary + Backup)   │
                         └──────────┬───────────┘
                                    │
                          ┌─────────▼──────────┐
                          │   Asterisk Core     │
                          │ (chan_sip + dialplan)│
                          └───┬─────────┬───────┘
                              │         │
                 ┌────────────┘         └────────────┐
                 ▼                                    ▼
       ┌───────────────────┐               ┌────────────────────┐
       │   Queue Engine     │               │   MySQL/PostgreSQL │
       │ (sales/support/    │◄─────AGI──────┤  agent_status,     │
       │  billing/overflow) │               │  cdr_records,      │
       └─────────┬──────────┘               │  customers         │
                 │                          └─────────┬──────────┘
                 ▼                                    │
       ┌───────────────────┐                          │
       │  200 Agent Phones  │                          │
       │ (chan_sip peers)   │                          │
       └─────────┬──────────┘                          │
                 │                                     │
                 ▼                                     ▼
       ┌───────────────────┐               ┌────────────────────┐
       │ Monitoring Scripts │               │  Grafana Dashboard  │
       │ dashboard/monitor/ │──────────────►│  (visual reporting) │
       │ auto-scaler        │               └────────────────────┘
       └───────────────────┘
```

## Design Decisions

### Why chan_sip
This build intentionally uses the classic `chan_sip` driver (`sip.conf`)
instead of `pjsip`, per project requirements. Trade-offs to be aware of:
- `chan_sip` is deprecated upstream and removed by default in Asterisk 21+;
  stick to Asterisk 18-20 LTS, or compile chan_sip from source separately.
- Simpler, more familiar syntax (`type=friend`, `host=dynamic`) for teams
  already used to legacy Asterisk configs.
- Fewer native security features than pjsip (no built-in ICE, weaker SRTP
  support) — mitigate with `alwaysauthreject=yes`, fail2ban, and TLS
  transport (already configured in `sip.conf`).
- Registration/NAT handling relies on `nat=force_rport,comedia` rather
  than pjsip's more granular NAT options — test carefully behind NAT/firewalls.

### Why dual SIP trunks
A single upstream provider is a single point of failure. The dialplan
(`from-trunk-primary` / `from-trunk-backup`) treats both trunks identically
downstream, so failover is transparent to callers and agents.

### Why database-backed agent status
Asterisk's in-memory queue state resets on restart and isn't easily queryable
from external dashboards. Mirroring state into MySQL via AGI/AMI events gives
persistent, queryable, and Grafana-friendly agent status.

### Queue strategy choices
- **Sales** → `rrmemory`: fair distribution, remembers last agent to avoid
  double-routing the same rep back-to-back.
- **Support** → `leastrecent`: spreads load to agents who've been idle longest.
- **Billing** → `fewestcalls`: balances load for a smaller, specialized team.
- **VIP** → `ringall`: fastest possible pickup for top-tier customers.

### Monitoring & alerting
Bash scripts poll AMI/CLI every few seconds and push alerts to a webhook
(Slack/Teams) when SLA thresholds are breached, rather than waiting for a
human to notice a growing queue.

## Scaling Beyond 200 Agents
- Move from a single Asterisk box to a **Kamailio (SIP proxy) + multiple
  Asterisk media servers** architecture for horizontal scaling.
- Shift CDR/agent-status writes to a message queue (RabbitMQ/Kafka) instead
  of direct DB writes, to avoid database becoming a bottleneck.
- Introduce read replicas for the reporting database so live dashboards don't
  compete with write-heavy call traffic.
