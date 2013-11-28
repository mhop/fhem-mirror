###################LoTT Uniroll###################
# UNIRoll:no synchronisation, the message protocoll begins directly with datas
# group address  16 Bit like an housecode
# channel address 4 Bit up to 16 devices
# command         4 Bit up: E(1110),stop: D(1101), down: B(1011)
# end off         1 Bit, zero or one it doesnot matter
# whole length   25 Bit
#time intervall:
#Bit-digit 0     high ca. 1,6 ms        equal 100(h64) 16us steps
#                low  ca. 0,576 ms             36(h24)
#Bit-digit 1     high ca. 0,576 ms             36(h24)
#                low  ca. 1,6 ms              100(h64)
#timespace ca.   100 ms 
#binary : 1010 1011 1100 1101 0110 1110 1
#hexa:    a    b    c    d    6    e    8 (an additional one bit)
#the message is sent with the general cul-command: G
#G0031A364242464abcd6e8   :  00 synchbits 3 databytes, 1 databit, HHLLLLHH, data

package main;

use strict;
use warnings;

my %codes = (
  "e" => "up",       #1110 e
  "d" => "stop",     #1101 d
  "b" => "down",	     #1011 b
);

my %readonly = (
  "thermo-on" => 1,
  "thermo-off" => 1,
);

use vars qw(%UNIRoll_c2b);		# Peter would like to access it from outside

my $UNIRoll_simple ="off off-for-timer on on-for-timer on-till reset timer toggle";

my %models = (
    R_23700 => 'simple',
    dummySimple => 'simple',
);

sub hex2fouru($);
sub four2hexu($$);
 
sub
UNIRoll_Initialize($)
 

{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    $UNIRoll_c2b{$codes{$k}} = $k;   # c2b liest das allgmeine Array der Gerätegruppe
  }
# print "UNIRoll_Initialize \n";
  $hash->{Match}     = "^G.*";
  $hash->{SetFn}     = "UNIRoll_Set";
  $hash->{StateFn}   = "UNIRoll_SetState";
  $hash->{DefFn}     = "UNIRoll_Define";
  $hash->{UndefFn}   = "UNIRoll_Undef";
  $hash->{ParseFn}   = "UNIRoll_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ".
                        "ignore:1,0 showtime:1,0 ".
                        "loglevel:0,1,2,3,4,5,6 " .
                        "model:".join(",", sort keys %models);
}

#####################################
sub
UNIRoll_SetState($$$$)   # 4 Skalare Parameter

{
  my ($hash, $tim, $vt, $val) = @_;  #@_ Array
# print "UNIRoll_SetState \n";

  $val = $1 if($val =~ m/^(.*) \d+$/);  # m match Funktion
  my $name = $hash->{NAME};
  (undef, $val) = ReplaceEventMap($name, [$name, $val], 0)
        if($attr{$name}{eventMap});
  return "setstate $name: undefined value $val" if(!defined($UNIRoll_c2b{$val}));
  return undef;
}


###################################
sub
UNIRoll_Set($@)
 
