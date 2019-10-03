# $Id$

# ToDo-List
# ---------
# - option to restrict the readings to the defined Mapping

# MatchList: add "8:KeyValueProtocol" => "^OK\\sVALUES\\s"
# Clients:   add KeyValueProtocol

# Test data
# ---------
# set myJeeLink parse OK VALUES LGW 12345 UpTime=2345678, SSID=MyCoolNetwork,LastReceiveTime=2015-11-17 13:39:14,Mode=OK,Connected,Cool,OTA=Ready
# set myJeeLink parse OK VALUES DAVIS 0 Channel=3, RSSI=-81, Battery=ok, WindSpeed=0, WindDirection=-36, TemperatureOutside=55.90
# set myJeeLink parse OK VALUES LGW 12345 UpTime=2345678, SSID=MyCoolNetwork,LastReceiveTime=2015-11-17 13:39:14,2015-11-18 14:15:16, Mode=OK,Connected,Cool,OTA=Ready
# set myJeeLink parse OK VALUES LGW 12345 U=2345678, S=MyCoolNetwork,T=2015-11-17 13:39:14,M=OK,Connected,Cool,O=Ready
# attr KeyValueProtocol_LGW_12345 Mapping U=UpTime,S=SSID,T=LastReceptionDate,M=Mode,O=OTA-State
# set myJeeLink parse INIT DICTIONARY U=UpTime,M=MessagesPerMinute,S=SSID

package main;

use strict;
use warnings;
use SetExtensions;

#=======================================================================================
sub KeyValueProtocol_Initialize($) {
  my ($hash) = @_;

  $hash->{Match}         = "^OK\\sVALUES\\s";
  $hash->{DefFn}         = "KeyValueProtocol_Define";
  $hash->{UndefFn}       = "KeyValueProtocol_Undef";
  $hash->{FingerprintFn} = "KeyValueProtocol_Fingerprint";
  $hash->{ParseFn}       = "KeyValueProtocol_Parse";
  $hash->{SetFn}         = "KeyValueProtocol_Set";
  $hash->{GetFn}         = "KeyValueProtocol_Get";
  $hash->{AttrFn}        = "KeyValueProtocol_Attr";
  $hash->{AttrList}      = "IODev " .
                           "Mapping " .
                           "$readingFnAttributes ";
                           
}


#=======================================================================================
sub KeyValueProtocol_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
  
  return "Usage: define <name> KeyValueProtocol <Type> <ID>" if(@a < 4);

  my $name = $a[0];
  my $type = $a[2];
  my $id   = $a[2] . "_" . $a[3];

  $hash->{STATE} = 'Initialized';
  $hash->{NAME}  = $name;
  $hash->{model} = $type;
  $hash->{ID}    = $id;
  
  $modules{KeyValueProtocol}{defptr}{$id} = $hash;
  
  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 4, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } 
  else {
    Log3 $name, 1, "$name: no I/O device";
  }
    
  return undef;
}


#=======================================================================================
sub KeyValueProtocol_Undef($$) {
  my ($hash, $arg) = @_;  
  my $id = $hash->{ID};
  
  delete($modules{KeyValueProtocol}{defptr}{$id});
  
  return undef;
}


#=======================================================================================
sub KeyValueProtocol_Get($@) {
  my ($hash, $name, $cmd, @args) = @_;
  
  
  return undef;
}


#=======================================================================================
sub KeyValueProtocol_Set($@) {
  my ($hash, $name, $cmd, @args) = @_;

  return undef;
}


#=======================================================================================
sub KeyValueProtocol_Fingerprint($$) {
  my ($name, $msg) = @_;
  return ("", $msg);
}


#=======================================================================================
sub KeyValueProtocol_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  
  return undef;
}


