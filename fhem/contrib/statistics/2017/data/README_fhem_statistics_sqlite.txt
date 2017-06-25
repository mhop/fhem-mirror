The file "fhem_statistics_2017.sqlite" is the database for the delivered statistics.

It contains the following schema:

CREATE TABLE jsonNodes(uniqueID VARCHAR(32) PRIMARY KEY UNIQUE, lastSeen TIMESTAMP DEFAULT CURRENT_TIMESTAMP, geo BLOB, json BLOB);