##################################################################################
# Note:
# =====
# The default installation of the MySQL/MariaDB database provides 
# for the use of the utf8mb4_bin collation.
# With this setting characters up to 4 bytes long (e.g. emojis) can be stored.
#  
# If the MySQL/MariaDB version used does not offer utf8mb4 for some reason, utf8 
# can be used instead.
# In this case the MySQL/MariaDB database would be created with the 
# following statement:
#
#   CREATE DATABASE `fhem` DEFAULT CHARACTER SET utf8 COLLATE utf8_bin;  
# 
# instead of the statement:
#
#   CREATE DATABASE `fhem` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
#
# shown in the first line below.
#
##################################################################################
CREATE DATABASE `fhem` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'fhemuser'@'%' IDENTIFIED BY 'fhempassword';
CREATE TABLE `fhem`.`history` (TIMESTAMP TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, DEVICE varchar(64), TYPE varchar(64), EVENT varchar(512), READING varchar(64), VALUE varchar(128), UNIT varchar(32));
CREATE TABLE `fhem`.`current` (TIMESTAMP TIMESTAMP, DEVICE varchar(64), TYPE varchar(64), EVENT varchar(512), READING varchar(64), VALUE varchar(128), UNIT varchar(32));
GRANT SELECT, INSERT, DELETE, UPDATE ON `fhem`.* TO 'fhemuser'@'%';
CREATE INDEX Search_Idx ON `fhem`.`history` (DEVICE, READING, TIMESTAMP) USING BTREE;

