#!/bin/bash
set -e

### ===== ログ設定 =====
LOGDIR="/var/log/tor-gateway"
LOGFILE="$LOGDIR/setup.log"
mkdir -p "$LOGDIR"
exec > >(tee -a "$LOGFILE") 2>&1

log() {
  echo "[INFO]  $(date '+%F %T') $1"
}

warn() {
  echo "[WARN]  $(date '+%F %T') $1"
}

err() {
  echo "[ERROR] $(date '+%F %T') $1"
  exit 1
}

trap 'err "失敗（行 $LINENO）"' ERR

log "=== Tor Ethernet Gateway 完全構築開始 ==="

### ===== インターフェース定義 =====
LAN_IF="eth0"        # 内蔵Ethernet (Mac接続用)
WAN_IF="wlan0"       # Wi-Fi (インターネット接続用)
LAN_IP="192.168.50.1"
LAN_NET="192.168.50.0/24"

log "使用するインターフェース: LAN=$LAN_IF (Mac接続), WAN=$WAN_IF (Internet)"

### ===== インターフェース確認 =====
if ! ip link show "$LAN_IF" &>/dev/null; then
  err "インターフェース $LAN_IF が見つかりません"
fi

if ! ip link show "$WAN_IF" &>/dev/null; then
  err "インターフェース $WAN_IF が見つかりません。Wi-Fi設定を確認してください"
fi

log "✓ インターフェース確認完了"

### ===== パッケージ =====
log "パッケージ更新"
apt update

log "必要パッケージインストール"
apt install -y tor dnsmasq iptables-persistent curl

### ===== IP フォワーディング =====
log "IP フォワーディング有効化"

cat > /etc/sysctl.d/99-tor-gateway.conf <<EOF
net.ipv4.ip_forward=1
EOF

sysctl --system

### ===== dhcpcd無効化（競合防止） =====
log "dhcpcd無効化（systemd-networkdと競合するため）"
systemctl disable dhcpcd 2>/dev/null || warn "dhcpcdが見つかりません（問題なし）"
systemctl stop dhcpcd 2>/dev/null || warn "dhcpcdが動作していません（問題なし）"

### ===== eth0の固定IP設定 =====
log "eth0 固定IP設定"

mkdir -p /etc/systemd/network

# 既存のnetwork設定を削除
rm -f /etc/systemd/network/10-*.network 2>/dev/null || true

cat > /etc/systemd/network/10-eth0.network <<EOF
[Match]
Name=$LAN_IF

[Network]
Address=$LAN_IP/24
ConfigureWithoutCarrier=yes
EOF

# wlan0はDHCPのまま
cat > /etc/systemd/network/20-wlan0.network <<EOF
[Match]
Name=$WAN_IF

[Network]
DHCP=yes
EOF

systemctl enable systemd-networkd
systemctl restart systemd-networkd

sleep 3

# IPアドレス確認
if ip addr show "$LAN_IF" | grep -q "$LAN_IP"; then
  log "✓ eth0のIPアドレス設定完了: $LAN_IP"
else
  warn "eth0のIPアドレスが設定されていません。手動設定を試みます..."
  ip addr flush dev "$LAN_IF" 2>/dev/null || true
  ip addr add "$LAN_IP/24" dev "$LAN_IF" 2>/dev/null || warn "IPアドレス設定失敗"
  ip link set "$LAN_IF" up 2>/dev/null || warn "インターフェース起動失敗"
fi

### ===== dnsmasq =====
log "dnsmasq 設定"

cat > /etc/dnsmasq.d/tor-gateway.conf <<EOF
interface=$LAN_IF
bind-interfaces
dhcp-range=192.168.50.10,192.168.50.100,12h
dhcp-option=3,$LAN_IP
dhcp-option=6,$LAN_IP
log-dhcp
log-queries
EOF

# dnsmasqのメイン設定確認
if ! grep -q "^conf-dir=/etc/dnsmasq.d/,\*.conf" /etc/dnsmasq.conf 2>/dev/null; then
  log "dnsmasq.conf に conf-dir を追加"
  echo "conf-dir=/etc/dnsmasq.d/,*.conf" >> /etc/dnsmasq.conf
fi

systemctl enable dnsmasq

log "dnsmasq起動中..."
if systemctl restart dnsmasq 2>&1; then
  sleep 2
  if systemctl is-active --quiet dnsmasq; then
    log "✓ dnsmasq 起動成功"
  else
    warn "✗ dnsmasq 起動確認失敗"
    journalctl -u dnsmasq --no-pager -n 10 || true
  fi
else
  warn "✗ dnsmasq 起動失敗"
  journalctl -u dnsmasq --no-pager -n 10 || true
fi

### ===== Tor設定（重要：0.0.0.0でリッスン） =====
log "Tor 設定（全インターフェースでリッスン）"

cat > /etc/tor/torrc <<'EOF'
# ログ設定
Log notice file /var/log/tor/notices.log
Log notice syslog

# 仮想アドレス設定
VirtualAddrNetworkIPv4 10.192.0.0/10
AutomapHostsOnResolve 1

# 透過プロキシ設定（0.0.0.0で全インターフェースからアクセス可能に）
TransPort 0.0.0.0:9040
TransListenAddress 0.0.0.0:9040

# DNS設定（0.0.0.0で全インターフェースからアクセス可能に）
DNSPort 0.0.0.0:9053
DNSListenAddress 0.0.0.0:9053

# パフォーマンス設定
AvoidDiskWrites 1
EOF

# ログディレクトリのパーミッション設定
log "Torログディレクトリのパーミッション設定"
mkdir -p /var/log/tor
chown debian-tor:debian-tor /var/log/tor
chmod 700 /var/log/tor

