
package main;
##############################################
# 88_IPWE.pm
# Modul for FHEM
#
# contributed by thomas dressler 2008
# $Id$

use strict;
use warnings;
use IO::Socket::INET;

use vars qw {%attr $init_done}; #make komodo happy
sub Log($$);
#####################################

sub
IPWE_Initialize($)
{
  my ($hash) = @_;
  # Consumer
  $hash->{DefFn}   = "IPWE_Define";
  $hash->{GetFn}   = "IPWE_Get";
  $hash->{AttrList}= "model:ipwe delay loglevel:0,1,2,3,4,5,6";
}

#####################################

sub
IPWE_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);
  Log 5, "IPWE Define: $a[0] $a[1] $a[2] $a[3]";
  return "Define the host as a parameter i.e. ipwe"  if(@a < 3);

  my $host = $a[2];
  my $delay=$a[3];
  $attr{$name}{delay}=$delay if $delay;
  Log 1, "ipwe device is none, commands will be echoed only" if($host eq "none");
  
  my $socket = IO::Socket::INET->new(PeerAddr=>$host,
                                     PeerPort=>80, #http
                                     timeout=>2,
                                     blocking=>1
                                     );

  if (!$socket) {
        $hash->{STATE} = "error opening device"; 
        Log 1,"$name: Error opening Connection to $host";
        return "Can't Connect to $host -> $@ ( $!)\n";
  }
  $socket->close;
  $hash->{Host} = $host;
  $hash->{STATE} = "Initialized";
  InternalTimer(gettimeofday()+$delay, "IPWE_GetStatus", $hash, 0);
  return undef;

}

sub IPWE_Get($@) 
{
  my ($hash, @a) = @_;
  return "argument is missing" if(int(@a) != 2);
  my $msg;
  $hash->{LOCAL} = 1;
    my $v = IPWE_GetStatus($hash);
    delete $hash->{LOCAL};
    my @data=split (/\n/, $v);
  if($a[1] eq "status") {
    $msg= "$a[0] $a[1] =>".$/."$v";
  }else {
    my ($l)= grep {/$a[1]/}@data;
    chop($l);
    $msg="$a[0] $a[1] =>$l";
  }
  $msg="$a[0]: Unknown get command $a[1]" if (!$msg);
  return $msg;
  }


  



#####################################

sub
IPWE_GetStatus($)
{
  my ($hash) = @_;
  
  my $buf;
  Log 5, "IPWE_GetStatus";
  my $name = $hash->{NAME};
  my $host = $hash->{Host};
  my $text='';
  my $alldata='';
  
  my $delay=$attr{$name}{delay}||300;
  InternalTimer(gettimeofday()+$delay, "IPWE_GetStatus", $hash, 0);
    my $socket = IO::Socket::INET->new(PeerAddr=>$host,
                                     PeerPort=>80, #http
                                     timeout=>2,
                                     blocking=>1
                                     );

  if (!$socket) {
        $hash->{STATE} = "error opening device"; 
        Log 1,"$name: Error opening Connection to $host";
        return "Can't Connect to $host -> $@ ( $!)\n";
  }
  Log 5, "$name: Connected to $host";
 
    $socket->autoflush(1);
    $socket->write("GET /ipwe.cgi HTTP/1.0\r\n");
    my @lines=$socket->getlines();
    close $socket;
    Log 5,"$name: Data received";
    
    my $allines=join('',@lines);
    my (@tables)= ($allines=~m#<tbody>(?:(?!<tbody>).)*</tbody>#sgi);
    my ($datatable)=grep{/Sensortyp/} @tables;
    my (@rows)=($datatable=~m#<tr>(?:(?!<tr>).)*</tr>#sgi);
    foreach my $l(@rows) {
        next if ($l=~/Sensortyp/); #headline
        my ($typ,$id,$sensor,$temp,$hum,$wind,$rain)=($l=~m#<td.*?>(.*?)<br></td>#sgi);
        next if ($typ=~/^\s+$/);
        $text= "Typ: $typ, ID: $id, Name $sensor, T: $temp H: $hum";
        if ($id == 8) {
           $text.= ",W: $wind, R: $rain";
        }
        Log 5,"$name: $text";
        if (!$hash->{local}){
            $hash->{CHANGED}[0] = $text;
            $hash->{READINGS}{$sensor}{TIME} = TimeNow();
            $hash->{READINGS}{$sensor}{VAL} = $text;;
            DoTrigger($name, undef) if($init_done);    
        }
        
        $alldata.="$text\n";
    }
    return $alldata;
}


1;


=pod
=begin html

<a name="IPWE"></a>
<h3>IPWE</h3>
<ul>
  <br>

  <a name="IPWEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; IPWE &lt;hostname&gt; [&lt;delay&gt;]</code>
    <br><br>

    Define a IPWE network attached weather data receiver device sold by ELV. Details see <a
    href="http://www.elv.de/output/controller.aspx?cid=74&detail=10&detail2=21508">here</a>.
    It's intended to receive the same sensors as WS300 (8 T/H-Sensors and one kombi sensor),
    but can be accessed via http and telnet.
    <br>
     For unknown reason, my try to use the telnet interface   was not working neither with raw sockets
      nor with Net::Telnet module. Therefore i choosed here the "easy" way
    to simple readout the http page and extract all data from the offered table. For this reason this module doesnt
    contain any option to configure this device.
    <br><br><b>Note:</b> You should give your sensors a name within the web interface, once they a received the first time.
    <br>To extract a single sensor simply match for this name or sensor id<br>
    <br>

    Attributes:
    <ul>
      <li><code>delay</code>: seconds between read accesses(default 300s)</li>

    </ul>
    <br>
    Example:
    <ul>
      <code>define ipwe IPWE ipwe1 120</code><br>
    </ul>
      <ul>
      <code>attr ipwe delay 600</code> : 10min between readouts<br>
    </ul>
    <br>
  </ul>

  <b>Set</b> <ul>N/A</ul><br>

  <a name="IPWEget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; status</code>
    <br><br>
    Gets actual data from device for sensors with data
    <br><br>
    <code>get &lt;name&gt; &lt;sensorname&gt; </code>
    <br><br>
    will grep output from device for this sensorname
    <br><br>
  </ul>


  <a name="IPWEattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a> (ipwe)</li>
    <li>delay</li>
    <li><a href="#loglevel">loglevel</a></li>
  </ul>
  <br>

</ul>
=end html
=cut
