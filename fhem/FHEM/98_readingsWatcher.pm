################################################################
#
#  $Id$
#
#  (c) 2015,2016 Copyright: HCS,Wzut
#  All rights reserved
#
#  FHEM Forum : https://forum.fhem.de/index.php/topic,49408.0.html
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
################################################################

package FHEM::readingsWatcher;  ## no critic 'package'
use strict;
use warnings;
use utf8;
use GPUtils qw(GP_Import GP_Export); # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday);

BEGIN 
{
  # Import from main::
  GP_Import( 
      qw(
          attr
          AttrVal
          AttrNum
          CommandAttr
          addToAttrList
          delFromAttrList
          delFromDevAttrList
          defs
          devspec2array
          init_done
          InternalTimer
          RemoveInternalTimer
          IsDisabled
          IsIgnored
          Log3
          modules
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          readingFnAttributes
          ReadingsNum
          ReadingsAge
          ReadingsTimestamp
          ReadingsVal
          setReadingsVal
          CommandSetReading
          CommandDeleteReading
          gettimeofday
          TimeNow
        )
  );

  # Export to main context
    GP_Export(
        qw(
          Initialize
          )
    );
}

# Versions History intern
my %vNotesIntern = 
(
 "2.0.0"  =>  "April 2020 , perlcritic -4 / PBP",
 "1.7.1"  =>  "25.01.20 fix ErrorValue 0",
 "1.7.0"  =>  "12.01.20 add OR / AND watching",
 "1.6.0"  =>  "27.08.19 package, Meta",
 "1.5.0"  =>  "18.02.19",
 "1.3.0"  =>  "26.01.18 use ReadingsAge",
 "1.2.0"  =>  "15.02.16 add Set, Get",
 "1.1.0"  =>  "14.02.16",
 "1.0.0"  =>  "(c) HCS, first version"
);


my $hasmeta = 0;

if (-e $attr{global}{modpath}.'/FHEM/Meta.pm')
 {
  $hasmeta = 1;
  require FHEM::Meta;
 }


sub Initialize
{
   my $hash = shift;
   $hash->{GetFn}     = "FHEM::readingsWatcher::Get";
   $hash->{SetFn}     = "FHEM::readingsWatcher::Set";
   $hash->{DefFn}     = "FHEM::readingsWatcher::Define";
   $hash->{UndefFn}   = "FHEM::readingsWatcher::Undefine";
   $hash->{AttrFn}    = "FHEM::readingsWatcher::Attr";
   $hash->{AttrList}  = "disable:0,1 interval deleteUnusedReadings:1,0 readingActivity ".$readingFnAttributes;

   return  FHEM::Meta::InitMod( __FILE__, $hash ) if ($hasmeta);

   return;
}

##################################################################################### 

sub Define
{
  my $hash = shift;
  my $def  = shift;
  my ($name, $type, $noglobal) = split("[ \t\n]+", $def, 3);

  if(exists($modules{readingsWatcher}{defptr})) 
  {
    my $error = 'one readingsWatcher device is already defined !';
    Log3 $name, 1, $error;
    return $error;
  }

  $modules{readingsWatcher}{defptr} = $hash;

  if (defined($noglobal) && ($noglobal  eq 'noglobal'))
  {   $hash->{DEF} = 'noglobal'; }
  else { addToAttrList('readingsWatcher'); $hash->{DEF} = 'global';} # global -> userattr 

  CommandAttr(undef,"$name interval 60") unless (exists($attr{$name}{interval}));
  CommandAttr(undef,"$name readingActivity none") unless (exists($attr{$name}{readingActivity}));

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+5, 'FHEM::readingsWatcher::OnTimer', $hash, 0);

  if ($hasmeta) { return $@ unless ( FHEM::Meta::SetInternals($hash) ) }
  return;
}

#####################################################################################

sub Undefine
{
  my $hash = shift;
  RemoveInternalTimer($hash);
  delete($modules{readingsWatcher}{defptr});
  if ($hash->{DEF} eq 'global')
  {
   delFromAttrList('readingsWatcher'); # global -> userattr
   my @devs = devspec2array("readingsWatcher!="); # wer hat alles ein Attribut readingsWatcher ?
   foreach (@devs)
   { delFromDevAttrList($_, 'readingsWatcher'); } # aufräumen
  }
  return;
}

#####################################################################################

