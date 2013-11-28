<HTML>
<HEAD>
</HEAD>
<BODY>
<TITLE>
FS 20 Haussteuerrung
</TITLE>
</BODY>

<?PHP

function is_posint($a) {
   return (((string)$a === (string)(int)$a) && ((int)$a >= 0));
}

function print_options($name, $device, $dimmable, $href)
{
  echo "<A href=\"fs20.php?device=$device&state=toggle&command=set\">";
  echo "$name</A>";
  echo "<FORM action=\"fs20.php\">";
  echo "<SELECT size=1 name=\"state\">";
  echo "<OPTION value=\"off\" selected>Off";
  if ( $dimmable ) {
    echo "<OPTION value=\"dimup\">Up";
    echo "<OPTION value=\"dimdown\">Down";
    echo "<OPTION value=\"dim06%\">6%";
    echo "<OPTION value=\"dim12%\">12%";
    echo "<OPTION value=\"dim18%\">18%";
    echo "<OPTION value=\"dim25%\">25%";
    echo "<OPTION value=\"dim31%\">31%";
    echo "<OPTION value=\"dim37%\">37%";
    echo "<OPTION value=\"dim43%\">43%";
    echo "<OPTION value=\"dim50%\">50%";
    echo "<OPTION value=\"dim56%\">56%";
    echo "<OPTION value=\"dim62%\">62%";
    echo "<OPTION value=\"dim68%\">68%";
    echo "<OPTION value=\"dim75%\">75%";
    echo "<OPTION value=\"dim81%\">81%";
    echo "<OPTION value=\"dim87%\">87%";
    echo "<OPTION value=\"dim93%\">93%";
  }
  echo "<OPTION value=\"dim100%\">100%";
  echo "</SELECT>";
  echo "<INPUT type=\"hidden\" name=\"device\" value=\"$device\">";
  echo "<INPUT type=\"hidden\" name=\"command\" value=\"set\">";
  echo "<BR>";
  echo "<INPUT type=\"submit\" name=\"dim\" value=\"Dim\">";
  echo "</FORM>";
}


