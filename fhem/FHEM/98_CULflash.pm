##############################################
# $Id$
# modified by M. Fischer
package main;
use strict;
use warnings;
use HttpUtils;

sub CommandCULflash($$);

my $host = "http://fhem.de";
my $path = "/fhemupdate4/svn/";
my $file = "controls_fhem.txt";
my $dfu    = "dfu-programmer";

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
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $moddir = "$modpath/FHEM";

  my %ctypes = (
    CUL_V2     => "at90usb162",
    CUL_V2_HM  => "at90usb162",
    CUL_V3     => "atmega32u4",
    CUL_V4     => "atmega32u2",
  );
  my @a = split("[ \t]+", $param);
  return "Usage: CULflash <Fhem-CUL-Device> <CUL-type>, ".
                "where <CUL-type> is one of ". join(" ", sort keys %ctypes)
      if(!(int(@a) == 2 &&
          ($a[0] eq "none" || ($defs{$a[0]} && $defs{$a[0]}{TYPE} eq "CUL")) &&
          $ctypes{$a[1]}));

  my $cul  = $a[0];
  my $target = $a[1];

  ################################
  # First get the index file to prove the file size
  my $filetimes = GetFileFromURL("$host$path$file");
  return "Can't get $host$path$file" if(!$filetimes);

  my %filesize;
  foreach my $l (split("[\r\n]", $filetimes)) {
    chomp($l);
    next if ($l !~ m/^UPD (20\d\d-\d\d-\d\d_\d\d:\d\d:\d\d) (\d+) (.*)$/);
    $filesize{$3} = $2;
  }
  return "FHEM/$target.hex is not found in $host$path$file"
        if(!$filesize{"FHEM/$target.hex"});

  ################################
  # Now get the firmware file:
  my $content = GetFileFromURL("$host$path/FHEM/$target.hex");
  return "File size for $target.hex does not correspond to $file entry"
          if(length($content) ne $filesize{"FHEM/$target.hex"});
  my $localfile = "$moddir/$target.hex";
  open(FH,">$localfile") || return "Can't write $localfile";
  print FH $content;
  close(FH);

  my $cmd = "($dfu MCU erase && $dfu MCU flash TARGET && $dfu MCU start) 2>&1";
  my $mcu = $ctypes{$target};
  $cmd =~ s/MCU/$mcu/g;
  $cmd =~ s/TARGET/$localfile/g;

  if($cul ne "none") {
    CUL_SimpleWrite($defs{$cul}, "B01");
    sleep(4);     # B01 needs 2 seconds for the reset
  }
  Log3 undef, 1, "CULflash $cmd";
  my $result = `$cmd`;
  Log3 undef, 1, "CULflash $result";
  return $result;
}

# vim: ts=2:et
1;

=pod
=begin html

<a name="CULflash"></a>
<h3>CULflash</h3>
<ul>
  <code>CULflash &lt;CUL-Name&gt; &lt;CUL-Version&gt;</code> <br>
  <br>
    Download the CUL firmware from a nightly SVN chekout and flash the
    hardware. Currently only the CUL is supported with its versions:
    CUL_V2, CUL_V2_HM, CUL_V3, CUL_V4.<br>
    <b>Note:</b> dfu-programmer has to be installed in the path, this is
    already the case with the Fritz!Box 7390 image from fhem.de<br>

    If the CUL is not yet flashed, then specify "none" as CUL-Name.
    Example:
    <ul>
    <code>CULflash CUL CUL_V3<br>
          CULflash none CUL_V3</code>
    </ul>
    Note: the message "dfu-programmer: failed to release interface 0." is
    normal on the FB7390.
</ul>


=end html
=cut
