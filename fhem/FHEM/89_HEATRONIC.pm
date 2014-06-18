###############################################################################
# $Id$

###############################################################################
# This module is based on a work of Norbert S. described on
# http://www.mikrocontroller.net/topic/317004
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
###############################################################################



###############################################################################
#   Changelog:
#
#   2014-06-10  initial version
#   2014-06-10  wrong calculation of ch_Toutside
#   2014-06-11  wrong calculation of sol_Tcylinder_bottom
#   2014-06-11  logging telegram when error occurs
#   2014-06-12  new telegrams found: 9000ff0000d3020000a600 / 9000ff0000d3010000aa00
#   2014-06-12  documentation
#   2014-06-13  new telegrams with unknown length 9900ff00...
#   2014-06-14  disabled controller data with length 11 and 19
#   2014-06-15  error in handling controller data
#   2014-06-17  telegram length from 2014-06-13 determined: 9 Bytes, switching
#               heating mode (comfort, eco, frost) at specified time



# TODO:
# - $debug
# - $interval: time between messages in secs
# - ersetzen -> $hash->{buffer} .= unpack('H*',$buf)
# - Abfrage in der Form =~ "ff1002(.{4})(.*)1003(.{4})ff(.*)" ??
#   Problem: Erkennung anderer Längen


# list of abbreviations:
# ch  = central heating
# hc  = heating circuit
# dhw = domestic hot water
# sol = solar
# T   = temperatur


package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday time);
use IO::File;

sub HEATRONIC_Initialize($);
sub HEATRONIC_Define($$);
sub HEATRONIC_Undef($$);
sub HEATRONIC_Read($);
sub HEATRONIC_DecodeMsg_CH1($$$);
sub HEATRONIC_DecodeMsg_CH2($$$);
sub HEATRONIC_DecodeMsg_HC($$$);
sub HEATRONIC_DecodeMsg_DHW($$$);
sub HEATRONIC_DecodeMsg_REQ($$$);
sub HEATRONIC_DecodeMsg_DT($$$);
sub HEATRONIC_DecodeMsg_SOL($$$);
sub HEATRONIC_CRCtest($$$);
sub HEATRONIC_CRCget($);

my @crc_table = qw( 0x00 0x02 0x04 0x06 0x08 0x0a 0x0c 0x0e 0x10 0x12 0x14 0x16 0x18 0x1a 0x1c 0x1e 
                    0x20 0x22 0x24 0x26 0x28 0x2a 0x2c 0x2e 0x30 0x32 0x34 0x36 0x38 0x3a 0x3c 0x3e
                    0x40 0x42 0x44 0x46 0x48 0x4a 0x4c 0x4e 0x50 0x52 0x54 0x56 0x58 0x5a 0x5c 0x5e
                    0x60 0x62 0x64 0x66 0x68 0x6a 0x6c 0x6e 0x70 0x72 0x74 0x76 0x78 0x7a 0x7c 0x7e
                    0x80 0x82 0x84 0x86 0x88 0x8a 0x8c 0x8e 0x90 0x92 0x94 0x96 0x98 0x9a 0x9c 0x9e
                    0xa0 0xa2 0xa4 0xa6 0xa8 0xaa 0xac 0xae 0xb0 0xb2 0xb4 0xb6 0xb8 0xba 0xbc 0xbe
                    0xc0 0xc2 0xc4 0xc6 0xc8 0xca 0xcc 0xce 0xd0 0xd2 0xd4 0xd6 0xd8 0xda 0xdc 0xde
                    0xe0 0xe2 0xe4 0xe6 0xe8 0xea 0xec 0xee 0xf0 0xf2 0xf4 0xf6 0xf8 0xfa 0xfc 0xfe
                    0x19 0x1b 0x1d 0x1f 0x11 0x13 0x15 0x17 0x09 0x0b 0x0d 0x0f 0x01 0x03 0x05 0x07
                    0x39 0x3b 0x3d 0x3f 0x31 0x33 0x35 0x37 0x29 0x2b 0x2d 0x2f 0x21 0x23 0x25 0x27
                    0x59 0x5b 0x5d 0x5f 0x51 0x53 0x55 0x57 0x49 0x4b 0x4d 0x4f 0x41 0x43 0x45 0x47
                    0x79 0x7b 0x7d 0x7f 0x71 0x73 0x75 0x77 0x69 0x6b 0x6d 0x6f 0x61 0x63 0x65 0x67
                    0x99 0x9b 0x9d 0x9f 0x91 0x93 0x95 0x97 0x89 0x8b 0x8d 0x8f 0x81 0x83 0x85 0x87
                    0xb9 0xbb 0xbd 0xbf 0xb1 0xb3 0xb5 0xb7 0xa9 0xab 0xad 0xaf 0xa1 0xa3 0xa5 0xa7
                    0xd9 0xdb 0xdd 0xdf 0xd1 0xd3 0xd5 0xd7 0xc9 0xcb 0xcd 0xcf 0xc1 0xc3 0xc5 0xc7
                    0xf9 0xfb 0xfd 0xff 0xf1 0xf3 0xf5 0xf7 0xe9 0xeb 0xed 0xef 0xe1 0xe3 0xe5 0xe7 );

