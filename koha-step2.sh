#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Koha Production Installer - Pasul 2
# Instalare MySQL Server + Apache + koha-common
# ============================================================

MYSQL_SERVICE="${MYSQL_SERVICE:-mysql}"
KOHA_PACKAGE="${KOHA_PACKAGE:-koha-common}"
APACHE_SERVICE="${APACHE_SERVICE:-apache2}"

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
log "Pasul 2: instalare MySQL Server, Apache și ${KOHA_PACKAGE}"

if [[ ! -f /etc/apt/sources.list.d/koha.list ]]; then
    die "Nu găsesc /etc/apt/sources.list.d/koha.list. Rulează mai întâi koha-step1.sh."
fi

log "Actualizez indexul pachetelor..."
apt-get update

log "Verific dacă pachetul mysql-server este disponibil..."
if ! apt-cache show mysql-server >/dev/null 2>&1; then
    die "Pachetul mysql-server nu este disponibil pe acest sistem. Pe unele versiuni Debian pachetul implicit este MariaDB, dar acest script este pentru MySQL."
fi

log "Verific dacă pachetul ${KOHA_PACKAGE} este disponibil..."
if ! apt-cache show "${KOHA_PACKAGE}" >/dev/null 2>&1; then
    die "Pachetul ${KOHA_PACKAGE} nu este disponibil. Verifică pasul 1 și repository-ul Koha."
fi

if dpkg -l | awk '{print $2}' | grep -qx 'mariadb-server'; then
    die "mariadb-server este deja instalat. Nu continui ca să evit conflictul cu MySQL. Dezinstalează/planifică migrarea înainte."
fi

log "Instalez MySQL Server..."
apt-get install -y mysql-server

log "Pornește și activează serviciul MySQL..."
systemctl enable --now "${MYSQL_SERVICE}"
systemctl is-active --quiet "${MYSQL_SERVICE}"

log "Verific accesul local la MySQL ca root prin sudo..."
mysql -u root -e "SELECT VERSION() AS mysql_version;"

log "Instalez Apache și module utile pentru Koha..."
apt-get install -y apache2

a2enmod rewrite >/dev/null
if apache2ctl -M 2>/dev/null | grep -q 'mpm_event_module'; then
    log "Apache folosește mpm_event. Îl las activ; koha-common va instala/configura ce are nevoie."
fi

log "Instalez ${KOHA_PACKAGE}..."
apt-get install -y "${KOHA_PACKAGE}"

log "Activez serviciile necesare..."
systemctl enable --now "${APACHE_SERVICE}"

if systemctl list-unit-files | grep -q '^memcached.service'; then
    systemctl enable --now memcached || true
fi

log "Verific instalarea Koha..."
if ! command -v koha-create >/dev/null 2>&1; then
    die "Comanda koha-create nu a fost găsită după instalarea ${KOHA_PACKAGE}."
fi

log "Versiuni/pachete instalate:"
mysql --version
apt-cache policy mysql-server "${KOHA_PACKAGE}" | sed 's/^/  /'

log "Pasul 2 finalizat cu succes."
echo
echo "Următorul pas recomandat:"
echo "  1) configurează /etc/koha/koha-sites.conf în pasul 3"
echo "  2) creează instanța cu: sudo koha-create --create-db NUME_INSTANTA"
echo
echo "Exemplu:"
echo "  sudo koha-create --create-db biblioteca"
