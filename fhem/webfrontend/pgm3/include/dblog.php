<?php

##DB-Functions for pgm3

include "config.php";



### If DB-query is used, this is the only point of connect. ###
if ($DBUse=="1") {
  @mysql_connect($DBNode, $DBUser, $DBPass) or die("Can't connect");
  @mysql_select_db($DBName) or die("No database found");
}


?>
