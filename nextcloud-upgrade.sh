#!/bin/bash

## Upgrade Nextcloud from https://git.karolak.fr/snippets/16
#
# This script upgrade your Nextcloud installation following these steps:
# - check presence of dependencies (needed commands)
# - check if latest version is already installed
# - download latest version and check integrity of the file with GPG
# - backup current installation
# - apply upgrade and restore configuration, data and applications
#   |-> restore backup if failed
# - delete downloaded files and backup
#
# Important:
# 1. It's to run under nextcloud's files owner (ex: nextcloud, www-data, etc.).
# 2. You have to adapt DIR and BACKUP variables to your configuration.
# 3. You nextcloud webroot must not be named "nextcloud" otherwise `clean`
#    function will wipe it.
#
# Usage: `./upgrade-nc [version]`
#
# Examples:
# `./upgrade-nc` will get latest version number from GitHub repo
# `./upgrade-nc 9.0.52`
# `su -l www-data -s /bin/bash -c '/path/to/upgrade-nc'`
##

# nextcloud webroot
#DIR='/var/www/nextcloud'
# where to store backup before upgrade
#BACKUP='/tmp/nextcloud-backup-'$(date +%F-%H-%M-%S)
# set to 'true' if you want to keep backup
KEEP_BACKUP='true'

function readvars() {
	PREV=null
	for val in $*; do
		case $val in
			'-up')	DEST='nextcloud'
				;;
			'-nc')	INSTANCE='nextcloud'
				;;
			'-oc')	INSTANCE='owncloud'
				;;
			'-dir') PREV='DIR'
				;;
			'-save') PREV='SAV'
				;;
			'-rembkp') KEEP_BACKUP='false'
				;;
			'-version') PREV='VERSION'
				;;
			*)	if [[ "$PREV" = "DIR" ]]; then
					DIR=$val
				elif [[ "$PREV" = "SAV" ]]; then
					BACKUP=$val'/backup-'$(date +%F-%H-%M-%S)
				elif [[ "$PREV" = "VERSION" ]]; then
					LATEST_VERSION=$val
				fi
				;;
		esac
	done
}

function main() {
    # dependencies
    DEPS=( curl wget grep awk sed gpg tar rsync php mysql mysqldump )
    check_dependencies

    # get enabled 3rdparty apps name
    APPS=$(
        php -f $DIR/occ app:list --shipped=false | \
        grep -E 'true|([0-9]\.?)+' | \
        awk '{ print $2 }' | \
        sed 's/://'
    )

    # get database information from nextcloud configuration
    DBNAME=$(php -r 'require $argv[1]."/config/config.php"; echo $CONFIG["dbname"];' $DIR)
    DBHOST=$(php -r 'require $argv[1]."/config/config.php"; echo $CONFIG["dbhost"];' $DIR)
    DBUSER=$(php -r 'require $argv[1]."/config/config.php"; echo $CONFIG["dbuser"];' $DIR)
    DBPASS=$(php -r 'require $argv[1]."/config/config.php"; echo $CONFIG["dbpassword"];' $DIR)

    # get latest version number from arg or from GitHub
#    if [ ! -z $1 ]; then
#        LATEST_VERSION=$1
#    else
    if [ -z $LATEST_VERSION ]; then
        LATEST_VERSION=$(
            curl -s https://api.github.com/repos/$DEST/server/releases/latest | \
            grep 'tag_name' | \
            awk '{ print $2 }' | \
            sed 's/[,|"|v]//g'
        )
    fi
    # get installed version number
    INSTALLED_VERSION=$(
        php -f $DIR/occ status | \
        grep 'versionstring' | \
        awk '{ print $3 }'
    )
    FILENAME=$DEST'-'$LATEST_VERSION'.tar.bz2'
    DOWNLOAD_URL='https://download.'$DEST'.com/server/releases/'$FILENAME
    GPG_SIG_URL=$DOWNLOAD_URL'.asc'
    GPG_PUBKEY_URL='https://'$DEST'.com/'$DEST'.asc'
    GPG_FINGERPRINT='A724937A'

    echo -e '\033[1m#-- check version\033[0m'
    if [ $INSTALLED_VERSION == $LATEST_VERSION ]; then
        echo 'Already latest version'
        exit 0
    fi

    download
    if [ $? != 0 ]; then
        echo 'Error while downloading'
        exit 1
    fi
    backup
    if [ $? != 0 ]; then
        echo 'Error while backuping'
        exit 1
    fi
    upgrade
    if [ $? != 0 ]; then
        echo 'Error while upgrading'
        restore
        exit 1
    fi
    clean
}

