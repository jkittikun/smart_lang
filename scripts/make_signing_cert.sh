#!/usr/bin/env bash
# Creates the free, self-signed "SmartLang Signing" code-signing certificate
# and adds it to your login keychain. Run it once, on your Mac.
#
# Why: macOS ties the Accessibility and Input Monitoring permissions to the
# certificate an app is signed with. Ad-hoc signed builds get a new identity
# every time, so the permissions have to be granted again after each update.
# Builds signed with this certificate keep them.
#
# Afterwards:
#   * ./scripts/build_app.sh signs with it automatically.
#   * Add the two GitHub secrets this script prints, so the Release workflow
#     signs with the same certificate (and in-app updates keep the permissions).
#
# The certificate and its password are also saved in ~/SmartLang-signing.
# Keep that folder safe (back it up, don't commit it): if you lose the
# certificate, the next version will need the permissions granted once more,
# and in-app updates won't accept it.
set -euo pipefail

NAME="SmartLang Signing"
DIR="$HOME/SmartLang-signing"
P12="$DIR/SmartLang-Signing.p12"
PWFILE="$DIR/password.txt"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

print_secrets() {
    echo
    echo "Add these two repository secrets on GitHub"
    echo "(Settings → Secrets and variables → Actions → New repository secret):"
    echo
    echo "  SMARTLANG_CERT_P12       the base64 text of $P12"
    echo "  SMARTLANG_CERT_PASSWORD  $(cat "$PWFILE")"
    echo
    if command -v pbcopy >/dev/null 2>&1; then
        base64 -i "$P12" | tr -d '\n' | pbcopy
        echo "The base64 text for SMARTLANG_CERT_P12 is on the clipboard now: paste it as the secret's value."
    else
        echo "Get the base64 text with:  base64 -i \"$P12\" | tr -d '\\n'"
    fi
}

if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$NAME\""; then
    echo "The \"$NAME\" certificate is already in your keychain."
    if [[ -f "$P12" && -f "$PWFILE" ]]; then
        print_secrets
    else
        echo "Its backup in $DIR is missing, so the GitHub secrets can't be printed."
        echo "To start over, delete \"$NAME\" (certificate and key) in Keychain Access and run this again."
    fi
    exit 0
fi

if [[ -e "$DIR" ]]; then
    echo "$DIR already exists. Move it away (or import $P12 into your keychain) and run this again."
    exit 1
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = SmartLang Signing

[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

echo "==> Creating the certificate (valid for 20 years)"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

PASSWORD="$(openssl rand -hex 16)"
LEGACY=()
# OpenSSL 3 (e.g. from Homebrew) needs -legacy for a .p12 that macOS can import.
if openssl version | grep -q '^OpenSSL 3'; then LEGACY=(-legacy); fi
openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$P12" -passout "pass:$PASSWORD"
printf '%s\n' "$PASSWORD" > "$PWFILE"
chmod 600 "$P12" "$PWFILE"

echo "==> Adding it to your login keychain"
security import "$P12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign

if ! security find-identity -p codesigning | grep -qF "\"$NAME\""; then
    echo "The certificate was imported but isn't listed as a code-signing identity."
    exit 1
fi
echo "Done. ./scripts/build_app.sh will now sign SmartLang with \"$NAME\"."
echo "(The first time, macOS may ask to let codesign use the key: click Always Allow.)"
print_secrets
