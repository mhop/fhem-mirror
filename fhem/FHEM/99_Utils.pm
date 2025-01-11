##############################################
# $Id$
package main;

use strict;
use warnings;

sub
Utils_Initialize($$)
{
  my ($hash) = @_;
}

sub
time_str2num($)
{
  my ($str) = @_;
  my @a;
  return time() if(!$str);
  @a = split("[T: -]", $str); # 31652, 110545, 
  return mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
}

sub
min(@)
{
  my ($min, @vars) = @_; 
  return $min if(!defined($min));
  for (@vars) {
    $min = $_ if $_ lt $min;
  }           
  return $min;
}

sub
max(@)
{
  my ($max, @vars) = @_; 
  return $max if(!defined($max));
  for (@vars) {
    $max = $_ if $_ gt $max;
  }           
  return $max;
}

sub
minNum($@)
{             
  my ($min, @vars) = @_; 
  for (@vars) {
    $min = $_ if $_ < $min;
  }           
  return $min;
}

sub
maxNum($@)
{             
  my ($max, @vars) = @_; 
  for (@vars) {
    $max = $_ if $_ > $max;
  }           
  return $max;
}


sub
abstime2rel($)
{
  my ($h,$m,$s) = split(":", shift);
  $m = 0 if(!$m);
  $s = 0 if(!$s);
  my $t1 = 3600*$h+60*$m+$s;

  my @now = localtime;
  my $t2 = 3600*$now[2]+60*$now[1]+$now[0];
  my $diff = $t1-$t2;
  $diff += 86400 if($diff <= 0);

  return sprintf("%02d:%02d:%02d", $diff/3600, ($diff/60)%60, $diff%60);
}

sub
defInfo($;$)
{
  my ($search,$internal) = @_;
  $internal = 'DEF' unless defined($internal);
  my @ret;
  my @etDev = devspec2array($search);
  foreach my $d (@etDev) {
    next unless $d;
    next if($d eq $search && !$defs{$d});
    push @ret, $defs{$d}{$internal};
  }
  return @ret;
}

my ($SVG_lt, $SVG_ltstr);
sub
SVG_time_to_sec($)
{
  my ($str) = @_;
  if(!$str) {
    return 0;
  }
  my ($y,$m,$d,$h,$mi,$s) = split("[-_:]", $str);
  $s = 0 if(!$s);
  $mi= 0 if(!$mi);
  $h = 0 if(!$h);
  $d = 1 if(!$d);
  $m = 1 if(!$m);

  if(!$SVG_ltstr || $SVG_ltstr ne "$y-$m-$d-$h") { # 2.5x faster
    $SVG_lt = mktime(0,0,$h,$d,$m-1,$y-1900,0,0,-1);
    $SVG_ltstr = "$y-$m-$d-$h";
  }
  return $s+$mi*60+$SVG_lt;
}


######## trim #####################################################
# What  : cuts blankspaces from the beginning and end of a string
# Call  : { trim(" Hello ") }
# Source: http://www.somacon.com/p114.php , 
#         http://www.fhemwiki.de/wiki/TRIM-Funktion-Anfangs/EndLeerzeichen_aus_Strings_entfernen
sub trim($)
{ 
   my $string = shift;
   $string =~ s/^\s+//;
   $string =~ s/\s+$//;
   return $string;
} 

######## ltrim ####################################################
# What  : cuts blankspaces from the beginning of a string
# Call  : { ltrim(" Hello") }
# Source: http://www.somacon.com/p114.php , 
#         http://www.fhemwiki.de/wiki/TRIM-Funktion-Anfangs/EndLeerzeichen_aus_Strings_entfernensub ltrim($)
sub ltrim($)
{
   my $string = shift;
   $string =~ s/^\s+//;
   return $string;
}

######## rtrim ####################################################
# What  : cuts blankspaces from the end of a string
# Call  : { rtrim("Hello ") }
# Source: http://www.somacon.com/p114.php , 
#         http://www.fhemwiki.de/wiki/TRIM-Funktion-Anfangs/EndLeerzeichen_aus_Strings_entfernensub ltrim($)
sub rtrim($)
{
   my $string = shift;
   $string =~ s/\s+$//;
   return $string;
}

######## UntoggleDirect ###########################################
# What  : For devices paired directly, converts state 'toggle' into 'on' or 'off'
# Call  : { UntoggleDirect("myDevice") }
#         define untoggle_myDevice notify myDevice { UntoggleDirect("myDevice") }
# Source: http://www.fhemwiki.de/wiki/FS20_Toggle_Events_auf_On/Off_umsetzen
sub UntoggleDirect($) 
{
 my ($obj) = shift;
 Log 4, "UntoggleDirect($obj)";
 if (Value($obj) eq "toggle"){
   if (OldValue($obj) eq "off") {
     {fhem ("setstate ".$obj." on")}
   }
   else {
     {fhem ("setstate ".$obj." off")}
   }
 }
 else {
   {fhem "setstate ".$obj." ".Value($obj)}
 }  
}


