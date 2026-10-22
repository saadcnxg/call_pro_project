# CallFlow Pro — Troubleshooting Guide

## Agents can't register (chan_sip)
- Check `sip show peers` — look for `Unavailable` status.
- Confirm firewall allows UDP 5060 and RTP range 10000-20000.
- Check `asterisk -rx "sip show registry"` for auth failures.
- Common cause: wrong password in `agents-sip.conf` vs. softphone config.

## One-way or no audio
- Almost always a NAT/RTP issue.
- Verify `externip` and `localnet` in `sip.conf` `[general]` section match
  your actual public IP and internal subnet.
- Check `nat=force_rport,comedia` is set both in `[general]` and on the
  `agent-template` peer template.
- Confirm RTP port range (10000-20000/udp) is open on firewall and
  forwarded correctly if behind NAT.

## Calls not reaching queues
- Run `asterisk -rx "dialplan show queues-context"` to confirm the
  dialplan loaded correctly (check for syntax errors first).
- Check `queue show <queue_name>` — if `0/0/0` members, no agents are
  logged into that queue via `AgentLogin`.
- Confirm agent dialed `*22` (login) after their SIP peer registered.

## Failover to backup trunk not working
- Test by disabling the primary trunk provider or blocking its IP.
- Confirm `from-trunk-backup` context exists and mirrors the routing
  logic of `from-trunk-primary`.
- Check `identify` sections match the correct source IP/domain per trunk.

## Database connection errors in dialplan (MYSQL app / AGI)
- Confirm `func_odbc.conf` / ODBC DSN is configured if using realtime.
- Test connectivity manually: `mysql -h <host> -u callflow_user -p callflow_db`
- Check `cdr_records` / `agent_status` tables exist (`database/schema.sql` ran).
- Look at `/var/log/asterisk/full` for `MYSQL()` application errors.

## Voicemail-to-email not sending
- Verify a working local MTA (Postfix/sendmail) or external SMTP relay.
- Test manually: `echo "test" | mail -s "test" you@example.com`
- Check `serveremail` in `voicemail.conf` matches a valid "From" address
  your SMTP relay is authorized to send as.

## High CPU / call quality degrades under load
- Check codec transcoding — prefer passthrough codecs (opus/g722) between
  agents and avoid unnecessary transcoding to ulaw/alaw.
- Confirm `directmedia=no` isn't forcing all RTP through the Asterisk
  box unnecessarily for scenarios where it could bridge directly (weigh
  against NAT/recording requirements).
- Check `dmesg` / `iostat` for disk I/O bottlenecks from call recording
  (MixMonitor) if using local disk — consider moving recordings to
  network storage or a separate volume.

## Auto-scaler script not moving agents
- Confirm the floating agent extensions actually exist and are registered.
- Run manually with `bash -x scripts/auto-scaler.sh` to see verbose output.
- Check `/var/log/callflowpro/auto-scaler.log` for permission or AMI
  connectivity errors.

## Quick Diagnostic Commands
```bash
asterisk -rx "core show channels"
asterisk -rx "sip show peers"
asterisk -rx "queue show"
asterisk -rx "core show version"
tail -f /var/log/asterisk/full
```
