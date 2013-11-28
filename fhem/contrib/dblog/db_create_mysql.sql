CREATE DATABASE `fhem` DEFAULT CHARACTER SET utf8 COLLATE utf8_bin;
CREATE USER 'fhemuser'@'%' IDENTIFIED BY 'fhempassword';
CREATE TABLE history (TIMESTAMP TIMESTAMP, DEVICE varchar(32), TYPE varchar(32), EVENT varchar(64), READING varchar(32), VALUE varchar(32), UNIT varchar(32));
CREATE TABLE current (TIMESTAMP TIMESTAMP, DEVICE varchar(32), TYPE varchar(32), EVENT varchar(64), READING varchar(32), VALUE varchar(32), UNIT varchar(32));
GRANT SELECT, INSERT, DELETE ON `fhem` .* TO 'fhemuser'@'%';


