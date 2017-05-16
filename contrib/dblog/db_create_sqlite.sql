CREATE TABLE current (TIMESTAMP TIMESTAMP, DEVICE varchar(32), TYPE varchar(32), EVENT varchar(512), READING varchar(32), VALUE varchar(32), UNIT varchar(32));
CREATE TABLE history (TIMESTAMP TIMESTAMP, DEVICE varchar(32), TYPE varchar(32), EVENT varchar(512), READING varchar(32), VALUE varchar(32), UNIT varchar(32));
CREATE INDEX Search_Idx ON `history` (DEVICE, READING, TIMESTAMP);