#!/bin/sh

tar cf - FHEM fhem.cfg fhem.pl log startfhem* www |
gzip -3 > backup/backup-`date -I`.tar.gz
echo backup done
exit 0