my $buffer = "";
my $fh;
#my $debug;
#my $interval;



sub
HEATRONIC_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{DefFn}   = "HEATRONIC_Define";
  $hash->{UndefFn} = "HEATRONIC_Undef";
  $hash->{ReadFn}  = "HEATRONIC_Read";
  $hash->{AttrList} =
	  "do_not_notify:1,0 loglevel:0,1,2,3,4,5,6 " . $readingFnAttributes;
}



sub
HEATRONIC_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> HEATRONIC <devicename>";
    Log3 $hash, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);
  my $name=$a[0];
  my $dev =$a[2];

  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash,0,0);
  
  $fh = IO::File->new("/opt/fhem/log/junkers.log",">");
  return $ret;
}



sub
HEATRONIC_Undef($$)
{
  my ( $hash, $arg ) = @_; 
  my $name = $hash->{NAME};  
  
  DevIo_CloseDev($hash);         
  RemoveInternalTimer($hash); 
  undef $fh;  
  return undef;              
}



sub
HEATRONIC_DoInit($)
{
  my ($hash) = @_;
  return undef;
}



sub
HEATRONIC_Read($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  my $x;
  my $value;
  my $length;
  my $position = 0;

#  $debug = AttrVal($name, "debug", 0);
#  $interval = AttrVal($name, "interval", 0);



  ############################
  # read data

  my $buf = DevIo_SimpleRead($hash);
  return if (!defined($buf));
 
#  $fh->print($buf);
#  $fh->flush();
  
  $buffer .= unpack('H*',$buf);



  #############################
  # parse messages
  
  # request data
  if ($buffer =~ "88000700") 
  {
    $position = index($buffer,"88000700");
    $length = 21;  

    if (length(substr($buffer,$position)) >= $length*2)
    {
      $value = HEATRONIC_DecodeMsg_REQ($hash,$buffer,$length);
      if (defined($value))
      {
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }
      else
      {
        Log3 $name, 3, "HEATRONIC error: Cannot handle message 'Request'";
	Log3 $name, 3, substr($buffer,$position,$length*2) . HEATRONIC_CRCget(substr($buffer,$position,$length*2));
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }		
    }
  }

  
  # vessel data 
  elsif ($buffer =~ "88001800") 
  {
    $position = index($buffer,"88001800");
    # 7D
#    if (length(substr($buffer,$position)) >= 32);
#    if (substr())

    $length = 33; # length 31 or 33 Bytes

    if (length(substr($buffer,$position)) >= $length*2)
    {
      $value = HEATRONIC_DecodeMsg_CH1($hash,substr($buffer,$position,$length*2),$length);
      if (!defined($value))
      {
        $length = 31;
        $value = HEATRONIC_DecodeMsg_CH1($hash,substr($buffer,$position,$length*2),$length);
        if (defined($value))
        {
          # nicht alles löschen, da Länge kleiner
          substr($buffer,$position,$length*2) = "";
        }
        else
        {
          Log3 $name, 3, "HEATRONIC error: Cannot handle message 'vessal data'";
          Log3 $name, 3, substr($buffer,$position,$length*2) . HEATRONIC_CRCget(substr($buffer,$position,$length*2));
          Log3 $name, 3, substr($buffer,$position,33*2) . HEATRONIC_CRCget(substr($buffer,$position,33*2));
          substr($buffer,$position,$length*2) = "";
          $buffer = "";
        }
      }
      else
      {
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }
    }
  }
  

  # heating circuit data
  elsif ($buffer =~ "88001900")
  {
    $position = index($buffer,"88001900");
    $length = 33;

    if (length(substr($buffer,$position)) >= $length*2)
    {
      # Bsp: 88 00 19 00 00 d1 80 00 80 00 00 00 00 00 00 01 fc 00 06 44 00 00 00 00 04 e0 00 01 d4 80 00 a0 00
      $value = HEATRONIC_DecodeMsg_CH2($hash,substr($buffer,$position,$length*2),$length);
      if (defined($value))
      {
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }
      else
      {
        Log3 $name, 3, "HEATRONIC error: Cannot handle message 'heating circuit data'";
        Log3 $name, 3, substr($buffer,$position,$length*2) . HEATRONIC_CRCget(substr($buffer,$position,$length*2));
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }
    }
  }

  
  # domestic hot water data
  elsif ($buffer =~ "88003400")
  {
  
    $position = index($buffer,"88003400");
	
    # length 22, 23 or 25 Bytes
    $length = 25;
	
    if (length(substr($buffer,$position)) >= $length*2)
    {
      $value = HEATRONIC_DecodeMsg_DHW($hash,substr($buffer,$position,$length*2),$length);
      if (!defined($value))
      {
        $length = 23;
        $value = HEATRONIC_DecodeMsg_DHW($hash,substr($buffer,$position,$length*2),$length);
        if (!defined($value))
        {
          $length = 22;
          $value = HEATRONIC_DecodeMsg_DHW($hash,substr($buffer,$position,$length*2),$length);
        }
      }
      
      if(defined($value))
      {
        # don't delete everything because of different lengths
        substr($buffer,$position,$length*2) = "";
      }
      else
      {
        Log3 $name, 3, "HEATRONIC error: Cannot handle message 'domestic hot water data'";
        Log3 $name, 3, substr($buffer,$position,25*2) . HEATRONIC_CRCget(substr($buffer,$position,25*2));
        substr($buffer,$position,$length*2) = "";
      }
    }
  }

  
  # date / time data
  elsif ($buffer =~ "90000600")
  {
    $position = index($buffer,"90000600");
    $length = 14;
   
    if (length(substr($buffer,$position)) >= $length*2)
    {
      $value = HEATRONIC_DecodeMsg_DT($hash,substr($buffer,$position,$length*2),$length);
      if (defined($value))
      {
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }
      else
      {
        Log3 $name, 3, "HEATRONIC error: Cannot handle message 'date / time data'";
        Log3 $name, 3, substr($buffer,$position,$length*2) . HEATRONIC_CRCget(substr($buffer,$position,$length*2));
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }
    }
  }
  

  # controller data (FW1xy / FW2xy)
  elsif ($buffer =~ "9000ff00")
  {
    $position = index($buffer,"9000ff00");
    $length = 17;
	
    if (length(substr($buffer,$position)) >= $length*2)
    {
      $value = HEATRONIC_DecodeMsg_HC($hash,substr($buffer,$position,$length*2),$length);
      if (!defined($value))
      {
        # 9000ff0000d3020000a600 / 9000ff0000d3010000aa00
        # from 23:00 to 05:00 first value, second value otherwise
        $length = 11;
        $value = HEATRONIC_DecodeMsg_HC($hash,substr($buffer,$position,$length*2),$length);
        if (!defined($value))
        {
    	  # 2014-06-13 found new messages: 9000ff00006f02c4000, 9000ff00006f03c5000
          # at 22:00, 06:00

          $length = 9;
          $value = HEATRONIC_DecodeMsg_HC($hash,substr($buffer,$position,$length*2),$length);
        }
      }
      
      if (defined($value))
      {
        # don't delete everything because of different lengths
        substr($buffer,$position,$length*2) = "";
      }
      else
      {
        Log3 $name, 3, "HEATRONIC error: Cannot handle message 'controller data'";
        Log3 $name, 3, substr($buffer,$position,17*2) . HEATRONIC_CRCget(substr($buffer,$position,17*2));
        substr($buffer,$position,$length*2) = "";
      }
    }
  }

  
  # Telegramm: Lastschaltmodul #1 (IPM)
  elsif ($buffer =~ "a000ff00")
  {
  }

  
  # Telegramm: Lastschaltmodul #2 (IPM)
  elsif ($buffer =~ "a100ff00")
  {
  }

  
  # solar data (ISM)
  elsif ($buffer =~ "b000ff00")
  {
    $position = index($buffer,"b000ff00");
    $length = 21;

    if (length(substr($buffer,$position)) >= $length*2)
    {
      $value = HEATRONIC_DecodeMsg_SOL($hash,substr($buffer,$position,$length*2),$length);
      if (defined($value))
      {
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }
      else
      {
        Log3 $name, 3, "HEATRONIC error: Cannot handle message 'solar data'";
        Log3 $name, 3, substr($buffer,$position,$length*2) . HEATRONIC_CRCget(substr($buffer,$position,$length*2));
        substr($buffer,$position,$length*2) = "";
        $buffer = "";
      }
    }
  }
}



