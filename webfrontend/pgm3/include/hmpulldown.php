<?php

##Pulldown for HomeMatic-Devices


		$order1=array("on","off","toggle","on-for-timer");
		$order2=range(0, 100, 1);
		$order3=array("pair","unpair","statusRequest","sign","raw","reset");
		$order8=array("-- Dim in % --");
		$order9=array("---------------");
		$orders=array_merge($order1, $order9, $order8, $order2, $order9, $order3);

		echo "
		<tr>
		<td colspan=1 align=right $bg2><font $fontcolor3>HomeMatic: </font></td><td align=left $bg2><font $fontcolor3>
		<form action=$forwardurl method='POST'>
		<input type=hidden name=showfht value=$showfht>
		<input type=hidden name=showhms value=$showhms>
		<input type=hidden name=showmenu value=$showmenu>
		<input type=hidden name=Action value=exec4>
		
		<select name=atorder size=1>
		<option></option>;
		<option>at</option></select>
		
		<select name=attime size=1>
		<option></option>;";
		for ($m=0; $m < 24; $m++)
       	        {
			if ( $m < 10) $m = '0'.$m;
			for ($k=0; $k < 60; $k=$k+2)
		        {	
				if ( $k < 10) $k = '0'.$k;
			  	echo "<option>$m:$k:00</option>";
			}
		}
					
		echo"</select>";




		echo"
		set 
		<select name=culhmdev size=1>
		<option value=>HomeMatic Device</option>";
		for ($m=0; $m < count($culhmdevs); $m++)
                        {
				echo $culhmdev;
				if ($culhmdev==$culhmdevs[$m])
				{
					echo "<option selected>$culhmdevs[$m]</option>";
				} else {
					echo "<option>$culhmdevs[$m]</option>";
				}
			};

		echo "
		</select><select name=orderpulldown size=1>
		<option value=>Order</option>";
		
		for ($m=0; $m < count($orders); $m++)
                        {
				if ($orderpulldown==$orders[$m])
				{
					echo "<option selected>$orders[$m]</option>";
				} else {
					echo "<option>$orders[$m]</option>";
				}
			};

		function mknullhm($zahl,$stellen) {
		for($i=strlen($zahl);$i<$stellen;$i++){
		$zahl="0" . $zahl;
		}
		return $zahl;
		}

		echo "</select>
		<select name=valuetime size=1>     
		<option value=>HH:MM:SS</option>";
		for ($m=1; $m < 15360; $m++) {
       	                  if ( $m > 16) $m = $m+1;
       	                  if ( $m > 32) $m = $m+2;
       	                  if ( $m > 64) $m = $m+4;
       	                  if ( $m > 128) $m = $m+8;
       	                  if ( $m > 256) $m = $m+16;
       	                  if ( $m > 512) $m = $m+32;
       	                  if ( $m > 1024) $m = $m+64;
       	                  if ( $m > 2048) $m = $m+128;
       	                  if ( $m > 4096) $m = $m+256;
       	                  if ( $m > 8192) $m = $m+512;
       	                  if ( $m > 0)
					$sek=$m;
					$std=floor($sek/3600);
					$min=floor(($sek-$std*3600)/60);
					$sec=$sek-$std*3600-$min*60;
					$std=mknullhm($std,2);
					$min=mknullhm($min,2);
					$sec=mknullhm($sec,2); 
				echo "<option value=$m>$std:$min:$sec</option>";}
		
		echo"</select>
		<input type=submit value='go!'></form></td></tr>";

?>
