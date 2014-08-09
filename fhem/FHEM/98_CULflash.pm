##############################################
# $Id$
package main;
use strict;
use warnings;
use HttpUtils;

sub CommandCULflash($$);

my $urlbase = "http://fhem.de/fhemupdate4/svn/";

#####################################
sub
CULflash_Initialize($$)
{
  my %chash = ( Fn=>"CommandCULflash",
                Hlp=>"<cul> <type>,flash the CUL from the nightly SVN" );
  $cmds{CULflash} = \%chash;

}

#####################################
sub
CommandCULflash($$)
{
  my ($cl, $param) = @_;
  my %ctypes = (
    CUL_V2 =>
      { cmd => 'dfu-programmer at90usb162 erase && '.
               'dfu-programmer at90usb162 flash $filepath && '.
               'dfu-programmer at90usb162 start',
        flash => 'CUL_SimpleWrite($defs{$device},"B01");sleep(4); undef;' },
    CUL_V2_HM =>
      { cmd => 'dfu-programmer at90usb162 erase && '.
               'dfu-programmer at90usb162 flash $filepath && '.
               'dfu-programmer at90usb162 start',
        flash => 'CUL_SimpleWrite($defs{$device},"B01");sleep(4); undef;' },
    CUL_V3 => 
      { cmd => 'dfu-programmer atmega32u4 erase && '.
               'dfu-programmer atmega32u4 flash $filepath && '.
               'dfu-programmer atmega32u4 start',
        flash => 'CUL_SimpleWrite($defs{$device},"B01");sleep(4); undef;' },
    CUL_V4 =>
      { cmd => 'dfu-programmer atmega32u2 erase && '.
               'dfu-programmer atmega32u2 flash $filepath && '.
               'dfu-programmer atmega32u2 start',
        flash => 'CUL_SimpleWrite($defs{$device},"B01");sleep(4); undef' },
  );

  my @a = split("[ \t]+", $param);
  return "Usage: CULflash [FHEM-Device|none] TYPE>, ".
                "where TYPE is one of ". join(" ", sort keys %ctypes)
      if(int(@a)!=2 || !($a[0] eq "none" || $defs{$a[0]}) || !$ctypes{$a[1]});

  my $device = $a[0];
  my $type = $a[1];
  my $filename = $a[1].".hex";
  my $fwdir = $attr{global}{modpath} . "/FHEM/firmware";
  my $filepath = "$fwdir/$filename";

  ################################
  # Get the firmware file:
  if(! -d $fwdir) {
    mkdir($fwdir) || return "$fwdir: $!";
  }
  my $content = GetFileFromURL("$urlbase/FHEM/firmware/$filename");
  return "Cannot get $urlbase/FHEM/firmware/$filename"
    if(!$content);
  if($content !~ m/:00000001FF/) {
    Log3 undef, 3, $content;
    return "The retrieved $filename is not a correct .hex file";
  }

  my $localfile = "$filepath";
  open(FH,">$localfile") || return "Can't write $localfile";
  print FH $content;
  close(FH);

  if($device ne "none" && $ctypes{$type}{flash}) {
    my $ret = eval $ctypes{$type}{flash};
    Log 1, "CULflash $device: $ret"
      if($ret);
  }
  my $cmd = eval "return \"$ctypes{$type}{cmd};\"";
  Log3 undef, 1, "CULflash $cmd";
  my $result = `($cmd) 2>&1`;
  Log3 undef, 1, "CULflash $result";
  return $result;
}

1;

=pod
=begin html

<a name="CULflash"></a>
<h3>CULflash</h3>
<ul>
  <code>CULflash [fhem-device|none]; &lt;TYPE&gt;</code> <br>
  <br>
    Download the firmware from a nightly SVN chekout and flash the
    hardware.
    Currently the CUL is supported with its versions:
    CUL_V2, CUL_V2_HM, CUL_V3, CUL_V4.<br>
    If the fhem-device is none, than the inserted device must already be in the
    flash-mode.<br>
    <b>Note:</b>for flashing the CUL dfu-programmer has to be installed in the
    path, this is already the case with the Fritz!Box 7390 image from
    fhem.de<br>

    Example:
    <ul>
    <code>CULflash CUL CUL_V3<br>
          CULflash none CUL_V3</code>
    </ul>
    Note: the message "dfu-programmer: failed to release interface 0." is
    normal on the FB7390.
</ul>

=end html

=begin html_DE

<a name="CULflash"></a>
<h3>CULflash</h3>
<ul>
  <code>CULflash [fhem-device|none]; &lt;TYPE&gt;</code> <br>
  <br>
    L&auml;dt die spezifizierte Firmware von fhem.de und programmiert das
    angeschlossene Ger&auml;t.
    Z.Zt unterst&uuml;tzt wird das CUL und folgende Versionen:
    CUL_V2, CUL_V2_HM, CUL_V3, CUL_V4.<br>
    Falls als fhem-device none angegeben wurde, dann muss sich das
    angeschlossene Ger&auml;t bereits in flash-mode befinden.<br>
    <b>Achtung:</b>F&uuml;r CUL flashen muss dfu-programmer installiert und im
    Pfad auffindbar sein, das ist der Fall bei dem Fritz!BOX 7390 Paket von
    fhem.de<br>

    Beispiele:
    <ul>
    <code>CULflash CUL CUL_V3<br>
          CULflash none CUL_V3</code>
    </ul>
    Achtung: die Meldung "dfu-programmer: failed to release interface 0." ist
    auf der FB7390 "normal".
</ul>

=end html_DE
=cut
