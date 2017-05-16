##############################################
# $Id$
package main;

use strict;
use warnings;
use Device::SerialPort;

my %sets = (
  "cmd"       => "",
  "freq"      => "",
);

#####################################
sub
SCIVT_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "SCIVT_Define";
  $hash->{GetFn}   = "SCIVT_Get";
  $hash->{SetFn}   = "SCIVT_Set";
  $hash->{AttrList}= "model:SCD10,SCD20,SCD30 loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
SCIVT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Define the serial device as a parameter, use none for a fake device"
        if(@a != 3);
  $hash->{STATE} = "Initialized";

  my $dev = $a[2];

  Log 1, "SCIVT device is none, commands will be echoed only"
    if($dev eq "none");

  if($dev ne "none") {
    Log 3, "SCIVT opening device $dev";
    my $po = new Device::SerialPort ($dev);
    return "SCIVT Can't open $dev: $!" if(!$po);
    Log 2, "SCIVT opened device $dev";
    $po->close();
  }

  $hash->{DeviceName} = $dev;
  $hash->{Timer} = 900; # call every 15 min
  $hash->{Cmd} = 'F';   # get all data,  min/max unchanged

  my $tn = TimeNow();
  $hash->{READINGS}{"freq"}{TIME} = $tn;
  $hash->{READINGS}{"freq"}{VAL} = $hash->{Timer};
  $hash->{READINGS}{"cmd"}{TIME} = $tn;
  $hash->{READINGS}{"cmd"}{VAL} = $hash->{Cmd};
  $hash->{CHANGED}[0] = "freq: $hash->{Timer}";
  $hash->{CHANGED}[1] = "cmd: $hash->{Cmd}";

  # InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  SCIVT_GetStatus($hash);
  $init_done = $oid;
  return undef;
}

#####################################
sub
SCIVT_Set($@)
{
my ($hash, @a) = @_;
 return "\"set SCIVT\" needs at least two parameter" if(@a < 3);
my $name = $hash->{NAME};
Log GetLogLevel($name,4), "SCIVT Set request $a[1] $a[2], old: Timer:$hash->{Timer} Cmd: $hash->{Cmd}"; 

return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

$name = shift @a;
my $type = shift @a;
my $arg = join("", @a);
my $tn = TimeNow();

if($type eq "freq") 
   { 
   if ($arg > 0)
      {
      $hash->{Timer} = $arg * 60; 
      $hash->{READINGS}{$type}{TIME} = $tn;
      $hash->{READINGS}{$type}{VAL} = $hash->{Timer};
      $hash->{CHANGED}[0] = "$type: $hash->{Timer}";
      }
   }

if($type eq "cmd") 
   { 
   if ($arg eq "F")
      {
      $hash->{Cmd} = 'F'; 	# F : get all data
      }
   if ($arg eq "L")		# L : get all data and clear min-/max values
      {
      $hash->{Cmd} = 'L'; 
      }
   $hash->{READINGS}{$type}{TIME} = $tn;
   $hash->{READINGS}{$type}{VAL} = $hash->{Cmd};
   $hash->{CHANGED}[0] = "$type: $hash->{Cmd}";
   }

DoTrigger($name, undef) if($init_done);

Log GetLogLevel($name,3), "SCIVT Set result Timer:$hash->{Timer} sec Cmd:$hash->{Cmd}";  
return "SCIVT => Timer:$hash->{Timer} Cmd:$hash->{Cmd}";
}

#####################################
sub
SCIVT_Get($@)
{
my ($hash, @a) = @_;
return "get for an SCIVT device needs exactly one parameter" if(@a != 2);
my $name = $hash->{NAME};

my $v;
if($a[1] eq "data") 
   {
   $v = SCIVT_GetLine($hash->{DeviceName}, $hash->{Cmd});
   if(!defined($v)) 
      {
      Log GetLogLevel($name,2), "SCIVT Get $a[1] error";
      return "$a[0] $a[1] => Error";
      }
   $v =~ s/[\r\n]//g;                          # Delete the NewLine
   $hash->{READINGS}{$a[1]}{VAL} = $v;
   $hash->{READINGS}{$a[1]}{TIME} = TimeNow();
   }
else 
   {
   if($a[1] eq "param") 
      {
      $v = "$hash->{DeviceName} $hash->{Timer} $hash->{Cmd}";
      }
   else
      {
      return "Unknown argument $a[1], must be data or param";
      }
   }

Log GetLogLevel($name,3), "SCIVT Get $a[1] $v";
return "$a[0] $a[1] => $v";
}

