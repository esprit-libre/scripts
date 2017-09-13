#!/bin/bash
set -e

readonly VERSION='1.2'
readonly DATE='13 sept. 2017'

CURRENT_DATE=$(date +%d/%m/%Y_%Hh%M)

version() {
	echo "$(basename "${0}") - version ${VERSION} - ${DATE}."
}

usage() {
	echo ''
	echo '$(basename "${0}") -p[ath] <THEPATH> [ OPTIONS ]'
	echo ''
	echo 'OPTIONS = { -v[ersion] | -h[elp] | -d[ebug] }'
	echo 'OPTIONS = { -l[evel] } : depth to explore, default is 1. }'
	echo 'OPTIONS = { -m[ails] } : email list (comma separated) to send report. }'
	echo 'OPTIONS = { -n[extcloud] } : use nextcloud file organization. }'
	echo 'OPTIONS = { -s[hort] } : friendly print for nextcloud case. }'
	echo ''
	echo 'This script intends to count space used by directories or by users.'
	echo ''
}

log() {
	if [ -n ${DEBUG} ]; then
		echo -e ${@}
	fi
}

init() {
	readonly  ERR="[\033[1;31mERROR\033[0m]	"
	readonly   OK="[\033[1;32mOK\033[0m]	"
	readonly WARN="[\033[1;33mWARN\033[0m]	"
	readonly INFO="[\033[36mINFO\033[0m]	"
}

parameters() {
	LEVEL=1
	while [[ $# -gt 0 ]]; do
		local key="$1"
		case $key in
			-d|-debug)
				DEBUG='true'
				log "${INFO}Debug logs activated"
				;;
			-h|--help)
				usage
				exit 0
				;;
			-l|-level)
				LEVEL="${2}"
				shift
				;;
			-m|-mails)
				MAILS="${2}"
				shift
				;;
			-n|-nextcloud)
				readonly NEXTCLOUD='true'
				;;
			-p|-path)
				readonly THEPATH="${2}"
				shift
				;;
			-s|-short)
				readonly SHORT='true'
				;;
			-v|--version)
				version
				exit 0
				;;
			*)
				log "${WARN}Unkown option: $1"
				;;
		esac
		shift
	done

	if [ ! -d "${THEPATH}" ]; then
		log "${ERR}Missing or wrong path info."
		usage
		return 1
	fi
	if [ -n "${LEVEL}" ]; then
		re='^[0-9]+$'
		if ! [[ "${LEVEL}" =~ $re ]]; then
			log "${WARN}Invalid value for level. Using '1' (default)."
			LEVEL=1
		fi
	fi
	if [ -n "${MAILS}" ] && [[ ! "${MAILS}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]]; then
		log "${WARN}Invalid mail: ${MAILS}. No mail report."
		unset MAILS
	fi
}

init
log "\n---------------------"
log -e "${INFO}Starting space usage - ${CURRENT_DATE}\n\n"
parameters "$@"

#~ GLOBAL="/usr/bin/du -sh"
if [ -n "${NEXTCLOUD}" ]; then
	if [ -n "${SHORT}" ]; then
		#~ STATS='/usr/bin/du -d 1 -h'
		#~ EXCLUDE='--exclude="*files_trashbin*" --exclude="*cache*" --exclude="*appdata*" \
			#~ --exclude="*files_external*" --exclude="*files_versions*" --exclude="*thumbnails*" \
			#~ --exclude="*updater_backup*" --exclude="*uploads*" --exclude="*locks*"'
		#~ STATS=$(${STATS} "${EXCLUDE}" ${THEPATH} | /bin/sed "s/${THEPATH//\//\\\/}//g")
		STATS=$(/usr/bin/du -d 1 -h --exclude="*files_trashbin*" --exclude="*cache*" --exclude="*appdata*" \
			--exclude="*files_external*" --exclude="*files_versions*" --exclude="*thumbnails*" \
			--exclude="*updater_backup*" --exclude="*uploads*" --exclude="*locks*" "${THEPATH}" | \
			/bin/sed "s/${THEPATH//\//\\\/}//g")
		#~ QUOTA=$(${GLOBAL} "${EXCLUDE}" "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
		QUOTA=$(/usr/bin/du -sh --exclude="*files_trashbin*" --exclude="*cache*" --exclude="*appdata*" \
			--exclude="*files_external*" --exclude="*files_versions*" --exclude="*thumbnails*" \
			--exclude="*updater_backup*" --exclude="*uploads*" --exclude="*locks*" "${THEPATH}" | \
			/bin/sed "s/${THEPATH//\//\\\/}//g")
		#~ GLOBAL=$(${GLOBAL} "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
		GLOBAL=$(/usr/bin/du -sh "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
	else
		#~ STATS="/usr/bin/du -d 2 -h"
		#~ EXCLUDE="| /bin/sed '/files_trashbin/d' | /bin/sed '/cache/d' | /bin/sed '/appdata_/d' | \
			#~ /bin/sed '/files_external/d' | /bin/sed '/files_versions/d' | /bin/sed '/thumbnails/d' | \
			#~ /bin/sed '/updater_backup/d' | /bin/sed '/uploads/d' | /bin/sed '/locks/d' | \
			#~ "
		#~ STATS=$(${STATS} "${THEPATH}" "${EXCLUDE}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
		STATS=$(/usr/bin/du -d 2 -h "${THEPATH}" | /bin/sed '/files_trashbin/d' | /bin/sed '/cache/d' | \
			/bin/sed '/appdata_/d' | /bin/sed '/files_external/d' | /bin/sed '/files_versions/d' | \
			/bin/sed '/thumbnails/d' | /bin/sed '/updater_backup/d' | /bin/sed '/uploads/d' | \
			/bin/sed '/locks/d' | /bin/sed "s/${THEPATH//\//\\\/}//g")
		QUOTA=$(/usr/bin/du -sh --exclude="*files_trashbin*" --exclude="*cache*" --exclude="*appdata*" \
			--exclude="*files_external*" --exclude="*files_versions*" --exclude="*thumbnails*" \
			--exclude="*updater_backup*" --exclude="*uploads*" --exclude="*locks*" "${THEPATH}" | \
			/bin/sed "s/${THEPATH//\//\\\/}//g")
		#~ GLOBAL=$(${GLOBAL} "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
		GLOBAL=$(/usr/bin/du -sh "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
	fi
else
	#~ STATS="/usr/bin/du -d ${LEVEL} -h"
	#~ STATS=$(${STATS} "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
	STATS=$(/usr/bin/du -d ${LEVEL} -h "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
	#~ GLOBAL=$(${GLOBAL} "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
	GLOBAL=$(/usr/bin/du -sh "${THEPATH}" | /bin/sed "s/${THEPATH//\//\\\/}//g")
fi



echo -e "${STATS}\n------------\nGLOBAL=${GLOBAL} ( vs QUOTA=${QUOTA})"

if [ -n "${MAILS}" ]; then
echo -e "Espace occupé pour ${THEPATH} - ${CURRENT_DATE}\n\n \
Occupation...\n...décomptée du quota = ${QUOTA}\n...réelle (sur disque) = ${GLOBAL}\n\n${STATS}" | \
/usr/bin/mail -a "Content-Type: text/plain; charset=UTF-8" \
	-s "[Cloud] Info quota pour ${THEPATH} - ${CURRENT_DATE}" "${MAILS}"
fi
