#!/usr/bin/env bash
# Aurum dedicated server - one-command installer for a free/cheap Linux VM
# (Oracle Cloud Always Free ARM or AMD, Google Cloud e2-micro, any Ubuntu/Debian VPS).
#
#   curl -fsSL https://raw.githubusercontent.com/mujahidsa-w/Aurum/claude/awesome-planck-jiaods/server/install.sh | sudo bash
#
# Installs Godot (x86_64 or arm64), the game, a systemd service on UDP 7777 that starts on
# boot and restarts on crash, opens the firewall and adds swap on small machines.
# Run again at any time to update to the latest version of the game.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GODOT_RELEASE="${GODOT_RELEASE:-stable}"
REPO="${AURUM_REPO:-https://github.com/mujahidsa-w/Aurum.git}"
BRANCH="${AURUM_BRANCH:-claude/awesome-planck-jiaods}"
PORT="${AURUM_PORT:-7777}"
LOBBY_SECONDS="${AURUM_LOBBY_SECONDS:-30}"
DIR=/opt/aurum

log() { echo -e "\033[1;33m[aurum]\033[0m $*"; }

if [ "$(id -u)" -ne 0 ]; then echo "Run as root (sudo)."; exit 1; fi

log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl unzip git libfontconfig1 iptables >/dev/null

# Small machines (1 GB) need swap to import the project.
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$mem_mb" -lt 3000 ] && ! swapon --show | grep -q /swapfile; then
  log "Adding 2 GB swap (RAM: ${mem_mb} MB)"
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

id aurum >/dev/null 2>&1 || useradd --system --create-home --home-dir "$DIR" --shell /usr/sbin/nologin aurum
mkdir -p "$DIR"

case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64|amd64) ARCH=x86_64 ;;
  *) echo "Unsupported CPU: $(uname -m)"; exit 1 ;;
esac
GODOT="$DIR/godot-$GODOT_VERSION"
if [ ! -x "$GODOT" ]; then
  log "Downloading Godot $GODOT_VERSION ($ARCH)"
  url="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.${ARCH}.zip"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/godot.zip" "$url"
  unzip -q "$tmp/godot.zip" -d "$tmp"
  mv "$tmp"/Godot_v*_linux.* "$GODOT"
  chmod +x "$GODOT"
  rm -rf "$tmp"
fi

if [ -d "$DIR/Aurum/.git" ]; then
  log "Updating the game"
  git -C "$DIR/Aurum" fetch -q --depth 1 origin "$BRANCH"
  git -C "$DIR/Aurum" reset -q --hard FETCH_HEAD
else
  log "Downloading the game"
  GIT_LFS_SKIP_SMUDGE=1 git clone -q --depth 1 -b "$BRANCH" "$REPO" "$DIR/Aurum"
fi
chown -R aurum:aurum "$DIR"

log "Importing the project (first time takes a few minutes)"
sudo -u aurum HOME="$DIR" "$GODOT" --headless --path "$DIR/Aurum/AurumGodot" --import > "$DIR/import.log" 2>&1 || true

cat > /etc/systemd/system/aurum-server.service <<UNIT
[Unit]
Description=Aurum dedicated game server (UDP $PORT)
After=network-online.target
Wants=network-online.target

[Service]
User=aurum
Environment=HOME=$DIR
WorkingDirectory=$DIR
ExecStart=$GODOT --headless --path $DIR/Aurum/AurumGodot res://scenes/server.tscn -- --server --port=$PORT --lobby-seconds=$LOBBY_SECONDS
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable aurum-server >/dev/null 2>&1
systemctl restart aurum-server

log "Opening UDP $PORT in the firewall"
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "$PORT/udp" >/dev/null
fi
# Oracle Cloud images ship iptables rules that reject everything except SSH.
if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null; then
  iptables -I INPUT 1 -p udp --dport "$PORT" -j ACCEPT
fi
if command -v netfilter-persistent >/dev/null; then
  netfilter-persistent save >/dev/null 2>&1 || true
elif [ -d /etc/iptables ]; then
  iptables-save > /etc/iptables/rules.v4 || true
fi

for i in $(seq 1 30); do
  if journalctl -u aurum-server --no-pager -n 50 2>/dev/null | grep -q "AURUM SERVER: listening"; then break; fi
  sleep 2
done
journalctl -u aurum-server --no-pager -n 5 2>/dev/null | grep "AURUM SERVER" || true

ip=$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
cat <<DONE

==========================================================================
 Aurum server is running on UDP $PORT   (status: systemctl status aurum-server)
 Public IP: $ip

 Add this in Firebase -> Realtime Database (Data tab), at the root:
   "config": { "server": { "host": "$ip", "port": $PORT } }
 or type  $ip:$PORT  in the game: Lobby -> SETTINGS -> Server -> SAVE

 Cloud firewall: also allow UDP $PORT from 0.0.0.0/0 in your provider's panel
 (Oracle: VCN -> Security List -> Add Ingress Rule, IP Protocol UDP, port $PORT).
 Update later: run this installer again.
==========================================================================
DONE