systemctl enable tor

log "Tor起動中..."
if systemctl restart tor 2>&1; then
  sleep 5
  if systemctl is-active --quiet tor; then
    log "✓ Tor 起動成功"
    # ポート確認
    if ss -tlnp | grep -q "0.0.0.0:9040"; then
      log "✓ TransPort (9040) が 0.0.0.0 でリッスン中"
    else
      warn "✗ TransPort (9040) が正しく起動していません"
    fi
    if ss -ulnp | grep -q "0.0.0.0:9053"; then
      log "✓ DNSPort (9053) が 0.0.0.0 でリッスン中"
    else
      warn "✗ DNSPort (9053) が正しく起動していません"
    fi
  else
    warn "✗ Tor 起動確認失敗"
    journalctl -u tor --no-pager -n 10 || true
  fi
else
  warn "✗ Tor 起動失敗"
  journalctl -u tor --no-pager -n 10 || true
fi

### ===== iptables =====
log "iptables 設定（Tor 強制 + Kill Switch）"

# 既存ルールをクリア
iptables -F
iptables -t nat -F
iptables -X

TOR_UID=$(id -u debian-tor)

# 基本許可
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i $LAN_IF -j ACCEPT

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS → Tor
iptables -t nat -A PREROUTING -i $LAN_IF -p udp --dport 53 -j REDIRECT --to-ports 9053
iptables -t nat -A PREROUTING -i $LAN_IF -p tcp --dport 53 -j REDIRECT --to-ports 9053

# TCP → Tor
iptables -t nat -A PREROUTING -i $LAN_IF -p tcp --syn -j REDIRECT --to-ports 9040

# NAT
iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE

# Kill Switch（Tor以外のWAN通信遮断）
iptables -A OUTPUT -o $WAN_IF -m owner ! --uid-owner $TOR_UID -j DROP

log "iptables 保存"
iptables-save > /etc/iptables/rules.v4

### ===== 設定ファイル保存 =====
log "設定情報を保存"

cat > /etc/tor-gateway.conf <<EOF
# Tor Gateway Configuration
LAN_INTERFACE=$LAN_IF
WAN_INTERFACE=$WAN_IF
LAN_IP=$LAN_IP
CONFIGURED_DATE=$(date '+%Y-%m-%d %H:%M:%S')
EOF

### ===== 動作確認 =====
log "=== 動作確認 ==="

echo ""
echo "=========================================="
echo "✨ Tor Gateway 構築完了"
echo "=========================================="
echo ""
echo "📡 ネットワーク設定:"
echo "  LAN (Mac接続): $LAN_IF"
echo "  WAN (Internet): $WAN_IF"
echo "  LAN IP: $LAN_IP"
echo "  DHCP範囲: 192.168.50.10 - 192.168.50.100"
echo ""
echo "🔧 サービス状態:"

if systemctl is-active --quiet dnsmasq; then
  echo "  ✓ dnsmasq: 動作中"
else
  echo "  ✗ dnsmasq: 停止中"
fi

if systemctl is-active --quiet tor; then
  echo "  ✓ Tor: 動作中"
else
  echo "  ✗ Tor: 停止中"
fi

if systemctl is-active --quiet systemd-networkd; then
  echo "  ✓ systemd-networkd: 動作中"
else
  echo "  ✗ systemd-networkd: 停止中"
fi

echo ""
echo "🌐 ネットワーク状態:"
echo ""
echo "[$LAN_IF - Mac接続用]"
ip addr show "$LAN_IF" | grep -E "inet " || echo "  IPアドレス未設定"
echo ""
echo "[$WAN_IF - インターネット接続]"
ip addr show "$WAN_IF" | grep -E "inet " || echo "  IPアドレス未設定"

echo ""
echo "🔍 Torポート状態:"
ss -tlnp | grep tor || echo "  Torポートが見つかりません"
ss -ulnp | grep 9053 || echo "  DNS UDPポートが見つかりません"

echo ""
echo "=========================================="
echo "🚀 使い方"
echo "=========================================="
echo ""
echo "1. 再起動してください:"
echo "   sudo reboot"
echo ""
echo "2. 再起動後、MacとラズパイをEthernetケーブルで接続"
echo ""
echo "3. Macで自動的にIPアドレス (192.168.50.x) を取得"
echo ""
echo "4. Macで動作確認:"
echo "   curl https://check.torproject.org/api/ip"
echo "   → {\"IsTor\": true} と表示されればOK！"
echo ""
echo "=========================================="
echo "📋 トラブルシューティング"
echo "=========================================="
echo ""
echo "サービス確認:"
echo "  sudo systemctl status tor"
echo "  sudo systemctl status dnsmasq"
echo ""
echo "ログ確認:"
echo "  sudo journalctl -u tor -f"
echo "  sudo tail -f /var/log/tor/notices.log"
echo ""
echo "ポート確認:"
echo "  sudo ss -tlnp | grep tor"
echo "  sudo ss -ulnp | grep 9053"
echo ""
echo "設定ファイル:"
echo "  /etc/tor-gateway.conf"
echo "  /etc/tor/torrc"
echo "  $LOGFILE"
echo ""
echo "=========================================="
echo "⚠️  重要事項"
echo "=========================================="
echo ""
echo "- このラズパイに接続した全ての通信はTor経由になります"
echo "- 通信速度はTorネットワークの速度に依存します"
echo "- Wi-Fi (wlan0) が常にインターネットに接続されている必要があります"
echo "- 再起動後も自動的に動作します"
echo ""