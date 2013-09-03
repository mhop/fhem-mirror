##############################################
#                                            #
# Written by Martin Paulat, 2013             #
#                                            #
##############################################

package main;

use strict;
use warnings;
use Date::Parse;



#####################################
sub
Revolt_Initialize($)
{
  my ($hash) = @_;

#                        r00C5E100303203C85921FF
  $hash->{Match}     = "^r......................\$";
  $hash->{DefFn}     = "Revolt_Define";
  $hash->{UndefFn}   = "Revolt_Undef";
  $hash->{ParseFn}   = "Revolt_Parse";
  $hash->{AttrList}  = "IODev ".
                       $readingFnAttributes;
}

#####################################
sub
Revolt_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> Revolt <id>" if(int(@a) != 3);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong <id> format: specify a 4 digit hex value"
  		if($a[2] !~ m/^[a-f0-9][a-f0-9][a-f0-9][a-f0-9]$/);

  $hash->{ID} = $a[2];
  #$hash->{STATE} = "Initialized";
  $modules{REVOLT}{defptr}{$a[2]} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
Revolt_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{REVOLT}{defptr}{$hash->{ID}})
        if(defined($hash->{ID}) &&
           defined($modules{REVOLT}{defptr}{$hash->{ID}}));
  return undef;
}

#####################################
sub
Revolt_Parse($$)
{
  my ($hash, $msg) = @_;

  $msg = lc($msg);
  my $seq = substr($msg, 1, 2);
  my $dev = substr($msg, 3, 4);
  my $cde = substr($msg, 7, 4);
  my $val = substr($msg, 11, 22);
  my $id       = substr($msg, 1, 4);
  my $voltage  = hex(substr($msg, 5, 2));
  my $current  = hex(substr($msg, 7, 4))*0.01;
  my $freq     = hex(substr($msg, 11, 2));
  my $power    = hex(substr($msg, 13, 4))*0.1;
  my $pf       = hex(substr($msg, 17, 2))*0.01;
  my $energy   = hex(substr($msg, 19, 4))*0.01;
  my $lastval;
  my $avg;
  
  my $type = "";
  
  if(!defined($modules{REVOLT}{defptr}{$id})) {
    Log3 undef,3, "Unknown Revolt device $id, please define it";
    $type = "Revolt" if(!$type);
    return "UNDEFINED ${type}_$id Revolt $id";
  }

  my $def = $modules{REVOLT}{defptr}{$id};
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));
  
  my $state;
  $state="P: ".sprintf("%5.1f",$power)." E: ".sprintf("%6.2f",$energy)." V: ".sprintf("%3d",$voltage)." C: ".sprintf("%6.2f",$current)." F: $freq Pf: ".sprintf("%4.2f",$pf);
  
  readingsBeginUpdate($def);
  
  if (defined($def->{READINGS}{".lastenergy"})) {
    $lastval=$def->{READINGS}{".lastenergy"}{VAL};
    if ($lastval != $energy) {
      $avg=(($lastval-$energy)*1000.0*3600.0)/(str2time($def->{READINGS}{".lastenergy"}{TIME})-gettimeofday());
      readingsBulkUpdate($def,".lastenergy", $energy,1);
      readingsBulkUpdate($def,"avgpower", sprintf("%.2f",$avg),1);
    }
  } else {
    readingsBulkUpdate($def,".lastenergy", $energy,1);
  }

  readingsBulkUpdate($def,"state", $state,1);
  Log3  $name,4, "$name: $state";
  readingsBulkUpdate($def,"voltage", $voltage,1);
  #Log3  $def,3, "$name:voltage $voltage";
  readingsBulkUpdate($def,"current", $current,1);
  #Log3  $def,3, "$name:current $current";
  readingsBulkUpdate($def,"frequency", $freq,1);
  #Log3  $def,3, "$name:frequency $freq";
  readingsBulkUpdate($def,"power", $power,1);
  #Log3  $def,3, "$name:power $power";
  readingsBulkUpdate($def,"pf", $pf,1);
  #Log3  $def,3, "$name:Pf $pf";
  readingsBulkUpdate($def,"energy", $energy,1);
  #Log3  $def,3, "$name:energy $energy";
  
  readingsEndUpdate($def, 1);

  return $name;
}

1;

=pod
=begin html

<a name="Revolt"></a>
<h3>Revolt NC-5462</h3>
<ul>
  Provides voltage, current, frequency, power, pf, energy readings for Revolt NC-5462 devices via CUL.
  <br><br>

  <a name="RevoltDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Revolt &lt;id&gt;</code>
    <br><br>
    &lt;id&gt; is a 4 digit hex number to identify the NC-5462 device.<br>
    Note: devices are autocreated on reception of the first message.<br>
  </ul>
  <br>
  <a name="RevoltReadings"></a>
  <b>Readings</b>
  <ul>
    <li>energy    [kWh]</li>
    <li>power     [W]</li>
    <li>voltage   [V]</li>
    <li>current   [A]</li>
    <li>frequency [Hz]</li>
    <li>Pf</li>
  </ul>

</ul>
=end html
=cut