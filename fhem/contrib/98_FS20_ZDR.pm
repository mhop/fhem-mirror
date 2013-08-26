package main;

use utf8;

sub
fs20_zdr_Initialize($)
{
 my ($hash) = @_;
 $hash->{DefFn}    = "fs20_zdr_Define";
 $hash->{SetFn} = "fs20_set";
 $hash->{AttrList} = "loglevel:0,1,2,3,4,5 powerDev volumeDev leftRightDev sleepMSDev 1_2_dev 3_4_dev 5_6_dev 7_8_dev";
}

sub 
fs20_set {
  my ($hash, @a) = @_;
  my $v = @a[1];
  
  my $name = $hash->{NAME};
  my $powerDev =  AttrVal($name, "powerDev", "");
  my $volumeDev =  AttrVal($name, "volumeDev", "");
  my $leftRightDev =  AttrVal($name, "leftRightDev", "");
  my $sleepMSDev =  AttrVal($name, "sleepMSDev", "");
  my $prog_1_2dev =  AttrVal($name, "1_2_dev", "");
  my $prog_3_4dev =  AttrVal($name, "3_4_dev", "");
  my $prog_5_6dev =  AttrVal($name, "5_6_dev", "");
  my $prog_7_8dev =  AttrVal($name, "7_8_dev", "");

  if ($v eq "on") {
    return "no power device set" if $powerDev eq "";
    fhem("set $powerDev on");
  } elsif ($v eq "off") {
    return "no power device set" if $powerDev eq "";
    fhem("set $powerDev off");
  } elsif ($v eq "volume_up") {
    return "no volume device set" if $volumeDev eq "";
    fhem("set $volumeDev on"); 
  } elsif ($v eq "volume_down") {
    return "no volume device set" if $volumeDev eq "";
    fhem("set $volumeDev off"); 
  } elsif ($v eq "left") {
    return "no leftRight device set" if $leftRightDev eq "";
    fhem("set $leftRightDev off"); 
  } elsif ($v eq "right") {
    return "no leftRight device set" if $leftRightDev eq "";
    fhem("set $leftRightDev on"); 
  } elsif ($v eq "sleep") {
    return "no sleepMS device set" if $sleepMSDev eq "";
    fhem("set $sleepMSDev off"); 
  } elsif ($v eq "ms") {
    return "no leftRight device set" if $sleepMSDev eq "";
    fhem("set $sleepMSDev on"); 
  } elsif ($v eq "1") {
    return "no 1_2 device set" if $prog_1_2dev eq "";
    fhem("set $prog_1_2dev off"); 
  } elsif ($v eq "2") {
    return "no 1_2 device set" if $prog_1_2dev eq "";
    fhem("set $prog_1_2dev on"); 
  } elsif ($v eq "3") {
    return "no 3_4 device set" if $prog_3_4dev eq "";
    fhem("set $prog_3_4dev off"); 
  } elsif ($v eq "4") {
    return "no 3_4 device set" if $prog_3_4dev eq "";
    fhem("set $prog_3_4dev on"); 
  } elsif ($v eq "5") {
    return "no 5_6 device set" if $prog_5_6dev eq "";
    fhem("set $prog_5_6dev off"); 
  } elsif ($v eq "6") {
    return "no 5_6 device set" if $prog_5_6dev eq "";
    fhem("set $prog_5_6dev on"); 
  } elsif ($v eq "7") {
    return "no 7_8 device set" if $prog_7_8dev eq "";
    fhem("set $prog_7_8dev off"); 
  } elsif ($v eq "8") {
    return "no 7_8 device set" if $prog_7_8dev eq "";
    fhem("set $prog_7_8dev on"); 
  } else {
    return "unknown set value, choose one of on off volume_up volume_down left right sleep ms 1 2 3 4 5 6 7 8";
  }

  if ($v eq "on" || $v eq "off") {
    $hash->{READINGS}{state}{VAL} = $v;
    $hash->{READINGS}{state}{TIME} = TimeNow();
    $hash->{STATE} = $v;
  }   
  return undef;
}

sub
fs20_zdr_Define($$)
{
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);

 if (int(@args) < 1)
 {
  return "fs20_zdr__Define: too many arguments. Usage:\n" .
         "define <name> FS20_zdr";
 }
 return "Invalid arguments. Usage: \n define <name> FS20_ZDR" if(int(@a) != 0);
 
 $hash->{STATE} = '??';

 return undef;
}

1;

=pod
=begin html

<a name="FS20_ZDR"></a>
<h3>FS20_ZDR</h3>
<ul>
  Creates a container device holding the sub devices for a FS20 ZDR device.

  <br><br>

  <a name="FS20_ZDRdefine"></a>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; FS20_ZDR</code>
    <br><br>

    Defines a FS20_ZDR device.<br><br>

    Example:
    <ul>
      <code>define radio FS20_ZDR</code><br>
    </ul>
  </ul>

  <a name="FS20_ZDRSet"></a>
  <h4>Set </h4>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    on                     # turn device on
    off                    # turn device off
    volume_up              # volume up
    volume_down            # volume down
    left                   # channel down
    right                  # channel up
    sleep                  # sleep
    ms                     # M/S command
    1 2 3 4 5 6 7 8        # radio channels
    </pre>

    Examples:
    <ul>
      <code>set radio volume_up</code><br>
    </ul>
  </ul>

powerDev volumeDev leftRightDev sleepMSDev 1_2_dev 3_4_dev 5_6_dev 7_8_dev
  <a name="FS20_ZDRAttr"></a>
  <h4>Attributes</h4> 
  <ul>
    <li><a name="FS20_ZDR_powerDev"><code>attr &lt;name&gt; powerDev &lt;deviceName&gt;</code></a>
                <br />Name of the device representing the power button</li>
    <li><a name="FS20_ZDR_volumeDev"><code>attr &lt;name&gt; volumeDev &lt;deviceName&gt;</code></a>
                <br />Name of the device representing the volume button</li>
    <li><a name="FS20_ZDR_leftRightDev"><code>attr &lt;name&gt; leftRightDev &lt;deviceName&gt;</code></a>
                <br />Name of the device representing the channel up/down (left/right) button</li>
    <li><a name="FS20_ZDR_sleepMSDev"><code>attr &lt;name&gt; sleepMSDev &lt;deviceName&gt;</code></a>
                <br />Name of the device representing the channel sleep / M/S button</li>
    <li><a name="FS20_ZDR_1_2_dev"><code>attr &lt;name&gt; 1_2_dev &lt;deviceName&gt;</code></a>
                <br />Name of the device representing channels 1 and 2/li>
    <li><a name="FS20_ZDR_3_4_dev"><code>attr &lt;name&gt; 3_4_dev &lt;deviceName&gt;</code></a>
                <br />Name of the device representing channels 3 and 4/li>
    <li><a name="FS20_ZDR_5_6_dev"><code>attr &lt;name&gt; 5_6_dev &lt;deviceName&gt;</code></a>
                <br />Name of the device representing channels 5 and 6/li>
    <li><a name="FS20_ZDR_7_8_dev"><code>attr &lt;name&gt; 7_8_dev &lt;deviceName&gt;</code></a>
                <br />Name of the device representing channels 7 and 8/li>
  </ul>

</ul>

=end html
=cut


