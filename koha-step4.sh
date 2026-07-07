#!/usr/bin/env bash
set -Eeuo pipefail

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "EROARE: Rulează scriptul cu sudo:"
        echo "sudo bash $0"
        exit 1
    fi
}

check_command() {
    local cmd="$1"

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "EROARE: Comanda ${cmd} nu există."
        echo "Verifică dacă pachetul koha-common este instalat."
        exit 1
    fi
}

ask_library_name() {
    local name

    echo
    echo "=========================================="
    echo " CREARE INSTANȚĂ KOHA"
    echo "=========================================="
    echo
    echo "Exemplu nume librărie / instanță:"
    echo "biblioteca"
    echo "library"
    echo "uem"
    echo
    echo "ATENȚIE:"
    echo "- folosește litere mici"
    echo "- fără spații"
    echo "- fără caractere speciale"
    echo "- exemplu corect: biblioteca"
    echo

    while true; do
        read -r -p "Introdu numele librăriei / instanței Koha: " name

        if [[ -z "${name}" ]]; then
            echo "EROARE: Numele nu poate fi gol."
            continue
        fi

        if [[ ! "${name}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
            echo "EROARE: Nume invalid."
            echo "Folosește doar litere mici, cifre, minus sau underscore."
            echo "Exemplu corect: biblioteca"
            continue
        fi

        printf '%s' "${name}"
        return 0
    done
}

confirm_continue() {
    local confirm

    read -r -p "Continui? [D/n]: " confirm
    confirm="${confirm:-D}"

    case "${confirm}" in
        D|d|DA|Da|da|Y|y|YES|Yes|yes)
            return 0
            ;;
        *)
            echo "Operațiune anulată."
            exit 0
            ;;
    esac
}

require_root

check_command "koha-create"
check_command "koha-plack"
check_command "koha-list"
check_command "apache2ctl"
check_command "systemctl"

LIBRARY_NAME="$(ask_library_name)"

echo
echo "Ai ales instanța Koha:"
echo "${LIBRARY_NAME}"
echo

if [[ -d "/etc/koha/sites/${LIBRARY_NAME}" ]]; then
    echo "EROARE: Instanța Koha pare să existe deja:"
    echo "/etc/koha/sites/${LIBRARY_NAME}"
    echo
    echo "Instanțe existente:"
    sudo koha-list || true
    echo
    echo "Alege alt nume sau șterge/verifică instanța existentă."
    exit 1
fi

echo "Se vor executa comenzile:"
echo
echo "sudo koha-create --create-db ${LIBRARY_NAME}"
echo "sudo koha-plack --enable ${LIBRARY_NAME}"
echo "sudo koha-plack --start ${LIBRARY_NAME}"
echo "sudo apache2ctl configtest"
echo "sudo systemctl restart apache2"
echo

confirm_continue

echo
echo "=========================================="
echo " Creez instanța Koha: ${LIBRARY_NAME}"
echo "=========================================="
echo

sudo koha-create --create-db "${LIBRARY_NAME}"

echo
echo "=========================================="
echo " Activez Plack pentru: ${LIBRARY_NAME}"
echo "=========================================="
echo

sudo koha-plack --enable "${LIBRARY_NAME}"

echo
echo "=========================================="
echo " Pornesc Plack pentru: ${LIBRARY_NAME}"
echo "=========================================="
echo

sudo koha-plack --start "${LIBRARY_NAME}"

echo
echo "=========================================="
echo " Verific configurația Apache"
echo "=========================================="
echo

sudo apache2ctl configtest

echo
echo "=========================================="
echo " Restart Apache"
echo "=========================================="
echo

sudo systemctl restart apache2

echo
echo "=========================================="
echo " INSTANȚĂ KOHA CREATĂ"
echo "=========================================="
echo
echo "Nume instanță:"
echo "${LIBRARY_NAME}"
echo

echo "Instanțe Koha existente:"
sudo koha-list || true

echo
echo "Status Plack:"
sudo koha-plack --status "${LIBRARY_NAME}" || true

echo
echo "Fișier configurare instanță:"
echo "/etc/koha/sites/${LIBRARY_NAME}/koha-conf.xml"

echo
echo "Pentru a vedea baza de date, userul și parola:"
echo "sudo grep -n \"<database>\\|<user>\\|<pass>\" /etc/koha/sites/${LIBRARY_NAME}/koha-conf.xml"

echo
echo "Pentru a vedea site-urile Apache create:"
echo "ls -l /etc/apache2/sites-enabled/ | grep ${LIBRARY_NAME}"
echo
echo "Gata."
