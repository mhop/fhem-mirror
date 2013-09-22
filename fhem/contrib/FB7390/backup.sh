#!/bin/sh

# optional backup command to speed up backup on th FB by omitting the backup of
# the perl directory. To use it set attr global backupcmd backup.sh

tar cf - FHEM fhem.cfg fhem.pl log startfhem* www |
gzip -3 > backup/backup-`date -I`.tar.gz
echo backup done
exit 0