######## UntoggleIndirect #########################################
# What  : For devices paired indirectly, switches the target device 'on' or 'off' also when a 'toggle' was sent from the source device
# Call  : { UntoggleIndirect("mySensorDevice","myActorDevice","50%") }
#         define untoggle_mySensorDevice_myActorDevice notify mySensorDevice { UntoggleIndirect("mySensorDevice","myActorDevice","50%%") }
# Source: http://www.fhemwiki.de/wiki/FS20_Toggle_Events_auf_On/Off_umsetzen
sub UntoggleIndirect($$$)
{
  my ($sender, $actor, $dimvalue) = @_;
  Log 4, "UntoggleIndirect($sender, $actor, $dimvalue)";
  if (Value($sender) eq "toggle")
  {
    if (Value($actor) eq "off") {fhem ("set ".$actor." on")}
    else {fhem ("set ".$actor." off")}
  }
  ## workaround for dimming currently not working with indirect pairing
  ## (http://culfw.de/commandref.html: "TODO/Known BUGS - FS20 dim commands should not repeat.")
  elsif (Value($sender) eq "dimup") {fhem ("set ".$actor." dim100%")}
  elsif (Value($sender) eq "dimdown") {fhem ("set ".$actor." ".$dimvalue)}
  elsif (Value($sender) eq "dimupdown")
  {
    if (Value($actor) eq $dimvalue) {fhem ("set ".$actor." dim100%")}
       ## Heuristic above doesn't work if lamp was dimmed, then switched off, then switched on, because state is "on", but the lamp is actually dimmed.
    else {fhem ("set ".$actor." ".$dimvalue)}
    sleep 1;
  }
  ## end of workaround
  else {fhem ("set ".$actor." ".Value($sender))}

  return;
}

sub 
IsInt($)
{
  defined $_[0] && $_[0] =~ /^[+-]?\d+$/;
}

# Small NC replacement: fhemNc("ip:port", "text", waitForReturn);
sub
fhemNc($$$)
{
  my ($addr, $txt, $waitForReturn) = @_;
  my $client = IO::Socket::INET->new(PeerAddr => $addr);
  return "Can't connect to $addr\n" if(!$client);
  syswrite($client, $txt);
  return "" if(!$waitForReturn);
  my ($ret, $buf) = ("", "");
  shutdown($client, 1);
  alarm(5);
  while(sysread($client, $buf, 256) > 0) {
    $ret .= $buf;
  }
  alarm(0);
  close($client);
  return $ret;
}

sub
round($$)
{
  my($v,$n) = @_;
  return sprintf("%.${n}f",$v);
}

sub
sortTopicNum(@)
{
  my ($sseq,@nums) = @_;

  my @sorted = map {$_->[0]}
               sort {$a->[1] cmp $b->[1]}
               map {[$_, pack "C*", split /\./]} @nums;

  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./} @nums;

  if($sseq eq "desc") {
      @sorted = reverse @sorted;
  }

  return @sorted;
}

sub
Svn_GetFile($$;$)
{
  my ($from, $to, $finishFn) = @_;
  require HttpUtils;
  return "Missing argument from or to" if(!$from || !$to);
  return "Forbidden characters in from/to"
                  if($from =~ m/\.\./ || $to =~ m/\.\./ || $to =~ m,^/,);
  HttpUtils_NonblockingGet({
    url=>"https://svn.fhem.de/trac/browser/trunk/fhem/$from?format=txt",
    callback=>sub($$$){ 
      if($_[1]) {
        Log 1, "ERROR Svn_GetFile $from: $_[1]";
        return;
      }
      if(!open(FH,">$to")) {
        Log 1, "ERROR Svn_GetFile $to: $!";
        return;
      }
      print FH $_[2];
      close(FH);
      Log 1, "SVN download of $from to $to finished";
      if($finishFn) {
        eval { &$finishFn; };
        Log 1, $@ if($@);
      }
    }});
  return "Download started, check the FHEM-log";
}

sub
WriteFile($$)
{
  my ($filename, $data) = @_;
  return "Forbidden characters in filename"
        if($filename =~ m/\.\./ || $filename =~ m,^/,);
  if(!open(FH,">$filename")) {
    Log 1, "ERROR WriteFile $filename: $!";
    return;
  }
  print FH $data;
  close(FH);
}

1;

