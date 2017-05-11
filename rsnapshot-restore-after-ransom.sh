#!/bin/bash

## Restore files from rsnapshot folders after ransomware infection
#
# version 1.0.1 - 05/05/2017
#
# This script gets back from rsnapshot directories non-infected files
# based on name and infected files extension
# 
# Important :
# - RSNAPSHOT_PATH should be full path to access to "daily.x" and others
# - works with PATTERN using * wildcard only...
#
# Usage:
#   ./rsnapshot-restore-after-ransom.sh -d INFECTED_DATA_PATH -r RSNAPSHOT_PATH [-p FILE_PATTERN] [-v]
#   ./rsnapshot-restore-after-ransom.sh --dir LINKS_PATH --rsnapshot RSNAPSHOT_PATH [--pattern FILE_PATTERN] [--verbose]
#
# Examples:
#   ./rsnapshot-restore-after-ransom.sh -d /data/shared_data -r /data/rsnapshot -p "*.jse"
#   ./rsnapshot-restore-after-ransom.sh -d /data/shared_data -r /data/rsnapshot -p "*.jse" -v >> /var/log/rsnapshot-restore-after-ransom.log 2>&1
##

function main() {
    echo -e '\033[1m# Starting rsnapshot restore after ransomware disaster\033[0m'
    echo "-- "$(date +%F-%H-%M-%S)" --"
    echo "-----------------------------------"

	# dependencies
	DEPS=( rsync ) #TODO: ??
	check_dependencies

	# Reading vars
	read_vars "$@"

	# Get infected file list
	treat_infected_files
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

    INFECTED_DIR=""
    RSNAPSHOT_BASE=""
    PATTERN=""
    INFECTED_COUNT=0
    #INFECTED=""
    LOG='false'

    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -d|--dir)
            if [ -d "$2" ] && [ -w "$2" ]; then
                # ${VAR//ab/yz} replace all sub-chains 'ab' from VAR by 'yz'
                INFECTED_DIR="${2}/"
                INFECTED_DIR="${INFECTED_DIR//'//'//}"
            else
                echo "[ERROR] Invalid INFECTED dir : "$2
                exit 1
            fi
            shift
            ;;
        -r|--rsnapshot)
            if [ -d "$2" ]; then
                # ${VAR//ab/yz} replace all sub-chains 'ab' from VAR by 'yz'
                RSNAPSHOT_BASE="${2}/"
                RSNAPSHOT_BASE="${RSNAPSHOT_BASE//'//'//}"
            else
                echo "[ERROR] Invalid RSNAPSHOT dir : "$2
                exit 1
            fi
            shift
            ;;
        -p|--pattern)
            PATTERN="$2"	#TODO: need for validity test?
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

    test ${LOG} = 'true' && echo "[LOG] INFECTED=\""${INFECTED_DIR}"\" ; RSNAPSHOT=\""${RSNAPSHOT_BASE}"\" ; PATTERN="${PATTERN}

    return 0
}

function treat_infected_files() {
    echo -e '\033[1m#-- list infected files\033[0m'

    test ${LOG} = 'true' && echo "[LOG] Searching for infected files in \""${INFECTED_DIR}"\"."
    # http://www.linuxprogrammingblog.com/pipe-in-bash-can-be-a-trap
    find ${INFECTED_DIR} -type f -name ${PATTERN} | while read INFECTED_FILE; do
    	INFECTED[$((INFECTED_COUNT++))]=${INFECTED_FILE}
		test ${LOG} = 'true' && echo -n "[LOG] Infected file n°="${INFECTED_COUNT}" : \""${INFECTED[${INFECTED_COUNT}-1]}"\""

		NOTFOUND='true'
		# explore each backup dir
		ls -Adt "${RSNAPSHOT_BASE}"/*/ | while read RSNAPSHOT_DAILY && ${NOTFOUND} = 'true'; do
			RSNAPSHOT_DAILY=$(ls -Adt "${RSNAPSHOT_DAILY}"/*/)${INFECTED_FILE}
			RSNAPSHOT_DAILY="${RSNAPSHOT_DAILY//'//'//}"
			if [ ! -e "${RSNAPSHOT_DAILY}" ]; then
				EXT=${PATTERN#*}
				mv "${INFECTED_FILE}" "${INFECTED_FILE}_virus"
				find "${RSNAPSHOT_BASE}" -type f -wholename "${RSNAPSHOT_DAILY%$EXT}.*" -exec cp -a {} "${INFECTED_FILE%/*}/" \;
				NOTFOUND='false'
				test ${LOG} = 'true' && echo " restored by \""${RSNAPSHOT_DAILY%$EXT}".*\""
			fi
		done
	done

    return 0
}

if [[ "$BASH_SOURCE" == "$0" ]]; then
    main "$@"
fi
