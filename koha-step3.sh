#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="/etc/koha/koha-sites.conf"
PORTS_FILE="/etc/apache2/ports.conf"
APACHE_PORTS_BACKUP=""

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "EROARE: Rulează scriptul cu sudo:"
        echo "sudo bash $0"
        exit 1
    fi
}

get_current_value() {
    local key="$1"

    grep -E "^[[:space:]]*${key}=" "${CONFIG_FILE}" \
        | tail -n 1 \
        | cut -d '=' -f2- \
        | sed 's/^[[:space:]]*//; s/^"//; s/"[[:space:]]*$//' || true
}

ask_value() {
    local key="$1"
    local description="$2"
    local example="$3"
    local default_value="$4"
    local input

    echo >&2
    echo "${description}" >&2
    echo "Câmp: ${key}" >&2
    echo "Exemplu: ${key}=\"${example}\"" >&2

    if [[ -n "${default_value}" ]]; then
        read -r -p "Valoare [${default_value}] (- pentru gol): " input

        if [[ "${input}" == "-" ]]; then
            input=""
        elif [[ -z "${input}" ]]; then
            input="${default_value}"
        fi
    else
        read -r -p "Valoare [gol]: " input
    fi

    printf '%s' "${input}"
}

set_existing_config_value() {
    local key="$1"
    local value="$2"
    local escaped_value

    escaped_value="$(printf '%s' "${value}" | sed 's/[&|\\]/\\&/g')"

    if grep -qE "^[[:space:]]*${key}=" "${CONFIG_FILE}"; then
        sed -i \
            "s|^[[:space:]]*${key}=.*|${key}=\"${escaped_value}\"|" \
            "${CONFIG_FILE}"
    else
        echo "ATENȚIE: Nu am găsit câmpul ${key} în ${CONFIG_FILE}. Nu îl adaug."
    fi
}

validate_port() {
    local port="$1"
    local name="$2"

    if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
        echo "EROARE: ${name} trebuie să fie numeric."
        exit 1
    fi

    if (( port < 1 || port > 65535 )); then
        echo "EROARE: ${name} trebuie să fie între 1 și 65535."
        exit 1
    fi
}

validate_settings() {
    validate_port "${INTRAPORT}" "INTRAPORT"
    validate_port "${OPACPORT}" "OPACPORT"

    if [[ -z "${DOMAIN}" && "${INTRAPORT}" == "${OPACPORT}" ]]; then
        echo
        echo "EROARE: Pentru acces direct prin IP,"
        echo "INTRAPORT și OPACPORT trebuie să fie diferite."
        echo
        echo "Recomandat:"
        echo 'OPACPORT="80"'
        echo 'INTRAPORT="8080"'
        exit 1
    fi

    case "${ZEBRA_MARC_FORMAT}" in
        marc21|unimarc)
            ;;
        *)
            echo
            echo "EROARE: ZEBRA_MARC_FORMAT trebuie să fie marc21 sau unimarc."
            exit 1
            ;;
    esac

    case "${USE_MEMCACHED}" in
        yes|no)
            ;;
        *)
            echo
            echo "EROARE: USE_MEMCACHED trebuie să fie yes sau no."
            exit 1
            ;;
    esac
}

configure_apache_ports_for_ip() {
    if [[ -n "${DOMAIN}" ]]; then
        echo
        echo "DOMAIN nu este gol."
        echo "Nu modific ${PORTS_FILE} pentru acces direct pe IP."
        return 0
    fi

    echo
    echo "DOMAIN este gol."
    echo "Configurez Apache pentru acces prin IP."
    echo
    echo "OPAC:  port ${OPACPORT}"
    echo "Staff: port ${INTRAPORT}"

    if [[ ! -f "${PORTS_FILE}" ]]; then
        echo
        echo "ATENȚIE: Nu există ${PORTS_FILE}."
        echo "Nu pot modifica porturile Apache."
        return 0
    fi

    APACHE_PORTS_BACKUP="${PORTS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "${PORTS_FILE}" "${APACHE_PORTS_BACKUP}"

    echo
    echo "Backup Apache creat:"
    echo "${APACHE_PORTS_BACKUP}"

    if ! grep -qE \
        "^[[:space:]]*Listen[[:space:]]+${OPACPORT}([[:space:]]|$)" \
        "${PORTS_FILE}"; then

        echo "Listen ${OPACPORT}" >> "${PORTS_FILE}"
        echo "Adăugat: Listen ${OPACPORT}"
    else
        echo "Există deja: Listen ${OPACPORT}"
    fi

    if ! grep -qE \
        "^[[:space:]]*Listen[[:space:]]+${INTRAPORT}([[:space:]]|$)" \
        "${PORTS_FILE}"; then

        if grep -qE \
            "^[[:space:]]*Listen[[:space:]]+${OPACPORT}[[:space:]]*$" \
            "${PORTS_FILE}"; then

            sed -i \
                "/^[[:space:]]*Listen[[:space:]]\+${OPACPORT}[[:space:]]*$/a Listen ${INTRAPORT}" \
                "${PORTS_FILE}"
        else
            echo "Listen ${INTRAPORT}" >> "${PORTS_FILE}"
        fi

        echo "Adăugat: Listen ${INTRAPORT}"
    else
        echo "Există deja: Listen ${INTRAPORT}"
    fi

    echo
    echo "Porturi Apache:"
    echo "------------------------------------------"
    grep -E "^[[:space:]]*Listen[[:space:]]+" "${PORTS_FILE}" || true
    echo "------------------------------------------"
}

