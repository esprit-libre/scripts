#!/bin/bash

set -e

readonly VERSION='1.6'
readonly DATE='26 jul. 2017'

shopt -s expand_aliases

usage() {
	echo ''
	echo '$(basename "${0}") -c[onfig] <config_file> [ OPTIONS ]'
	echo ''
	echo 'OPTIONS = { -v[ersion] | -h[elp] | -d[ebug] }'
	echo 'OPTIONS = { -n[extcloud <NC_WWW_PATH> }'
	echo ''
	echo 'This script intend to create users if they does not exists.'
	echo 'Informations are fetch from an external file in parameter'
	echo '[TODO] If a user already exists, it will update its information.'
	echo ''
}

version() {
	echo "$(basename "${0}") - version ${VERSION} - ${DATE}."
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
			-n|-nextcloud)
				NC_WWW_PATH="${2}"
				log "${INFO}nextcloud path is '${NC_WWW_PATH}'"
				shift
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
		log "${ERR}Missing config file"
		usage
		return 1
	fi
}

linux_user() {
	if [ -n "${GROUP}" -a $(grep -c -e ${GROUP}: /etc/group) -eq 0 ]; then
		log "${INFO}Group '${GROUP}' does not exist. Creating it..."
		groupadd "${GROUP}" > /dev/null 2>&1 && log "${OK}Group '${GROUP}' created." || log "${ERR}Group '${GROUP}' not created with error ${?}."
	fi

	if [ -z "${UNIXPASS}" ]; then
		echo "Please enter user password:"
		read UNIXPASS
	fi

	local COMMAND="${GROUP} ${USERNAME}"
	if [ $(grep -c -e ${USERNAME}: /etc/passwd) -ne 0 ]; then
		log "${WARN}User already exists. Updating information."
		usermod -g ${COMMAND}
	else
		useradd -m -Ng ${COMMAND}
	fi
	if [ ${?} -eq 0 ]; then
		log "${OK}User '${USERNAME}' created or modified."
	else
		log "${ERR}User '${USERNAME}' not created with error ${?}."
		return 2
	fi
	echo -e "${UNIXPASS}\n${UNIXPASS}" | (passwd ${USERNAME}) > /dev/null 2>&1
	for status in "${PIPESTATUS[@]}"; do
		if [ ${status} -ne 0 ] ; then
			log "${ERR}'${USERNAME}' password change finished with error ${?}."
			return 3
		fi
	done
	log "${OK}Samba access created for user '${USERNAME}'."

	if [ -d "${USERPATH}" ]; then
		log "${INFO}Creating user space in ${USERPATH}"
		mkdir -p ${USERPATH}/${USERNAME}
		chown -R ${USERNAME}:${GROUP} ${USERPATH}/${USERNAME}
		chmod -R o-rwx ${USERPATH}/${USERNAME}
	else
		log "${WARN}Path '${USERPATH}' does not exist or is not dir. No user path created."
	fi
}

samba_user() {
	echo -e "${UNIXPASS}\n${UNIXPASS}" | (smbpasswd -a -s ${USERNAME})
	for status in "${PIPESTATUS[@]}"; do
		if [ ${status} -ne 0 ] ; then
			log "${ERR}Samba access failed for user '${USERNAME}' with error ${?}."
			return 4
		fi
	done
	log "${OK}Samba access created for user '${USERNAME}'."
}

