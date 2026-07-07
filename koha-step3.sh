#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="/etc/koha/koha-sites.conf"

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
        | sed 's/^[[:space:]]*//; s/^"//; s/"[[:space:]]*$//'
}

ask_value() {
    local key="$1"
    local description="$2"
    local example="$3"
    local default_value="$4"
    local input

    echo
    echo "${description}"
    echo "Câmp: ${key}"
    echo "Exemplu: ${key}=\"${example}\""

    if [[ -n "${default_value}" ]]; then
        read -r -p "Valoare [${default_value}]: " input
        input="${input:-$default_value}"
    else
        read -r -p "Valoare [gol]: " input
    fi

    printf '%s' "${input}"
}

set_existing_config_value() {
    local key="$1"
    local value="$2"

    if grep -qE "^[[:space:]]*${key}=" "${CONFIG_FILE}"; then
        sed -i "s|^[[:space:]]*${key}=.*|${key}=\"${value}\"|" "${CONFIG_FILE}"
    else
        echo "ATENȚIE: Nu am găsit câmpul ${key} în ${CONFIG_FILE}. Nu îl adaug."
    fi
}

configure_apache_ports_for_ip() {
    local ports_file="/etc/apache2/ports.conf"

    if [[ -n "${DOMAIN}" ]]; then
        echo
        echo "DOMAIN nu este gol, deci nu modific /etc/apache2/ports.conf pentru acces pe IP."
        return 0
    fi

    echo
    echo "DOMAIN este gol, deci configurez Apache pentru acces pe IP."
    echo "Trebuie să existe în ${ports_file}:"
    echo "Listen ${OPACPORT}"
    echo "Listen ${INTRAPORT}"

    if [[ ! -f "${ports_file}" ]]; then
        echo "ATENȚIE: Nu există ${ports_file}. Nu pot modifica porturile Apache."
        return 0
    fi

    local ports_backup="${ports_file}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "${ports_file}" "${ports_backup}"

    echo
    echo "Backup creat pentru Apache ports.conf:"
    echo "${ports_backup}"

    if ! grep -qE "^[[:space:]]*Listen[[:space:]]+${OPACPORT}([[:space:]]|$)" "${ports_file}"; then
        echo "Listen ${OPACPORT}" >> "${ports_file}"
        echo "Adăugat: Listen ${OPACPORT}"
    else
        echo "Există deja: Listen ${OPACPORT}"
    fi

    if ! grep -qE "^[[:space:]]*Listen[[:space:]]+${INTRAPORT}([[:space:]]|$)" "${ports_file}"; then
        if grep -qE "^[[:space:]]*Listen[[:space:]]+${OPACPORT}([[:space:]]|$)" "${ports_file}"; then
            sed -i "/^[[:space:]]*Listen[[:space:]]\+${OPACPORT}[[:space:]]*$/a Listen ${INTRAPORT}" "${ports_file}"
        else
            echo "Listen ${INTRAPORT}" >> "${ports_file}"
        fi

        echo "Adăugat: Listen ${INTRAPORT}"
    else
        echo "Există deja: Listen ${INTRAPORT}"
    fi

    echo
    echo "Verificare /etc/apache2/ports.conf:"
    echo "------------------------------------------"
    grep -E "^[[:space:]]*Listen[[:space:]]+" "${ports_file}" || true
    echo "------------------------------------------"
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
echo "Se vor modifica DOAR câmpurile existente din lista standard."
echo "Nu se adaugă câmpuri noi."
echo
echo "Pentru IP simplu, lasă:"
echo "DOMAIN=\"\""
echo
echo "Pentru domeniu, exemplu:"
echo "DOMAIN=\".domain.com\""
echo

CURRENT_DOMAIN="$(get_current_value DOMAIN)"
CURRENT_INTRAPORT="$(get_current_value INTRAPORT)"
CURRENT_INTRAPREFIX="$(get_current_value INTRAPREFIX)"
CURRENT_INTRASUFFIX="$(get_current_value INTRASUFFIX)"
CURRENT_OPACPORT="$(get_current_value OPACPORT)"
CURRENT_OPACPREFIX="$(get_current_value OPACPREFIX)"
CURRENT_OPACSUFFIX="$(get_current_value OPACSUFFIX)"
CURRENT_DEFAULTSQL="$(get_current_value DEFAULTSQL)"
CURRENT_ZEBRA_MARC_FORMAT="$(get_current_value ZEBRA_MARC_FORMAT)"
CURRENT_ZEBRA_LANGUAGE="$(get_current_value ZEBRA_LANGUAGE)"
CURRENT_USE_MEMCACHED="$(get_current_value USE_MEMCACHED)"
CURRENT_MEMCACHED_SERVERS="$(get_current_value MEMCACHED_SERVERS)"
CURRENT_MEMCACHED_PREFIX="$(get_current_value MEMCACHED_PREFIX)"

DOMAIN="$(ask_value "DOMAIN" "Domeniul pentru instanțele Koha. Lasă gol dacă folosești doar IP." ".domain.com" "${CURRENT_DOMAIN:-}")"

INTRAPORT="$(ask_value "INTRAPORT" "Portul pentru interfața bibliotecarului / staff client." "8080" "${CURRENT_INTRAPORT:-8080}")"

INTRAPREFIX="$(ask_value "INTRAPREFIX" "Prefix pentru interfața staff. Pentru IP simplu, lasă gol." "" "${CURRENT_INTRAPREFIX:-}")"

INTRASUFFIX="$(ask_value "INTRASUFFIX" "Suffix pentru interfața staff. De obicei se lasă gol." "" "${CURRENT_INTRASUFFIX:-}")"

OPACPORT="$(ask_value "OPACPORT" "Portul pentru OPAC, adică interfața publică." "80" "${CURRENT_OPACPORT:-80}")"

OPACPREFIX="$(ask_value "OPACPREFIX" "Prefix pentru OPAC. Pentru IP simplu, lasă gol." "" "${CURRENT_OPACPREFIX:-}")"

OPACSUFFIX="$(ask_value "OPACSUFFIX" "Suffix pentru OPAC. De obicei se lasă gol." "" "${CURRENT_OPACSUFFIX:-}")"

DEFAULTSQL="$(ask_value "DEFAULTSQL" "Fișier SQL cu date implicite. De obicei se lasă gol." "/cale/date.sql" "${CURRENT_DEFAULTSQL:-}")"

ZEBRA_MARC_FORMAT="$(ask_value "ZEBRA_MARC_FORMAT" "Format MARC pentru indexare. Valori acceptate: marc21 sau unimarc." "marc21" "${CURRENT_ZEBRA_MARC_FORMAT:-marc21}")"

ZEBRA_LANGUAGE="$(ask_value "ZEBRA_LANGUAGE" "Limba principală pentru Zebra indexing. Valori uzuale: en, fr, es." "en" "${CURRENT_ZEBRA_LANGUAGE:-en}")"

USE_MEMCACHED="$(ask_value "USE_MEMCACHED" "Folosește memcached pentru instanța Koha. Valori: yes sau no." "yes" "${CURRENT_USE_MEMCACHED:-yes}")"

MEMCACHED_SERVERS="$(ask_value "MEMCACHED_SERVERS" "Server memcached în format ip:port." "127.0.0.1:11211" "${CURRENT_MEMCACHED_SERVERS:-127.0.0.1:11211}")"

MEMCACHED_PREFIX="$(ask_value "MEMCACHED_PREFIX" "Prefix namespace memcached pentru Koha." "koha_" "${CURRENT_MEMCACHED_PREFIX:-koha_}")"

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

echo
echo "Configurarea a fost salvată în:"
echo "${CONFIG_FILE}"

echo
echo "Backup:"
echo "${BACKUP_FILE}"

echo
echo "Conținut actual modificat:"
echo "------------------------------------------"
grep -E '^(DOMAIN|INTRAPORT|INTRAPREFIX|INTRASUFFIX|OPACPORT|OPACPREFIX|OPACSUFFIX|DEFAULTSQL|ZEBRA_MARC_FORMAT|ZEBRA_LANGUAGE|USE_MEMCACHED|MEMCACHED_SERVERS|MEMCACHED_PREFIX)=' "${CONFIG_FILE}" || true
echo "------------------------------------------"

echo
echo "Verificare Apache:"
apache2ctl configtest || true

echo
echo "Gata."