=pod
=item helper
=item summary    FHEM utility functions
=item summary_DE FHEM Hilfsfunktionen
=begin html

<a name="Utils"></a>
<h3>Utils</h3>
<ul>
  This is a collection of functions that can be used module-independent
  in all your own development<br>
  <br>
  <b>Defined functions</b><br><br>
  <ul>
    <li><b>abstime2rel("HH:MM:SS")</b><br>tells you the difference as HH:MM:SS
      between now and the argument</li><br>

    <li><b>IsInt("string")</b><br>returns 1 if the argument is an integer,
      otherwise an empty string (which evaluates to false).
      </li><br>

    <li><b>ltrim("string")</b><br>returns string without leading
      spaces</li><br>

    <li><b>max(str1, str2, ...)</b><br>returns the highest value from a given
      list (sorted alphanumeric)</li><br>

    <li><b>maxNum(num1, num2, ...)</b><br>returns the highest value from a
      given list (sorted numeric)</li><br>

    <li><b>min(str1, str2, ...)</b><br>returns the lowest value from a given
      list (sorted alphanumeric)</li><br>

    <li><b>minNum(num1, num2, ...)</b><br>returns the lowest value from a given
      list (sorted numeric)</li><br>

    <li><b>rtrim("string")</b><br>returns string without trailing
      spaces</li><br>

    <li><b>time_str2num("YYYY-MM-DD HH:MM:SS")</b><br>convert a time string to
      number of seconds since 1970</li><br>

    <li><b>trim("string")</b><br>returns string without leading and without
      trailing spaces</li><br>

    <li><b>UntoggleDirect("deviceName")</b><br>For devices paired directly,
       converts state 'toggle' into 'on' or 'off'</li><br>

    <li><b>UntoggleIndirect()</b><br>For devices paired indirectly, switches
      the target device 'on' or 'off', also when a 'toggle' was sent from the
      source device</li><br>

    <li><b>defInfo("devspec", "internal")</b><br>return an array with the
      internal values of all devices found with devspec, e.g.
      defInfo("TYPE=SVG", "GPLOTFILE").</li><br>

    <li><b>SVG_time_to_sec("YYYY-MM-DD_HH:MM:SS")</b><br>converts the argument
      to the number of seconds since 1970. Optimized for repeated use of similar
      timestamps.</li><br>

    <li><b>fhemNc("host:port", "textToSend", waitForReturn)</b><br>
      sends textToSend to host:port, and if waitForReturn is set, then read
      the answer (wait up to 5 seconds) and return it. Intended as small
      nc replacement.
      </li><br>

    <li><b>round(value, digits)</b><br>
      round &lt;value&gt; to given digits behind comma
      </li><br>

    <li><b>getUniqueId()</b><br>
      return the FHEM uniqueID used by the fheminfo command. Uses the
      getKeyValue / setKeyValue functions.
      </li><br>

    <li><b>setKeyValue(keyName, value)</b><br>
      store the value in the file $modpath/FHEM/FhemUtils/uniqueID (the name is
      used for backward compatibility), or in the database, if using configDB.
      value may not contain newlines, and only one value per key is stored.
      The file/database entry will be written immediately, no explicit save is
      required.  If the value is undef, the entry will be deleted.
      Returns an error-string or undef.
      </li><br>

    <li><b>getKeyValue(keyName)</b><br>
      return ($error, $value), stored previously by setKeyValue.
      $error is set if there was an error.  Both are undef, if there is no
      value yet for this key.
      </li><br>

    <li><b>sortTopicNum("asc"|"desc",&lt;list of numbers&gt;)</b><br>
      sort an array of numbers like x.x.x<br>
      (Forum #98578)
      </li><br>

    <li><b>Svn_GetFile(from, to, [finishFn])</b><br>
      Retrieve a file diretly from the fhem.de SVN server.<br>
      If the third (optional) parameter is set, it must be a function, which is
      executed after the file is saved.
      Example:
      <ul>
        <code>{ Svn_GetFile("contrib/86_FS10.pm", "FHEM/86_FS10.pm") }</code>
        <code>{ Svn_GetFile("contrib/86_FS10.pm", "FHEM/86_FS10.pm", sub(){CommandReload(undef, "86_FS10")}) }</code>
      </ul>
      </li><br>

    <li><b>WriteFile(file, content)</b><br>
      Write a file in/below the curent directory.
      Example:
      <ul>
        attr m2d readingList map:.* { WriteFile("www/images/map.png",$EVENT);; {map=>"images/map.png"} }
        attr m2d devStateIcon { '&lt;img src="fhem/images/map.png" style="max-width:256;;max-height:256;;"&gt;' }

      </ul>
      </li><br>

  </ul>
</ul>
=end html
=cut
