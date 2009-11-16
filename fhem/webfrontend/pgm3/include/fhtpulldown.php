<?php

##Pulldown for FHT--Devices


		$orders=array("mon-from1","mon-to1","tue-from1","tue-to1","wed-from1","wed-to1","thu-from1",
			      "thu-to1","fri-from1","fri-to1","sat-from1","sat-to1","sun-from1","sun-to1",
				"mon-from2","mon-to2","tue-from2","tue-to2","wed-from2","wed-to2","thu-from2",
			      "thu-to2","fri-from2","fri-to2","sat-from2","sat-to2","sun-from2","sun-to2",
				"day-temp","night-temp","desired-temp","report1","report2","windowopen-temp"
			);

		echo "
		<tr>
		<td colspan=1 align=right $bg2><font $fontcolor3>FHT: </font></td><td align=left $bg2><font $fontcolor3>
		<form action=$forwardurl method='POST'>";
		echo"<input type=hidden name=Action value=exec3>
		
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
		<select name=fhtdev size=1>
		<option></option>";
		for ($m=0; $m < count($fhtdevs); $m++)
                        {
				echo $fhtdev;
				if ($fhtdev==$fhtdevs[$m])
				{
					echo "<option selected>$fhtdevs[$m]</option>";
				} else {
					echo "<option>$fhtdevs[$m]</option>";
				}
			};

		echo "
		</select><select name=orderpulldown size=1>
		<option></option>";
		
		for ($m=0; $m < count($orders); $m++)
                        {
				if ($orderpulldown==$orders[$m])
				{
					echo "<option selected>$orders[$m]</option>";
				} else {
					echo "<option>$orders[$m]</option>";
				}
			};
		echo "</select>
		<select name=valuetime size=1>
		<option></option>";
		for ($m=0; $m < 24; $m++)
       	        {
			if ( $m < 10) $m = '0'.$m;
			for ($k=0; $k < 60; $k=$k+5)
		        {	
				if ( $k < 10) $k = '0'.$k;
			  	echo "<option>$m:$k:00</option>";
			}
		}
		echo "<option>*********</option>";
		for ($m=10; $m < 30; $m++)
			 {
				echo "<option>$m.0</option>";
				echo "<option>$m.5</option>";
			}
		if (isset($valuetime))	echo"<option selected>$valuetime</option>";
		echo"</select>";

		echo "<input type=submit value='go!'></form></td></tr>";

?>
