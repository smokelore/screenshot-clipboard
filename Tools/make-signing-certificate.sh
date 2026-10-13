#!/bin/zsh
# Creates the self-signed certificate build.sh signs with, so macOS remembers the app's permissions across rebuilds.
set -euo pipefail
name="Screenshot Clipboard Local Signing"
if security find-certificate -c "$name" >/dev/null 2>&1; then
  echo "\"$name\" is already in your keychain."
  exit 0
fi

umask 077
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
password=$(/usr/bin/openssl rand -hex 16)
cat > "$dir/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
# macOS's own LibreSSL, not a Homebrew OpenSSL 3, whose default .p12 encryption `security import` may reject.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cert.cnf" \
  -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$name" \
  -out "$dir/identity.p12" -passout pass:"$password" 2>/dev/null
security import "$dir/identity.p12" -k ~/Library/Keychains/login.keychain-db -P "$password" -T /usr/bin/codesign >/dev/null
echo "Added \"$name\" to your login keychain. Run ./build.sh --install to use it."
