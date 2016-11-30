# Send email for every Shell connection
echo 'Acces SSH en '`whoami`' sur '`hostname`' le' `date` `who` | mail -s "[`hostname`] SSH "`whoami`" depuis `who | cut -d"(" -f2 | cut -d")" -f1`" my@mail.com
