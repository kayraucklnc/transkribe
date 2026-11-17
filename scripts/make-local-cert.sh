#!/usr/bin/env bash
# Creates a self-signed code-signing certificate, "Transkribe Local", in your login keychain, once.
# scripts/build-app.sh signs with it, so macOS recognizes each new build as the same app and keeps
# its permissions. It stays on this Mac and can only sign apps you build here.
set -euo pipefail

NAME="Transkribe Local"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "✓ \"$NAME\" already exists"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CONF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -out "$WORK/cert.p12" -passout "pass:$PASS" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
       -out "$WORK/cert.p12" -passout "pass:$PASS"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
# Trust it for code signing (macOS asks for your password once).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
echo "✓ Created \"$NAME\". Rebuild with scripts/build-app.sh --install, allow permissions one last time."
