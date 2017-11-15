#######################################################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;

sub holiday_refresh($;$$);

#####################################
sub
holiday_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "holiday_Define";
  $hash->{GetFn}    = "holiday_Get";
  $hash->{SetFn}    = "holiday_Set";
  $hash->{UndefFn}  = "holiday_Undef";
  $hash->{AttrList} = $readingFnAttributes;
}


#####################################
sub
holiday_Define($$)
{
  my ($hash, $def) = @_;

  return holiday_refresh($hash->{NAME}, undef, 1) if($init_done);
  InternalTimer(gettimeofday()+1, "holiday_refresh", $hash->{NAME}, 0);
  return undef;
}

sub
holiday_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($name);
  return undef;
}

sub
holiday_refresh($;$$)
{
  my ($name, $fordate, $showAvailable) = (@_);
  my $hash = $defs{$name};
  my $fromTimer=0;

  return if(!$hash);           # Just deleted

  my $nt = gettimeofday();
  my @lt = localtime($nt);
  my @fd;
  if(!$fordate) {
    $fromTimer = 1;
    $fordate = sprintf("%02d-%02d", $lt[4]+1, $lt[3]);
    @fd = @lt;
  } else {
    my ($m,$d) = split("-", $fordate);
    @fd = localtime(mktime(1,1,1,$d,$m-1,$lt[5],0,0,-1));
  }

  Log3 $name, 5, "holiday_refresh $name called for $fordate ($fromTimer)";

  my $dir = $attr{global}{modpath} . "/FHEM";
  my ($err, @holidayfile) = FileRead("$dir/$name.holiday");
  if($err) {
    $dir = $attr{global}{modpath}."/FHEM/holiday";
    ($err, @holidayfile) = FileRead("$dir/$name.holiday");
    $hash->{READONLY} = 1;
  } else {
    $hash->{READONLY} = 0;
  }

  if($err) {
    if($showAvailable) {
      my @ret;
      if(configDBUsed()) {
        @ret = cfgDB_FW_fileList($dir,".*.holiday",@ret);
        map { s/\.configDB$//;$_ } @ret;
      } else {
        if(opendir(DH, $dir)) {
          @ret = grep { m/\.holiday$/ } readdir(DH);
          closedir(DH);
        }
      }
      $err .= "\nAvailable holiday files: ".
              join(" ", map { s/.holiday//;$_ } @ret);
    } else {
      Log 1, "$name: $err";
    }
    return $err;
  }
  $hash->{HOLIDAYFILE} = "$dir/$name.holiday";

  my @foundList;
  foreach my $l (@holidayfile) {
    next if($l =~ m/^\s*#/);
    next if($l =~ m/^\s*$/);
    my $found;

    if($l =~ m/^1/) {               # Exact date: 1 MM-DD Holiday
      my @args = split(" +", $l, 3);
      if($args[1] eq $fordate) {
        $found = $args[2];
      }

    } elsif($l =~ m/^2/) {          # Easter date: 2 +1 Ostermontag

      ###mh new code for easter sunday calc w.o. requirement for
      # DateTime::Event::Easter
      #                   replace $a1 with $1 !!!
      # split line from file into args '2 <offset from E-sunday> <tagname>'
      my @a = split(" ", $l, 3);

      # get month & day for E-sunday
      my ($Om,$Od) = western_easter(($lt[5]+1900));
      my $timex = mktime(0,0,12,$Od,$Om-1, $lt[5],0,0,-1); # gen timevalue
      $timex = $timex + $a[1]*86400; # add offset days

      my ($msecond, $mminute, $mhour,
          $mday, $mmonth, $myear, $mrest) = localtime($timex);
      $myear = $myear+1900;
      $mmonth = $mmonth+1;
      #Log 1, "$name: Ostern:".sprintf("%04d-%02d-%02d", $lt[5]+1900, $Om, $Od).
      #             " Target:".sprintf("%04d-%02d-%02d", $myear, $mmonth, $mday);

      next if($mday != $fd[3] || $mmonth != $fd[4]+1);
      $found = $a[2];
      Log 4, "$name: Match day: $a[2]\n";

    } elsif($l =~ m/^3/) {          # Relative date: 3 -1 Mon 03 Holiday
      my @a = split(" +", $l, 5);
      my %wd = ("Sun"=>0, "Mon"=>1, "Tue"=>2, "Wed"=>3,
                "Thu"=>4, "Fri"=>5, "Sat"=>6);
      my @md = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
      $md[1]=29 if(schaltjahr($fd[5]+1900) && $fd[4] == 1);
      my $wd = $wd{$a[2]};
      if(!defined($wd)) {
        Log 1, "Wrong timespec: $l";
        next;
      }
      next if($wd != $fd[6]);       # Weekday
      next if($a[3] != ($fd[4]+1)); # Month
      if($a[1] > 0) {               # N'th day from the start
        my $d = $fd[3] - ($a[1]-1)*7;
        next if($d < 1 || $d > 7);
      } elsif($a[1] < 0) {          # N'th day from the end
        my $d = $fd[3] - ($a[1]+1)*7;
        my $md = $md[$fd[4]];
        next if($d > $md || $d < $md-6);
      }

      $found = $a[4];

    } elsif($l =~ m/^4/) {          # Interval: 4 MM-DD MM-DD Holiday
      my @args = split(" +", $l, 4);
      if($args[1] le $fordate && $args[2] ge $fordate) {
        $found = $args[3];
      }

    } elsif($l =~ m/^5/) { # nth weekday since MM-DD / before MM-DD
      my @a = split(" +", $l, 6);
      # arguments: 5 <distance> <weekday> <month> <day> <name>
      my %wd = ("Sun"=>0, "Mon"=>1, "Tue"=>2, "Wed"=>3,
                "Thu"=>4, "Fri"=>5, "Sat"=>6);
      my $wd = $wd{$a[2]};
      if(!defined($wd)) {
        Log 1, "Wrong weekday spec: $l";
        next;
      }
      next if $wd != $fd[6]; # check wether weekday matches today
      my $yday=$fd[7];
      # create time object of target date - mktime counts months and their
      # days from 0 instead of 1, so subtract 1 from each
      my $tgt=mktime(0,0,1,$a[4],$a[3]-1,$fd[5],0,0,-1);
      my $tgtmin=$tgt;
      my $tgtmax=$tgt;
      my $weeksecs=7*24*60*60; # 7 days, 24 hours, 60 minutes, 60seconds each
      my $cd=mktime(0,0,1,$fd[3],$fd[4],$fd[5],0,0,-1);
      if ( $a[1] =~ /^-([0-9])*$/ ) {
        $tgtmin -= $1*$weeksecs; # Minimum: target date minus $1 weeks
        $tgtmax = $tgtmin+$weeksecs; # Maximum: one week after minimum
	# needs to be lower than max and greater than or equal to min
        if( ($cd ge $tgtmin) && ( $cd lt $tgtmax) ) {
          $found=$a[5];
	}
      } elsif ( $a[1] =~ /^\+?([0-9])*$/ ) {
        $tgtmin += ($1-1)*$weeksecs; # Minimum: target date plus $1-1 weeks
        $tgtmax = $tgtmin+$weeksecs; # Maximum: one week after minimum
	# needs to be lower than or equal to max and greater min
        if( ($cd gt $tgtmin) && ( $cd le $tgtmax) ) {
          $found=$a[5];
	}
      } else {
        Log 1, "Wrong distance spec: $l";
        next;
      }
    }
    push @foundList, $found if($found);

  }

  push @foundList, "none" if(!int(@foundList));
  my $found = join(", ", @foundList);

  if($fromTimer) {
    RemoveInternalTimer($name);
    $nt -= ($lt[2]*3600+$lt[1]*60+$lt[0]);         # Midnight
    $nt += 86400 + 2;                              # Tomorrow
    $hash->{TRIGGERTIME} = $nt;
    InternalTimer($nt, "holiday_refresh", $name, 0);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state', $found);
    readingsBulkUpdate($hash, 'yesterday', CommandGet(undef,"$name yesterday"));
    readingsBulkUpdate($hash, 'tomorrow',  CommandGet(undef,"$name tomorrow"));
    readingsEndUpdate($hash,1);
    return undef;
  } else {
    return $found;
  }
}

sub
holiday_Set($@)
{
  my ($hash, @a) = @_;

  return "unknown argument $a[1], choose one of createPrivateCopy:noArg"
      if($a[1] ne "createPrivateCopy");
  return "Already a private version" if(!$hash->{READONLY});
  my $fname = $attr{global}{modpath}."/FHEM/holiday/$hash->{NAME}.holiday";
  my ($err, @holidayfile) = FileRead($fname);
  return $err if($err);
  $fname = $attr{global}{modpath}."/FHEM/$hash->{NAME}.holiday";
  $err = FileWrite($fname, @holidayfile);
  holiday_refresh($hash->{NAME});
  return $err;
}

sub
holiday_Get($@)
{
  my ($hash, @a) = @_;

  shift(@a) if($a[1] && $a[1] eq "MM-DD");
  return "argument is missing" if(int(@a) < 2);
  my $arg;

  if($a[1] =~ m/^[01]\d-[0-3]\d/) {
    $arg = $a[1];

  } elsif($a[1] =~ m/^(yesterday|today|tomorrow)$/) {
    my $t = time();
    $t += 86400 if($a[1] eq "tomorrow");
    $t -= 86400 if($a[1] eq "yesterday");
    my @a = localtime($t);
    $arg = sprintf("%02d-%02d", $a[4]+1, $a[3]);

  } elsif($a[1] eq "days") {
    my $t = time() + ($a[2] ? int($a[2]) : 0)*86400;
    my @a = localtime($t);
    $arg = sprintf("%02d-%02d", $a[4]+1, $a[3]);

  } else {
    return "unknown argument $a[1], choose one of ".
      "yesterday:noArg today:noArg tomorrow:noArg days:2,3,4,5,6,7 MM-DD";

  }
  return holiday_refresh($hash->{NAME}, $arg);
}

sub
schaltjahr($)
{
  my($jahr) = @_;
  return 0 if $jahr % 4;       # 2009
  return 1 unless $jahr % 400; # 2000
  return 0 unless $jahr % 100; # 2100
  return 1;                    # 2012
}

### mh sub western_easter copied from cpan Date::Time::Easter
### mh changes marked with # mh
### mh
### mh calling parameter is 4 digit year
### mh
sub
western_easter($)
{
  my $year = shift;
  my $golden_number = $year % 19;

  #quasicentury is so named because its a century, only its 
  # the number of full centuries rather than the current century
  my $quasicentury = int($year / 100);
  my $epact = ($quasicentury - int($quasicentury/4) -
        int(($quasicentury * 8 + 13)/25) + ($golden_number*19) + 15) % 30;

  my $interval = $epact - int($epact/28)*
                (1 - int(29/($epact+1)) * int((21 - $golden_number)/11) );
  my $weekday = ($year + int($year/4) + $interval +
                 2 - $quasicentury + int($quasicentury/4)) % 7;
  
  my $offset = $interval - $weekday;
  my $month = 3 + int(($offset+40)/44);
  my $day = $offset + 28 - 31* int($month/4);
  
  return $month, $day;
}
1;

=pod
=item summary    define holidays in a local file
=item summary_DE Urlaubs-/Feiertagskalender aus einer lokalen Datei
=begin html

<a name="holiday"></a>
<h3>holiday</h3>
<ul>
  <a name="holidaydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; holiday</code>
    <br><br>
    Define a set of holidays. The module will try to open the file
    &lt;name&gt;.holiday in the <a href="#modpath">modpath</a>/FHEM directory
    first, then in the modpath/FHEM/holiday directory, the latter containing a
    set of predefined files. The set will be shown if an error occures at the
    time of the definietion.<br>

    If entries in the holiday file match the current day, then the STATE of
    this holiday instance displayed in the <a href="#list">list</a> command
    will be set to the corresponding values, else the state is set to the text
    none. Most probably you'll want to query this value in some perl script:
    see Value() in the <a href="#perl">perl</a> section or the global attribute
    <a href="#holiday2we"> holiday2we</a>.<br> The file will be reread once
    every night, to compute the value for the current day, and by each get
    command (see below).<br>
    <br>

    Holiday file definition:<br>
    The file may contain comments (beginning with #) or empty lines.
    Significant lines begin with a number (type) and contain some space
    separated words, depending on the type. The different types are:<br>
    <ul>
      <li>1<br>
          Exact date. Arguments: &lt;MM-DD&gt; &lt;holiday-name&gt;<br>
          Exampe: 1 12-24 Christmas
          </li>
      <li>2<br>
          Easter-dependent date. Arguments: &lt;day-offset&gt;
          &lt;holiday-name&gt;.
          The offset is counted from Easter-Sunday.
          <br>
          Exampe: 2 1 Easter-Monday<br>
          Sidenote: You can check the easter date with:
          fhem> { join("-", western_easter(2011)) }
          </li>
      <li>3<br>
          Month dependent date. Arguments: &lt;nth&gt; &lt;weekday&gt;
          &lt;month &lt;holiday-name&gt;.<br>
          Examples:<br>
          <ul>
            3  1 Mon 05 First Monday In May<br>
            3  2 Mon 05 Second Monday In May<br>
            3 -1 Mon 05 Last Monday In May<br>
            3  0 Mon 05 Each Monday In May<br>
          </ul>
          </li>
      <li>4<br>
          Interval. Arguments: &lt;MM-DD&gt; &lt;MM-DD&gt; &lt;holiday-name&gt;
          .<br>
          Note: An interval cannot contain the year-end.
          Example:<br>
          <ul>
            4 06-01 06-30 Summer holiday<br>
            4 12-20 01-10 Winter holiday  # DOES NOT WORK.
                                        Use the following 2 lines instead:<br>
            4 12-20 12-31 Winter holiday<br>
            4 01-01 01-10 Winter holiday<br>
          </ul>
          </li>
      <li>5<br>
          Date relative, weekday fixed holiday. Arguments: &lt;nth&gt;
          &lt;weekday&gt; &lt;month&gt; &lt;day&gt; &lt; holiday-name&gt;<br>
          Note that while +0 or -0 as offsets are not forbidden, their behaviour
          is undefined in the sense that it might change without notice.<br>
          Examples:<br>
          <ul>
            5 -1 Wed 11 23 Buss und Bettag (first Wednesday before Nov, 23rd)<br>
            5 1 Mon 01 31 First Monday after Jan, 31st (1st Monday in February)<br>
          </ul>
          </li>
    </ul>
  </ul>
  <br>

  <a name="holidayset"></a>
  <b>Set</b>
  <ul>
    <li>createPrivateCopy<br>
      <ul>
        if the holiday file is opened from the FHEM/holiday directory (which is
        refreshed by FHEM-update), then it is readonly, and should not be
        modified. With createPrivateCopy the file will be copied to the FHEM
        directory, where it can be modified.
      </ul></li>
  </ul><br>

  <a name="holidayget"></a>
  <b>Get</b>
    <ul>
      <code>get &lt;name&gt; &lt;MM-DD&gt;</code><br>
      <code>get &lt;name&gt; yesterday</code><br>
      <code>get &lt;name&gt; today</code><br>
      <code>get &lt;name&gt; tomorrow</code><br>
      <code>get &lt;name&gt; days <offset></code><br>
      <br><br>
      Return the holiday name of the specified date or the text none.
      <br><br>
    </ul>
    <br>

  <a name="holidayattr"></a>
  <b>Attributes</b><ul>N/A</ul><br>

</ul>

=end html

=begin html_DE

<a name="holiday"></a>
<h3>holiday</h3>
<ul>
  <a name="holidaydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; holiday</code>
    <br><br>
    Definiert einen Satz mit Urlaubsinformationen. Das Modul versucht die
    Datei &lt;name&gt;.holiday erst in <a href="#modpath">modpath</a>/FHEM zu
    &ouml;ffnen, und dann in modpath/FHEM/holiday, Letzteres enth&auml;lt eine
    Liste von per FHEM-update verteilten Dateien f&uuml;r diverse
    (Bundes-)L&auml;nder. Diese Liste wird bei einer Feherlmeldung angezeigt.

    Wenn Eintr&auml;ge im der Datei auf den aktuellen Tag passen wird der STATE
    der Holiday-Instanz die im <a href="#list">list</a> Befehl angezeigt wird
    auf die entsprechenden Werte gesetzt. Andernfalls ist der STATE auf den
    Text "none" gesetzt.
 
    Meistens wird dieser Wert mit einem Perl Script abgefragt: siehe Value() im
    <a href="#perl">perl</a> Abschnitt oder im globalen Attribut <a
    href="#holiday2we"> holiday2we</a>.<br> Die Datei wird jede Nacht neu
    eingelesen um den Wert des aktuellen Tages zu erzeugen.  Auch jeder "get"
    Befehl liest die Datei neu ein.

    <br><br>

    Holiday file Definition:<br>
    Die Datei darf Kommentare, beginnend mit #, und Leerzeilen enthalten.  Die
    entscheidenden Zeilen beginnen mit einer Zahl (Typ) und enthalten durch
    Leerzeichen getrennte W&ouml;rter, je nach Typ. Die verschiedenen Typen
    sind:<br>
    <ul>
      <li>1<br>
          Genaues Datum. Argument: &lt;MM-TT&gt; &lt;Feiertag-Name&gt;<br>
          Beispiel: 1 12-24 Weihnachten
          </li>
      <li>2<br>
          Oster-abh&auml;ngiges Datum. Argument: &lt;Tag-Offset&gt;
          &lt;Feiertag-Name&gt;.
          Der Offset wird vom Oster-Sonntag an gez&auml;hlt.
          <br>
          Beispiel: 2 1 Oster-Montag<br>
          Hinweis: Das Osterdatum kann vorher gepr&uuml;ft werden:
          fhem> { join("-", western_easter(2011)) }
          </li>
      <li>3<br>
          Monats-abh&auml;ngiges Datum. Argument: &lt;X&gt; &lt;Wochentag&gt;
          &lt;Monat&gt; &lt;Feiertag-Name&gt;.<br>
          Beispiel:<br>
          <ul>
            3  1 Mon 05 Erster Montag In Mai<br>
            3  2 Mon 05 Zweiter Montag In Mai<br>
            3 -1 Mon 05 Letzter Montag In Mai<br>
            3  0 Mon 05 Jeder Montag In Mai<br>
          </ul>
          </li>
      <li>4<br>
          Intervall. Argument: &lt;MM-TT&gt; &lt;MM-TT&gt; &lt;Feiertag-Name&gt;
          .<br>
          Achtung: Ein Intervall darf kein Jahresende enthalten.
          Beispiel:<br>
          <ul>
            4 06-01 06-30 Sommerferien<br>
            4 12-20 01-10 Winterferien # FUNKTIONIER NICHT,
                                        stattdessen folgendes verwenden:<br>
            4 12-20 12-31 Winterferien<br>
            4 01-01 01-10 Winterferien<br>
          </ul>
          </li>
      <li>5<br>
          Datum relativ, Wochentags ein fester Urlaubstag/Feiertag. Argument:
          &lt;X&gt; &lt;Wochentag&gt; &lt;Monat&gt; &lt;Tag&gt; 
          &lt;Feiertag-Name&gt;<br> Hinweis: Da +0 oder -0 als Offset nicht
          verboten sind, ist das Verhalten hier nicht definiert, kann sich also
          ohne Info &auml;ndern;<br>
          Beispiel:<br>
          <ul>
            5 -1 Wed 11 23 Buss und Bettag (erster Mittwoch vor dem 23. Nov)<br>
            5 1 Mon 01 31 Erster Montag in Februar<br>
          </ul>
          </li>
    </ul>
  </ul>
  <br>

  <a name="holidayset"></a>
  <b>Set</b>
  <ul>
    <li>createPrivateCopy<br>
      <ul>
        Falls die Datei in der FHEM/holiday Verzeichnis ge&ouml;ffnet wurde,
        dann ist sie nicht beschreibbar, da dieses Verzeichnis mit FHEM
        update aktualisiert wird. Mit createPrivateCopy kann eine private Kopie
        im FHEM Verzeichnis erstellt werden.
      </ul></li>
  </ul><br>

  <a name="holidayget"></a>
  <b>Get</b>
    <ul>
      <code>get &lt;name&gt; &lt;MM-DD&gt;</code><br>
      <code>get &lt;name&gt; yesterday</code><br>
      <code>get &lt;name&gt; today</code><br>
      <code>get &lt;name&gt; tomorrow</code><br>
      <code>get &lt;name&gt; days <offset></code><br>
      <br><br>
      Gibt den Name des Feiertages zum angebenenen Datum zur&uuml;ck oder den
      Text none.
      <br><br>
    </ul>
    <br>

  <a name="holidayattr"></a>
  <b>Attributes</b><ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    </ul><br>

</ul>

=end html_DE
=cut