sub
HEATRONIC_DecodeMsg_CH1($$$)
{
  my ($hash,$string,$length) = @_;
  my $name = $hash->{NAME};
  
  if (defined(HEATRONIC_CRCtest($hash,$string,$length)))
  {
    my $ch_Tflow_desired    = hex(substr($string,4*2,2));
    my $ch_Tflow_measured   = hex(substr($string,5*2,4))/10;
    my $ch_Treturn          = hex(substr($string,17*2,4))/10;
    my $ch_Tmixer           = hex(substr($string,13*2,4))/10;
    my $ch_burner_power     = hex(substr($string,8*2,2));
    my $ch_burner_operation = (hex(substr($string,9*2,2)) & 0x08) ? 1 : 0;
    my $ch_pump_heating     = (hex(substr($string,11*2,2)) & 0x20) ? 1 : 0;
    my $ch_pump_cylinder    = (hex(substr($string,11*2,2)) & 0x40) ? 1 : 0;
    my $ch_pump_circulation = (hex(substr($string,11*2,2)) & 0x80) ? 1 : 0;
    my $ch_burner_fan       = (hex(substr($string,11*2,2)) & 0x01) ? 1 : 0;
    my $ch_mode             = (hex(substr($string,9*2,2)) & 0x03);
	
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "ch_Tflow_desired", $ch_Tflow_desired); 
    readingsBulkUpdate($hash, "ch_Tflow_measured", sprintf("%.1f",$ch_Tflow_measured)); 
    readingsBulkUpdate($hash, "ch_Treturn", ($ch_Treturn*10 == 0x8000) ? sprintf("%.1f",$ch_Treturn) : "n/a");
    readingsBulkUpdate($hash, "ch_Tmixer", sprintf("%.1f", $ch_Tmixer));
    readingsBulkUpdate($hash, "ch_mode", $ch_mode);
    readingsBulkUpdate($hash, "ch_burner_fan", $ch_burner_fan);
    readingsBulkUpdate($hash, "ch_burner_operation", $ch_burner_operation);
    readingsBulkUpdate($hash, "ch_pump_heating", $ch_pump_heating);
    readingsBulkUpdate($hash, "ch_pump_cylinder", $ch_pump_cylinder);
    readingsBulkUpdate($hash, "ch_pump_circulation", $ch_pump_circulation);
    readingsBulkUpdate($hash, "ch_burner_power", $ch_burner_power);
    readingsEndUpdate($hash,1);

    return 1;
  }
  else
  {
    return undef;
  }
}