#=======================================================================================
sub KeyValueProtocol_Parse($$) {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  my $buffer = $msg;

  if( $msg =~ m/^OK VALUES/) {
    my @parts = split(' ', substr($msg, 10));
    my $sensorType = $parts[0];
    my $id = $parts[0] . "_" . $parts[1];

    if($modules{KeyValueProtocol}{defptr}{$id}) {
      my $rhash = $modules{KeyValueProtocol}{defptr}{$id};
      my $rname = $rhash->{NAME};

      my %mappings;
      # our "Mapping" attribute has priority
      my $mappingsString = AttrVal($rname, "Mapping", "");
      $mappingsString = InternalVal($rname, AttrVal($rname, "IODev", "") . "_Mapping", "") if (!$mappingsString);
      if ($mappingsString) {
        %mappings = split (/[,=]/, $mappingsString);
      }
      else {
        # Do we have initMessages in the IODevice?
        if ($rhash->{IODev}->{initMessages}) {
          my @ima = split('\n', $rhash->{IODev}->{initMessages});
          for my $i (0 .. $#ima) {
            my @im = split("INIT DICTIONARY ", $ima[$i]);
            if ($im[1]) {
              %mappings = split (/[,=]/, $im[1]);
              last;
            }
          }
        }
      }

      readingsBeginUpdate($rhash);

      my @kvPairs;
      my @data = split(',', substr($msg, 12 + length($parts[0]) + length($parts[1])));
      for my $i (0 .. $#data) {
        if(@kvPairs && index($data[$i], "=") == -1) {
          splice(@kvPairs, @kvPairs -1, 1, $kvPairs[@kvPairs -1] . "," . $data[$i]);
        }
        else {
          push(@kvPairs, $data[$i]);
        }
      }

      while (@kvPairs) {
        my $kvPairString = shift(@kvPairs);
        my @kvPair = split('=', $kvPairString, 2);

        my $value = $kvPair[1];

        my $key = $kvPair[0];
        $key =~ s/^\s+|\s+$//g;
        if (%mappings) {
          my $newKey = $mappings{$key};
          $key = $newKey if ($newKey);
        }

        readingsBulkUpdate($rhash, $key, $value) if ($value ne "");
      }

      readingsEndUpdate($rhash, 1);

      my @list;
      push(@list, $rname);
      return @list;
    }
    else {
      return "UNDEFINED KeyValueProtocol_$id KeyValueProtocol $parts[0] $parts[1]";
    }
  }
}

1;

=pod
=item summary    A generic module to receive key-value-pairs from an IO-Device like JeeLink.
=item summary_DE Empfängt key-value-pairs von einem IO-Device wie z.B. JeeLink.
=begin html

<a name="KeyValueProtocol"></a>
<h3>KeyValueProtocol</h3>

<ul>
  A generic module to receive key-value-pairs from an IODevice like JeeLink.<br>
  The data source can send any key/value pairs, which will get converted into readings.<br>
  The protocol that the sketch must send is: OK VALUES Key1=Value1,Key2=Value2, ...<br>
  <br>
  
  <a name="KeyValueProtocol_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; KeyValueProtocol &lt;Type&gt &lt;ID&gt;</code> <br>
    <br>
  </ul>
  
  <a name="KeyValueProtocol_Set"></a>
  <b>Set</b>
  <ul>

  </ul>
  <br>

  <a name="KeyValueProtocol_Get"></a>
  <b>Get</b>
  <ul>

  </ul>
  <br>

  <a name="KeyValueProtocol_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>Mapping<br>
      The Mapping attribute can optionally be used to translate the Keys.<br>
      The format is: ReceivedKey1=NewKey1,ReceivedKey2=NewKey2, ...<br>
      The Sketch can then send short Keys, which will get translated to long names.<br>
      Example: attr myKVP Mapping T=Temperature,H=Humidity<br>
      If the sketch then sends: OK VALUES T=12,H=70<br>
      you will get the readings Temperature and Humidity with the Values 12 and 70<br>
    </li>
  </ul>
  <br>
  
  <a name="KeyValueProtocol_Readings"></a>
  <b>Readings</b><br>
  <ul>
  Depending on the received data
  </ul>
  <br>

</ul>

=end html
=cut
