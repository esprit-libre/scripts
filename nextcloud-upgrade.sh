#!/bin/bash

## Upgrade Nextcloud
#
# version 1.0.0 - 27/02/2017
#
# This script upgrade your Nextcloud installation following these steps:
# - adjust permissions
# - check presence of dependencies (needed commands)
# - check if latest version is already installed
# - download latest version and check integrity of the file with GPG
# - backup current installation
# - apply upgrade and restore configuration, data and applications
#   |-> restore backup if failed
# - adjust permissions
#
# Important:
# - It's to run under root or user that can modify files rights and use www-data
#
# Usage: `./nextcloud-upgrade.sh [-up|--upgrade owncloud|nextcloud] [-d|--dir {INSTALL_PATH}] \
#                                [-s|--save {SAVE_PATH}] [-v|--version {VERSION}] [-l]`
#
# Examples:
# `./nextcloud-upgrade.sh -d INST_PATH` will get latest version number from GitHub repo and ask if keeping save
# `./nextcloud-upgrade.sh -up owncloud -d INST_PATH -s SAVE_PATH -v 9.0.52 -l`
# `./nextcloud-upgrade.sh -up owncloud -d /var/www/owncloud -s /home/www -l -v 9.0.8 >upgrade.log 2>&1`
##

function main() {
    echo -e '\033[1m#Starting owncloud/nextcloud upgrade\033[0m'
    echo "-- "$(date +%F-%H-%M-%S)" --"
    echo "-----------------------------------"
    readvars "$@"

    # Moving to working directory (SAVE)
    manage_permissions "start"

    # dependencies
    DEPS=( curl wget grep awk sed gpg tar php mysql mysqldump sudo ) # rsync
    check_dependencies

    # get enabled 3rdparty apps name
    test ${LOG} = 'true' && echo -n "[LOG] Checking APPS... "
    APPS=$(
        sudo -u www-data php $DIR/occ app:list --shipped=false | \
        grep -E 'true|([0-9]\.?)+' | \
        awk '{ print $2 }' | \
        sed 's/://'
    )
    test ${LOG} = 'true' && echo "APPS="${APPS}

    # get database information from nextcloud configuration
    DBNAME=$(php -r 'require $argv[1]."config/config.php"; echo $CONFIG["dbname"];' $DIR)
    DBHOST=$(php -r 'require $argv[1]."config/config.php"; echo $CONFIG["dbhost"];' $DIR)
    DBUSER=$(php -r 'require $argv[1]."config/config.php"; echo $CONFIG["dbuser"];' $DIR)
    DBPASS=$(php -r 'require $argv[1]."config/config.php"; echo $CONFIG["dbpassword"];' $DIR)
    test ${LOG} = 'true' && echo "[LOG] DBNAME="${DBNAME}"; DBHOST="${DBHOST}"; DBUSER="${DBUSER}"; DBPASS="${DBPASS}

    # if empty, get latest version number from arg or from GitHub
    if [ -z $LATEST_VERSION ]; then
	    # Warning : does not work with owncloud
	    test ${LOG} = 'true' && echo -n "[LOG] Fetching LATEST_VERSION... "
        LATEST_VERSION=$(
            curl -s https://api.github.com/repos/$DEST/server/releases/latest | \
            grep 'tag_name' | \
            awk '{ print $2 }' | \
            sed 's/[,|"|v]//g'
        )
        test ${LOG} = 'true' && echo "LATEST_VERSION="${LATEST_VERSION}
    fi
    # get product and installed version number
    test ${LOG} = 'true' && echo -n "[LOG] Getting infos on installed instance... "
    CURRENT_VERSION=$(sudo -u www-data php $DIR/occ -V | awk '{ print $3 }')
    PRODUCT=$(
        sudo -u www-data php $DIR/occ -V | \
        awk '{ print $1 }' | \
        tr '[:upper:]' '[:lower:]'
    )
    test ${LOG} = 'true' && echo ${PRODUCT}" "${CURRENT_VERSION}" ; upgrade to "${DEST}" "${LATEST_VERSION}

    echo -e '\033[1m#-- check version\033[0m'

    if [ $CURRENT_VERSION == $LATEST_VERSION ]; then
        echo '[WARNING] Already latest version'
        exit 0
    fi

    download
    if [ $? != 0 ]; then
        echo '[ERROR] Error while downloading'
        exit 1
    fi
    backup
    if [ $? != 0 ]; then
        echo '[ERROR] Error while backuping'
        exit 1
    fi
    upgrade
    if [ $? != 0 ]; then
        echo '[ERROR] Error while upgrading'
        restore
        exit 1
    fi
    clean

    # Restore folders permissions
    manage_permissions "end"
}