sub
HEATRONIC_DecodeMsg_CH2($$$)
{
  my ($hash,$string,$length) = @_;
  my $name = $hash->{NAME};

  if (defined(HEATRONIC_CRCtest($hash,$string, $length)))
  {
    my $ch_Toutside = hex(substr($string,4*2,2));
    if ($ch_Toutside != 255) { $ch_Toutside = ($ch_Toutside * 256 + hex(substr($string,5*2,2))) / 10 }
    else {$ch_Toutside = (255 - hex(substr($string,5*2,2)))/-10;}

    my $ch_runtime_tot  = hex(substr($string,17*2,6));
    my $ch_runtime_ch   = hex(substr($string,23*2,6));
    my $ch_starts_tot   = hex(substr($string,14*2,6));
    my $ch_starts_ch    = hex(substr($string,26*2,6));
	
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "ch_Toutside", sprintf("%.1f",$ch_Toutside));
    readingsBulkUpdate($hash, "ch_runtime_tot", $ch_runtime_tot);
    readingsBulkUpdate($hash, "ch_runtime_ch", $ch_runtime_ch);
    readingsBulkUpdate($hash, "ch_starts_tot", $ch_starts_tot);
    readingsBulkUpdate($hash, "ch_starts_ch", $ch_starts_ch);
    readingsEndUpdate($hash,1);

    return 1;
  }
  else 
  { 
    return undef;
  }
}