{
  my ($hash, @a) = @_; # Eingabewerte nach define name typ devicecode channelcode
  my $ret = undef;
  my $na = int(@a);    #na Anzahl Felder in a
 # print "UNIRoll_Set \n";
  return "no set value specified" if($na < 2 || $na > 3);
  return "Readonly value $a[1]" if(defined($readonly{$a[1]}));

  my $c = $UNIRoll_c2b{$a[1]}; # Wert des Kommandos: up stop down
  my $name = $a[0];            # Gerätename
  if(!defined($c)) {

    # Model specific set arguments
    if(defined($attr{$name}) && defined($attr{$name}{"model"})) {
      my $mt = $models{$attr{$name}{"model"}};
      return "Unknown argument $a[1], choose one of "
                                               if($mt && $mt eq "sender");
      return "Unknown argument $a[1], choose one of $UNIRoll_simple"
                                               if($mt && $mt eq "simple");
    }
    return "Unknown argument $a[1], choose one of " .
                                join(" ", sort keys %UNIRoll_c2b);
  }

  my $v = join(" ", @a);
  Log GetLogLevel($name,2), "UNIRoll set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  my $val;
 
# G0030A364242464abcd6e8   :  00 Synchbits 3 Datenbytes, 1 Datenbit, HHLLLLHH, Daten
# Damit kein Befehl einen zufälligen Betrieb stoppt 
# vorher ein gezielter Stopp Befehl
  my $stop = "d";
  IOWrite($hash, "","G0030A364242464".$hash->{XMIT}.$hash->{BTN}.$stop); 
#  print "$hash XMIT:$hash->{XMIT}    BTN: $hash->{BTN} c: $c \n";           
  IOWrite($hash, "","G0030A364242464".$hash->{XMIT}.$hash->{BTN}.$c);              
# XMIT: Gerätegruppe, BTN: Kanalnummer, c: Commando


 
  ###########################################
  # Set the state of a device to off if on-for-timer is called
  if($modules{UNIRoll}{ldata}{$name}) {
    CommandDelete(undef, $name . "_timer");
    delete $modules{UNIRoll}{ldata}{$name};
  }
  if($a[1] =~ m/for-timer/ && $na == 3 &&
     defined($attr{$name}) && defined($attr{$name}{"follow-on-for-timer"})) {
    my $to = sprintf("%02d:%02d:%02d", $val/3600, ($val%3600)/60, $val%60);
    $modules{UNIRoll}{ldata}{$name} = $to;
    Log 4, "Follow: +$to setstate $name off";
    CommandDefine(undef,
                $name."_timer at +$to setstate $name off; trigger $name off");
  }

  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{XMIT} $hash->{BTN}";
  my $tn = TimeNow();
  my $defptr = $modules{UNIRoll}{defptr};
  foreach my $n (keys %{ $defptr->{$code} }) {
    my $lh = $defptr->{$code}{$n};
    $lh->{CHANGED}[0] = $v;
    $lh->{STATE} = $v;
    $lh->{READINGS}{state}{TIME} = $tn;
    $lh->{READINGS}{state}{VAL} = $v;
    my $lhname = $lh->{NAME};
    if($name ne $lhname) {
      DoTrigger($lhname, undef);
    }
  }

  return $ret;
}

#############################

sub 
UNIRoll_Define($$) 


# Gerät anmelden hash: Hash-adresse, def: Eingabe bei define .....
# Hauscode, Kanalnummer aufbereiten prüfen
 {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $u = "wrong syntax: define <name> UNIRoll device adress " .
                        "addr [fg addr] [lm addr] [gm FF]";
# print "UNIRoll_Define \n";

  return $u if(int(@a) < 4);
  return "Define $a[0]: wrong device address format: specify a 4 digit hex value ".
         "or an 8 digit quad value"
  		if( ($a[2] !~ m/^[a-f0-9]{4}$/i) && ($a[2] !~ m/^[1-4]{8}$/i) );

  return "Define $a[0]: wrong chanal format: specify a 1 digit hex value " .
         "or a 2 digit quad value"
  		if( ($a[3] !~ m/^[a-f0-9]{1}$/i) && ($a[3] !~ m/^[1-4]{2}$/i) );

  my $devcode = $a[2];
  $devcode = four2hexu($devcode,4) if (length($devcode) == 8);

  my $chacode = $a[3];
  $chacode = four2hexu($chacode,2) if (length($chacode) == 4);

  $hash->{XMIT} = lc($devcode);             # hex Kleinschreibung ?
  $hash->{BTN}  = lc($chacode);
 
# Gerätedaten aufbauen, 
# defptr: device pointer global

  my $code = lc("$devcode $chacode");              #lc lowercase Kleinschreibung
  my $ncode = 1;                                   #?
  my $name = $a[0];                                #Gerätename
  $hash->{CODE}{$ncode++} = $code;
  $modules{UNIRoll}{defptr}{$code}{$name}   = $hash;

# print "Test IoPort $hash def $def code $code.\n";

  AssignIoPort($hash);  # Gerät anmelden
}

#############################
sub
UNIRoll_Undef($$)

