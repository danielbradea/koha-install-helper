#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STEP1_SCRIPT="${SCRIPT_DIR}/koha-step1.sh"
STEP2_SCRIPT="${SCRIPT_DIR}/koha-step2.sh"
STEP3_SCRIPT="${SCRIPT_DIR}/koha-step3.sh"
STEP4_SCRIPT="${SCRIPT_DIR}/koha-step4.sh"
STEP5_SCRIPT="${SCRIPT_DIR}/koha-step5.sh"

pause_menu() {
    echo
    read -r -p "Apasă Enter pentru a reveni la meniu..." _
}

run_step1() {
    echo
    echo "=== PASUL 1: Actualizare sistem și surse Koha ==="
    echo
    echo "Ramura implicită este: stable"
    echo "Exemple alternative: oldstable, 25.05"
    echo

    read -r -p "Introdu KOHA_SUITE [stable]: " koha_suite
    koha_suite="${koha_suite:-stable}"

    echo
    echo "Ai ales KOHA_SUITE=${koha_suite}"
    read -r -p "Continui? [D/n]: " confirm
    confirm="${confirm:-D}"

    case "${confirm}" in
        D|d|DA|Da|da|Y|y|YES|Yes|yes)
            ;;
        *)
            echo "Operațiune anulată."
            return 0
            ;;
    esac

    if [[ ! -f "${STEP1_SCRIPT}" ]]; then
        echo "EROARE: Nu găsesc scriptul:"
        echo "${STEP1_SCRIPT}"
        return 1
    fi

    chmod +x "${STEP1_SCRIPT}"

    echo
    echo "Pornesc pasul 1 cu KOHA_SUITE=${koha_suite}..."
    echo

    sudo env KOHA_SUITE="${koha_suite}" bash "${STEP1_SCRIPT}"
}

run_step2() {
    echo
    echo "=== PASUL 2: Instalare MySQL și Koha ==="
    echo
    echo "Acest pas instalează mysql-server, apache2 și koha-common."
    echo

    read -r -p "Continui? [D/n]: " confirm
    confirm="${confirm:-D}"

    case "${confirm}" in
        D|d|DA|Da|da|Y|y|YES|Yes|yes)
            ;;
        *)
            echo "Operațiune anulată."
            return 0
            ;;
    esac

    if [[ ! -f "${STEP2_SCRIPT}" ]]; then
        echo "EROARE: Nu găsesc scriptul:"
        echo "${STEP2_SCRIPT}"
        return 1
    fi

    chmod +x "${STEP2_SCRIPT}"

    echo
    echo "Pornesc pasul 2: MySQL + Koha..."
    echo

    sudo bash "${STEP2_SCRIPT}"
}

run_step3() {
    echo
    echo "=== PASUL 3: Configurare /etc/koha/koha-sites.conf ==="
    echo
    echo "Acest pas modifică setările implicite pentru instanțele Koha."
    echo "Se va crea automat backup înainte de modificare."
    echo

    confirm_continue || return 0

    if [[ ! -f "${STEP3_SCRIPT}" ]]; then
        echo "EROARE: Nu găsesc scriptul:"
        echo "${STEP3_SCRIPT}"
        return 1
    fi

    chmod +x "${STEP3_SCRIPT}"

    echo
    echo "Pornesc pasul 3: configurare Koha..."
    echo

    sudo bash "${STEP3_SCRIPT}"
}

run_step4() {
    echo
    echo "=== PASUL 4: Creare instanță Koha ==="
    echo
    echo "Acest pas face:"
    echo "- sudo koha-create --create-db nume_instanta"
    echo "- sudo koha-plack --enable nume_instanta"
    echo "- sudo koha-plack --start nume_instanta"
    echo "- sudo apache2ctl configtest"
    echo "- sudo systemctl restart apache2"
    echo

    confirm_continue || return 0

    run_script "${STEP4_SCRIPT}" "PASUL 4: Creare instanță Koha"
}

run_step5() {
    echo
    echo "=== PASUL 5: Traduceri Koha ==="
    echo
    echo "Acest pas listează și instalează traduceri Koha."
    echo "Default instalează: română, franceză și germană."
    echo

    confirm_continue || return 0

    run_script "${STEP5_SCRIPT}" "PASUL 5: Traduceri Koha"
}

while true; do
    clear
    echo "=========================================="
    echo "       INSTALARE KOHA - MENIU PRINCIPAL"
    echo "=========================================="
    echo
    echo "1) Actualizare Ubuntu și surse Koha"
    echo "2) Instalare MySQL și Koha"
    echo "3) Configurare /etc/koha/koha-sites.conf"
    echo "4) Creare instanță Koha"
    echo "5) Listeaza si instaleaza traduceri Koha"
    echo "0) Ieșire"
    echo

    read -r -p "Alege o opțiune: " option

    case "${option}" in
        1)
            run_step1
            pause_menu
            ;;
        2)
            run_step2
            pause_menu
            ;;
        3)
            run_step3
            pause_menu
            ;;
        4)
            run_step3
            pause_menu
            ;;
        5)
            run_step3
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

