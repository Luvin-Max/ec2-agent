# EC2 Monitoring Agent

Lightweight Node.js agent that collects system metrics from EC2 instances and sends them to your backend via the telemetry API.

## What it collects

| Metric | Source |
|--------|--------|
| CPU % | `/proc/stat` (2-sample diff) |
| Memory % | `/proc/meminfo` |
| Disk % | `df /` |
| Net In/Out (KB) | `/proc/net/dev` |
| Process health | `pgrep` |
| Uptime, hostname | `os` module |

## Quick Setup (on EC2)

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/ec2-agent.git
cd ec2-agent

# 2. Run setup (as root/sudo)
sudo bash setup.sh
```

The script will:
- Install Node.js 20 if missing (Amazon Linux & Ubuntu supported)
- Auto-detect your EC2 Instance ID from metadata
- Prompt for BACKEND_URL and other config
- Create `/opt/ec2-agent/.env` with your settings
- Install and start the `ec2-agent` systemctl service
- Enable auto-start on reboot

## Manual Config

```bash
sudo nano /opt/ec2-agent/.env
sudo systemctl restart ec2-agent
```

## Useful Commands

```bash
# Live logs
journalctl -u ec2-agent -f

# Status
systemctl status ec2-agent

# Restart
sudo systemctl restart ec2-agent

# Uninstall
sudo bash uninstall.sh
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BACKEND_URL` | ✅ | — | Backend API base URL |
| `INSTANCE_ID` | ✅ | — | EC2 Instance ID |
| `INTERVAL_MS` | ❌ | `60000` | Collection interval (ms) |
| `MONITOR_PROCESSES` | ❌ | — | Comma-separated process names |
| `ALERT_CPU` | ❌ | `80` | CPU threshold for degraded status |
| `ALERT_MEM` | ❌ | `85` | Memory threshold |
| `ALERT_DISK` | ❌ | `90` | Disk threshold |
| `AGENT_SECRET` | ❌ | — | Shared secret for `x-agent-secret` header |

## Telemetry Payload

Sends POST to `BACKEND_URL/api/aws-instances/telemetry`:

```json
{
  "instanceId": "i-0abc...",
  "metrics": {
    "cpu": 23.4,
    "mem": 47.1,
    "diskUsage": 68.0,
    "netIn": 120.5,
    "netOut": 210.3,
    "processHealth": { "nginx": "running" },
    "customMetrics": { "hostname": "...", "uptime": 3600 }
  },
  "status": "up",
  "collectedAt": "2026-04-10T12:00:00Z",
  "logs": [{ "timestamp": "...", "message": "Heartbeat", "severity": "info" }]
}
```

## Supported OS

- Amazon Linux 2 / Amazon Linux 2023
- Ubuntu 20.04, 22.04, 24.04
- Debian 11+