apache_config_test() {
    echo
    echo "Verificare configurație Apache..."

    if apache2ctl configtest; then
        echo
        echo "Apache: configurație OK."
        return 0
    fi

    echo
    echo "EROARE: Configurația Apache nu este validă."

    if [[ -n "${APACHE_PORTS_BACKUP}" && -f "${APACHE_PORTS_BACKUP}" ]]; then
        echo
        echo "Restaurez automat backup-ul Apache:"
        echo "${APACHE_PORTS_BACKUP}"

        cp -a "${APACHE_PORTS_BACKUP}" "${PORTS_FILE}"

        echo
        echo "Verific din nou Apache..."

        if apache2ctl configtest; then
            echo "Rollback reușit."
        else
            echo "ATENȚIE: Apache continuă să raporteze o eroare."
        fi
    fi

    exit 1
}

require_root

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "EROARE: Nu există fișierul:"
    echo "${CONFIG_FILE}"
    echo
    echo "Instalează întâi koha-common."
    exit 1
fi

BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "${CONFIG_FILE}" "${BACKUP_FILE}"

echo "Backup creat:"
echo "${BACKUP_FILE}"

echo
echo "=========================================="
echo " CONFIGURARE /etc/koha/koha-sites.conf"
echo "=========================================="
echo
echo "Se vor modifica DOAR câmpurile existente."
echo "Nu se adaugă câmpuri noi."
echo
echo "Default pentru acces prin IP:"
echo 'DOMAIN=""'
echo 'INTRAPORT="8080"'
echo 'OPACPORT="80"'
echo

CURRENT_ZEBRA_MARC_FORMAT="$(get_current_value ZEBRA_MARC_FORMAT)"
CURRENT_ZEBRA_LANGUAGE="$(get_current_value ZEBRA_LANGUAGE)"
CURRENT_USE_MEMCACHED="$(get_current_value USE_MEMCACHED)"
CURRENT_MEMCACHED_SERVERS="$(get_current_value MEMCACHED_SERVERS)"
CURRENT_MEMCACHED_PREFIX="$(get_current_value MEMCACHED_PREFIX)"

DOMAIN="$(
    ask_value \
        "DOMAIN" \
        "Domeniul pentru instanțele Koha. Lasă gol dacă folosești doar IP." \
        ".domain.com" \
        ""
)"

INTRAPORT="$(
    ask_value \
        "INTRAPORT" \
        "Portul pentru interfața bibliotecarului / staff client." \
        "8080" \
        "8080"
)"

INTRAPREFIX="$(
    ask_value \
        "INTRAPREFIX" \
        "Prefix pentru interfața staff. Pentru IP simplu, lasă gol." \
        "" \
        ""
)"

INTRASUFFIX="$(
    ask_value \
        "INTRASUFFIX" \
        "Suffix pentru interfața staff. De obicei se lasă gol." \
        "" \
        ""
)"

OPACPORT="$(
    ask_value \
        "OPACPORT" \
        "Portul pentru OPAC, adică interfața publică." \
        "80" \
        "80"
)"

OPACPREFIX="$(
    ask_value \
        "OPACPREFIX" \
        "Prefix pentru OPAC. Pentru IP simplu, lasă gol." \
        "" \
        ""
)"

OPACSUFFIX="$(
    ask_value \
        "OPACSUFFIX" \
        "Suffix pentru OPAC. De obicei se lasă gol." \
        "" \
        ""
)"

DEFAULTSQL="$(
    ask_value \
        "DEFAULTSQL" \
        "Fișier SQL cu date implicite. De obicei se lasă gol." \
        "/cale/date.sql" \
        ""
)"

ZEBRA_MARC_FORMAT="$(
    ask_value \
        "ZEBRA_MARC_FORMAT" \
        "Format MARC pentru indexare. Valori: marc21 sau unimarc." \
        "marc21" \
        "${CURRENT_ZEBRA_MARC_FORMAT:-marc21}"
)"

