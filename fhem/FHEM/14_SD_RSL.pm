###########################################
# SIGNALduini RSL Modul. Modified version of FHEMduino Modul by Wzut
#  
# $Id$
# Supports following devices:
# - Conrad RSL 
#####################################

package main;

use strict;
use warnings;

my %sets = ( "on:noArg"  => "", "off:noArg"  => "");

my @RSLCodes;

    # Tastenpaar [1 - 3] , Schiebeschalter/Kanal [I - IV] , an-aus [1 - 0] 
    $RSLCodes[0][0][0] =  62;   # ? / ?    off  
    $RSLCodes[0][0][1] =  54;   # ? / ?    on   
    $RSLCodes[1][1][0] =   1;   # 1 / I    off
    $RSLCodes[1][1][1] =  14;   # 1 / I    on
    $RSLCodes[1][2][0] =  46;   # 2 / I    off   
    $RSLCodes[1][2][1] =  38;   # 2 / I    on
    $RSLCodes[1][3][0] =  30;   # 3 / I    off
    $RSLCodes[1][3][1] =  22;   # 3 / I    on 
    $RSLCodes[1][4][0] =  53;   # 4 / I    off  - nicht auf 12 Kanal FB 
    $RSLCodes[1][4][1] =  57;   # 4 / I    on   - nicht auf 12 Kanal FB
    $RSLCodes[2][1][0] =  13;   # 1 / II   off
    $RSLCodes[2][1][1] =   5;   # 1 / II   on
    $RSLCodes[2][2][0] =  37;   # 2 / II   off
    $RSLCodes[2][2][1] =  41;   # 2 / II   on
    $RSLCodes[2][3][0] =  21;   # 3 / II   off
    $RSLCodes[2][3][1] =  25;   # 3 / II   on  
    $RSLCodes[2][4][0] =  56;   # 4 / II   off - nicht auf 12 Kanal FB
    $RSLCodes[2][4][1] =  48;   # 4 / II   on  - nicht auf 12 Kanal FB
    $RSLCodes[3][1][0] =   4;   # 1 / III  off
    $RSLCodes[3][1][1] =   8;   # 1 / III  on
    $RSLCodes[3][2][0] =  40;   # 2 / III  off
    $RSLCodes[3][2][1] =  32;   # 2 / III  on
    $RSLCodes[3][3][0] =  24;   # 3 / III  off
    $RSLCodes[3][3][1] =  16;   # 3 / III  on
    $RSLCodes[3][4][0] =  50;   # 4 / III  off - nicht auf 12 Kanal FB
    $RSLCodes[3][4][1] =  60;   # 4 / III  on  - nicht auf 12 Kanal FB
    $RSLCodes[4][1][0] =  10;   # 1 / IV   off
    $RSLCodes[4][1][1] =   2;   # 1 / IV   on
    $RSLCodes[4][2][0] =  34;   # 2 / IV   off
    $RSLCodes[4][2][1] =  44;   # 2 / IV   on
    $RSLCodes[4][3][0] =  18;   # 3 / IV   off
    $RSLCodes[4][3][1] =  28;   # 3 / IV   on
    $RSLCodes[4][4][0] =  35;   # 4 / IV   off - nicht auf 12 Kanal FB
    $RSLCodes[4][4][1] =  19;   # 4 / IV   on  - nicht auf 12 Kanal FB

sub SD_RSL_Initialize($)
{ 
  my ($hash) = @_;

  $hash->{Match}     = "^P1#[A-Fa-f0-9]+";
  $hash->{SetFn}     = "SD_RSL_Set";
  $hash->{DefFn}     = "SD_RSL_Define";
  $hash->{UndefFn}   = "SD_RSL_Undef";
  $hash->{AttrFn}    = "SD_RSL_Attr";
  $hash->{ParseFn}   = "SD_RSL_Parse";
  $hash->{AttrList}  = "IODev RSLrepetition ignore:0,1 ".$readingFnAttributes;
  
  $hash->{AutoCreate}=
        { "RSL.*" => { GPLOT => "", FILTER => "%NAME",  autocreateThreshold => "2:30"} };
}

#####################################

