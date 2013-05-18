CREATE DATABASE `fhem` DEFAULT CHARACTER SET utf8 COLLATE utf8_bin;
CREATE USER 'fhemuser'@'%' IDENTIFIED BY 'fhempassword';
CREATE TABLE `fhem`.`history` (TIMESTAMP TIMESTAMP, DEVICE varchar(32), TYPE varchar(32), EVENT varchar(512), READING varchar(32), VALUE varchar(32), UNIT varchar(32));
CREATE TABLE `fhem`.`current` (TIMESTAMP TIMESTAMP, DEVICE varchar(32), TYPE varchar(32), EVENT varchar(512), READING varchar(32), VALUE varchar(32), UNIT varchar(32));
GRANT SELECT, INSERT, DELETE, UPDATE ON `fhem`.* TO 'fhemuser'@'%';
CREATE INDEX Search_Idx ON `fhem`.`history` (DEVICE, READING, TIMESTAMP);

