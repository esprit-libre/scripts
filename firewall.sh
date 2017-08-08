#!/bin/bash

### BEGIN INIT INFO
# Provides:          firewall
# Required-Start:    $remote_fs $syslog $local_fs $network
# Required-Stop:     $remote_fs $syslog $local_fs $network
# Should-Start:      $named
# Should-Stop:       $named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Applique des règles iptables
# Description:       Ce script contient le paramétrage du pare-feu
### END INIT INFO

# Vider les tables actuelles
iptables -t filter -F # table par défaut
iptables -t nat -F
iptables -t mangle -F

# Vider les règles personnelles
iptables -t filter -X
iptables -t nat -X
iptables -t mangle -X

#-----------------------------------------------------------------------------------------------
# Définitions
#-----------------------------------------------------------------------------------------------
# Adresses IP
IF_ADMIN="x.x.x.x"		# IP d'administration
IF_PROD1="y.y.y.y"		# IP principale du service
#IF_PROD2="w.w.w.w"		# IP secondaire du service
#IF_PROD3="z.z.z.z"		# IP tertiaire du service
#NET_PROD="x.x.x.x/16"			# Masque des IP de service
SUPERVISION_1="a.a.a.a"	# serveur de supervision
#SUPERVISION_2="b.b.b.b"	# serveur de supervision
SUPERVISION_OVH_1="213.186.33.62"
SUPERVISION_OVH_2="92.222.184.0/24"
SUPERVISION_OVH_3="92.222.185.0/24"
SUPERVISION_OVH_4="92.222.186.0/24"
SUPERVISION_OVH_5="167.114.37.0/24"
SUPERVISION_OVH_6="213.186.45.4"
SUPERVISION_OVH_7="213.251.184.9"
SUPERVISION_OVH_8="37.59.0.235"
SUPERVISION_OVH_9="8.33.137.2"
SUPERVISION_OVH_10="213.186.33.13"
SUPERVISION_OVH_11="213.186.50.98"
SUPERVISION_OVH_12="94.23.211.250"
SUPERVISION_OVH_13="94.23.211.251"
SUPERVISION_OVH_14="37.187.231.251"
SUPERVISION_OVH_15="151.80.231.244-151.80.231.247"

# Ports
SSH_PORT="22"			# SSH
HTTP_PORTS="80,443"		# Web
#MONIT_PORT="161"		# SNMP
NAGIOS_PORT="5666"		# Nagios

#-----------------------------------------------------------------------------------------------
# Règles préalables
#-----------------------------------------------------------------------------------------------
# Interdire toute connexion entrante et sortante
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

#-----------------------------------------------------------------------------------------------
# Règles spécifiques au loopback (lo)
#-----------------------------------------------------------------------------------------------
# Tout autoriser sur le loopback
iptables -A INPUT -i lo -j ACCEPT
# Autoriser les serveurs de supervision
iptables -A INPUT -i eth0 -s "$SUPERVISION_1" -j ACCEPT
if [ -n "${SUPERVISION_2}" ]; then
	iptables -A INPUT -i eth0 -s "$SUPERVISION_2" -j ACCEPT
fi
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_1" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_2" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_3" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_4" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_5" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_6" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_7" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_8" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_9" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_10" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_11" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_12" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_13" -j ACCEPT
iptables -A INPUT -i eth0 -s "$SUPERVISION_OVH_14" -j ACCEPT
iptables -A INPUT -i eth0 -m iprange --src-range "$SUPERVISION_OVH_15" -j ACCEPT

#-----------------------------------------------------------------------------------------------
# Règles de sécurité anti-flood et anti-scan
#-----------------------------------------------------------------------------------------------
# Vérifie si l'IP est déjà présente dans une liste noire. Si c'est le cas, on la rejette
# immédiatement, met à jour la liste et l'attaquant est de nouveau blacklisté
iptables -A INPUT -m recent --name blacklist_180 --update --seconds 180 -j DROP         # 3 min
iptables -A INPUT -m recent --name blacklist_21600 --update --seconds 21600 -j DROP     # 6 h

# Rejet des tentative de scan HTTP par l'adresse IP directe
iptables -A INPUT -p tcp --tcp-flags PSH,ACK PSH,ACK --dport 80 -m string --to 700 --algo bm \
  --string 'Host: '$IF_ADMIN -m recent --name blacklist_180 --set -j REJECT --reject-with tcp-reset
iptables -A INPUT -p tcp --tcp-flags PSH,ACK PSH,ACK --dport 80 -m string --to 700 --algo bm \
  --string 'Host: '$IF_PROD1 -m recent --name blacklist_180 --set -j REJECT --reject-with tcp-reset