function download() {
    echo -e '\033[1m#-- download\033[0m'

    # download nextcloud and its signature file
    wget -q --show-progress ${DOWNLOAD_URL}
    wget -q --show-progress ${GPG_SIG_URL}

    # check nextcloud key is present
    gpg --list-keys $GPG_FINGERPRINT > /dev/null
    if [ $? != 0 ]; then
        wget -q --show-progress $GPG_PUBKEY_URL -O - | gpg -q --import -
    fi

    # check integrity of the downloaded file
    gpg -q --verify ${FILENAME}.asc $FILENAME 2> /dev/null
    if [ $? != 0 ]; then
        echo 'Mismatch between file and its signature'
        exit 1
    fi

    return 0
}

function backup() {
    echo -e '\033[1m#-- backup\033[0m'

    # enable mode maintenance
    php -f $DIR/occ maintenance:mode --on
    # backup nextcloud directory and database
    rsync -ac --exclude '.[git|bzr|svn]*' --exclude 'data' $DIR/ $BACKUP
    mysqldump -h $DBHOST -u $DBUSER -p$DBPASS -B $DBNAME > ${BACKUP}.sql 2> /dev/null

    return 0
}

function restore() {
    echo -e '\033[1m#-- restore\033[0m'

    if [ ! -d $BACKUP ]; then
        echo 'Error: backup is missing'
        exit 1
    fi

    # restore nextcloud directory and database
    rsync -avc --delete --exclude '.[git|bzr|svn]*' --exclude 'data' $BACKUP/ $DIR
    mysql -h $DBHOST -u $DBUSER -p$DBPASS -D $DBNAME < ${BACKUP}.sql 2> /dev/null
    # disable mode maintenance
    php -f $DIR/occ maintenance:mode --off

    return 0
}

function upgrade() {
    echo -e '\033[1m#-- upgrade\033[0m'

    # extract downloaded archive and delete it
    tar -xaf $FILENAME
    # restore configuration
    rsync -ac $BACKUP/config/config.php $DEST/config/
    # restore 3rdparty apps
    for app in $APPS; do
        rsync -ac $BACKUP/apps/$app $DEST/apps/
    done
    # replace installed nextcloud by the updated one
    rsync -avc --delete --exclude '.[git|bzr|svn]*' --exclude 'data' $DEST/ $DIR
    # disable mode maintenance
    php -f $DIR/occ maintenance:mode --off
    # launch nextcloud upgrade process
    php -f $DIR/occ upgrade
    # update .htaccess to handle pretty url
    php -f $DIR/occ maintenance:update:htaccess
    # re-enable 3rdparty apps
    for app in $APPS; do
        php -f $DIR/occ app:enable $app
    done

    # check state of the owncloud installation after upgrade
    STATE=$(php -f $DIR/occ status | grep 'installed' | awk '{ print $3 }')
    INTEGRITY=$(
        php -f $DIR/occ integrity:check-core | \
        grep 'INVALID_HASH' | \
        sed 's/[-|\s|:]//g'
    )
    if [ $STATE != 'true' ] || [ ! -z $INTEGRITY ]; then
        return 1
    fi

    return 0
}

function check_dependencies() {
    echo -e '\033[1m#-- check dependencies\033[0m'

    for dep in "${DEPS[@]}"; do
        if [ ! "$(command -v $dep)" ]; then
            echo 'Missing dependency: '$dep
            exit 1
        fi
    done

    return 0
}

function clean() {
    echo -e '\033[1m#-- clear\033[0m'

    rm -rf $DEST
    rm -f $FILENAME
    rm -f $FILENAME.asc
    if [ $KEEP_BACKUP != 'true' ]; then
        rm -rf $BACKUP
        rm -f $BACKUP.sql
    fi

    return 0
}

if [[ "$BASH_SOURCE" == "$0" ]]; then
	readvars "$@"
    main "$@"
fi