sub SD_RSL_Define($$)
{ 

  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> SD_RSL <code (00000-FFFFFF)_channel (1-4)_button (1-4)>"  if(int(@a) != 3);

  my $name = $a[0];
  my ($device,$channel,$button) = split("_",$a[2]);
  return "wrong syntax: use channel 1 - 4"  if(($channel > 4)); # || ($channel < 1 ));
  return "wrong syntax: use button 1 - 4"  if(($button > 4));   # || ($button < 1));
  return "wrong syntax: use code 000000 - FFFFFF" if (length($device) != 6);
  return "wrong Device Code $device , please use 000000 - FFFFFF" if ((hex($device) < 0) || (hex($device) > 16777215));

  my $code = uc($a[2]);
  $hash->{DEF}   = $code;

  $modules{SD_RSL}{defptr}{$code} = $hash;
  $modules{SD_RSL}{defptr}{$code}{$name} = $hash;
  # code auf 32Bit umrechnen  int 16777216 = 0x1000000
  #$hash->{OnCode}  = ($RSLCodes[$channel][$button][1]*16777216) + hex($device);
  #$hash->{OffCode} = ($RSLCodes[$channel][$button][0]*16777216) + hex($device);
  $hash->{OnCode}  = "10" . sprintf('%06b', ($RSLCodes[$channel][$button][1])) . sprintf('%24b',hex($device));
  $hash->{OffCode} = "10" . sprintf('%06b', ($RSLCodes[$channel][$button][0])) . sprintf('%24b',hex($device));
  
  AssignIoPort($hash);

   return undef;
}

##########################################################
sub SD_RSL_Set($@)
{ 
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $cmd  = $a[1];
  my $c;
  my $message;

  return join(" ", sort keys %sets) if((@a < 2) || ($cmd eq "?"));

  $c = $hash->{OnCode}  if  ($cmd eq "on") ;
  $c = $hash->{OffCode} if  ($cmd eq "off");

  return "Unknown argument $cmd, choose  on or off" if(!$c);

  my $io = $hash->{IODev};
  ## Send Message to IODev using IOWrite
  $message = 'P1#' . $c . '#R' . AttrVal($name, "RSLrepetition", 6);
  Log3 $name, 4, $io->{NAME} . " RSL_SET_sendCommand: $name -> message: $message";
  IOWrite($hash, 'sendMsg', $message);
  #my $ret = IOWrite($hash, 'sendMsg', $c."_".AttrVal($name, "RSLrepetition", 6));
  #Log3 $hash, 5, "$name Set return : $ret";

  #if (($cmd eq "on")  && ($hash->{STATE} eq "off")){$cmd = "stop";}
  #if (($cmd eq "off") && ($hash->{STATE} eq "on")) {$cmd = "stop";}

  #$hash->{CHANGED}[0] = $cmd;
  #$hash->{STATE} = $cmd;
  readingsSingleUpdate($hash,"state",$cmd,1); 
  return undef;
}

###################################################################
sub RSL_getButtonCode($$)
{ 

  my ($hash,$msg) = @_;

  my $DeviceCode         = "undef";
  my $receivedButtonCode = "undef";
  my $receivedActionCode = "undef";
  my $parsedButtonCode   = "undef";
  my $action             = "undef";
  my $button             = -1;
  my $channel            = -1;

  ## Groupcode
  $DeviceCode  = substr($msg,2,6);
  $receivedButtonCode  = substr($msg,0,2);
  Log3 $hash, 5, "SD_RSL Message Devicecode: $DeviceCode Buttoncode: $receivedButtonCode";

  if ((hex($receivedButtonCode) & 0xc0) != 0x80) {
    Log3 $hash, 4, "SD_RSL Message Error: received Buttoncode $receivedButtonCode begins not with bin 10";
    return "";
  }
  $parsedButtonCode  = hex($receivedButtonCode) & 63; # nur 6 Bit bitte
  Log3 $hash, 4, "SD_RSL Message parsed Devicecode: $DeviceCode Buttoncode: $parsedButtonCode";

  for (my $i=0; $i<5; $i++)
  {
    for (my $j=0; $j<5; $j++)
    {
      next if ($i == 0 && $j != 0);
      next if ($i != 0 && $j == 0);
      if ($RSLCodes[$i][$j][0] == $parsedButtonCode) 
        {$action ="off"; $button = $j; $channel = $i;}
      if ($RSLCodes[$i][$j][1] == $parsedButtonCode) 
        {$action ="on";  $button = $j; $channel = $i;}
    }
  }

  if (($button >-1) && ($channel > -1)) 
  {
    Log3 $hash, 4, "RSL button return/result: ID: $DeviceCode $receivedButtonCode DEVICE: $DeviceCode $channel $button ACTION: $action";
    return $DeviceCode."_".$channel."_".$button." ".$action;
  }

  return "";
}

