##############################################
# $Id: 14_CUL_TCM97001.pm 6689 2014-10-05 12:27:19Z rudolfkoenig $
package main;

# From dancer0705
# Receive TCM 97001 temperature sensor

use strict;
use warnings;

sub
CUL_TCM97001_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^s....."; 
  $hash->{DefFn}     = "CUL_TCM97001_Define";
  $hash->{UndefFn}   = "CUL_TCM97001_Undef";
  $hash->{ParseFn}   = "CUL_TCM97001_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
                        $readingFnAttributes;
  $hash->{AutoCreate}=
        { "CUL_TCM97001.*" => { GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME" } };
}

#############################
sub
CUL_TCM97001_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_TCM97001 <code>"
        if(int(@a) < 3 || int(@a) > 5);

  $hash->{CODE} = $a[2];
  $hash->{lastT} =  0;
  $hash->{lastH} =  0;

  $modules{CUL_TCM97001}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";

  return undef;
}

#####################################
sub
CUL_TCM97001_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_TCM97001}{defptr}{$hash->{CODE}})
     if(defined($hash->{CODE}) &&
        defined($modules{CUL_TCM97001}{defptr}{$hash->{CODE}}));
  return undef;
}

###################################
sub
CUL_TCM97001_Parse($$)
{
  my ($hash, $msg) = @_;
  $msg = substr($msg, 1);
  # Msg format: AAATT
  my @a = split("", $msg); 

  my $id3 = hex($a[0] . $a[1]);

  my $def = $modules{CUL_TCM97001}{defptr}{$id3};
  if(!$def) {
    Log3 $hash, 2, "CUL_TCM97001 Unknown device $id3, please define it";
    if (length($msg) == 8) {
      return "UNDEFINED CUL_TCM97001_$id3 CUL_TCM97001 $id3" if(!$def); 
    } else {
      return "UNDEFINED CUL_TCM97001_$id3 CUL_TCM97001 $id3" if(!$def); 
    } 
  }
  my $now = time();

  my $name = $def->{NAME};

  Log3 $name, 4, "CUL_TCM97001 $name $id3 ($msg)";

  my ($msgtype, $val);

  if (length($msg) == 8) {
    # Only tmp device
    #eg. 1000 1111 0100 0011 0110 1000 = 21.8C
    #eg. --> shift2  0100 0011 0110 10
    my $temp    = (hex($a[3].$a[4].$a[5]) >> 2) & 0xFFFF;  


    my $negative    = (hex($a[2]) >> 0) & 0x3; 

    if ($negative == 0x3) {
      $temp = (~$temp & 0x03FF) + 1;
      $temp = -$temp;
    }

    $temp = $temp / 10;

    $def->{lastT} = $now;
    $msgtype = "temperature";
    $val = sprintf("%2.1f", ($temp) );
    Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 T: $val";


    # I think bit 3 on byte 3 is battery warning
    my $batbit    = (hex($a[2]) >> 0) & 0x4; 

    my $mode    = (hex($a[5]) >> 0) & 0x1; 

    my $unknown    = (hex($a[4]) >> 0) & 0x2; 
    

    my $state="";
    my $t = ReadingsVal($name, "temperature", undef);

    if(defined($t)) {
      $state="T: $t";
    }

    readingsBeginUpdate($def);
    readingsBulkUpdate($def, "state", $state);
    readingsBulkUpdate($def, $msgtype, $val);
    if ($batbit) {
      readingsBulkUpdate($def, "Battery", "Low");
    } else {
      readingsBulkUpdate($def, "Battery", "ok");
    }
    if ($mode) {
      Log3 $def, 5, "CUL_TCM97001 Mode: manual triggert";
    } else {
      Log3 $def, 5, "CUL_TCM97001 Mode: auto triggert";
    }
    if ($unknown) {
        Log3 $def, 5, "CUL_TCM97001 Unknown Bit: $unknown";
    }
    my $debug = "TEMP:$val°C BATT:";
    if ($batbit) {
      $debug = $debug . "empty";
    } else {
      $debug = $debug . "OK";
    }
    $debug = $debug . " HEX:0x";
    $debug = $debug . $a[0].$a[1].$a[2].$a[3].$a[4].$a[5];
    $debug = $debug . " BIN:";

    my @list = unpack("(A4)*", unpack ('B*', pack ('H*',$a[0].$a[1].$a[2].$a[3].$a[4].$a[5])));
    my $string = join(" ", @list);
    $debug = $debug . $string;
    Log3 $def, 5, "CUL_TCM97001 DEBUG: $debug";
    readingsEndUpdate($def, 1);
  } elsif (length($msg) == 12) { 
    # Long with tmp
    # All nibbles must be reversed  
    # e.g. 154E800480	   0001	0101 0100	1110 1000	0000 0000	0100 1000	0000
    #                      A    B    C    D    E    F    G    H    I
    # A+B = Addess
    # C Bit 1 Battery
    # D+E+F Temp 
    # G+H Hum
    my $bin = undef;

    my @a = split("", $msg);
    my $bitReverse = undef;
    my $x = undef;
    foreach $x (@a) {
       my $bin3=sprintf("%04b",hex($x));
      $bitReverse = $bitReverse . reverse($bin3); 
    }
    my $hexReverse = unpack("H*", pack ("B*", $bitReverse));

    #Split reversed a again
    my @aReverse = split("", $hexReverse);

    my $CRC = (hex($aReverse[0])+hex($aReverse[1])+hex($aReverse[2])+hex($aReverse[3])
              +hex($aReverse[4])+hex($aReverse[5])+hex($aReverse[6])+hex($aReverse[7])) & 15;
    if ($CRC + hex($aReverse[8]) == 15) {
        Log3 $def, 5, "CUL_TCM97001: CRC OK";
        my $temp = undef;
        if (hex($aReverse[5]) > 3) {
           # negative temp
           $temp = ((-hex($aReverse[3]) + -hex($aReverse[4]) * 16 + -hex($aReverse[5]) * 256)+1+4096)/10;
        } else {
           # positive temp
           $temp = (hex($aReverse[3]) + hex($aReverse[4]) * 16 + hex($aReverse[5]) * 256)/10;
        }

        $def->{lastT} = $now;
        my $humidity = hex($aReverse[7]).hex($aReverse[6]);

        $msgtype = "humidity";
        $val = $humidity;
        readingsBeginUpdate($def);
        readingsBulkUpdate($def, $msgtype, $val);

        $msgtype = "temperature";
        $val = sprintf("%2.1f", ($temp) );
        readingsBulkUpdate($def, $msgtype, $val);
        Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 T: $val H: $humidity"; 

        my $state="";
        my $t = ReadingsVal($name, "temperature", undef);
        my $h = ReadingsVal($name, "humidity", undef);
        if(defined($t) && defined($h)) {
          $state="T: $t H: $h";

        } elsif(defined($t)) {
          $state="T: $t";

        } elsif(defined($h)) {
          $state="H: $h";

        }

        readingsBulkUpdate($def, "state", $state);
        

        my $batbit = hex($aReverse[2]) & 1;
        my $mode = (hex($aReverse[2]) & 8) >> 3;

        if ($batbit) {
          readingsBulkUpdate($def, "Battery", "Low");
        } else {
          readingsBulkUpdate($def, "Battery", "ok");
        }
        if ($mode) {
          Log3 $def, 5, "CUL_TCM97001 Mode: manual triggert";
        } else {
          Log3 $def, 5, "CUL_TCM97001 Mode: auto triggert";
        }
        my $debug = "TEMP:$val°C HUM:$humidity :BATT:";
        if ($batbit) {
          $debug = $debug . "empty";
        } else {
          $debug = $debug . "OK";
        }
        $debug = $debug . " HEX:0x";
        $debug = $debug . $hexReverse;
        $debug = $debug . " BIN:$bitReverse";
        Log3 $def, 5, "CUL_TCM97001 DEBUG: $debug";
        readingsEndUpdate($def, 1);
    } else {
        Log3 $def, 5, "CUL_TCM97001: CRC Failed";
    }

  }

  return $name;
}

1;


=pod
=begin html

<a name="CUL_TCM97001"></a>
<h3>CUL_TCM97001</h3>
<ul>
  The CUL_TCM97001 module interprets temperature messages of TCM 97001 sensor received by the CUL.<br>
  <br>
  New received device packages are add in fhem category CUL_TCM97001 with autocreate.
  <br><br>

  <a name="CUL_TCM97001define"></a>
  <b>Define</b> <ul>The received devices created automatically.</ul><br>

  <a name="CUL_TCM97001events"></a>
  <b>Generated events:</b>
  <ul>
     <li>temperature: $temp</li>
     <li>humidity: $hum</li>
     <li>Battery: $bat</li>
  </ul>
  <br>

</ul>


=end html
=cut
