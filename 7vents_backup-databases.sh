#!/bin/bash
set -e

readonly VERSION='1.4'
readonly DATE='25 jul. 2017'

CURRENT_DATE=$(date +%Y-%m-%d_%Hh%M)

shopt -s expand_aliases

version() {
	echo "$(basename "${0}") - version ${VERSION} - ${DATE}."
}

usage() {
	echo ''
	echo '$(basename "${0}") -c[onfig] <config_file> [ OPTIONS ]'
	echo ''
	echo 'OPTIONS = { -v[ersion] | -h[elp] | -d[ebug] }'
	echo ''
	echo 'This script intends to backup ics calendars from davical base,'
	echo 'and databases themselves: PostgreSQL and MariaDB.'
	echo ''
}

log() {
	if [ -n ${DEBUG} ]; then
		echo -e ${@}
	fi
}

main() {
	init
	parameters "$@"
	processing
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
			-c|-config)
				readonly CONFIG="${2}"
				shift
				;;
			-d|-debug)
				DEBUG='true'
				log "${INFO}Debug logs activated"
				;;
			-h|--help)
				usage
				exit 0
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

	if [ -z "${CONFIG}" ]; then
		log "${ERR}Missing config file."
		usage
		return 1
	else
		local TEMP=`cat $CONFIG`
		URL_DAVICAL=$(echo $TEMP | cut -f1 -d,;)
		DIR_BACKUP=$(echo $TEMP | cut -f2 -d,;)
		USER=$(echo $TEMP | cut -f3 -d,;)
		PASS=$(echo $TEMP | cut -f4 -d,;)
		if [ ! -d "${DIR_BACKUP}" ]; then
			log "${ERR}Backup dir does not exist."
			usage
			return 2
		fi
	fi
}

processing() {
	log "${INFO}PostgreSQL 'davical' database extraction..."
	pg_dump -U davical_dba davical > ${DIR_BACKUP}/davical_${CURRENT_DATE}.pgsql
	if [ ${?} -eq 0 ]; then
		log "${OK}PostgreSQL extraction succeed."
	else
		log "${ERR}PostgreSQL extraction failed with error ${?}."
		return 3
	fi

	su - postgres -c "psql davical -c 'select dav_name from collection ;'" > ${DIR_BACKUP}/davical-list-tmp.txt
	cat ${DIR_BACKUP}/davical-list-tmp.txt | grep / | sort -u | sed 's/^\s*//' | sed 'sZ/*$ZZ' | sed 'sZ/ZZ' > ${DIR_BACKUP}/davical-list-propre.txt
	sed -i '/addresses/d' ${DIR_BACKUP}/davical-list-propre.txt
	{ while IFS='/' read usr cal; do
		log "${INFO}Fetching http://${URL_DAVICAL}/caldav.php/${usr}/${cal}/ ..."
		wget -q --http-user=${USER} --http-passwd="${PASS}" -O ${DIR_BACKUP}/"${usr}"-"${cal}"-"${CURRENT_DATE}".ics http://${URL_DAVICAL}/caldav.php/"${usr}"/"${cal}"/
	done ; } < ${DIR_BACKUP}/davical-list-propre.txt

	log "${INFO}MariaDB database extraction..."
	mysqldump --ignore-table=mysql.event -A > ${DIR_BACKUP}/mysql_all_${CURRENT_DATE}.sql
	if [ ${?} -eq 0 ]; then
		log "${OK}MariaDB extraction succeed."
	else
		log "${ERR}MariaDB extraction failed with error ${?}."
		return 4
	fi

	mysql -e 'SHOW DATABASES;' > ${DIR_BACKUP}/liste_database_tmp.txt
	cat ${DIR_BACKUP}/liste_database_tmp.txt | grep -v Database | grep -v performance_schema | grep -v information_schema > ${DIR_BACKUP}/liste_database.txt
	{ while read u1; do
		log "${INFO}MariaDB ${u1} database extraction..."
		mysqldump --skip-lock-tables --ignore-table=mysql.event "${u1}" > ${DIR_BACKUP}/"${u1}"_${CURRENT_DATE}.sql
	done ; } < ${DIR_BACKUP}/liste_database.txt

	log "${INFO}Cleaning backup dir."
	find ${DIR_BACKUP} -type f -a -ctime +15 -exec rm '{}' \;
}

main "$@"