sub Set
{
 my ($hash, $name, $cmd) = @_;

 if ($cmd eq 'inactive')
 {
  readingsSingleUpdate($hash, 'state', 'inactive', 1);
  RemoveInternalTimer($hash);
  $hash->{INTERVAL} = 0;
  return;
 }
 elsif ($cmd eq 'active')
 {
  readingsSingleUpdate($hash, 'state', 'active', 1);
  $hash->{INTERVAL} = AttrVal($name,'interval',60);
  return;
 }

 return  if(IsDisabled($name));

 if (($cmd eq 'checkNow') || ($cmd eq 'active'))
 { 
  OnTimer($hash);
  return;
 }

 if  ($cmd eq 'clearReadings')
 {
  foreach (keys %{$defs{$name}{READINGS}}) # alle eignen Readings 
  {
   if ($_ =~ /_/) # device.reading
   {
    readingsDelete($hash, $_);
    Log3 $name,4,"$name, delete reading $_";
   }
  }
 return;
 }

 return "unknown argument $cmd, choose one of checkNow:noArg inactive:noArg active:noArg clearReadings:noArg";
}

#####################################################################################

sub Get
{
 my ($hash, $name , $cmd)= @_;
 return if(!$cmd);

 my (@parts, $rSA,  $age , @devs, $state);
 my ($dw,$rw,$tw,$sw,$aw) = (6,7,7,5,3);

 if ($cmd eq 'devices')
 {
  foreach my $deviceName (devspec2array("readingsWatcher!="))
  {
   $rSA  = ($deviceName eq  $name) ? '' : AttrVal($deviceName, 'readingsWatcher', '');
   $dw   = length($deviceName) if (length($deviceName) > $dw);

   if ($rSA)
   {
    if (IsDisabled($deviceName)) 
    { 
      $sw  = 8 if ($sw<8);
      push @devs, "$deviceName,-,-,disabled,-";
    }
    elsif (IsIgnored($deviceName))
    { 
      $sw  = 7 if ($sw<7);
      push @devs, "$deviceName,-,-,ignored,-";
    }
    else
     { 
       my @r = split(';',$rSA);

       foreach (@r)
       {
       $_ =~ s/\+/,/g;
       @parts = split(',', $_);
       if (@parts > 2)
       { 
        my $timeout = int($parts[0]);
        $tw =  length($timeout) if(length($timeout) > $tw);

        shift @parts;   # Timeoutwert
        shift @parts;   # Ersatzwert

        foreach (@parts) # alle zu überwachenden Readings
        {
          $_  =~ s/^\s+|\s+$//g;
          $_  = 'state' if ($_ eq 'STATE');
          $rw =  length($_) if(length($_) > $rw); 

          if (($_ eq 'state') && (ReadingsVal($deviceName,'state','') eq 'inactive'))
          {
            $state   = 'inactive';
            $age     = '-';
          }
          else
          {
           $age = ReadingsAge($deviceName, $_, undef);
 
           if (!defined($age))
           {
            $state   = 'unknown';
            $age     = 'undef';
           }
           else
           {
            $state = ($age>$timeout) ? 'timeout' : 'ok';
           }
          }
          $aw = length($age)   if(length($age)   > $aw);
          $sw = length($state) if(length($state) > $sw);
          push @devs, "$deviceName, $_, $timeout, $state, $age";
        }
       } # @parts >2 
       
       else 
       { 
         $sw   = 16 if ($sw<16);
         push @devs, "$deviceName,-,-,wrong parameters,-";
       } 
      } # not disabled
    } # rSA
   }
  } # foreach

  if (int(@devs))
  {
   $dw += 2;
   $rw += 2;
   $sw += 2;
   $aw += 2;

   my $s  = 'Device'.(' ' x ($dw-6)).'| Reading'.(' ' x ($rw-7)).'|'.(' ' x ($tw-6)).'Timeout |'.(' ' x ($sw-5)).'State |'.(' ' x ($aw-3)).'Age';
   my $line = ('-'x(length($s)));
   while ( $s =~ m/\|/g ) { substr $line,(pos($s)-1),1,'+'; }
   $s .= "\n".$line."\n";

   foreach(@devs) 
   { 
      my @ar  = split(',',$_);
      $s .= $ar[0] . (' ' x ($dw - length$ar[0])); # linksbündig
      $s .= '| '.$ar[1] . (' ' x ($rw - length$ar[1])); # linksbündig
      $s .= '| '.(' ' x ($tw - length$ar[2])).$ar[2];   # rechtsbündig
      $s .= ' |'.(' ' x ($sw - length$ar[3])).$ar[3].' |';   # rechtsbündig
      $s .= (' ' x ($aw - length$ar[4])).$ar[4];   # rechtsbündig
      $s .= "\n";
   }
   return $s.$line;
  }
  return 'Sorry, no devices with valid attribute readingsWatcher found !';
 } # get devices

 return "unknown command $cmd, choose one of devices:noArg";
}

