#!/bin/bash

## Links by dates for readability of rsnapshot folders
#
# version 1.0.3 - 28/04/2017
#
# This script create links for rsnapshot sub-directories replacing daily.0
# by the date of creation of this folder.
#
# Usage:
#  `./rsnapshot-date-link.sh -l LINKS_PATH -s SNAPSHOT_PATH [-d DEEP] [-r] [-v]
#  `./rsnapshot-date-link.sh --links LINKS_PATH --snapshot SNAPSHOT_PATH [--deep DEEP] [--relative] [--verbose]
#
# Examples:
# `./rsnapshot-date-link.sh -l /home/user/links -s /data/user/rsnapshot -r -v -d 3
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
    SNAPSHOT_PATH=""
    DEEP=0
    RELATIVE='false'
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
        -s|--snapshot)
            if [ -d "$2" ]; then
                # ${VAR//ab/yz} replace all sub-chains 'ab' from VAR by 'yz'
                SNAPSHOT_PATH="${2}/"
                SNAPSHOT_PATH="${SNAPSHOT_PATH//'//'//}"
            else
                echo "[ERROR] Invalid SNAPSHOT_PATH dir : "$2
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
        -r|--relative)
            RELATIVE='true'
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

    test ${LOG} = 'true' && echo "[LOG] LINKS_PATH=\""${LINKS_PATH}"\" ; SNAPSHOT_PATH=\""${SNAPSHOT_PATH}"\" ; DEEP="${DEEP}"\" ; RELATIVE="${RELATIVE}

    return 0
}

function clean_links() {
    echo -e '\033[1m#-- clean links\033[0m'

    test ${LOG} = 'true' && echo -n "[LOG] Removing old links in \""${LINKS_PATH}"/*\"."
    #rm -rf "${LINKS_PATH}"/*
    test ${LOG} = 'true' && echo " result="$?

    return 0
}

function create_links() {
    echo -e '\033[1m#-- create links\033[0m'

	test ${RELATIVE} = 'true' && cd "${LINKS_PATH}"

	LINK_NUM=1
	# sed 's,/$,,g' : remove ending /
	# ls -Adt : list folders except . and .. and sort them by modify date
	ls -Adt "${SNAPSHOT_PATH}"/*/ | sed 's,/$,,g' | while read FOLD_TO_LINK; do
		# `printf %03d $((LINK_NUM))` : converts 1 digit number to 3 digit number
		LINKNAME=$(date -r "${FOLD_TO_LINK}" "+%Y.%m.%d_%Hh%Mmin")"_"`printf %03d $((LINK_NUM))`

		DEPTH=${DEEP}
		while [ ${DEPTH} -gt 0 ] # Explore inside dir at indicated level
		do
			shopt -s nullglob	# see: http://stackoverflow.com/questions/18884992/how-do-i-assign-ls-to-an-array-in-linux-bash
			TEMP=("${FOLD_TO_LINK}"/*/)
			shopt -u nullglob
			if [ ${#TEMP[@]} -eq 1 ]; then
				FOLD_TO_LINK="${TEMP}"
			fi
			((DEPTH--))
		done

		FOLD_TO_LINK="${FOLD_TO_LINK//'//'/'/'}"	# clean // into /
		LINKS_DIR="${LINKS_PATH//'//'/'/'}"			# clean // into /

		# relative symlink
		if [ ${RELATIVE} = 'true' ]; then
			# First step : remove common path
			COMPARE='true'
			while $COMPARE
			do
				# Compare first part of PATHS
				if [ "${LINKS_DIR%%/*}" = "${FOLD_TO_LINK%%/*}" ]; then
					LINKS_DIR="${LINKS_DIR#*/}"			# removes first bloc of PATH
					FOLD_TO_LINK="${FOLD_TO_LINK#*/}"	# removes first bloc of PATH
				else
					COMPARE='false'
				fi
			done
			
			# Second step : count how many path diff we have to reach LINKS_DIR
			NB_REL=0
			while [ -n "${LINKS_DIR}" ]
			do
				LINKS_DIR="${LINKS_DIR#*/}"
				((NB_REL++))
			done

			test ${NB_REL} -eq 0 && FOLD_TO_LINK="/${FOLD_TO_LINK}"	# if no part of PATH are similar, restore initial /

			# Third step : add relative information
			while [ ${NB_REL} -gt 0 ]
			do
				FOLD_TO_LINK="../${FOLD_TO_LINK}"
				((NB_REL--))
			done

			ln -s "${FOLD_TO_LINK}" "${LINKNAME}"

		# absolute symlink
		else
			ln -s "${FOLD_TO_LINK}" "${LINKS_DIR}"/"${LINKNAME}"
		fi

		((LINK_NUM++))

		test ${LOG} = 'true' && echo "[LOG] link created: "${LINKNAME}" -> "${FOLD_TO_LINK}
	done

	return 0
}

if [[ "$BASH_SOURCE" == "$0" ]]; then
    main "$@"
fi