function readvars() {
    echo -e '\033[1m#-- read vars\033[0m'

    DEST="nextcloud"
    KEEP_BACKUP="true"
    SAVE=$(pwd)
    LOG='false'

    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -up|--upgrade)
            if [ "$2" = "owncloud" ] || [ "$2" = "nextcloud" ]; then
                DEST="${2}"
            else
                echo "[WARNING] Unrecognized choice (owncloud vs nextcloud: "$2"). Default is nextcloud."
                DEST="nextcloud"
            fi
            shift
            ;;
        -d|--dir)
            if [ -w "$2" ]; then
                # ${VAR//ab/yz} replace all sub-chains 'ab' from VAR by 'yz'
                DIR="${2}/"
                DIR="${DIR//'//'//}"
            else
                echo "[ERROR] Invalid install dir : "$2
                exit 1
            fi
            shift
            ;;
        -s|--save)
            if [ -w "$2" ]; then
                SAVE="${2}/"
                SAVE="${SAVE//'//'//}"
            else
                echo "[WARNING] Invalid save dir : "$2
                echo -n "> Save in current directory (y|o, default) or no save (n) ? "
                read answer
                if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
                    KEEP_BACKUP='false'
                fi
            fi
            shift
            ;;
        -v|--version)
            LATEST_VERSION="$2"
            shift
            ;;
        -l|--log)
            LOG='true'
            ;;
        *)
            echo "[WARNING] Unkown option: $1"
            ;;
    esac
    shift
    done

    test ${LOG} = 'true' && echo "[LOG] DEST="${DEST}"; DIR="${DIR}"; SAVE="${SAVE}"; VERSION="${LATEST_VERSION}"; KEEP_BACKUP="${KEEP_BACKUP}
    return 0
}

function download() {
    echo -e '\033[1m#-- download\033[0m'

	# Building URLs
    FILENAME=$DEST'-'$LATEST_VERSION'.tar.bz2'
    if [ $DEST = "owncloud" ]; then
        DOWNLOAD_URL='https://download.'$DEST'.org/community/'$FILENAME
        GPG_PUBKEY_URL='https://'$DEST'.org/'$DEST'.asc'
        GPG_FINGERPRINT='F6978A26'
    else
        DOWNLOAD_URL='https://download.'$DEST'.com/server/releases/'$FILENAME
        GPG_PUBKEY_URL='https://'$DEST'.com/'$DEST'.asc'
        GPG_FINGERPRINT='A724937A'
    fi
    GPG_SIG_URL=$DOWNLOAD_URL'.asc'
    test ${LOG} = 'true' && echo "[LOG] DOWNLOAD_URL="${DOWNLOAD_URL}
    test ${LOG} = 'true' && echo "[LOG] GPG_PUBKEY_URL="${GPG_PUBKEY_URL}

    # download nextcloud and its signature file
    if [ ! -e ${FILENAME} ]; then
        test ${LOG} = 'true' && echo "[LOG] Downloading version and signature..."
        # check if we use Wheezy (version 7)
        while read ligne; do
            if [ ${ligne:0:1} = "7" ]; then
                wget -q --progress=bar ${DOWNLOAD_URL}
                wget -q --progress=bar ${GPG_SIG_URL}
                wget -q --progress=bar $GPG_PUBKEY_URL -O - | gpg -q --import -
            else
                wget -q --show-progress ${DOWNLOAD_URL}
                wget -q --show-progress ${GPG_SIG_URL}
                wget -q --show-progress $GPG_PUBKEY_URL -O - | gpg -q --import -
            fi
        done < /etc/debian_version
    fi

    # check integrity of the downloaded file
    test ${LOG} = 'true' && echo "[LOG] Checking integrity..."
    gpg -q --verify ${FILENAME}.asc $FILENAME 2> /dev/null
    if [ $? != 0 ]; then
        echo '[ERROR] Mismatch between file and its signature'
        exit 1
    fi

    return 0
}