{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};
# print "UNIRoll_Undef \n";
    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{UNIRoll}{defptr}{$c} }) {
      delete($modules{UNIRoll}{defptr}{$c}{$dname})
        if($modules{UNIRoll}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

sub
UNIRoll_Parse($$)


{
 #  print "UNIRoll_Parse \n";
}

#############################
sub
hex2fouru($)
{
  my $v = shift;
  my $r = "";
  foreach my $x (split("", $v)) {
    $r .= sprintf("%d%d", (hex($x)/4)+1, (hex($x)%4)+1);
  }
 #  print "UNIRoll_hex2fouru $r \n";

  return $r;
}

#############################
sub
four2hexu($$)
{
  my ($v,$len) = @_;
  my $r = 0;
  foreach my $x (split("", $v)) {
    $r = $r*4+($x-1);
  }
#   print "UNIRoll_fourhex r:$r len: $len\n";

  return sprintf("%0*x", $len,$r);
}


1;


=pod
=begin html

<a name="UNIRoll"></a>
<h3>UNIRoll</h3>
<ul>
  The protocol is used by the Lott UNIROLL R-23700 reciever. The radio
  (868.35 MHz) messages are either received through an <a href="#FHZ">FHZ</a>
  or an <a href="#CUL">CUL</a> device, so this must be defined first.
  Recieving sender messages is not integrated.
  The CUL have to allow working with zero synchbits on the beginning of a message.
  <br><br>

  <a name="UNIRolldefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; UNIRoll &lt;devicegroup&gt; &lt;deviceaddress&gt; </code>
    <br><br>

   The values of devicegroup addres (similar to the housecode) and device address (button) can be either defined as
   hexadecimal value or as ELV-like "quad-decimal" value with digits 1-4. We
   will reference this ELV-like notation as ELV4 later in this document. You
   may even mix both hexadecimal and ELV4 notations, because FHEM can detect
   the used notation automatically by counting the digits.
   There is no master or group code integrated.
   <br>

   <ul>
   <li><code>&lt;devicecode&gt;</code> is a 4 digit hex or 8 digit ELV4 number,
     corresponding to the housecode address.</li>
   <li><code>&lt;channel&gt;</code> is a 1 digit hex or 2 digit ELV4 number,
     corresponding to a button of the transmitter.</li>
   </ul>
   <br>

    Examples:
    <ul>
      <code>define lamp UNIRoll 7777 0
      <code>define otherlamp UNIRoll 24242424 11
    </ul>
  </ul>
  <br>

  <a name="UNIRollset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    up
    stop
    down               
    </pre>
    Examples:
    <ul>
      <code>set roll up</code><br>
      <code>set roll1,roll2,roll3 up</code><br>
      <code>set roll1-roll3 up</code><br>
    </ul>
    <br>

  <b>Get</b> <ul>N/A</ul><br>

  <a name="UNIRollattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Set the IO or physical device which should be used for sending signals
        for this "logical" device. An example for the physical device is an FHZ
        or a CUL.</li><br>

    <a name="eventMap"></a>
    <li>eventMap<br>
        Replace event names and set arguments. The value of this attribute
        consists of a list of space separated values, each value is a colon
        separated pair. The first part specifies the "old" value, the second
        the new/desired value. If the first character is slash(/) or komma(,)
        then split not by space but by this character, enabling to embed spaces.
        Examples:<ul><code>
        attr device eventMap up:open down:closed<br>
        set device open
        </code></ul>
        </li><br>

    <li><a href="#loglevel">loglevel</a></li><br>

    <li><a href="#showtime">showtime</a></li><br>

    <a name="model"></a>
    <li>model<br>
        The model attribute denotes the model type of the device.
        The attributes will (currently) not be used by the fhem.pl directly.
        It can be used by e.g. external programs or web interfaces to
        distinguish classes of devices and send the appropriate commands.
        The spelling of the model names are as quoted on the printed
        documentation which comes which each device. This name is used
        without blanks in all lower-case letters. Valid characters should be
        <code>a-z 0-9</code> and <code>-</code> (dash),
        other characters should be ommited. Here is a list of "official"
        devices:<br><br>

          <b>Receiver/Actor</b>: there is only one reciever: R_23700
    </li><br>

  </ul>
  <br>

  
</ul>