sub
HEATRONIC_DecodeMsg_HC($$$)
{
  my ($hash,$string,$length) = @_;
  my $name = $hash->{NAME};

  my $type;
  my $prefix = "hc1_";
  my $hc_Tdesired;
  my $hc_Tmeasured;
  
  if (defined(HEATRONIC_CRCtest($hash,$string, $length)))
  {

    # Messages of length 11 Bytes are unknown -> no handling
    if ($length == 11)
    { return 1; }
	
    $type = hex(substr($string,5*2,2));
	
    if ($type == 111) { $prefix = "hc1_";}
    elsif($type == 112) { $prefix = "hc2_"; }
    elsif($type == 114) { $prefix = "hc3_"; }
    elsif($type == 116) { $prefix = "hc4_"; }
	
    if ($length != 9)
    {
      $hc_Tdesired   = hex(substr($string,8*2,4))/10;
      $hc_Tmeasured  = hex(substr($string,10*2,4))/10;
    }
    my $hc_mode       = hex(substr($string,6*2,2));
	
    readingsBeginUpdate($hash);
    if ($length != 9)
    {
      readingsBulkUpdate($hash, $prefix . "Tdesired", sprintf("%.1f",$hc_Tdesired));
      readingsBulkUpdate($hash, $prefix . "Tmeasured", sprintf("%.1f",$hc_Tmeasured));
    }
    readingsBulkUpdate($hash, $prefix . "mode", $hc_mode);
    readingsEndUpdate($hash,1);

    return 1;
  }
  else 
  { 
    return undef;
  }
}



sub 
HEATRONIC_DecodeMsg_DHW($$$)
{
  my ($hash,$string,$length) = @_;
  my $name = $hash->{NAME};

  if (defined(HEATRONIC_CRCtest($hash,$string, $length)))
  {
    my $dhw_Tdesired  = hex(substr($string,4*2,2));
    my $dhw_Tmeasured = hex(substr($string,5*2,4))/10;
    my $dhw_Tcylinder = hex(substr($string,7*2,4))/10;
    my $ch_runtime_dhw = hex(substr($string,14*2,6));
    my $ch_starts_dhw = hex(substr($string,17*2,6));
	
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "dhw_Tdesired", $dhw_Tdesired);
    readingsBulkUpdate($hash, "dhw_Tmeasured", sprintf("%.1f",$dhw_Tmeasured));
    readingsBulkUpdate($hash, "dhw_Tcylinder", sprintf("%.1f",$dhw_Tcylinder));
    readingsBulkUpdate($hash, "ch_runtime_dhw", $ch_runtime_dhw);
    readingsBulkUpdate($hash, "ch_starts_dhw", $ch_starts_dhw);
    readingsEndUpdate($hash,1);
    return 1;
  }
  else 
  { 
    return undef;
  }
}



sub
HEATRONIC_DecodeMsg_REQ($$$)
{
  my ($hash,$string,$length) = @_;
  return 1;
}



sub
HEATRONIC_DecodeMsg_DT($$$)
{
  my ($hash,$string,$length) = @_;
  my $name = $hash->{NAME};
  
  if (defined(HEATRONIC_CRCtest($hash,$string,$length)))
  {
    my $year  = 2000 + hex(substr($string,4*2,2));
    my $month = hex(substr($string,5*2,2));
    my $day   = hex(substr($string,7*2,2));
    my $hours = hex(substr($string,6*2,2));
    my $min   = hex(substr($string,8*2,2));
    my $sec   = hex(substr($string,9*2,2));
    my $dow   = hex(substr($string,10*2,2));
#    my $dst     = (hex(substr($string,11*2,2)) & 0x01) ? "dst" : "";
	
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "ch_time", sprintf("%4d-%02d-%02d %02d:%02d:%02d", $year, $month, $day, $hours, $min, $sec ));
    readingsEndUpdate($hash,1);

    return 1;
  }
  else
  {
    return undef;
  }
}



