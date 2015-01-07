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
        { "CUL_TCM97001.*" => { GPLOT => "temp4:Temp,", FILTER => "%NAME" } };
}

#############################
sub
CUL_TCM97001_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_TCM97001 <code> [corr] [minsecs]"
        if(int(@a) < 3 || int(@a) > 5);

  $hash->{CODE} = 0; #$a[2];
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
    return "UNDEFINED CUL_TCM97001_$id3 CUL_TCM97001 $id3" if(!$def);
  }
  my $now = time();

  my $name = $def->{NAME};

  Log3 $name, 4, "CUL_TCM97001 $name $id3 ($msg)";

  my ($msgtype, $val);

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

  return $name;
}

1;


=pod
=begin html

<a name="CUL_TCM97001"></a>
<h3>CUL_TCM97001</h3>
<ul>
  The CUL_TCM97001 module interprets temperature messages of TCM 97001 sendor received by the CUL.
  <br><br>

  <a name="CUL_TCM97001define"</a>
  <b>Define</b> <ul>N/A</ul><br>

  <a name="CUL_TCM97001set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_TCM97001get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_TCM97001attr"></a>
  <b>Attributes</b>
  <ul>N/A</ul>
  <br>

  <a name="CUL_TCM97001events"></a>
  <b>Generated events:</b>
  <ul>
     <li>temperature: $temp</li>
  </ul>
  <br>

</ul>


=end html
=cut