#####################################################################################

sub OnTimer
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $interval = AttrNum($name, 'interval', 0);
  $hash->{INTERVAL} = $interval;
  RemoveInternalTimer($hash);

  return if (!$interval);

  InternalTimer(gettimeofday()+$interval, 'FHEM::readingsWatcher::OnTimer', $hash, 0);

  readingsSingleUpdate($hash, 'state', 'disabled', 0) if (IsDisabled($name));
  return if(IsDisabled($name) || !$init_done );

  my ($timeOutState, $errorValue, $timeout, $error, $readingsList);
  my ($rSA, $age, @devices, $rts, @parts, @devs);
  my ($alives, $deads, $state, $readings, $skipped, $timeouts) = (0, 0, '', 0, 0, 0);
  my @timeOutdevs = (); my @deadDevs = (); my @skipDevs = ();

  foreach (keys %{$defs{$name}{READINGS}}) # alle eignen Readings 
  { $readingsList .=  $_ .',' if ($_ =~ /_/); }# nur die mit _ im Namen

  @devs = devspec2array("readingsWatcher!=");

  my ($areading,$dead,$alive) = split(":",AttrVal($name,'readingActivity','none:dead:alive'));
  $dead = 'dead'  if (!defined($dead));
  $alive= 'alive' if (!defined($alive));
  $areading = ''  if ($areading eq 'none');

  readingsBeginUpdate($hash);

  foreach  my $deviceName (@devs) 
  {
    my $or_and = 0; # Readings beim auswerten OR
    my ($d_a,$d_d,$ok_device) = (0,0,0); 
    $timeOutState = '';

    $rSA = ($deviceName eq  $name) ? '' : AttrVal($deviceName, 'readingsWatcher', '');

    if($rSA && !IsDisabled($deviceName) && !IsIgnored($deviceName)) 
    {
     push @devices, $deviceName if  !grep {/$deviceName/} @devices; # keine doppelten Namen

     $or_and = 1 if (index($rSA,'+') != -1); # Readings beim auswerten AND
     $rSA =~ s/\+/,/g ; # eventuell vorhandene + auch in Komma wandeln

     # rSA: timeout, errorValue, reading1, reading2, reading3, ...
     #      120,---,temperature,humidity,battery
     # or   900,,current,eState / no errorValue = do not change reading

     my @r = split(';', $rSA);
     foreach (@r)
     {
        @parts = split(',', $_);

        if (@parts > 2)
        {
         $ok_device  = 1;
         $timeout    = int($parts[0]);
         $errorValue = $parts[1]; # = leer, Readings des Device nicht anfassen !

         # die ersten beiden brauchen wir nicht mehr
         shift @parts; shift @parts;

         foreach (@parts) # alle zu überwachenden Readings
         { 
          $_ =~ s/^\s+|\s+$//g; # $_ = Reading Name

          $state = 0;
          if ($_ eq 'STATE')
          {
           $_ = 'state'; $state = 1; # Sonderfall STATE 
          } 

          $age = ReadingsAge($deviceName, $_, undef);

          if (defined($age))
          {
           $readings++;

           if (($age > $timeout) && ($timeout>0))
           {
             push @timeOutdevs, $deviceName if  !grep {/$deviceName/} @timeOutdevs;
             $timeOutState = "timeout";
             $d_d++; # Device Tote
             $timeouts++;
             $rts = ReadingsTimestamp($deviceName, $_,0);
             setReadingsVal($defs{$deviceName},$_,$errorValue,$rts) if (($errorValue ne'')&& $rts); # leise setzen ohne Event
             $defs{$deviceName}->{STATE} = $errorValue if (($errorValue ne'') && $state);
           }
           else
           {
            $d_a++; # Device Lebende
            $timeOutState = "ok";
           }

           my $r = $deviceName.'_'.$_;

           readingsBulkUpdate($hash, $r, $timeOutState) if ($timeout>0);
           $readingsList =~  s/$r,// if ($readingsList) ; # das Reading aus der Liste streichen, leer solange noch kein Device das Attr hat !

           if ($timeout < 1)
           {
            $error = "Invalid timeout value $timeout for reading $deviceName $_";
            Log3 $name,2,$name.', '.$error;
           }
          }#age
          else
          {
            setReadingsVal($defs{$deviceName},$_,'unknown',TimeNow()) if ($errorValue); # leise setzen ohne Event
            $defs{$deviceName}->{STATE} = 'unknown' if ($errorValue && $state);
            Log3 $name,3,$name.', reading Timestamp for '.$_.' not found on device '.$deviceName;
            readingsBulkUpdate($hash, $deviceName.'_'.$_, 'no Timestamp');
          }
         }# foreach @parts , Reading
       }# parts > 2 
     } # Anzahl Readings Sätze im Device, meist nur einer

     if ($ok_device && $timeOutState)
     {
      if ((!$or_and && $d_d) || ($or_and && !$d_a)) # tot bei OR und mindestens einem Toten ||  AND aber kein noch Lebender
      {
       $error = CommandSetReading(undef, "$deviceName $areading $dead") if ($areading);
       $deads++; # dead devices
       push @deadDevs, $deviceName;
      }
      else  # wenn es nicht tot ist muss es eigentlich noch leben ....
      {
       $error = CommandSetReading(undef, "$deviceName $areading $alive") if ($areading);
       $alives++; # alive devices
      }
      Log3 $name,2,$name.', '.$error if ($error);
     }
     else
     {
      Log3 $name,2,$name.', insufficient parameters for device '.$deviceName.' - skipped !';
      $skipped++;
      CommandSetReading(undef, "$deviceName $areading unknown") if ($areading);
      push @skipDevs, $deviceName;
     }
    } # defined($rSA) && !IsDisabled($deviceName) && !IsIgnored($deviceName)
  } # foreach $deviceName

  readingsBulkUpdate($hash,'readings' , $readings);
  readingsBulkUpdate($hash,'devices'  , int(@devices));
  readingsBulkUpdate($hash,'alive'    , $alives);
  readingsBulkUpdate($hash,'dead'     , $deads);
  readingsBulkUpdate($hash,'skipped'  , $skipped) if ($skipped);
  readingsBulkUpdate($hash,'timeouts' , $timeouts);
  readingsBulkUpdate($hash,'state'    , ($timeouts) ? 'timeout' : 'ok');

  readingsDelete($hash, 'skipped') if (!$skipped && AttrNum($name,'deleteUnusedReadings','1'));

  # nicht aktualisierte Readings markieren oder löschen
  if ($readingsList) 
  { 
    my @ar = split(",",$readingsList); 
     foreach (@ar)
     {
       if ($_)
       {
        if (AttrNum($name,'deleteUnusedReadings',1))
        {
         readingsDelete($hash, $_);
         Log3 $name,3,$name.', delete unused reading '.$_;
        }
         else 
        { 
         readingsBulkUpdate($hash, $_ , 'unused'); 
         Log3 $name,4,$name.', unused reading '.$_;
        }
       }
     }
  }

  if (@devices)
  { readingsBulkUpdate($hash,'.associatedWith' , join(',',@devices)); }
  else
  { readingsDelete($hash, '.associatedWith'); }

  if (int(@timeOutdevs))
  { readingsBulkUpdate($hash,'timeoutdevs',join(',',@timeOutdevs));}
  else
  { readingsBulkUpdate($hash,'timeoutdevs','none');}

  if (int(@deadDevs))
  { readingsBulkUpdate($hash,'deadDevs',join(',',@deadDevs));}
  else
  { readingsBulkUpdate($hash,'deadDevs','none');}

  if (int(@skipDevs))
  { readingsBulkUpdate($hash,'skippedDevs',join(',',@skipDevs));}
  else
  { readingsBulkUpdate($hash,'skippedDevs','none');}

  readingsEndUpdate($hash, 1);

  return;
}

