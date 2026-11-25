#!/bin/bash
# Cuts this runner off from Snapreel's real services and, unless told "off", answers for them with the practice
# server. Fails (and with it the session) unless every host is proven to be cut off, so a tester can never reach
# the real service. Usage: start_stub.sh APP_SOURCE_DIR WORK_DIR stub|off
# Leaves WORK_DIR/ca.pem for the simulators to trust.
set -euo pipefail
SRC="$1"; W="$2"; MODE="$3"; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$W"
# Every Supabase project named anywhere in the app (a comment's made-up one too: harmless), and its storage host.
REFS=$(grep -rhoE '[a-z0-9]{20}\.supabase\.co' "$SRC/Snapreel" "$SRC/Shared" "$SRC/SnapreelBroadcast" "$SRC/SnapreelLiveActivity" --include=*.swift \
  | sed 's/\.supabase\.co//' | sort -u)
[ -n "$REFS" ] || { echo "no Supabase project found in the app's source: the practice server no longer fits the app"; exit 1; }
HOSTS="snapreel.video www.snapreel.video snapreel-push.vercel.app"
for r in $REFS; do HOSTS="$HOSTS $r.supabase.co $r.storage.supabase.co"; done
# Any other host of ours that the source calls.
for h in $(grep -rhoE 'https://[A-Za-z0-9.-]+' "$SRC/Snapreel" "$SRC/Shared" --include=*.swift | sed 's#https://##' | grep -E 'snapreel|vercel|supabase|arclayer' | sort -u); do
  case " $HOSTS " in *" $h "*) ;; *) HOSTS="$HOSTS $h" ;; esac
done
# The real address, for terms, privacy and other plain pages (before /etc/hosts changes it).
SITE_IP=$(dig +short snapreel.video A | grep -E '^[0-9.]+$' | head -1 || true)
for h in $HOSTS; do printf '127.0.0.1 %s\n::1 %s\n' "$h" "$h" | sudo tee -a /etc/hosts > /dev/null; done
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true
sleep 1
for h in $HOSTS; do
  for ip in $(dscacheutil -q host -a name "$h" | awk '/address:/ { print $2 }'); do
    case "$ip" in 127.0.0.1|::1) ;; *) echo "$h still resolves to $ip"; exit 1 ;; esac
  done
  dscacheutil -q host -a name "$h" | grep -q '127.0.0.1' || { echo "$h is not redirected"; exit 1; }
done
echo "cut off: $HOSTS"
[ "$MODE" = "stub" ] || exit 0

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
sudo nohup python3 "$HERE/cloud_stub.py" --cert "$W/leaf.pem" --key "$W/leaf.key" --site-ip "$SITE_IP" > "$W/stub.log" 2>&1 &
for _ in $(seq 1 40); do curl -sf http://127.0.0.1:8899/ > /dev/null && break; sleep 0.5; done
for h in $HOSTS; do
  curl -s --max-time 20 --cacert "$W/ca.pem" -D - -o /dev/null "https://$h/auth/v1/settings" | grep -qi '^x-practice-server: yes' \
    || { echo "$h is not answered by the practice server"; exit 1; }
done
echo "the practice server answers for all of them"