########################################################
sub SD_RSL_Parse($$)
{ 

  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my (undef ,$rawData) = split("#",$msg);
  
  Log3 $hash, 4, "$name RSL_Parse Message: $rawData";

  my $result = RSL_getButtonCode($hash,$rawData);

  if ($result ne "") 
  {
    my ($deviceCode,$action) = split m/ /, $result, 2;

    Log3 $hash, 4, "$name Parse: Device: $deviceCode  Action: $action";

    my $def = $modules{SD_RSL}{defptr}{$hash->{NAME} . "." . $deviceCode};
    $def = $modules{SD_RSL}{defptr}{$deviceCode} if(!$def);

    if(!$def) 
    {
      Log3 $hash, 3, "UNDEFINED Remotebutton send to define: $deviceCode";
      return "UNDEFINED RSL_$deviceCode SD_RSL $deviceCode";
    }

    $hash = $def;

    my $name = $hash->{NAME};
    return "" if(IsIgnored($name));

    if(!$action) 
    {
      Log3 $name, 5, "$name SD_RSL_Parse: can't decode $msg";
      return "";
    }

    Log3 $name, 5, "$name SD_RSL_Parse actioncode: $action";

    #if (($action eq "on")  && ($hash->{STATE} eq "off")){$action = "stop";}
    #if (($action eq "off") && ($hash->{STATE} eq "on")) {$action = "stop";}

    #$hash->{CHANGED}[0] = $action;
    #$hash->{STATE} = $action;
    readingsSingleUpdate($hash,"state",$action,1); 

    return $name;
  }
  return "";
}

########################################################
sub SD_RSL_Undef($$)
{ 
  my ($hash, $name) = @_;
  delete($modules{SIGNALduino_RSL}{defptr}{$hash->{DEF}}) if($hash && $hash->{DEF});
  return undef;
}

sub SD_RSL_Attr(@)
{
  my @a = @_;

  # Make possible to use the same code for different logical devices when they
  # are received through different physical devices.
  return if($a[0] ne "set" || $a[2] ne "IODev");
  my $hash = $defs{$a[1]};
  my $iohash = $defs{$a[3]};
  my $cde = $hash->{DEF};
  delete($modules{SIGNALduino_FA20RF}{defptr}{$cde});
  $modules{SIGNALduino_FA20RF}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
  return undef;
}

1;

=pod
=item summary devices communicating using the Conrad RSL protocol
=item summary_DE Anbindung von Conrad RSL Ger&auml;ten

=begin html

<a name="SD_RSL"></a>
<h3>RSL</h3>
The SD_RSL module decrypts and sends Conrad RSL messages sent by the SIGNALduino.<br>
<br>
<a name="SD_RSL_Define"></a>
<b>Define</b>
<ul>
	<p><code>define &lt;name&gt; SD_RSL &lt;code&gt;_&lt;channel&gt;_&lt;button&gt;</code>
	<br>
	<br>
	<code>&lt;name&gt;</code> is any name assigned to the device.
	For a better overview it is recommended to use a name in the form &quot;RSL_B1A800_1_2&quot;
	<br /><br />
	<code>&lt;code&gt;</code> The code is 00000-FFFFFF
	<br /><br />
	<code>&lt;channel&gt;</code> The channel is 1-4
	<br /><br />
	<code>&lt;button&gt;</code> The button is 1-4
	<br /><br />
</ul>   
<a name="SD_RSL_Set"></a>
<b>Set</b>
<ul>
  <code>set &lt;name&gt; &lt;value&gt;</code>
  <br /><br />
  <code>&lt;value&gt;</code> can be one of the following values:<br>
  <pre>
  off
  on
  </pre>
</ul>
<a name="SD_RSL_Get"></a>
<b>Get</b>
<ul>
	N/A
</ul>
<a name="SD_RSL_Attr"></a>
<b>Attribute</b>
<ul>
        <li><a href="#IODev">IODev</a></li>
	<li><a href="#do_not_notify">do_not_notify</a></li>
	<li><a href="#eventMap">eventMap</a></li>
	<li><a href="#ignore">ignore</a></li>
	<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	<li>RSLrepetition<br>
	Set the repeats for sending signal. 
	</li>
</ul>
=end html
=cut