if [ -n "${IF_PROD2}" ]; then
iptables -A INPUT -p tcp --tcp-flags PSH,ACK PSH,ACK --dport 80 -m string --to 700 --algo bm \
  --string 'Host: '$IF_PROD2 -m recent --name blacklist_180 --set -j REJECT --reject-with tcp-reset
fi
if [ -n "${IF_PROD3}" ]; then
iptables -A INPUT -p tcp --tcp-flags PSH,ACK PSH,ACK --dport 80 -m string --to 700 --algo bm \
  --string 'Host: '$IF_PROD3 -m recent --name blacklist_180 --set -j REJECT --reject-with tcp-reset
fi

# Rejet des script-kiddies
iptables -A INPUT -p tcp --tcp-flags PSH,ACK PSH,ACK --dport 80 -m string --to 700 --algo bm \
  --string 'w00t' -m recent --name blacklist_21600 --set -j REJECT --reject-with tcp-reset

# Rejet des paquets dont l'état de connexion est invalide + logs
iptables -A INPUT -m state --state INVALID -m limit --limit 3/s -j LOG --log-prefix "Invalid INPUT: "
iptables -A INPUT -m state --state INVALID -j DROP

# Rejeter les paquets dont le premier paquet TCP n'est pas SYN + logs des scan des ports TCP
iptables -A INPUT -p TCP ! --tcp-flags ALL SYN -m state --state NEW -m limit --limit 3/s -j LOG \
  --log-prefix "INPUT TCP without SYN: "
iptables -A INPUT -p TCP ! --tcp-flags ALL SYN -m state --state NEW -j DROP

#-----------------------------------------------------------------------------------------------
# Maintient des connexions en cours ou affiliées
#-----------------------------------------------------------------------------------------------
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

#-----------------------------------------------------------------------------------------------
# Règles spécifiques à l'interface d'amin
#-----------------------------------------------------------------------------------------------
# SSH
iptables -A INPUT -i eth0 -p tcp -d "${IF_ADMIN}" --dport "${SSH_PORT}" -m state --state NEW,ESTABLISHED -j ACCEPT

# Monitoring SNMP
if [ -n "${SUPERVISION_1}" -a -n "${MONIT_PORT}" ]; then
	iptables -A INPUT -i eth0 -p udp -d "${IF_ADMIN}" -s "${SUPERVISION_1}" --dport "${MONIT_PORT}" -j ACCEPT
fi

# Monitoring Nagios
if [ -n "${SUPERVISION_1}" -a -n "${NAGIOS_PORT}" ]; then
	iptables -A INPUT -i eth0 -p tcp -d "${IF_ADMIN}" -s "${SUPERVISION_1}" --dport "${NAGIOS_PORT}" -j ACCEPT
fi
if [ -n "${SUPERVISION_2}" -a -n "${NAGIOS_PORT}" ]; then
	iptables -A INPUT -i eth0 -p tcp -d "${IF_ADMIN}" -s "${SUPERVISION_2}" --dport "${NAGIOS_PORT}" -j ACCEPT
fi

#-----------------------------------------------------------------------------------------------
# Règles communes à toutes les interfaces
#-----------------------------------------------------------------------------------------------
# ICMP (Ping)
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-reply -m limit --limit 1/s -j ACCEPT

# ICMP (rejet des notifications de paquets mal adressés)
iptables -A INPUT -p icmp --icmp-type destination-unreachable -m limit --limit 1/s -j LOG \
  --log-prefix "ICMP dest unreach: "
iptables -A INPUT -p icmp --icmp-type destination-unreachable -j DROP

# HTTP + HTTPS  -       Note: la 2e ligne permet les connexions vers les autres serveurs ownCloud
iptables -A INPUT -i eth0 -p tcp -m multiport --dports "${HTTP_PORTS}" -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp -m multiport --sports "${HTTP_PORTS}" -m state --state ESTABLISHED -j ACCEPT

#-----------------------------------------------------------------------------------------------
# Règle OUTBOUND
#-----------------------------------------------------------------------------------------------
# On considère le serveur comme sûr, il peut émettre sans restriction
iptables -A OUTPUT -j ACCEPT

#-----------------------------------------------------------------------------------------------
# Règle par défaut
#-----------------------------------------------------------------------------------------------
# Si aucune règle ne correspond, on logue puis on rejette
iptables -A INPUT -m limit --limit 3/second -j LOG --log-prefix "Bad INPUT: "
iptables -A INPUT -m recent --name blacklist_180 --set -j DROP
