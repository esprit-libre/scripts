#-----------
# Template script from https://code.crapouillou.net/snippets/1
#-----------

set -e	# info : http://stackoverflow.com/questions/19622198/what-does-set-e-mean-in-a-bash-script
cleanup()
{
    echo "Something bad happened during backup, check ${LOG_PATH}"
    exit $1
}
ts_log()
{
    echo `date '+%Y-%m-%d %H:%M:%S'`" - "$1 >> ${LOG_PATH}
}
trap '[ "$?" -eq 0 ] || cleanup' EXIT	# Trap on non-zero exit

ts_log "Starting new backup ${BACKUP_DATE}..."

BACKUP_DATE=`date +%Y%m%d_%H%M%S`
LOG_PATH=/var/log/borg-user.log

BORG=/usr/bin/borg
export BORG_RSH="ssh -i /root/.borg/user_id_rsa"
export BORG_PASSPHRASE="`cat /root/.borg/passphrase`"
#BORG_REPOSITORY=user@server.com:/data/user/borg/servername
BORG_REPOSITORY=sshname:/data/user/borg/servername
BORG_ARCHIVE=${BORG_REPOSITORY}::${BACKUP_DATE}

ts_log 'Dumping MySQL db...'
MYSQL_PASS=`cat /root/.borg/mysql_user`
MYSQL_USER="mysqluser"
MYSQL_DATABASE="database"
MYSQL_TMP_DUMP_FILE=/root/.borg/mysql_all_db.sql

#mysqldump --all-databases --events -p$MYSQL_PASS > $MYSQL_TMP_DUMP_FILE
mysqldump -u$MYSQL_USER --events -p$MYSQL_PASS $MYSQL_DATABASE > $MYSQL_TMP_DUMP_FILE

ts_log "Pushing archive ${BORG_ARCHIVE}"
$BORG create \
     -v --stats --compression lzma,9 \
     $BORG_ARCHIVE \
     /etc /var/www /home $MYSQL_TMP_DUMP_FILE \
     --exclude '/home/logs' \
     >> ${LOG_PATH} 2>&1

ts_log "Rotating old backups."
$BORG prune -v $BORG_REPOSITORY \
      --keep-daily=7 \
      --keep-weekly=4 \
      --keep-monthly=6 \
      >> ${LOG_PATH} 2>&1

ts_log 'Cleaning up...'
rm $MYSQL_TMP_DUMP_FILE