sub
HEATRONIC_DecodeMsg_SOL($$$)
{
  my ($hash,$string,$length) = @_;
  my $name = $hash->{NAME};
  
  my $type;
  
  if (defined(HEATRONIC_CRCtest($hash,$string,$length)))
  {
  
    my $sol_Tcollector     = 0;
    my $sol_Tcylinder_bottom = 0;
    if (hex(substr($string,5*2,2)) == 3)
    {
      if (hex(substr($string,10*2,2)) != 255)
      {
        $sol_Tcollector       = hex(substr($string,10*2,4))/10;
        $sol_Tcylinder_bottom = hex(substr($string,12*2,4))/10;
      }
      else
      {
        $sol_Tcollector       = hex(255-substr($string,11*2,2))/-10;
        $sol_Tcylinder_bottom = hex(substr($string,12*2,4))/10;
      }
	
      my $sol_pump            = (hex(substr($string,14*2,2)) & 0x01) ? 1 : 0;
      my $sol_yield_last_hour = hex(substr($string,8*2,4));
      my $sol_yield_2         = hex(substr($string,6*2,4));
      my $sol_runtime         = hex(substr($string,17*2,4));
	
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "sol_Tcollector", $sol_Tcollector);
      readingsBulkUpdate($hash, "sol_Tcylinder_bottom", $sol_Tcylinder_bottom);
      readingsBulkUpdate($hash, "sol_yield_last_hour", $sol_yield_last_hour);
      readingsBulkUpdate($hash, "sol_yield_2", $sol_yield_2);
      readingsBulkUpdate($hash, "sol_pump", $sol_pump);
      readingsBulkUpdate($hash, "sol_runtime", $sol_runtime);
      readingsEndUpdate($hash,1);

      return 1;
    }
    elsif (hex(substr($string,5*2,2)) == 4)
    {
      my $hybrid_buffer   = hex(substr($string,6*2,4));
      my $hybrid_sysinput = hex(substr($string,8*2,4));

      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "sol_Thybrid_buffer", $hybrid_buffer);
      readingsBulkUpdate($hash, "sol_Thybrid_sysinput", $hybrid_sysinput);
      readingsEndUpdate($hash,1);

      return 1;
	  
    }
  }
  else
  {
    return undef;
  }
}



sub
HEATRONIC_CRCtest($$$)
{
  my ($hash,$string, $length) = @_;
  my $crc = 0;
  my $i;
  
  return undef if ($length < 3);
   
  for $i (0 .. $length-3)
  {
    $crc = hex($crc_table[$crc]);
    $crc ^= hex(substr($string,$i*2,2));
  }
  
  if ($crc == hex(substr($string,$length*2-4,2)))
  {
    return 1;
  }
  else
  {
    return undef;
  }
}



sub
HEATRONIC_CRCget($)
{
  my ($string) = @_;
  my $crc = 0;
  my $i;
  my $length = length($string)/2;

  for $i (0 .. $length-3)
  {
    $crc = hex($crc_table[$crc]);
    $crc ^= hex(substr($string,$i*2,2));
  }
  
  return "(".sprintf("%02x",$crc) . "/" . substr($string,$length*2-4,2) .")";
}

1;

=pod
=begin html

<a name="HEATRONIC"></a>
<h3>HEATRONIC</h3>