function backup() {
    echo -e '\033[1m#-- backup\033[0m'

    TEMP=${DIR%/} # ${DIR%/} Remove ending / ; ${TEMP##/*/} keep only dir name
    SAVE=${SAVE}${TEMP##/*/}"-"$PRODUCT"-"${CURRENT_VERSION}"_"$(date +%F-%H-%M-%S)
    test ${LOG} = 'true' && echo "[LOG] SAVE="${SAVE}

    # enable mode maintenance
    test ${LOG} = 'true' && echo "[LOG] Maintenance mode on..."
    sudo -u www-data php $DIR/occ maintenance:mode --on

    # backup nextcloud directory and database
    test ${LOG} = 'true' && echo -n "[LOG] Dumping directory and database... "
    #~ rsync -ac --include="code/data/" --exclude="data" $DIR $SAVE
    cp -a ${DIR%/} ${SAVE} # ${DIR%/} removes the ending slash
    mysqldump -h $DBHOST -u $DBUSER -p$DBPASS -B $DBNAME > ${SAVE}.sql 2> /dev/null
    test ${LOG} = 'true' && echo "mysqldump="$?

    return 0
}

function restore() {
    echo -e '\033[1m#-- restore\033[0m'

    if [ ! -d $SAVE ]; then
        echo '[ERROR] backup is missing'
        exit 1
    fi

    # restore nextcloud directory and database
    test ${LOG} = 'true' && echo -n "[LOG] Restoring directory and database... "
    #~ rsync -ac --delete --include="code/data/" --exclude="data" $SAVE $DIR
    rm -rf ${DIR}
    cp -a ${SAVE} ${DIR%/} # ${DIR%/} removes the ending slash
    #~ find ${DIR} -name '.git*' -exec rm -R {} \;
    mysql -h $DBHOST -u $DBUSER -p$DBPASS -D $DBNAME < ${SAVE}.sql 2> /dev/null
    test ${LOG} = 'true' && echo "mysql="$?

    # disable mode maintenance
    test ${LOG} = 'true' && echo "[LOG] Maintenance mode off..."
    sudo -u www-data php $DIR/occ maintenance:mode --off

    return 0
}

function upgrade() {
    echo -e '\033[1m#-- upgrade\033[0m'

    # extract downloaded archive and delete it
    test ${LOG} = 'true' && echo "[LOG] Extract archive..."
    tar -xaf $FILENAME

    # restore configuration
    test ${LOG} = 'true' && echo "[LOG] Copy config.php to new dir..."
    #~ rsync -ac $SAVE/config/config.php $DEST/config/
    cp -a ${SAVE}/config/config.php ${DEST}/config/
    # patch https://help.nextcloud.com/t/owncloud-9-1-4-2-migration-to-nextcloud-not-working/8630
    test ${CURRENT_VERSION} = '9.1.4' && sed -i -e "s/9.1.4/9.1.3/g" ${DEST}/config/config.php

    # restore 3rdparty apps
    test ${LOG} = 'true' && echo "[LOG] Copy Apps to new dir..."
    for app in $APPS; do
        test ${LOG} = 'true' && echo "     - "${app}
        #~ rsync -ac $SAVE/apps/$app $DEST/apps/
        cp -a ${SAVE}/apps/$app ${DEST}/apps
    done

    # replace installed nextcloud by the updated one
    test ${LOG} = 'true' && echo "[LOG] Replace by new version..."
    #~ rsync -ac --delete --include="code/data/" --exclude="data" $DEST/ $DIR # --exclude=".[git|bzr|svn]*"
    test -d ${SAVE} && rm -rf ${DIR} # delete only if a backup exists
    cp -a ${DEST} ${DIR%/} # ${DIR%/} removes the ending slash
    test ${DEST} = 'owncloud' && find ${DIR} -name '.git*' -exec rm -rf {} \;

    # Adjust folders permissions
    manage_permissions "upgrade"

    # disable mode maintenance
    test ${LOG} = 'true' && echo "[LOG] Maintenance mode off..."
    sudo -u www-data php $DIR/occ maintenance:mode --off

    # launch nextcloud upgrade process
    test ${LOG} = 'true' && echo "[LOG] Start occ upgrade..."
    if [ ${LATEST_VERSION%.*} = '11.0' ]; then
        # patch https://github.com/nextcloud/server/issues/3616
        # option --skip-migration-test does not work for all 11.0.x versions
        sudo -u www-data php $DIR/occ upgrade
    else
        sudo -u www-data php $DIR/occ upgrade --skip-migration-test
    fi

    # update .htaccess to handle pretty url
    test ${LOG} = 'true' && echo "[LOG] Update .htaccess..."
    sudo -u www-data php $DIR/occ maintenance:update:htaccess

    # re-enable 3rdparty apps
    test ${LOG} = 'true' && echo "[LOG] Reenable Apps one by one..."
    for app in $APPS; do
        sudo -u www-data php $DIR/occ app:enable $app
    done

    # check state of the owncloud installation after upgrade
    test ${LOG} = 'true' && echo -n "[LOG] Checking state and integrity post install... "
    STATE=$(sudo -u www-data php $DIR/occ status | grep 'installed' | awk '{ print $3 }')
    INTEGRITY=$(
        sudo -u www-data php $DIR/occ integrity:check-core | \
        grep 'INVALID_HASH' | \
        sed 's/[-|\s|:]//g'
    )
    test ${LOG} = 'true' && echo "STATE="${STATE}"; INTEGRITY="${INTEGRITY}
    if [ $STATE != 'true' ] || [ ! -z $INTEGRITY ]; then
        return 1
    fi

    return 0
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

function manage_permissions() {
	if [[ "$1" == "start" ]]; then
        test ${LOG} = 'true' && echo "[LOG] Moving to 'save' directory..."
        cd ${SAVE}
    elif [[ "$1" == "upgrade" ]]; then
        # Update permissions to be sure there is no problem with the script
        test ${LOG} = 'true' && echo "[LOG] Updating permissions..."
        chown -R www-data:www-data ${DIR}
    elif [[ "$1" == "end" ]]; then
        # Restore permissions
        test ${LOG} = 'true' && echo "[LOG] Restoring permissions..."
        chown -R root:www-data ${DIR}
        chmod -R o-rwx ${DIR}
        chown -R www-data:www-data ${DIR}"config"
        chown -R www-data:www-data ${DIR}"apps"
    fi

    return 0
}

function clean() {
    echo -e '\033[1m#-- clear\033[0m'

    test ${LOG} = 'true' && echo "[LOG] Removing tempory directory..."
    rm -rf $DEST
    if [ $KEEP_BACKUP != 'true' ]; then
        test ${LOG} = 'true' && echo "[LOG] Removing directory and SQL backup..."
        rm -rf $SAVE
        rm -f $SAVE.sql
    fi

    return 0
}

if [[ "$BASH_SOURCE" == "$0" ]]; then
    main "$@"
fi
