<?php

##Pulldown for Logfiles
# the path of the logs must be set in config.php. (It may differ from the path in fhem.cfg)


   $showlogfile=       $_POST['logfile'];
   if (! $showlogfile==""){
	include '../config.php';
	$pos=strrpos($showlogfile,'/');
	$lname=substr($showlogfile,$pos+1,strlen($showlogfile));
	$finallog=$logpath.$lname;
	$logorder='cat '.$finallog.' '.$logsort;
	exec($logorder,$logoutput);
	echo "<b>$logorder</b><br><br>";
	foreach($logoutput as $data) echo "$data<br>";
	exit;
      }

   $fs20logfile=       $_POST['fs20logfile'];
   if (! $fs20logfile==""){
	include '../config.php';
	$fhemlog=$_POST['fhemlog'];
	$pos=strrpos($fhemlog,'/');
	$lname=substr($fhemlog,$pos+1,strlen($fhemlog));
	$fhemlog=$logpath.$lname;
	$logorder='grep '.$fs20logfile.' '.$fhemlog.' '.$logsort;
	exec($logorder,$logoutput);
	echo "<b>$logorder</b><br><br>";
	foreach($logoutput as $data) echo "$data<br>";
	exit;
      }





	echo " <tr>
		<td colspan=1 align=right $bg2><font $fontcolor3>Defined Logs:</font>
		</td><td colspan=1 align=left $bg2><font $fontcolor3>
		<form action=include/logpulldown.php method='POST'>
		<input type=hidden name=showlogfile value=$logfile>
		<select name=logfile size=1>
		<option></option>";
		for ($m=0; $m < count($logpaths); $m++)
                        {
				echo "<option>$logpaths[$m]</option>";
			};
	echo " </select>
		<input type=submit value='show'></form></td></tr>

		<tr><td colspan=1 align=right $bg2>
		<font $fontcolor3>FS20-Logs:</font>
		</td><td colspan=1 align=left $bg2><font $fontcolor3>

		<form action=include/logpulldown.php method='POST'>
		<input type=hidden name=showfs20log value=$fs20logfile>
		<input type=hidden name=fhemlog value=$fhemlog>
		<select name=fs20logfile size=1>
		<option></option>";
		for ($m=0; $m < count($fs20devs); $m++)
                        {
				echo "<option>$fs20devs[$m]</option>";
			};
	echo " </select>
		<input type=submit value='show'></form></td></tr>";





?>
