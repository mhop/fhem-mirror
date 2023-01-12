###################################################################
# Usage:
# ======
#
# - Open a terminal session
# - goto a directory where the datbase should be created
# - create a new database:
#   sudo sqlite3 <file>         (e.g./opt/fhem/fhem.db)
# 
# - change owner and user rights of the new file
#
#   sudo chown fhem /opt/fhem/fhem.db
#   sudo chmod 600 /opt/fhem/fhem.db
#
# - execute the statements shown below
#
###################################################################
PRAGMA auto_vacuum = FULL;
CREATE TABLE history (TIMESTAMP TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, DEVICE varchar(64), TYPE varchar(64), EVENT varchar(512), READING varchar(64), VALUE varchar(128), UNIT varchar(32));
CREATE TABLE current (TIMESTAMP TIMESTAMP, DEVICE varchar(64), TYPE varchar(64), EVENT varchar(512), READING varchar(64), VALUE varchar(128), UNIT varchar(32));
CREATE INDEX Search_Idx ON `history` (DEVICE, READING, TIMESTAMP);