function generate_random()
{
  $devices=array("dg.gang", "dg.wand", "dg.dusche", "dg.bad", "dg.reduit", "dg.eltern", "dg.kino", "og.gang", "og.bad.links", "og.bad.rechts", "og.bad.sterne", "og.bad.decke", "og.stefan.decke", "og.stefan.pult", "og.sandra.decke", "og.kind.r", "og.kind.l", "eg.sitzplatz", "eg.wohnzimmer", "eg.bar", "eg.tisch", "eg.decke", "eg.kueche", "eg.bahnlicht", "eg.bad", "eg.gang", "eg.og.treppe", "ug.gast", "ug.gast.dose", "ug.aussen", "ug.gang", "ug.eg.treppe");

  #number of events (min - max)
  $event_min=isset($_GET['event_min']) ? $_GET['event_min'] : 5;
  $event_max=isset($_GET['event_max']) ? $_GET['event_max'] : 20;

  #maximum delay in minutes
  $delay_min=isset($_GET['delay_min']) ? $_GET['delay_min'] : 0;
  $delay_max=isset($_GET['delay_max']) ? $_GET['delay_max'] : 240;

  #minimum and maximum ontime in minutes
  $ontime_min=isset($_GET['ontime_min']) ? $_GET['ontime_min'] : 5;
  $ontime_max=isset($_GET['ontime_max']) ? $_GET['ontime_max'] : 60;

  $variant=isset($_GET['variant']) ? $_GET['variant'] : "onoff";

  echo "<H2>Random event generator (\"holiday-function\")</H2>";
  echo "<FORM action=\"fs20.php\">";
  echo "<TABLE>";
  echo "<TR><TD>Number of events:</TD><TD><INPUT type=\"text\" size=\"3\" name=\"event_min\" value=\"$event_min\">-";
  echo "<INPUT type=\"text\" size=\"3\" name=\"event_max\" value=\"$event_max\">";
  if ( $event_min > $event_max ) { echo " : <FONT color=\"red\">min has to be <= max</FONT>"; unset($_GET['random']); }
  if ( !is_posint($event_min)) { echo " : <FONT color=\"red\">min has to be a integer</FONT>"; unset($_GET['random']); }
  if ( !is_posint($event_max)) { echo " : <FONT color=\"red\">max has to be a integer</FONT>"; unset($_GET['random']); }
  echo "</TD></TR>";
  echo "<TR><TD>Delay from now:</TD><TD><INPUT type=\"text\" size=\"3\" name=\"delay_min\" value=\"$delay_min\">-";
  echo "<INPUT type=\"text\" size=\"3\" name=\"delay_max\" value=\"$delay_max\">Min.";
  if ( $delay_min > $delay_max ) { echo " : <FONT color=\"red\">min has to be <= max</FONT>"; unset($_GET['random']); }
  if ( !is_posint($delay_min)) { echo " : <FONT color=\"red\">min has to be a integer</FONT>"; unset($_GET['random']); }
  if ( !is_posint($delay_max)) { echo " : <FONT color=\"red\">max has to be a integer</FONT>"; unset($_GET['random']); }
  echo "</TD></TR>";
  echo "<TR><TD>Time to keep on:</TD><TD><INPUT type=\"text\" size=\"3\" name=\"ontime_min\" value=\"$ontime_min\">-";
  echo "<INPUT type=\"text\" size=\"3\" name=\"ontime_max\" value=\"$ontime_max\">Min.";
  if ( $ontime_min > $ontime_max ) { echo " : <FONT color=\"red\">min has to be <= max</FONT>"; unset($_GET['random']); }
  if ( !is_posint($ontime_min)) { echo " : <FONT color=\"red\">min has to be a integer</FONT>"; unset($_GET['random']); }
  if ( !is_posint($ontime_max)) { echo " : <FONT color=\"red\">max has to be a integer</FONT>"; unset($_GET['random']); }
  echo "</TD></TR>";
  echo "<TR><TD colspan=\"2\">Varant: <SELECT size=1 name=\"variant\">";
  echo "<OPTION value=\"onoff\"";
  printf("%s", $variant == "onoff" ? " selected" : "");
  echo ">on / off";
  echo "<OPTION value=\"oft\"";
  printf("%s", $variant == "oft" ? " selected" : "");
  echo ">on-for-timer";
  echo "</SELECT>";
  echo "<INPUT type=\"submit\" name=\"random\" value=\"Generate!\">";
  echo "</TD></TR></TABLE>";
  echo "</FORM><P>";

  if ( isset($_GET['random'])) {
    $event=rand($event_min, $event_max);
    echo "Just copy lines below into FHZ1000 command window";
    echo "<pre>";
    for($i=0; $i<$event; $i++) {
 
      $starttime=rand($delay_min, $delay_max);
      $hour=intval($starttime/60);
      $minute=intval($starttime%60);
      $second=rand(0,59);

      $ontime=rand($ontime_min, $ontime_max);

      $dev=$devices[array_rand($devices)];

      if ($variant == "oft") {
        printf("at +%02d:%02d:%02d set %s on-for-timer %d<br>", $hour, $minute, $second, $dev, $ontime);
      } elseif ($variant == "onoff") {
        $offtime=$starttime + $ontime;
        $hour_off=intval($offtime / 60);
        $minute_off=intval($offtime % 60);
        $second_off=rand(0,59);
        printf("at +%02d:%02d:%02d set %s on<br>", $hour, $minute, $second, $dev);
        printf("at +%02d:%02d:%02d set %s off<br>", $hour_off, $minute_off, $second_off, $dev);
      }
    }
    echo "<pre>";
  }
}

?>


<H1>
FS 20 Haussteuerrung
</H1>
Quicklinks: 
<A HREF="#EG">EG</A> 
<A HREF="#GE">Generic</A> 
<A HREF="#RA">Random</A>

