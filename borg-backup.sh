#!/bin/bash
set -e

readonly VERSION='1.0'
readonly DATE='9 aug. 2017'
readonly LOG_PATH=/var/log/borg-user.log
readonly BORG=/usr/bin/borg

CURRENT_DATE=$(date +%Y%m%d_%H%M%S)

version() {
	echo "$(basename "${0}") - version ${VERSION} - ${DATE}."
}

usage() {
	echo ''
	echo '$(basename "${0}") -s[erver] <remote_server> -u[ser] <remote_user> -f[olders] <dir_to_backup> [ OPTIONS ]'
	echo ''
	echo 'OPTIONS = { -v[ersion] | -h[elp] | -d[ebug] }'
	echo 'OPTIONS = { -n[obase] } : no databases backup, even if -m and -b are set'
	echo 'OPTIONS = { -m[yuser] <mysql_user> } : use with -b option. If not set, root is used.'
	echo 'OPTIONS = { -b[ase] <mysql_base> } : use with -m option. If not set, all databases are dumped.'
	echo ''
	echo 'This script intends to backup folders and MariaDB databases to a remote server'
	echo 'using BorgBackup software.'
	echo ''
}

log() {
	if [ -n ${DEBUG} ]; then
		echo -e ${@}
	fi
	echo -e ${@} >> ${LOG_PATH}
}

init() {
	readonly  ERR="[\033[1;31mERROR\033[0m]	"
	readonly   OK="[\033[1;32mOK\033[0m]	"
	readonly WARN="[\033[1;33mWARN\033[0m]	"
	readonly INFO="[\033[36mINFO\033[0m]	"
}

parameters() {
	while [[ $# -gt 0 ]]; do
		local key="$1"
		case $key in
			-b|-base)
				readonly MYSQLBASE="${2}"
				shift
				;;
			-d|-debug)
				DEBUG='true'
				log "${INFO}Debug logs activated"
				;;
			-f|-folders)
				readonly FOLDERS="${2}"
				shift
				;;
			-h|--help)
				usage
				exit 0
				;;
			-m|-myuser)
				readonly MYSQLUSER="${2}"
				shift
				;;
			-n|-nobase)
				NOBASE='true'
				;;
			-s|-server)
				readonly REMOTESERVER="${2}"
				shift
				;;
			-u|-user)
				readonly REMOTEUSER="${2}"
				shift
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

	if [ -z "${REMOTESERVER}" ]; then
		log "${ERR}Missing remote server info."
		usage
		return 1
	fi
	if [ -z "${REMOTEUSER}" ]; then
		log "${ERR}Missing remote user info."
		usage
		return 2
	fi
	if [ -z "${FOLDERS}" ]; then
		log "${ERR}Missing folders to save info."
		usage
		return 2
	fi
	if [ -n "${MYSQLBASE}" -a -z "${MYSQLUSER}" ]; then
		log "${ERR}MySQL user info missing. Should be BASE+USER or none (=dump all)."
		usage
		return 3
	elif [ -n "${MYSQLUSER}" -a -z "${MYSQLBASE}" ]; then
		log "${ERR}MySQL base info missing. Should be BASE+USER or none (=dump all)."
		usage
		return 4
	elif [ -n "${MYSQLUSER}" -a -n "${MYSQLBASE}" ]; then
		if [ -f "/root/.borg/mysql_${MYSQLUSER}" ]; then
			MYSQLPASS=`cat /root/.borg/mysql_${MYSQLUSER}`
		else
			log "${ERR}MySQL password missing. Please fill \"~/.borg/mysql_${MYSQLUSER}\" file."
			return 5
		fi
	fi
}

init
parameters "$@"

export BORG_RSH="ssh -i /root/.ssh/${REMOTESERVER}"
export BORG_PASSPHRASE="`cat /root/.borg/${REMOTESERVER}`"
BORG_REPOSITORY="${REMOTESERVER}":/data/"${REMOTEUSER}"/borg/$(hostname)
BORG_ARCHIVE=${BORG_REPOSITORY}::${CURRENT_DATE}

log "${INFO}Dumping MariaDB databases..."
if [ ! -d /tmp/"${REMOTESERVER}"_"${REMOTEUSER}" ]; then
	mkdir /tmp/"${REMOTESERVER}"_"${REMOTEUSER}"
elif [ $( ls -1 /tmp/"${REMOTESERVER}"_"${REMOTEUSER}" | wc -l ) -gt 0 ]; then
	rm -r /tmp/"${REMOTESERVER}"_"${REMOTEUSER}"/*
fi

if [ -z "${NOBASE}" -a -n "${MYSQLBASE}" ]; then
	mysqldump -u"${MYSQLUSER}" -p"${MYSQLPASS}" "${MYSQLBASE}" > /tmp/"${REMOTESERVER}"_"${REMOTEUSER}"/"${MYSQLBASE}"_${CURRENT_DATE}.sql
elif [ -z "${NOBASE}" ]; then
	mysql -e 'SHOW DATABASES;' | grep -v Database | grep -v performance_schema | grep -v information_schema | grep -v mysql > /tmp/"${REMOTESERVER}"_"${REMOTEUSER}"/base_list
	{ while read u1; do
		log "${INFO}MariaDB ${u1} database extraction..."
		mysqldump "${u1}" > /tmp/"${REMOTESERVER}"_"${REMOTEUSER}"/"${u1}"_${CURRENT_DATE}.sql
	done ; } < /tmp/"${REMOTESERVER}"_"${REMOTEUSER}"/base_list
fi

log "${INFO}Pushing archive ${BORG_ARCHIVE}"
$BORG create \
     -v --stats --compression lzma,9 \
     $BORG_ARCHIVE \
     "${FOLDERS}" /tmp/"${REMOTESERVER}"_"${REMOTEUSER}" \
     --exclude '/home/*/.ssh' \
     --exclude '/home/*/cache' \
     --exclude '/root/.borg' \
     --exclude '/root/.ssh' \
     >> ${LOG_PATH} 2>&1

log "${INFO}Rotating old backups."
$BORG prune -v $BORG_REPOSITORY \
      --keep-daily=7 \
      --keep-weekly=4 \
      --keep-monthly=6 \
      >> ${LOG_PATH} 2>&1

log "${INFO}Cleaning up..."
rm -r /tmp/"${REMOTESERVER}"_"${REMOTEUSER}"
