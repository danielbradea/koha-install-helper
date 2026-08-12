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
        echo "Verifică dacă pachetul necesar este instalat."
        exit 1
    fi
}

ask_library_name() {
    echo
    echo "=========================================="
    echo " CREARE INSTANȚĂ KOHA"
    echo "=========================================="
    echo
    echo "Exemplu nume librărie / instanță:"
    echo "biblioteca"
    echo "library"
    echo
    echo "ATENȚIE:"
    echo "- folosește litere mici"
    echo "- fără spații"
    echo "- fără caractere speciale"
    echo "- sunt permise doar litere mici și cifre"
    echo "- exemplu corect: biblioteca"
    echo

    while true; do
        read -r -p "Introdu numele librăriei / instanței Koha: " LIBRARY_NAME

        if [[ -z "${LIBRARY_NAME}" ]]; then
            echo
            echo "EROARE: Numele nu poate fi gol."
            echo
            continue
        fi

        if [[ ! "${LIBRARY_NAME}" =~ ^[a-z0-9]+$ ]]; then
            echo
            echo "EROARE: Numele instanței nu este valid."
            echo "Folosește doar:"
            echo "- litere mici a-z"
            echo "- cifre 0-9"
            echo
            echo "Exemplu corect:"
            echo "biblioteca"
            echo
            continue
        fi

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
            echo
            echo "Operațiune anulată."
            exit 0
            ;;
    esac
}

# ==========================================================
# VERIFICĂRI INIȚIALE
# ==========================================================

require_root

check_command "apache2ctl"
check_command "systemctl"
check_command "a2enmod"

# ==========================================================
# NUME INSTANȚĂ
# ==========================================================

LIBRARY_NAME=""
ask_library_name

echo
echo "Ai ales instanța Koha:"
echo "${LIBRARY_NAME}"
echo

# ==========================================================
# VERIFICARE DACĂ INSTANȚA EXISTĂ
# ==========================================================

if [[ -d "/etc/koha/sites/${LIBRARY_NAME}" ]]; then
    echo "EROARE: Instanța Koha există deja:"
    echo "/etc/koha/sites/${LIBRARY_NAME}"
    echo
    echo "Instanțe existente:"
    koha-list || true
    echo
    echo "Alege alt nume sau verifică instanța existentă."
    exit 1
fi

if koha-list 2>/dev/null | grep -Fxq "${LIBRARY_NAME}"; then
    echo "EROARE: Instanța '${LIBRARY_NAME}' apare deja în koha-list."
    echo
    koha-list || true
    exit 1
fi

# ==========================================================
# CONFIGURARE APACHE
# ==========================================================

echo
echo "=========================================="
echo " CONFIGURARE APACHE"
echo "=========================================="
echo

echo "Activez modul CGI..."
a2enmod cgi

echo
echo "Activez modul rewrite..."
a2enmod rewrite

echo
echo "Activez modul headers..."
a2enmod headers

echo
echo "Verific configurația Apache..."
echo

if ! apache2ctl configtest; then
    echo
    echo "EROARE: Configurația Apache nu este validă."
    exit 1
fi

echo
echo "Restart Apache..."
systemctl restart apache2

echo
echo "Apache configurat."
echo

# ==========================================================
# CONFIRMARE
# ==========================================================

echo "=========================================="
echo " COMENZI CARE VOR FI EXECUTATE"
echo "=========================================="
echo
echo "koha-create --create-db ${LIBRARY_NAME}"
echo "koha-plack --enable ${LIBRARY_NAME}"
echo "koha-plack --start ${LIBRARY_NAME}"
echo "apache2ctl configtest"
echo "systemctl restart apache2"
echo

confirm_continue

# ==========================================================
# CREARE INSTANȚĂ
# ==========================================================

echo
echo "=========================================="
echo " CREARE INSTANȚĂ KOHA"
echo "=========================================="
echo
echo "Creez instanța:"
echo "${LIBRARY_NAME}"
echo

koha-create --create-db "${LIBRARY_NAME}"

echo
echo "Instanța a fost creată."
echo

# ==========================================================
# ACTIVARE PLACK
# ==========================================================

echo "=========================================="
echo " ACTIVARE PLACK"
echo "=========================================="
echo

echo "Activez Plack pentru ${LIBRARY_NAME}..."
koha-plack --enable "${LIBRARY_NAME}"

echo
echo "Pornesc Plack pentru ${LIBRARY_NAME}..."
koha-plack --start "${LIBRARY_NAME}"

echo
echo "Plack pornit."
echo

# ==========================================================
# VERIFICARE APACHE DUPĂ CREAREA INSTANȚEI
# ==========================================================

echo "=========================================="
echo " VERIFICARE APACHE"
echo "=========================================="
echo

if ! apache2ctl configtest; then
    echo
    echo "EROARE: Configurația Apache nu este validă"
    echo "după crearea instanței Koha."
    exit 1
fi

echo
echo "Configurația Apache este OK."

echo
echo "Restart Apache..."
systemctl restart apache2

# ==========================================================
# STATUS FINAL
# ==========================================================

echo
echo "=========================================="
echo " INSTANȚĂ KOHA CREATĂ CU SUCCES"
echo "=========================================="
echo

echo "Nume instanță:"
echo "${LIBRARY_NAME}"
echo

echo "Instanțe Koha existente:"
koha-list || true

echo
echo "Status Plack:"
koha-plack --status "${LIBRARY_NAME}" || true

echo
echo "Fișier configurare instanță:"
echo "/etc/koha/sites/${LIBRARY_NAME}/koha-conf.xml"

echo
echo "Pentru a vedea baza de date, userul și parola:"
echo "grep -n \"<database>\\|<user>\\|<pass>\" /etc/koha/sites/${LIBRARY_NAME}/koha-conf.xml"

echo
echo "Site-uri Apache pentru această instanță:"
ls -l /etc/apache2/sites-enabled/ | grep "${LIBRARY_NAME}" || true

echo
echo "Porturi Apache:"
grep -E '^[[:space:]]*Listen[[:space:]]+' /etc/apache2/ports.conf || true

SERVER_IP="$(hostname -I | awk '{print $1}')"

echo
echo "=========================================="
echo " ACCES KOHA"
echo "=========================================="
echo
echo "Dacă ai configurat:"
echo 'DOMAIN=""'
echo 'OPACPORT="80"'
echo 'INTRAPORT="8080"'
echo
echo "OPAC:"
echo "http://${SERVER_IP}/"
echo
echo "Staff:"
echo "http://${SERVER_IP}:8080/"
echo

echo "Gata."