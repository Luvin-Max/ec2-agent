#!/bin/bash
# ============================================================
#  EC2 Monitoring Agent — Setup Script
#  Usage: bash setup.sh
#  Run as: ec2-user or root on Amazon Linux 2 / Ubuntu
# ============================================================

set -e  # Exit on any error

# ─── Colors ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/ec2-agent"
SERVICE_NAME="ec2-agent"

log()    { echo -e "${BLUE}[Agent]${NC} $1"; }
success(){ echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "============================================"
echo "   EC2 Monitoring Agent — Setup Script"
echo "============================================"
echo ""

# ─── 1. Check OS ─────────────────────────────────────────────
log "Detecting OS..."
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  log "OS: $PRETTY_NAME"
else
  error "Cannot detect OS. /etc/os-release not found."
fi

# ─── 2. Install Node.js if missing ──────────────────────────
if ! command -v node &> /dev/null; then
  log "Node.js not found. Installing..."
  
  if [[ "$OS" == "amzn" ]]; then
    # Amazon Linux
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
    yum install -y nodejs
  elif [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    # Ubuntu / Debian
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  else
    error "Unsupported OS: $OS. Install Node.js manually and re-run."
  fi
  success "Node.js installed: $(node --version)"
else
  success "Node.js already installed: $(node --version)"
fi

# ─── 3. Create install directory ────────────────────────────
log "Creating install directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
success "Directory ready: $INSTALL_DIR"

# ─── 4. Copy agent files ────────────────────────────────────
log "Copying agent files..."
cp agent.js "$INSTALL_DIR/agent.js"
cp package.json "$INSTALL_DIR/package.json"
success "Agent files copied."

# ─── 5. Configure .env ──────────────────────────────────────
ENV_FILE="$INSTALL_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  warn ".env already exists at $ENV_FILE — skipping config prompts."
  warn "Edit it manually if needed: nano $ENV_FILE"
else
  echo ""
  echo "─── Configuration ─────────────────────────────────"
  
  read -rp "Enter BACKEND_URL (e.g. https://yourbackend.com): " BACKEND_URL
  [ -z "$BACKEND_URL" ] && error "BACKEND_URL is required."
  
  # Auto-detect Instance ID from AWS metadata
  log "Trying to auto-detect EC2 Instance ID..."
  DETECTED_ID=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
  
  if [ -n "$DETECTED_ID" ]; then
    success "Auto-detected Instance ID: $DETECTED_ID"
    read -rp "Use this Instance ID? [Y/n]: " USE_DETECTED
    if [[ "$USE_DETECTED" =~ ^[Nn]$ ]]; then
      read -rp "Enter INSTANCE_ID manually: " INSTANCE_ID
    else
      INSTANCE_ID="$DETECTED_ID"
    fi
  else
    warn "Could not auto-detect Instance ID (not on EC2 or metadata unavailable)."
    read -rp "Enter INSTANCE_ID manually (e.g. i-0abc123): " INSTANCE_ID
  fi
  [ -z "$INSTANCE_ID" ] && error "INSTANCE_ID is required."
  
  read -rp "Interval in ms [default: 60000]: " INTERVAL_MS
  INTERVAL_MS="${INTERVAL_MS:-60000}"
  
  read -rp "Processes to monitor (comma-separated, e.g. nginx,node) [optional]: " MONITOR_PROCESSES
  
  read -rp "Alert CPU threshold % [default: 80]: " ALERT_CPU
  ALERT_CPU="${ALERT_CPU:-80}"
  
  read -rp "Alert MEM threshold % [default: 85]: " ALERT_MEM
  ALERT_MEM="${ALERT_MEM:-85}"
  
  read -rp "Alert DISK threshold % [default: 90]: " ALERT_DISK
  ALERT_DISK="${ALERT_DISK:-90}"
  
  # Write .env
  cat > "$ENV_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
INSTANCE_ID=$INSTANCE_ID
INTERVAL_MS=$INTERVAL_MS
MONITOR_PROCESSES=$MONITOR_PROCESSES
ALERT_CPU=$ALERT_CPU
ALERT_MEM=$ALERT_MEM
ALERT_DISK=$ALERT_DISK
AGENT_SECRET=
EOF

  chmod 600 "$ENV_FILE"
  success ".env created at $ENV_FILE"
fi

# ─── 6. Install systemctl service ───────────────────────────
log "Installing systemctl service..."

# Detect user
AGENT_USER="${SUDO_USER:-ec2-user}"
if id "ubuntu" &>/dev/null && [ "$AGENT_USER" = "ec2-user" ]; then
  AGENT_USER="ubuntu"
fi

# Write service file dynamically with correct user
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=EC2 Monitoring Agent
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$AGENT_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=/usr/bin/node $INSTALL_DIR/agent.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

success "Service file created: /etc/systemd/system/${SERVICE_NAME}.service"

# Set ownership
chown -R "$AGENT_USER":"$AGENT_USER" "$INSTALL_DIR"

# ─── 7. Enable and start service ────────────────────────────
log "Enabling and starting $SERVICE_NAME service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 2

# ─── 8. Status check ────────────────────────────────────────
echo ""
echo "─── Service Status ─────────────────────────────────"
systemctl status "$SERVICE_NAME" --no-pager -l | head -20

echo ""
if systemctl is-active --quiet "$SERVICE_NAME"; then
  success "Agent is RUNNING ✅"
  echo ""
  echo "  Useful commands:"
  echo "  • View logs:    journalctl -u $SERVICE_NAME -f"
  echo "  • Stop agent:   systemctl stop $SERVICE_NAME"
  echo "  • Restart:      systemctl restart $SERVICE_NAME"
  echo "  • Edit config:  nano $INSTALL_DIR/.env"
  echo "  • After edit:   systemctl restart $SERVICE_NAME"
else
  error "Agent failed to start. Check logs: journalctl -u $SERVICE_NAME -n 50"
fi

echo ""
echo "============================================"
echo "   Setup Complete! 🎉"
echo "============================================"
echo ""
