#!/bin/bash
# Starts the practice server on this runner and points Snapreel's host names at it.
# Usage: start_stub.sh APP_SOURCE_DIR WORK_DIR. Leaves WORK_DIR/ca.pem for the simulators to trust.
set -euo pipefail
SRC="$1"; W="$2"; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$W"
REF=$(grep -rhoE 'https://[a-z]{20}\.supabase\.co' "$SRC/Snapreel" --include=*.swift | head -1 | sed -E 's#https://([a-z]+)\..*#\1#')
HOSTS="snapreel.video www.snapreel.video snapreel-push.vercel.app"
[ -n "$REF" ] && HOSTS="$HOSTS $REF.supabase.co $REF.storage.supabase.co"
# The real address, for terms, privacy and other plain pages (before /etc/hosts changes it).
SITE_IP=$(dig +short snapreel.video A | grep -E '^[0-9.]+$' | head -1 || true)
cat > "$W/ca.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Snapreel rig (this runner only)
[v3]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
CNF
NAMES=$(for h in $HOSTS; do printf 'DNS:%s,' "$h"; done | sed 's/,$//')
cat > "$W/leaf.ext" <<EXT
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $NAMES
EXT
openssl req -x509 -newkey rsa:2048 -nodes -days 3 -keyout "$W/ca.key" -out "$W/ca.pem" -config "$W/ca.cnf" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout "$W/leaf.key" -out "$W/leaf.csr" -subj "/CN=snapreel.video" 2>/dev/null
openssl x509 -req -in "$W/leaf.csr" -CA "$W/ca.pem" -CAkey "$W/ca.key" -CAcreateserial -days 3 -sha256 -extfile "$W/leaf.ext" -out "$W/leaf.pem" 2>/dev/null
for h in $HOSTS; do echo "127.0.0.1 $h" | sudo tee -a /etc/hosts > /dev/null; done
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true
sudo nohup python3 "$HERE/cloud_stub.py" --cert "$W/leaf.pem" --key "$W/leaf.key" --site-ip "$SITE_IP" > "$W/stub.log" 2>&1 &
for _ in $(seq 1 30); do curl -sf http://127.0.0.1:8899/ > /dev/null && break; sleep 0.5; done
curl -s --cacert "$W/ca.pem" https://snapreel.video/api/health && echo " practice server answers for: $HOSTS"