mail_user() {
	# Dovecot
	if [ -d "${MAILPATH}" ]; then
		log "${INFO}Creating user mail space in ${MAILPATH}"
		mkdir -p ${MAILPATH}/${USERNAME}/Mail
		maildirmake.dovecot ${MAILPATH}/${USERNAME}/Mail ${USERNAME}
		chown -R ${USERNAME}:${GROUP} ${MAILPATH}/${USERNAME}
		chmod -R 700 ${MAILPATH}/${USERNAME}
	else
		log "${WARN}Path '${MAILPATH}' does not exist or is not dir. No user path created."
		return 5
	fi

	# Fetchmail
	echo "set postmaster '${USERNAME}'" > /home/${USERNAME}/.fetchmailrc
	echo "set logfile '/var/log/mails/${USERNAME}-fetchmail.log'" >> /home/${USERNAME}/.fetchmailrc
	echo "set bouncemail" >> /home/${USERNAME}/.fetchmailrc
	echo "set no spambounce" >> /home/${USERNAME}/.fetchmailrc
	echo "poll ${MAILSERV} proto ${MAILPROTO}" >> /home/${USERNAME}/.fetchmailrc
	echo "user '${USERMAIL}' there has password '${MAILPASS}'" >> /home/${USERNAME}/.fetchmailrc
	echo "mda '/usr/bin/procmail -f %F'" >> /home/${USERNAME}/.fetchmailrc

	chown ${USERNAME}:${GROUP} /home/${USERNAME}/.fetchmailrc
	chmod 600 /home/${USERNAME}/.fetchmailrc

	# Procmail
	echo "# Use maildir-style mailbox in user's home directory" > /home/${USERNAME}/.procmailrc
	echo "DEFAULT=/data/mails/${USERNAME}/Mail/" >> /home/${USERNAME}/.procmailrc
	echo "MAILDIR=/data/mails/${USERNAME}/Mail/" >> /home/${USERNAME}/.procmailrc
	echo "LOGFILE=/var/log/mails/${USERNAME}-procmail.log" >> /home/${USERNAME}/.procmailrc
	echo "VERBOSE=off" >> /home/${USERNAME}/.procmailrc

	chown ${USERNAME}:${GROUP} /home/${USERNAME}/.procmailrc
	chmod 710 /home/${USERNAME}/.procmailrc

	# Log files
	if [ ! -d "/var/log/mails/" ]; then
		mkdir -p /var/log/mails/
		log "${INFO}Log path created (/var/log/mails)"
	fi
	touch /var/log/mails/${USERNAME}-fetchmail.log
	touch /var/log/mails/${USERNAME}-procmail.log
	chown ${USERNAME}:${GROUP} /var/log/mails/${USERNAME}*
	chmod 600 /var/log/mails/${USERNAME}*

	# Crontab
	log "${INFO}Setting up cron job"
	sed -i "/ ${USERNAME} /d" /etc/crontab #to avoid removal of similar names like
	sed -i "/ ${USERNAME}$/d" /etc/crontab # 'pierrel' removed with 'pierre' case
	echo "# Fetchmail de l'utilisateur ${USERNAME}" >> /etc/crontab
	echo "*/15 0-7 * * * ${USERNAME} fetchmail --keep >/dev/null 2>&1" >> /etc/crontab
	echo "*/2 8-18 * * * ${USERNAME} fetchmail --keep >/dev/null 2>&1" >> /etc/crontab
	echo "*/15 19-23 * * * ${USERNAME} fetchmail --keep >/dev/null 2>&1" >> /etc/crontab
}

nextcloud_user() {
	log "${INFO}Creating user in nextcloud env..."
	local LAST_SEEN=$(su -s /bin/bash www-data -c 'php /var/www/cloud/occ user:lastseen '"${USERNAME}")
	export OC_PASS="${UNIXPASS}"
	if [ "${LAST_SEEN}" = "User does not exist" ]; then
		su -s /bin/bash www-data -c 'php /var/www/cloud/occ user:add --group='"${GROUP}"' --password-from-env '"${USERNAME}"
	else
		su -s /bin/bash www-data -c 'php /var/www/cloud/occ user:resetpassword --password-from-env '"${USERNAME}"
	fi
	[ ${?} -ne 0 ] && return 6
	su -s /bin/bash www-data -c 'php /var/www/cloud/occ user:setting '"${USERNAME}"' settings email '"${USERMAIL}"
}

processing() {
	while read line; do
		local extract=${line%%#*} # purge comments

		if [ ${#extract} -gt 0 ]; then
			log "${INFO}Ligne: ${extract}"

			# variables
			local USERNAME=$(echo ${extract} | cut -f1 -d\,)
			local GROUP=$(echo ${extract} | cut -f2 -d\,)
			local UNIXPASS=$(echo ${extract} | cut -f3 -d\,)
			local USERPATH=$(echo ${extract} | cut -f4 -d\,)
			local USERMAIL=$(echo ${extract} | cut -f5 -d\,)
			local MAILPROTO=$(echo ${extract} | cut -f6 -d\,)
			local MAILSERV=$(echo ${extract} | cut -f7 -d\,)
			local MAILPASS=$(echo ${extract} | cut -f8 -d\,)
			local MAILPATH=$(echo ${extract} | cut -f9 -d\,)

			if [ -z "${USERNAME}" ]; then
				log "${ERR}Missing user login."
				continue
			fi

			linux_user
			[ ${?} -ne 0 ] && continue

			samba_user
			[ ${?} -ne 0 ] && continue

			if [ -z "${USERMAIL}" ] || [[ ! "${USERMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]]; then
				log "${ERR}Invalid mail: ${USERMAIL}. Nothing done."
				continue
			fi
			if [ -z "${MAILPROTO}" ] || [[ ! "${MAILPROTO}" =~ ^(imap|pop3)$ ]]; then
				log "${ERR}Invalid mail protocol: ${MAILPROTO}. Nothing done."
				continue
			fi
			if [ -z "${MAILSERV}" ]; then
			# https://www.developpez.net/forums/d933281/systemes/linux/shell-commandes-gnu/expression-reguliere-mail/#post5257432
				log "${ERR}No mail server defined: ${USERMAIL}. Nothing done."
				continue
			fi

			mail_user
			[ ${?} -ne 0 ] && continue

			if [ -d ${NC_WWW_PATH} ]; then
				nextcloud_user
				[ ${?} -ne 0 ] && continue
			fi
		fi
	done < ${CONFIG}
}

main "$@"