<ul>
     The HEATRONIC module interprets messages received from the HT-Bus of a Junkers Boiler. Possible Adapters are described in
	 http://www.mikrocontroller.net/topic/317004 (only in german).
	 
	 <br/><br/>
	 <a name="HEATRONIC_Define"></a>
     <B>Define:</B><br/>
	 <ul><code>define &lt;name&gt; HEATRONIC &lt;device&gt;</code><br/><br/></ul>
	 
	 <B>Example:</B></br>
	 <ul>
	   <code> define Boiler HEATRONIC /dev/ttyUSB0@9600</code>
	 </ul><br/>
	 
	 <a name="HEATRONIC_readings"><b>Readings:</b></a>
	 <ul>
	     <li><B>ch_Tflow_desired</B><br/>
		   required flow temperature (in domestic hot water mode value of max vessel temperature)<br>
		 </li><br/>
	     <li><B>ch_Tflow_measured</B><br/>
		   current measured flow temperature
		 </li><br/>
 	     <li><B>ch_Treturn</B><br/>
		   current measured return temperature
		 </li><br/>
 	     <li><B>ch_Tmixer</B><br/>
		   current measured mixer temperature
		 </li><br/>
 	     <li><B>ch_mode</B><br/>
		   current operation mode (0=off, 1=heating, 2=domestic hot water)
		 </li><br/>
	     <li><B>ch_burner_fan</B><br/>
		   status of burner fan (0=off, 1=running)
		 </li><br/>
	     <li><B>ch_burner_operation</B><br/>
		   burner status (0=off, 1=on)
		 </li><br/>
	     <li><B>ch_pump_heating</B><br/>
		   status of the heating pump(0=off, 1=running)
		 </li><br/>
	     <li><B>ch_pump_cylinder</B><br/>
		   status of cylinder loading pump (0=off, 1=running)
		 </li><br/>
	     <li><B>ch_pump_circulation</B><br/>
		   status of circulation pump (0=off, 1=running)
		 </li><br/>
	     <li><B>ch_burner_power</B><br/>
		   burner power in percent
		 </li><br/>

	     <li><B>ch_Toutside</B><br/>
		   outside temperature
		 </li><br/>
	     <li><B>ch_runtime_total</B><br/>
		   runtime of burner in minutes (heating and domestic hot water)
		 </li><br/>
	     <li><B>ch_runtime_ch</B><br/>
		   runtime of burner in minutes (heating only)
		 </li><br/>
	     <li><B>ch_runtime_dhw</B><br/>
		   runtime of burner in minutes (domestic hot water only)
		 </li><br/>
	     <li><B>ch_starts_tot</B><br/>
		   count of burner operations (heating and domestic hot water)
		 </li><br/>
	     <li><B>ch_starts_ch</B><br/>
		   count of burner operations (heating only)
		 </li><br/>
	     <li><B>ch_starts_dhw</B><br/>
		   count of burner operations (domestic hot water only)
		 </li><br/>
		 <li><B>ch_time</B><br/>
		   system time of boiler
		 </li><br/>
		 
	     <li><B>hc1_Tdesired .. hc4_Tdesired</B><br/>
		   required room temperature for heating circuit 1-4
		 </li><br/>
	     <li><B>hc1_Tmeasured .. hc4_Tmeasured</B><br/>
           current measured room temperature for heating circuit 1-4
		 </li><br/>
	     <li><B>hc1_Tmode .. hc4_Tmode</B><br/>
		   operating mode for heating circuit 1-4
		 </li><br/>

	     <li><B>dhw_Tdesired</B><br/>
		   required domestic hot water temperature
		 </li><br/>
	     <li><B>dhw_Tmeasured</B><br/>
		   current measured domestic hot water temperature
		 </li><br/>
	     <li><B>dhw_Tcylinder</B><br/>
		   current measured domestic hot water temperature at the top of the cylinder
		 </li><br/>

	     <li><B>sol_Tcollector</B><br/>
		   temperature of collector groupp 1
		 </li><br/>
	     <li><B>sol_Tcylinder_bottom</B><br/>
		   temperature at the bottom of solar cylinder
		 </li><br/>
	     <li><B>sol_yield_last_hour</B><br/>
		   yield of collector in the last hour
		 </li><br/>
         <li><B>sol_yield_2</B><br/>
		   This value is unkown at the moment. The name can be changed later.
		 </li><br/>
	     <li><B>sol_pump</B><br/>
		   status of solar circuit pump (0=off, 1=running)
		 </li><br/>
	     <li><B>sol_runtime</B><br/>
		    runtime of solar pump in minutes
		 </li><br/>
	 </ul>
</ul>

=end html
=begin html_DE

<a name="HEATRONIC"></a>
<h3>HEATRONIC</h3>

