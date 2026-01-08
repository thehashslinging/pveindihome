#!/bin/bash

echo "=== INDIHOME NETWORK FIX SCRIPT ==="

### 1. SET DNS (CLOUDFLARE + GOOGLE ONLY)
echo "[1/6] Setting DNS (Cloudflare + Google)..."

cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=1.1.1.1 8.8.8.8
EOF

systemctl restart systemd-resolved

# pastikan resolv.conf ke systemd
if [ ! -L /etc/resolv.conf ]; then
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

### 2. SET MTU VM BRIDGE (vmbr0)
echo "[2/6] Setting MTU vmbr0..."
if grep -q "vmbr0" /etc/network/interfaces; then
    sed -i '/vmbr0/,+10 s/mtu .*/mtu 1492/' /etc/network/interfaces
    grep -q "mtu 1492" /etc/network/interfaces || \
    sed -i '/vmbr0/ a\    mtu 1492' /etc/network/interfaces
fi

if command -v ifreload >/dev/null 2>&1; then
    ifreload -a
else
    systemctl restart networking
fi

### 3. SET DOCKER MTU + DNS
echo "[3/6] Setting Docker MTU & DNS..."

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "mtu": 1492,
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF

systemctl restart docker

### 4. INSTALL IPTABLES-PERSISTENT
echo "[4/6] Installing iptables-persistent..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent

### 5. TCP MSS CLAMPING (CRITICAL FOR INDIHOME)
echo "[5/6] Applying TCP MSS clamping..."

iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

iptables -t mangle -C POSTROUTING -o docker0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
iptables -t mangle -A POSTROUTING -o docker0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

iptables -t mangle -C FORWARD -o vmbr0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
iptables -t mangle -A FORWARD -o vmbr0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

iptables -t mangle -C FORWARD -i vmbr0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
iptables -t mangle -A FORWARD -i vmbr0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

netfilter-persistent save

### 6. STATUS CHECK
echo "[6/6] Status check..."

echo
echo "DNS aktif:"
resolvectl status | grep "DNS Servers"

echo
echo "Docker MTU:"
ip link show docker0 | grep mtu || echo "docker0 belum aktif (normal jika belum ada container)"

echo
echo "MSS rules:"
iptables -t mangle -L | grep TCPMSS

echo
echo "=== DONE ==="
echo "Reboot sangat disarankan."
