CREATE DATABASE `fhem` DEFAULT CHARACTER SET utf8 COLLATE utf8_bin;
CREATE USER 'fhemuser'@'%' IDENTIFIED BY 'fhempassword';
CREATE TABLE `fhem`.`history` (TIMESTAMP TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, DEVICE varchar(64), TYPE varchar(64), EVENT varchar(512), READING varchar(64), VALUE varchar(128), UNIT varchar(32));
CREATE TABLE `fhem`.`current` (TIMESTAMP TIMESTAMP, DEVICE varchar(64), TYPE varchar(64), EVENT varchar(512), READING varchar(64), VALUE varchar(128), UNIT varchar(32));
GRANT SELECT, INSERT, DELETE, UPDATE ON `fhem`.* TO 'fhemuser'@'%';
CREATE INDEX Search_Idx ON `fhem`.`history` (DEVICE, READING, TIMESTAMP);