sub Attr
{
 my ($cmd, $name, $attrName, $attrVal) = @_;
 my $hash = $defs{$name};

 return 'not allowed !' if ($name eq $attrName);

 if ($cmd eq 'set')
 {
   if ($attrName eq 'disable')
   {
    readingsSingleUpdate($hash,'state','disabled',1) if (int($attrVal) == 1);
    OnTimer($hash) if (int($attrVal) == 0);
    return;
   }
   if (($attrName eq 'readingActivity') && ($attrVal eq 'state'))
   {
    my $error = 'forbidden value state !';
    Log3 $name,1,"$name, readingActivity $error";
    return $error;
   }
 }
 elsif ($cmd eq 'del')
 {
  if ($attrName eq 'disable')
  {
   OnTimer($hash);
  }
 }
   return;
}
#####################################################################################
1;

=pod
=encoding utf8

=item helper
=item summary    cyclical watching of readings updates
=item summary_DE zyklische Überwachung von Readings auf Aktualisierung
=begin html

<a name="readingsWatcher"></a>
<h3>readingsWatcher</h3>
<ul>
   The module monitors readings in other modules that its readings or their times change at certain intervals and<br>
   if necessary, triggers events that can be processed further with other modules (for example, notify, DOIF).<br>
   Forum : <a href="https://forum.fhem.de/index.php/topic,49408.0.html">https://forum.fhem.de/index.php/topic,49408.0.html</a><br><br>
  
   <a name="readingsWatcher_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsWatcher</code><br>
    <br>
    Defines a readingsWatcher device.<br><br>
    Afterwards each FHEM device has the new global attribute readingsWatcher<br>
    This attribute must be assigned at all monitored devices as follows:<br>
    Timeout in seconds, new Reading value, Reading1 of the device, Reading2, etc.<br><br>

    Example: A radio thermometer sends its values at regular intervals (eg.5 seconds)<br>
    If these remain off for a time X, the module can overwrite these invalid values with any other new value (Ex. ???)<br>
    The readingsWatcher attribute could be set here as follows:<br><br>
    <code>attr myThermo readingsWatcher 300, ???, temperature</code><br><br>
    or if more than one reading should be monitored<br><br>
    <code>attr myThermo readingsWatcher 300, ???, temperature, humidity</code><br><br>
    If readings are only to be monitored for their update and should <b>not</b> be overwritten<br>
    so the replacement string must be <b>empty</b><br><br>
    Example : <code>attr myThermo readingsWatcher 300,,temperature,humidity</code><br><br>
    other examples :<br>
    <code>attr weather readingsWatcher 300,,temperature+humidity</code> (new)<br>
    <code>attr weather readingsWatcher 300,,temperature,humidity;3600,???,battery</code>
  </ul>
 
  <a name="readingsWatcherSet"></a>
   <b>Set</b>
   <ul>
   <li>active</li>
   <li>inactive</li>
   <li>checkNow</li>
   <li>clearReadings</li>
   </ul>

  <a name="readingsWatcherGet"></a>
   <b>Get</b>
   <ul>
   devices
   </ul>

  <a name="readingsWatcherAttr"></a>
  <b>Attribute</b>
  <ul>
     <br>
     <ul>
       <a name="disable"></a><li><b>disable</b><br>deactivate/activate the device</li><br>
       <a name="interval"></a><li><b>interval &lt;seconds&gt;</b><br>Time interval for continuous check (default 60)</li><br>
       <a name="deleteUnusedReadings"></a><li><b>deleteUnusedReadings</b><br>delete unused readings (default 1)</li><br>
       <a name="readingActifity"></a><li><b>readingActifity</b> (default none)<br>
       Similar to the HomeMatic ActionDetector, the module can set its own reading in the monitored device and save the monitoring status.<br>
       <code>attr &lt;name&gt; readingActifity actifity</code><br>
       Creates the additional reading actifity in the monitored devices and supplies it with the status dead or alive<br>     
       <code>attr &lt;name&gt; readingActifity activ:0:1</code><br>
       Creates the additional reading activ in the monitored devices and supplies it with the status 0 or 1
      </li><br>
     </ul>
  </ul>
  <br> 
