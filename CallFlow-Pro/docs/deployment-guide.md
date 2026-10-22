# CallFlow Pro — Deployment Guide

## Prerequisites
- Ubuntu 22.04 LTS server (min 4 vCPU / 8GB RAM for 200 agents)
- Docker + Docker Compose v2
- A public IP or NAT-forwarded ports: 5060/udp, 5061/tcp (TLS), 10000-20000/udp (RTP)
- Two SIP trunk provider accounts (primary + backup) for failover

## Option A — Docker Compose (recommended for testing/demo)

```bash
git clone <your-repo-url> CallFlow-Pro
cd CallFlow-Pro

# 1. Copy environment template and fill in secrets
cp .env.example .env
nano .env      # set MYSQL_PASSWORD, ALERT_WEBHOOK, GRAFANA_PASSWORD, etc.

# 2. Edit configs/sip.conf and replace:
#    - YOUR_PUBLIC_IP
#    - YOUR_TRUNK1_USERNAME / PASSWORD
#    - YOUR_TRUNK2_USERNAME / PASSWORD

# 3. Generate 200 agent configs
chmod +x scripts/*.sh
./scripts/generate-agents.sh

# 4. Bring the stack up
docker compose up -d

# 5. Verify Asterisk is healthy
docker exec -it callflowpro-asterisk asterisk -rx "core show version"
docker exec -it callflowpro-asterisk asterisk -rx "sip show peers"
```

## Option B — Bare-metal Install

```bash
# 1. Install Asterisk 20 LTS
sudo apt update && sudo apt install -y build-essential libssl-dev libncurses5-dev \
    libnewt-dev libxml2-dev linux-headers-$(uname -r) libsqlite3-dev uuid-dev

wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-20-current.tar.gz
tar xvf asterisk-20-current.tar.gz && cd asterisk-20*/
sudo contrib/scripts/install_prereq install
./configure && make menuselect && make -j$(nproc) && sudo make install
sudo make config
sudo make samples

# 2. Copy CallFlow Pro configs over the samples
sudo cp configs/*.conf /etc/asterisk/
sudo cp configs/agents-sip.conf /etc/asterisk/ 2>/dev/null || true

# 3. Set up MySQL
sudo apt install -y mysql-server
sudo mysql < database/schema.sql

# 4. Install ODBC for realtime (optional but recommended)
sudo apt install -y unixodbc unixodbc-dev odbc-mysql

# 5. Start Asterisk
sudo systemctl enable asterisk
sudo systemctl start asterisk
sudo asterisk -rvvv
```

## Post-Install Checklist
- [ ] `sip show peers` shows all 200 agents registered
- [ ] Test inbound call routes through IVR → correct queue
- [ ] Test agent login (`*22`) and logout (`*23`) feature codes
- [ ] Pull down primary trunk, confirm backup trunk takes over
- [ ] Confirm voicemail-to-email delivery works
- [ ] Run `scripts/queue-monitor.sh` and confirm live data appears
- [ ] Run `scripts/report-generator.sh` manually and check CSV output
- [ ] Set up cron for `auto-scaler.sh` (every minute) and
      `report-generator.sh` (daily at 23:59)
- [ ] Enable TLS/SRTP for production (see `features.conf` notes)
- [ ] Change every default password/secret in configs and `.env`

## Load Testing (Step 45 of the roadmap)
Use [SIPp](https://github.com/SIPp/sipp) to simulate concurrent calls:

```bash
sudo apt install -y sip-tester
sipp -sn uac 127.0.0.1:5060 -s 6001 -m 200 -r 10
```
This ramps up to 200 concurrent calls at 10 calls/second — watch
`queue-monitor.sh` and system resource usage (`htop`) during the test.
