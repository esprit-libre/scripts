#!/bin/bash

## Links by dates for readability of rsnapshot folders
#
# version 1.0.0 - 27/04/2017
#
# This script create links for rsnapshot sub-directories replacing daily.0
# by the date of creation of this folder.
#
# Usage:
#  `./rsnapshot-date-link.sh -l LINKS_PATH -r RSNAPSHOT_PATH [-d DEEP] [-v]
#  `./rsnapshot-date-link.sh --links LINKS_PATH --rsnap RSNAPSHOT_PATH [--deep DEEP] [--verbose]
#
# Examples:
# `./rsnapshot-date-link.sh -l /home/user/links -r /data/user/rsnapshot -v -d 3
##

function main() {
    echo -e '\033[1m#Starting rsnapshot links by date\033[0m'
    echo "-- "$(date +%F-%H-%M-%S)" --"
    echo "-----------------------------------"

    # dependencies
    DEPS=( rsync ) # sudo
    check_dependencies

	# Reading vars
    read_vars "$@"

	# Old links deletion
	clean_links

	# New links creation
	create_links
}

function check_dependencies() {
    echo -e '\033[1m#-- check dependencies\033[0m'

    for dep in "${DEPS[@]}"; do
        if [ ! "$(command -v $dep)" ]; then
            echo '[ERROR] Missing dependency: '$dep
            exit 1
        fi
    done

    return 0
}

function read_vars() {
    echo -e '\033[1m#-- read vars\033[0m'

    LINKS_PATH=""
    RSNAPSHOT_PATH=""
    DEEP=0
    LOG='false'

    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -l|--links)
            if [ -d "$2" ] && [ -w "$2" ]; then
                # ${VAR//ab/yz} replace all sub-chains 'ab' from VAR by 'yz'
                LINKS_PATH="${2}/"
                LINKS_PATH="${LINKS_PATH//'//'//}"
            else
                echo "[ERROR] Invalid LINKS_PATH dir : "$2
                exit 1
            fi
            shift
            ;;
        -r|--rsnap)
            if [ -d "$2" ]; then
                # ${VAR//ab/yz} replace all sub-chains 'ab' from VAR by 'yz'
                RSNAPSHOT_PATH="${2}/"
                RSNAPSHOT_PATH="${RSNAPSHOT_PATH//'//'//}"
            else
                echo "[ERROR] Invalid RSNAPSHOT_PATH dir : "$2
                exit 1
            fi
            shift
            ;;
        -d|--deep)
            if [ "$2" -ge 0 ]; then
                DEEP="$2"
            fi
            shift
            ;;
        -v|--verbose)
            LOG='true'
            ;;
        *)
            echo "[WARNING] Unkown option: $1"
            ;;
    esac
    shift
    done

    test ${LOG} = 'true' && echo "[LOG] LINKS_PATH=\""${LINKS_PATH}"\" ; RSNAPSHOT_PATH=\""${RSNAPSHOT_PATH}"\" ; DEEP="${DEEP}

    return 0
}

function clean_links() {
    echo -e '\033[1m#-- clean links\033[0m'

    test ${LOG} = 'true' && echo -n "[LOG] Removing old links in \""${LINKS_PATH}"\"."
    rm -rf "${LINKS_PATH}"/*
    test ${LOG} = 'true' && echo " result="$?

    return 0
}

function create_links() {
    echo -e '\033[1m#-- create links\033[0m'

	counting=1
	# sed 's,/$,,g' : remove ending /
	# ls -Adt : list folders except . and .. and sort them by modify date
	ls -Adt "${RSNAPSHOT_PATH}"/*/ | sed 's,/$,,g' | while read fold; do
		# `printf %03d $((counting))` : converts 1 digit number to 3 digit number
		linkname=$(date -r "${fold}" "+%Y.%m.%d_%Hh%Mmin")"_"`printf %03d $((counting))`
		
		DEPTH=${DEEP}
		while [ ${DEPTH} -gt 0 ] # Explore inside dir at indicated level
		do
			shopt -s nullglob	# see: http://stackoverflow.com/questions/18884992/how-do-i-assign-ls-to-an-array-in-linux-bash
			TEMP=("${fold}"/*/)
			shopt -u nullglob
			#test ${LOG} = 'true' && echo "[LOG] ls explo["${DEPTH}"]: "${TEMP}" ("${#TEMP[@]}")"
			if [ ${#TEMP[@]} -eq 1 ]; then
				fold="${TEMP}"
			fi
			((DEPTH--))
		done

		fold="${fold//'//'/'/'}"				# clean // into /
		LINKS_PATH="${LINKS_PATH//'//'/'/'}"	# clean // into /
		ln -s "${fold}" "${LINKS_PATH}"/"${linkname}"
		((counting++))
		
		test ${LOG} = 'true' && echo "[LOG] Folder: "${fold}
		test ${LOG} = 'true' && echo "[LOG] |_Link: "${linkname}
	done

	return 0
}

if [[ "$BASH_SOURCE" == "$0" ]]; then
    main "$@"
fi