</ul>

=end html

=begin html_DE

<a name="readingsWatcher"></a>
<h3>readingsWatcher</h3>
<ul>
  Das Modul überwacht Readings in anderen Modulen darauf das sich dessen Readings bzw. deren Zeiten in bestimmten Abständen
  ändern<br> und löst ggf. Events aus die mit anderen Modulen (z.B. notify,DOIF) weiter verarbeitet werden können.<br>
  Forum : <a href="https://forum.fhem.de/index.php/topic,49408.0.html">https://forum.fhem.de/index.php/topic,49408.0.html</a><br><br>
 
  <a name="readingsWatcher_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsWatcher</code><br>
    <br>
    Definiert ein readingsWatcher Device.<br><br>
    Danach besitzt jedes FHEM Device das neue globale Attribut readingsWatcher<br>
    Dieses Attribut ist bei allen zu überwachenden Geräten wie folgt zu belegen :<br>
    <code>attr mydevice timeout,[Ersatz],Readings1,[Readings2][;timeout2,Ersatz2,Reading,Reading]</code>
    Timeout in Sekunden, neuer Reading Wert, Reading1 des Devices, Reading2, usw.<br><br>
    Beispiel : Ein Funk Thermometer sendet in regelmäßigen Abständen ( z.b.5 Sekunden ) seine Werte.<br> 
    Bleiben diese nun für eine bestimmte Zeit aus, so kann das Modul diesen nun nicht mehr aktuellen Werte (oder Werte)<br>
    mit einem beliebigen anderen Wert überschreiben ( z.B. ??? )<br>
    Das Attribut readingsWatcher könnte hier wie folgt gesetzt werden :<br><br>
    <code>attr AussenTemp readingsWatcher 300,???,temperature</code><br><br>
    oder falls mehr als ein Reading &uuml;berwacht werden soll<br><br>
    <code>attr AussenTemp readingsWatcher 300,???,temperature,humidity</code><br><br>
    Sollen Readings nur auf ihre Aktualiesierung überwacht, deren Wert aber <b>nicht</b> überschrieben werden,<br>
    so  muss der Ersatzsstring <b>leer</b> gelassen werden :<br>
    Bsp : <code>attr AussenTemp readingsWatcher 300,,temperature,humidity</code><br><br>
    <br>
    weitere Beispiele :<br>
    <code>attr wetter readingsWatcher 300,,temperature+humidity</code> (neu)<br>
    <code>attr wetter readingsWatcher 300,,temperature,humidity;3600,???,battery</code>
  </ul>

  <a name="readingsWatcherSet"></a>
   <b>Set</b>
   <ul>
   <li>active</li>
   <li>inactive</li>
   <li>checkNow</li>
   <li>clearReadings</li>
   </ul><br>

  <a name="readingsWatcherGet"></a>
   <b>Get</b>
   <ul>
   <li>devices</li>
   </ul><br>

  <a name="readingsWatcherAttr"></a>
  <b>Attribute</b>
  <ul>
     <br>
     <ul>
       <a name="disable"></a><li><b>disable</b><br>Deaktiviert das Device</li><br>
       <a name="interval"></a><li><b>interval &lt;Sekunden&gt;</b> (default 60)<br>Zeitintervall zur kontinuierlichen Überprüfung</li><br>
       <a name="deleteUnusedReadings"></a><li><b>deleteUnusedReadings</b> (default 1)<br>Readings mit dem Wert unused werden automatisch gelöscht</li><br>
       <a name="readingActifity"></a><li><b>readingActifity</b> (default none)<br>
       Das Modul kann ähnlich dem HomeMatic ActionDetector im überwachten Gerät ein eigenes Reading setzen und den Überwachungsstatus<br>
       in diesem speichern. Beispiel :<br>
       <code>attr &lt;name&gt; readingActifity actifity</code><br>
       Erzeugt in den überwachten Geräten das zusäzliche Reading actifity und versorgt es mit dem Status dead bzw alive<br>     
       <code>attr &lt;name&gt; readingActifity aktiv:0:1</code><br>
       Erzeugt in den überwachten Geräten das zusätzliche Reading aktiv und versorgt es mit dem Status 0 bzw 1
       </li><br>
     </ul>
  </ul>
  <br> 

</ul>

=end html_DE

=for :application/json;q=META.json 98_readingsWatcher.pm

{
  "abstract": "Module for cyclical watching of readings updates",
  "x_lang": {
    "de": {
      "abstract": "Modul zur zyklische Überwachung von Readings auf Aktualisierung"
    }
  },
  "keywords": [
    "readings",
    "watch",
    "supervision",
    "überwachung"
  ],
  "version": "2.0.0",
  "release_status": "stable",
  "author": [
    "Wzut"
  ],
  "x_fhem_maintainer": [
    "Wzut"
  ],
  "x_fhem_maintainer_github": [
    "Wzut"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "GPUtils": 0,
        "Time::HiRes": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut


