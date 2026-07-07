#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_LANGUAGES="ro-RO fr-FR de-DE"

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

pause_menu() {
    echo
    read -r -p "Apasă Enter pentru a continua..." _
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
            return 1
            ;;
    esac
}

list_languages() {
    echo
    echo "=========================================="
    echo " LIMBI DISPONIBILE KOHA"
    echo "=========================================="
    echo

    echo "Rulez:"
    echo "sudo koha-translate --list"
    echo

    sudo koha-translate --list || {
        echo
        echo "Dacă --list nu funcționează pe versiunea ta, încearcă manual:"
        echo "sudo koha-translate --help"
        return 1
    }
}

install_languages() {
    local languages

    echo
    echo "=========================================="
    echo " INSTALARE TRADUCERI KOHA"
    echo "=========================================="
    echo
    echo "Default se instalează:"
    echo "${DEFAULT_LANGUAGES}"
    echo
    echo "Exemple:"
    echo "ro-RO"
    echo "ro-RO fr-FR de-DE"
    echo "it-IT es-ES"
    echo

    read -r -p "Introdu limbile de instalat [${DEFAULT_LANGUAGES}]: " languages
    languages="${languages:-$DEFAULT_LANGUAGES}"

    echo
    echo "Se vor instala traducerile:"
    echo "${languages}"
    echo

    echo "Comanda:"
    echo "sudo koha-translate --install ${languages}"
    echo

    confirm_continue || return 0

    echo
    echo "=========================================="
    echo " Instalez traduceri"
    echo "=========================================="
    echo

    sudo koha-translate --install ${languages}

    echo
    echo "Traducerile au fost instalate."
    echo

    echo "Recomandat: repornește serviciile Koha/Apache."
    echo "Rulez acum:"
    echo "sudo systemctl restart apache2"
    echo

    sudo systemctl restart apache2

    echo
    echo "Gata."
}

require_root
check_command "koha-translate"
check_command "systemctl"

while true; do
    clear
    echo "=========================================="
    echo "       KOHA - TRADUCERI"
    echo "=========================================="
    echo
    echo "1) Listează limbile disponibile"
    echo "2) Instalează traduceri"
    echo "0) Înapoi / Ieșire"
    echo

    read -r -p "Alege o opțiune: " option

    case "${option}" in
        1)
            list_languages
            pause_menu
            ;;
        2)
            install_languages
            pause_menu
            ;;
        0)
            echo "Ieșire."
            exit 0
            ;;
        *)
            echo "Opțiune invalidă."
            pause_menu
            ;;
    esac
done
