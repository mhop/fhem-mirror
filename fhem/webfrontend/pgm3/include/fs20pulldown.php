<?php

##Pulldown for FS20-Devices


		$orders=array("on","off","dimup","dimdown","on-for-timer","off-for-timer","dim06%","dim12%",
			"dim18%","dim25%","dim31%","dim37%","dim43%","dim50%","dim56%","dim62%","dim68%",
			"dim75%","dim81%","dim87%","dim93%","dim100%","dimupdown","on-old-for-timer","reset",
			"sendstate","timer","toggle");

		echo "
		<tr>
		<td colspan=1 align=right $bg2><font $fontcolor3>FS20: </font></td><td align=left $bg2><font $fontcolor3>
		<form action=$forwardurl method='POST'>
		<input type=hidden name=showfht value=$showfht>
		<input type=hidden name=showhms value=$showhms>
		<input type=hidden name=showmenu value=$showmenu>
		<input type=hidden name=Action value=exec2>
		
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
		<select name=fs20dev size=1>
		<option></option>";
		for ($m=0; $m < count($fs20devs); $m++)
                        {
				echo $fs20dev;
				if ($fs20dev==$fs20devs[$m])
				{
					echo "<option selected>$fs20devs[$m]</option>";
				} else {
					echo "<option>$fs20devs[$m]</option>";
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
		for ($m=0; $m < 6000; $m++)
       	                 {if ( $m > 20) $m = $m+4;
       	                 if ( $m > 60) $m = $m+55;
				echo "<option>$m</option>";}
		
		echo"</select>
		<input type=submit value='go!'></form></td></tr>";

?>
