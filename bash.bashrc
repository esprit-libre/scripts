alias minicom='sudo minicom --color=on --capturefile=~/Public/$(date +%Y).$(date +%m).$(date +%d)-$(date +%H%M)_capture_tty.log'

alias ls='ls --color=auto'
alias ll='ls -AlF'
alias la='ls -A'
alias l='ls -CF'

# Send email for every Shell connection
#echo 'Acces SSH en '`whoami`' sur '`hostname`' le' `date` `who` | mail -s "[`hostname`] SSH "`whoami`" depuis `who | cut -d"(" -f2 | cut -d")" -f1`" my@mail.com
IP="$(who --ips)"
echo -e 'Acces SSH en '`whoami`' sur '`hostname`' le' `date`'\n\n'`who`'\n\n'`who --ips` | mail -s "[`hostname`] SSH "`whoami`" depuis ${IP##* }" my@mail.com

PS1='\n\[\e[1;48;5;31m\] \u@\h \[\e[48;5;240m\] \W \[\e[0m\] '