<HR>

<A name="EG">
<H2>EG</H2>
</A>

<TABLE background=images/EG.gif width=567 height=589 border=0>
<TR height=100 align=center><TD width=55></TD><TD width=70></TD><TD width=25></TD><TD width=100></TD><TD width=60></TD><TD width=25></TD><TD width=70></TD><TD width=25></TD><TD width=70></TD><TD></TD></TR>
<TR height=120 align=center><TD></TD><TD colspan=2>
<?PHP print_options("BAR", "eg.bar", TRUE, "EG"); ?>
</TD><TD></TD><TD colspan=4>
<?PHP print_options("WOHNZIMMER", "eg.wohnzimmer", TRUE, "EG"); ?>
</TD><TD></TD><TD></TD></TR>
<TR height=20></TR>
<TR height=70 align=center><TD></TD><TD>
<?PHP print_options("BAD", "eg.bad", FALSE, "EG"); ?>
</TD><TD></TD><TD colspan=2>
<?PHP print_options("GANG", "eg.gang", TRUE, "EG"); ?>
</TD><TD></TD><TD>
<?PHP print_options("TREPPE", "eg.og.treppe", FALSE, "EG"); ?>
</TD><TD></TD><TD></TD><TD></TD></TR>
<TR height=20></TR>
<TR height=70 align=center><TD></TD><TD colspan=2>
<?PHP print_options("KUECHE", "eg.kueche", TRUE, "EG"); ?>
</TD><TD></TD><TD colspan=3>
<?PHP print_options("ESSTISCH", "eg.tisch", TRUE, "EG"); ?>
</TD><TD></TD><TD>
<?PHP print_options("BAHNLICHT", "eg.bahnlicht", FALSE, "EG"); ?>
</TD><TD></TD></TR>
<TR height=20 align=center></TR>
<TR height=70 align=center><TD></TD><TD></TD><TD></TD><TD></TD><TD colspan=3>
<?PHP print_options("DECKE", "eg.decke", FALSE, "EG"); ?>
</TD><TD></TD><TD>
<?PHP print_options("SITZPLATZ", "eg.sitzplatz", FALSE, "EG"); ?>
</TD><TD></TD></TR>
<TR></TR>
</TABLE>

<HR>

<A name="GE">
<H2>Send generic command:</H2>
<FORM action="fs20.php">
<?PHP
echo "<INPUT type=\"textarea\" cols=\"80\" rows=\"5\" name=\"generic\"";
printf("value=\"%s\">", isset($_GET['generic']) ? $_GET['generic'] : "");
?>
<INPUT type="submit" name="submit" value="send">
</FORM>

<HR>

<A name="RA">
<?PHP
generate_random();

//execute command
unset($cmdline);

if (isset($_GET['generic'])) {
  $cmdline=explode("\n", $_GET['generic']);
} elseif (isset($_GET['device']) && isset($_GET['state']) && isset($_GET['command'])) {
  $cmdline=array($_GET['command']." ".$_GET['device']." ".$_GET['state']);
}

if (isset($cmdline)) {
  array_push($cmdline, "quit");
  echo "<HR><H2>Last command</H2>";
  echo "<TABLE><TR valign=top><TD>send:</TD><TD>";
  foreach($cmdline as $line) {
    echo "$line<br>";
  }
  echo "</TD></TR></TABLE>";
  echo "<H3><Output></H3>";
  $fp = fsockopen("localhost", 7072, $errno, $errstr, 10);
  if (!$fp) {
    echo "$errstr ($errno)<br>\n";
  } else {
    foreach($cmdline as $line) {
      fwrite($fp, $line."\n");
    }
    echo "<pre>";
    while (!feof($fp)) {
      echo htmlentities(fgets($fp));
    }
    echo "</pre>";
    fclose($fp);
  }

  echo "<HR>";

}

?>

</BODY>
</HTML>