#####################################
sub
SCIVT_GetStatus($)
{
my ($hash) = @_;
my $dnr = $hash->{DEVNR};
my $name = $hash->{NAME};

# Call us in n minutes again.
InternalTimer(gettimeofday()+ $hash->{Timer}, "SCIVT_GetStatus", $hash,1);

my %vals;
my $result = SCIVT_GetLine($hash->{DeviceName}, $hash->{Cmd});

if(!defined($result)) 
   {
   Log GetLogLevel($name,4), "SCIVT read error, retry $hash->{DeviceName}, $hash->{Cmd}";
   $result = SCIVT_GetLine($hash->{DeviceName}, $hash->{Cmd});
   }

if(!defined($result)) 
   {
   Log GetLogLevel($name,2), "SCIVT read error, abort $hash->{DeviceName}, $hash->{Cmd}";
   $hash->{STATE} = "timeout";
   return $hash->{STATE};
   }
if (length($result) < 10)
   {
   Log GetLogLevel($name,2), "SCIVT incomplete line ($result)";
   $hash->{STATE} = "incomplete";
   }
else
   {
   $result =~ s/^.*R://;
   $result =~ s/[\r\n ]//g;   
   Log GetLogLevel($name,3), "SCIVT $result (raw)";
   $result=~ s/,/./g;
   my @data = split(";", $result);

   my @names = ("Vs", "Is", "Temp", "minV", "maxV", "minI", "maxI");
   my $tn = TimeNow();
   for(my $i = 0; $i < int(@names); $i++) 
      {
      $hash->{CHANGED}[$i] = "$names[$i]: $data[$i]";
      $hash->{READINGS}{$names[$i]}{TIME} = $tn;
      $hash->{READINGS}{$names[$i]}{VAL} = $data[$i];
      }

   DoTrigger($name, undef) if($init_done);

   $result =~ s/;/ /g;  
   $hash->{STATE} = "$result";
   }

return $hash->{STATE};
}

#####################################
sub
SCIVT_GetLine($$)
{
my $retry = 0;
my ($dev,$cmd) = @_;

  return "R:13,66; 0,0;30;13,62;15,09;- 0,2; 2,8;\n"
        if($dev eq "none");       # Fake-mode

  my $serport = new Device::SerialPort ($dev);
  if(!$serport) {
    Log 1, "SCIVT: Can't open $dev: $!";
    return undef;
  }
  $serport->reset_error();
  $serport->baudrate(1200);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');

  my $rm = "SCIVT timeout reading the answer";
  my $data="";

  $serport->write($cmd);
  sleep(1);

  for(;;) 
   {
    my ($rout, $rin) = ('', '');
    vec($rin, $serport->FILENO, 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, 3.0);

    if($nfound < 0) {
      $rm = "SCIVT Select error $nfound / $!";
      goto DONE;
    }
    last if($nfound == 0);

    my $buf = $serport->input();
    if(!defined($buf) || length($buf) == 0) {
      $rm = "SCIVT EOF on $dev";
      goto DONE;
    }


    $data .= $buf;
    if($data =~ m/[\r\n]/) {    # Newline received
      $serport->close();
      return $data;
    }
  }

DONE:
  $serport->close();
  Log 3, "SCIVT $rm";
  return undef;
}

1;

=pod
=begin html

<a name="SCIVT"></a>
<h3>SCIVT</h3>
<ul>
  <br>

  <a name="SCIVTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SCIVT &lt;SCD-device&gt;</code>
    <br><br>

    Define a SCD series solar controler device. Details see <a
    href="http://english.ivt-hirschau.de/content.php?parent_id=CAT_64&doc_id=DOC_118">here</a>.
    You probably need a Serial to USB controller like the PL2303.
    <br>
    Defining an SCIVT device will schedule an internal task, which reads the
    status of the device every 5 minutes, and triggers notify/filelog commands.
    <br>Note: Currently this device does not support a "set" function, only
    a single get function which reads the device status immediately.
    <br><br>

    Example:
    <ul>
      <code>define scd  SCIVT /dev/ttyUSB2</code><br>
    </ul>
    <br>
  </ul>

  <a name="SVICTset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SVICTget"></a>
  <b>Get</b>
  <ul>
    <code>get SCVIT data</code>
    <br>
  </ul>
  <br>

  <a name="SVICTattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a> (SCD)</li>
  </ul>
  <br>

</ul>


=end html
=cut