<ul>
     Das HEATRONIC Modul wertet die Nachrichten aus, die über den HT-Bus von einer Junkers-Heizung übertragen werden. Mögliche Adapter werden unter http://www.mikrocontroller.net/topic/317004 
	 vorgestellt.
	 
	 <br/><br/>
	 <a name="HEATRONIC_Define"></a>
     <B>Define:</B><br/>
	 <ul><code>define &lt;name&gt; HEATRONIC &lt;device&gt;</code><br/><br/></ul>
	 
	 <B>Beispiel:</B></br>
	 <ul>
	   <code> define Heizung HEATRONIC /dev/ttyUSB0@9600</code>
	 </ul><br/>
	 
	 <a name="HEATRONIC_readings"><b>Readings:</b></a>
	 <ul>
	     <li><B>ch_Tflow_desired</B><br/>
		   benötigte Vorlauf-Temperatur (im Warmwasser-Modus max. Kesseltemperatur)
		 </li><br/>
	     <li><B>ch_Tflow_measured</B><br/>
		   aktuell gemessene Vorlauf-Temperatur
		 </li><br/>
 	     <li><B>ch_Treturn</B><br/>
		   aktuell gemessene Rücklauf-Temperatur
		 </li><br/>
 	     <li><B>ch_Tmixer</B><br/>
		   aktuell gemessene Mischer-Temperatur
		 </li><br/>
 	     <li><B>ch_mode</B><br/>
		   aktueller Betriebsmodus (0=aus, 1=Heizen, 2=Warmwasser)
		 </li><br/>
	     <li><B>ch_burner_fan</B><br/>
		   Status Brenner-Gebläse (0=aus, 1=läuft)
		 </li><br/>
	     <li><B>ch_burner_operation</B><br/>
		   Brenner-Status (0=off, 1=an)
		 </li><br/>
	     <li><B>ch_pump_heating</B><br/>
		   Status der Heizungspumpe(0=aus, 1=läuft)
		 </li><br/>
	     <li><B>ch_pump_cylinder</B><br/>
		   Status der Speicherladepumpe (0=aus, 1=läuft)
		 </li><br/>
	     <li><B>ch_pump_circulation</B><br/>
		   Status der Zirkulationspumpe (0=aus, 1=läuft)
		 </li><br/>
	     <li><B>ch_burner_power</B><br/>
		   Brennerleistung in Prozent
		 </li><br/>

	     <li><B>ch_Toutside</B><br/>
		   Außentemperatur
		 </li><br/>
	     <li><B>ch_runtime_total</B><br/>
		   Brennerlaufzeit in Minuten (Heizen und Warmwasser)
		 </li><br/>
	     <li><B>ch_runtime_ch</B><br/>
		   Brennerlaufzeit in Minuten (nur Heizen)
		 </li><br/>
	     <li><B>ch_runtime_dhw</B><br/>
		   Brennerlaufzeit in Minuten (nur Warmwasser)
		 </li><br/>
	     <li><B>ch_starts_tot</B><br/>
		   Anzahl der Brennerstarts (Heizen und Warmwasser)
		 </li><br/>
	     <li><B>ch_starts_ch</B><br/>
		   Anzahl der Brennerstarts (nur Heizen)
		 </li><br/>
	     <li><B>ch_starts_dhw</B><br/>
		   Anzahl der Brennerstarts (nur Warmwasser)
		 </li><br/>
		 <li><B>ch_time</B><br/>
		   Systemzeit der Heizung
		 </li><br/>
		 
	     <li><B>hc1_Tdesired .. hc4_Tdesired</B><br/>
		   benötigte Raumtemperatur Heizkreis 1-4
		 </li><br/>
	     <li><B>hc1_Tmeasured .. hc4_Tmeasured</B><br/>
           aktuell gemessene Raumtemperatur Heizkreis 1-4
		 </li><br/>
	     <li><B>hc1_Tmode .. hc4_Tmode</B><br/>
		   Betriebsmodus Heizkreis 1-4
		 </li><br/>

	     <li><B>dhw_Tdesired</B><br/>
		   benötigte Warmwasser-Temperatur
		 </li><br/>
	     <li><B>dhw_Tmeasured</B><br/>
		   aktuell gemessene Warmwasser-Temperatur
		 </li><br/>
	     <li><B>dhw_Tcylinder</B><br/>
		   aktuell gemessene Warmwasser-Temperatur Speicher oben
		 </li><br/>

	     <li><B>sol_Tcollector</B><br/>
		   Temperatur Kollektorgruppe 1
		 </li><br/>
	     <li><B>sol_Tcylinder_bottom</B><br/>
		   Temperatur Solarspeicher unten
		 </li><br/>
	     <li><B>sol_yield_last_hour</B><br/>
		   Kollektorertrag der letzten Stunde
		 </li><br/>
         <li><B>sol_yield_2</B><br/>
		   Der Wert ist noch nicht bekannt. Der Name kann sich noch ändern.
		 </li><br/>
	     <li><B>sol_pump</B><br/>
		   Status der Solarpumpe (0=off, 1=läuft)
		 </li><br/>
	     <li><B>sol_runtime</B><br/>
		   Laufzeit der Solarpumpe in Minuten
		 </li><br/>
	 </ul>
</ul>

=end html_DE

=cut