ZEBRA_LANGUAGE="$(
    ask_value \
        "ZEBRA_LANGUAGE" \
        "Limba principală pentru Zebra indexing." \
        "en" \
        "${CURRENT_ZEBRA_LANGUAGE:-en}"
)"

USE_MEMCACHED="$(
    ask_value \
        "USE_MEMCACHED" \
        "Folosește memcached pentru Koha. Valori: yes sau no." \
        "yes" \
        "${CURRENT_USE_MEMCACHED:-yes}"
)"

MEMCACHED_SERVERS="$(
    ask_value \
        "MEMCACHED_SERVERS" \
        "Server memcached în format IP:port." \
        "127.0.0.1:11211" \
        "${CURRENT_MEMCACHED_SERVERS:-127.0.0.1:11211}"
)"

MEMCACHED_PREFIX="$(
    ask_value \
        "MEMCACHED_PREFIX" \
        "Prefix namespace memcached pentru Koha." \
        "koha_" \
        "${CURRENT_MEMCACHED_PREFIX:-koha_}"
)"

validate_settings

echo
echo "=========================================="
echo " Configurație aleasă"
echo "=========================================="
echo "DOMAIN=\"${DOMAIN}\""
echo "INTRAPORT=\"${INTRAPORT}\""
echo "INTRAPREFIX=\"${INTRAPREFIX}\""
echo "INTRASUFFIX=\"${INTRASUFFIX}\""
echo "OPACPORT=\"${OPACPORT}\""
echo "OPACPREFIX=\"${OPACPREFIX}\""
echo "OPACSUFFIX=\"${OPACSUFFIX}\""
echo "DEFAULTSQL=\"${DEFAULTSQL}\""
echo "ZEBRA_MARC_FORMAT=\"${ZEBRA_MARC_FORMAT}\""
echo "ZEBRA_LANGUAGE=\"${ZEBRA_LANGUAGE}\""
echo "USE_MEMCACHED=\"${USE_MEMCACHED}\""
echo "MEMCACHED_SERVERS=\"${MEMCACHED_SERVERS}\""
echo "MEMCACHED_PREFIX=\"${MEMCACHED_PREFIX}\""
echo

read -r -p "Scriu aceste valori în ${CONFIG_FILE}? [D/n]: " confirm
confirm="${confirm:-D}"

case "${confirm}" in
    D|d|DA|Da|da|Y|y|YES|Yes|yes)
        ;;
    *)
        echo
        echo "Operațiune anulată."
        echo "Backupul rămâne aici:"
        echo "${BACKUP_FILE}"
        exit 0
        ;;
esac

set_existing_config_value "DOMAIN" "${DOMAIN}"
set_existing_config_value "INTRAPORT" "${INTRAPORT}"
set_existing_config_value "INTRAPREFIX" "${INTRAPREFIX}"
set_existing_config_value "INTRASUFFIX" "${INTRASUFFIX}"
set_existing_config_value "OPACPORT" "${OPACPORT}"
set_existing_config_value "OPACPREFIX" "${OPACPREFIX}"
set_existing_config_value "OPACSUFFIX" "${OPACSUFFIX}"
set_existing_config_value "DEFAULTSQL" "${DEFAULTSQL}"
set_existing_config_value "ZEBRA_MARC_FORMAT" "${ZEBRA_MARC_FORMAT}"
set_existing_config_value "ZEBRA_LANGUAGE" "${ZEBRA_LANGUAGE}"
set_existing_config_value "USE_MEMCACHED" "${USE_MEMCACHED}"
set_existing_config_value "MEMCACHED_SERVERS" "${MEMCACHED_SERVERS}"
set_existing_config_value "MEMCACHED_PREFIX" "${MEMCACHED_PREFIX}"

configure_apache_ports_for_ip
apache_config_test

echo
echo "=========================================="
echo " Configurarea a fost salvată"
echo "=========================================="
echo
echo "${CONFIG_FILE}"

echo
echo "Backup koha-sites.conf:"
echo "${BACKUP_FILE}"

if [[ -n "${APACHE_PORTS_BACKUP}" ]]; then
    echo
    echo "Backup Apache ports.conf:"
    echo "${APACHE_PORTS_BACKUP}"
fi

echo
echo "Conținut actual:"
echo "------------------------------------------"

grep -E \
'^(DOMAIN|INTRAPORT|INTRAPREFIX|INTRASUFFIX|OPACPORT|OPACPREFIX|OPACSUFFIX|DEFAULTSQL|ZEBRA_MARC_FORMAT|ZEBRA_LANGUAGE|USE_MEMCACHED|MEMCACHED_SERVERS|MEMCACHED_PREFIX)=' \
"${CONFIG_FILE}" || true

echo "------------------------------------------"

echo
echo "Gata."