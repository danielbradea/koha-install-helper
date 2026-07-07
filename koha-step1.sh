#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Koha Production Installer - Pasul 1
# Actualizare Ubuntu + configurare sursă oficială de pachete Koha
# ============================================================

KOHA_SUITE="${KOHA_SUITE:-stable}"
KOHA_REPO_URL="https://debian.koha-community.org/koha"
KOHA_KEY_URL="${KOHA_REPO_URL}/gpg.asc"
KOHA_KEYRING="/usr/share/keyrings/koha-archive-keyring.gpg"
KOHA_SOURCE_FILE="/etc/apt/sources.list.d/koha.list"

log() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    printf '\nEROARE: %s\n' "$*" >&2
    exit 1
}

trap 'die "Scriptul s-a oprit la linia ${LINENO}."' ERR

if [[ "${EUID}" -ne 0 ]]; then
    die "Rulează acest script cu sudo."
fi

if [[ ! -r /etc/os-release ]]; then
    die "Nu pot identifica sistemul de operare."
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"debian"* ]]; then
    die "Acest script este destinat Ubuntu/Debian. Sistem detectat: ${PRETTY_NAME:-necunoscut}"
fi

export DEBIAN_FRONTEND=noninteractive

log "Sistem detectat: ${PRETTY_NAME}"
log "Ramura Koha selectată: ${KOHA_SUITE}"

log "Actualizez indexul pachetelor..."
apt-get update

log "Instalez actualizările disponibile..."
apt-get -y upgrade

log "Instalez dependențele necesare..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https

log "Creez directorul pentru cheile APT..."
install -d -m 0755 /usr/share/keyrings

log "Descarc cheia oficială Koha..."
curl -fsSL "${KOHA_KEY_URL}" \
    | gpg --dearmor --yes -o "${KOHA_KEYRING}"

chmod 0644 "${KOHA_KEYRING}"

log "Configurez repository-ul Koha..."
cat > "${KOHA_SOURCE_FILE}" <<EOF
deb [signed-by=${KOHA_KEYRING}] ${KOHA_REPO_URL} ${KOHA_SUITE} main
EOF

chmod 0644 "${KOHA_SOURCE_FILE}"

log "Actualizez indexul APT..."
apt-get update

log "Verific dacă pachetul koha-common este disponibil..."
if ! apt-cache show koha-common >/dev/null 2>&1; then
    die "Pachetul koha-common nu este disponibil pentru KOHA_SUITE=${KOHA_SUITE}."
fi

log "Curăț pachetele care nu mai sunt necesare..."
apt-get -y autoremove
apt-get clean

log "Pasul 1 finalizat cu succes."
echo
echo "Repository configurat:"
cat "${KOHA_SOURCE_FILE}"
echo
echo "Versiunea disponibilă:"
apt-cache policy koha-common
