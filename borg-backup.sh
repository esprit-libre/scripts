#!/bin/bash

## borg script
#
# version 0.0.1 - 02/05/2017
#
# This script launch backup with borg tool and prune old backup based on
# purge setup
#
# Usage:
#  `./borg-backup.sh [-v|--verbose] [-l|--log LOG_PATH]
##

set -e	# interrupt on error
function cleanup()
{
    echo "Something bad happened during backup, check ${LOG_PATH}"
    exit $1
}
function write_log()
{
	test ${DEBUG} = 'true' && echo "[LOG] "$1
    echo `date '+%Y-%m-%d %H:%M:%S'`" - "$1 >> ${LOG_PATH}
}
trap '[ "$?" -eq 0 ] || cleanup' EXIT	# trap on non-zero exit


function main() {
    write_log '\033[1m# Starting borg backup script\033[0m'
    write_log "-- "$(date +%Y-%m-%d %H-%M-%S)" --"
    write_log "-----------------------------------"

    # Reading vars
    read_vars "$@"

	# dependencies
    DEPS=( borg )
    check_dependencies

	# Old links deletion
	clean_links

	# New links creation
	create_links
}

function read_vars() {
    write_log '\033[1m#-- read vars\033[0m'

    DEBUG='false'
    LOG_PATH="/var/log/borg-backup.log"

    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -v|--verbose)
            LOG='true'
            ;;
        -l|--log)
            if [ -d "$2" ] && [ -w "$2" ]; then
                # ${VAR//ab/yz} replace all sub-chains 'ab' from VAR by 'yz'
                LINKS_PATH="${2}/"
                LINKS_PATH="${LINKS_PATH//'//'//}"
            else
                write_log "[ERROR] Invalid LINKS_PATH dir : "$2
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
        *)
            write_log "[WARNING] Unkown option: $1"
            ;;
    esac
    shift
    done

    test ${LOG} = 'true' && echo "[LOG] LINKS_PATH="${LINKS_PATH}"; RSNAPSHOT_PATH="${RSNAPSHOT_PATH}"; DEEP="${DEEP}

    return 0
}

function check_dependencies() {
    write_log '\033[1m#-- check dependencies\033[0m'

    for dep in "${DEPS[@]}"; do
        if [ ! "$(command -v $dep)" ]; then
            write_log '[ERROR] Missing dependency: '$dep
            exit 1
        fi
    done

    return 0
}

function clean_links() {
    echo -e '\033[1m#-- clean links\033[0m'

    test ${LOG} = 'true' && echo "[LOG] Removing old links... "${LINKS_PATH}
    rm -rf "${LINKS_PATH}"/*
    echo "Resultat: "$?

    return 0
}

function create_links() {
	counting=1
	# sed 's,/$,,g' : remove ending /
	# ls -Adt : list folders except . and .. and sort them by modify date
	ls -Adt "${RSNAPSHOT_PATH}"/*/ | sed 's,/$,,g' | while read fold; do
		fold="${fold//'//'//}"	# clean // into /
		# `printf %03d $((counting))` : converts 1 digit number to 3 digit number
		linkname=$(date -r "${fold}" "+%Y.%m.%d_%Hh%Mmin")"_"`printf %03d $((counting))`
		test ${LOG} = 'true' && echo "[LOG] Folder: "${fold}
		test ${LOG} = 'true' && echo "[LOG] |_Link: "${linkname}
		# TODO : explore $fold to go inside at $deep level
		ln -s "${fold}" "${LINKS_PATH}"/"${linkname}"
		((counting++))
	done

	return 0
}


if [[ "$BASH_SOURCE" == "$0" ]]; then
    main "$@"
fi


#-----------
# https://code.crapouillou.net/snippets/1
#-----------

# http://stackoverflow.com/questions/19622198/what-does-set-e-mean-in-a-bash-script
set -e

cleanup()
{
    echo "Something bad happened during backup, check ${LOG_PATH}"
    exit $1
}

ts_log()
{
    echo `date '+%Y-%m-%d %H:%m:%S'` $1 >> ${LOG_PATH}
}

# Trap on non-zero exit
trap '[ "$?" -eq 0 ] || cleanup' EXIT

BACKUP_DATE=`date +%Y-%m-%d`
LOG_PATH=/var/log/borg-backup.log

BORG=/usr/bin/borg
export BORG_RSH="ssh -i /root/.ssh/id_rsa"
# Fichier dans lequel est stocké la passphrase du dépôt borg 
# (attention aux permissions)
export BORG_PASSPHRASE="`cat ~root/.borg/passphrase`"
BORG_REPOSITORY=borg@nas.example.com:/var/lib/borg-backups/
BORG_ARCHIVE=${BORG_REPOSITORY}::${BACKUP_DATE}

# Fichier dans lequel est stocké le mot de passe root mysql 
# (attention aux permissions)
MYSQL_ROOT_PASS=`cat /etc/yunohost/mysql`
MYSQL_TMP_DUMP_FILE=/root/mysql_all_db.sql
LDAP_TMP_DUMP_FILE=/root/ldap_all_db.ldif


ts_log "Starting new backup ${BACKUP_DATE}..."

ts_log 'Dumping MySQL db...'
mysqldump --all-databases --events -p$MYSQL_ROOT_PASS > $MYSQL_TMP_DUMP_FILE

ts_log 'Dumping LDAP...'
slapcat -l $LDAP_TMP_DUMP_FILE

ts_log "Pushing archive ${BORG_ARCHIVE}"
$BORG create \
     -v --stats --compression lzma,9 \
     $BORG_ARCHIVE \
     /etc /var/mail /home $MYSQL_TMP_DUMP_FILE $LDAP_TMP_DUMP_FILE \
     >> ${LOG_PATH} 2>&1

ts_log "Rotating old backups."
$BORG prune -v $BORG_REPOSITORY \
      --keep-daily=7 \
      --keep-weekly=4 \
      --keep-monthly=6 \
      >> ${LOG_PATH} 2>&1

ts_log 'Cleaning up...'
rm $MYSQL_TMP_DUMP_FILE
rm $LDAP_TMP_DUMP_FILE


#-----------
# mon script d'origine
#-----------
############################
###       VARIABLES      ###
############################
# Serveur à sauvegarder
SOURCE='/home'
MONTAGE='/mount_point'

# Serveur de sauvegarde
REP_DIR='/home/atticuser'
REPOSITORY='/mount_point/serv.attic'

# passphrase
ATTIC_PASSPHRASE="***y"
export ATTIC_PASSPHRASE

############################
###         INIT         ###
############################
# Créer et monter le répertoire
#mkdir $MONTAGE
echo ***x | sshfs -p 1234 atticuser@serv:$REP_DIR $MONTAGE -o password_stdin

############################
###      RECURRENT       ###
############################
# Sauvegarde, les excludes sont conservés (mais remis pour les évolutions)
/usr/local/bin/attic create --stats $REPOSITORY::$(date +%Y%m%d_%H%M%S) $SOURCE \
      --exclude '/home/logs' \
      --exclude '/home/lost+found' \
      
# Nettoyage de l'historique passé
/usr/local/bin/attic prune -v $REPOSITORY --keep-daily=31 --keep-weekly=26 --keep-monthly=6

############################
###       SORTIE         ###
############################
# Temporisation pour que les actions en cours se terminent
sleep 10
# Démonter le répertoire
fusermount -u $MONTAGE
#rm -r $MONTAGE
