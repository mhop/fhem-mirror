##############################################################################
#
# 70_STV.pm
#
# a module to send messages or commands to a Samsung TV
# for example a LE40B650
#
# written 2012 by Gabriel Bentele <gabriel at bentele.de>>
#
# $Id$
#
# Version = 1.1
#
##############################################################################
#
# define <name> STV <host>
#
# set <name> <key> <value>
#
# where <key> is one of mute, volume, call, sms, date
# examples:
# set <name> mute on
# set <name> volume 20
# set <name> call Peter 1111111 Klaus 222222Peter 1111111 Klaus 222222
# set <name> sms Peter 1111111 Klaus 222222 das ist der text
# set <name> date 2012-12-10 18:07:04 Peter 11111 Bier 2012-12-11 23:59:20 Paulaner
#
##############################################################################

package main;
use IO::Socket::INET;

my @gets = ('dummy');

sub
STV_Initialize($)
{
my ($hash) = @_;
 $hash->{DefFn}    = "STV_Define";
 $hash->{StateFn}  = "STV_SetState";
 $hash->{SetFn}    = "STV_Set";
 $hash->{AttrList} = "loglevel:0,1,2,3,4,5";

}

sub
STV_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  return "Undefined value $val" if(!defined($it_c2b{$val}));
  return undef;
}


sub
STV_Define($$)
{
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);

 if (int(@args) < 2)
 {
  return "energy_Define: too much arguments. Usage:\n" .
         "define <name> STV <host> <port>";
 }

 $hash->{Host} = $args[2];
 $hash->{STATE} = 'Initialized';

 Log 3, "sub define2 with host: $hash->{Host}";

 return undef;
}

sub connection($$)
{
	my $tmp =  shift ; 
 	Log 4, "connection message: $tmp";
	my $TV = shift;
	my $buffer = "";
	my $tmp2 = "";

	my $sock = new IO::Socket::INET (
        	PeerAddr => $TV,
        	PeerPort => '52235',
        	Proto => 'tcp',
        	Timout => 5
        );
	if (defined ($sock)){
		print $sock $tmp;
		my $buff ="";
		while ((read $sock, $buff, 1) > 0){
		$buffer .= $buff;
		}
		@tmp2 = split (/\n/,$buffer);
 		Log 3, "$TV response: $tmp2[0]";
 		Log 4, "$TV buffer response: $buffer";
		$sock->close();
 		Log 4, "$TV: socket closed";
	}else{
 		Log 4, "$TV: not able to close socket";
	}
}

sub STV_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $TV = $hash->{Host};
  my $count = @a;

  my $arg    = lc($a[1]);      # mute volume
  my $cont1  = ucfirst($arg);  # Mute
  my $cont2 = ""; 
  my $cont3 = "";
  my $cont4 = "";
  my $cont5 = "";
  my $cont6 = "";
  my $cont7 = "";
  my $cont8 = "";
  my $cont9 = "";
	
  if (defined $a[2]) { $cont2 = $a[2]}
  if (defined $a[3]) { $cont3 = $a[3]}
  if (defined $a[4]) { $cont4 = $a[4]}
  if (defined $a[5]) { $cont5 = $a[5]}
  if (defined $a[6]) { $cont6 = $a[6]}
  if (defined $a[7]) { $cont7 = $a[7]}
  if (defined $a[8]) { $cont8 = $a[8]}
  if (defined $a[9]) { $cont9 = $a[9]}

  my $callsoap = "";
  my $message = "";
  my $head = "";
  my $kind = 0;
  my $size = "";
  my $body = "";

if ( $arg eq "mute" )
{	
	$kind = 1;
	if ( $cont2 eq "off" ){
		$cont2 = 0 ;
	}else {
		$cont2 = 1 ;
	}
}
if ( $arg eq "volume")
{	
	if ( $cont2 > 0 and $cont2 < 100 ){
		$kind = 1;
	}else {
		Log 3, "$name Volume: not correct";	
		$kind = 0;
	}
}
if ( $arg eq "call")
{
	$kind = 2;
	
}
if ( $arg eq "sms")
{
	$kind = 3;
	for my $i (6..$count){
		$body .= $a[$i];
		$body .= " ";
	}	
}
if ( $arg eq "date")
{
	$kind = 4;
	for my $i (10..$count){
		$body .= $a[$i];
		$body .= " ";
	}	
}

if ( $kind eq 1){
        $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
        $callsoap .= "<s:Envelope s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\">\r\n";
        $callsoap .= "<s:Body>\r\n";
        $callsoap .= "<ns0:Set$cont1 xmlns:ns0=\"urn:schemas-upnp-org:service:RenderingControl:1\">\r\n";
        $callsoap .= "<InstanceID>0</InstanceID>\r\n";
        $callsoap .= "<Desired$cont1>$cont2</Desired$cont1>\r\n";
        $callsoap .= "<Channel>Master</Channel>\r\n";
        $callsoap .= "</ns0:Set$cont1>\r\n";
        $callsoap .= "</s:Body>\r\n";
        $callsoap .= "</s:Envelope>\r\n";

        $size = length($callsoap);

        $head .= "POST /upnp/control/RenderingControl1 HTTP/1.1\r\n";
        $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
        $head .= "SOAPACTION: \"SoapAction:urn:schemas-upnp-org:service:RenderingControl:1#Set$cont1\"\r\n";
        $head .= "Cache-Control: no-cache\r\n";
        $head .= "Host: $TV:52235\r\n";
        $head .= "Content-Length: $size\r\n";
        $head .= "Connection: Close\r\n";
        $head .= "\r\n";

        $message .= $head;
        $message .= $callsoap;
}

my $calldate=`date +"%Y-%m-%d"`;
chomp($calldate);
my $calltime=`date +"%H:%M:%S"`;
chomp($calltime);

if ( $kind eq 2 ){ # CALL
        $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
        $callsoap .= "<s:Envelope s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" >\r\n";
        $callsoap .= "<s:Body>\r\n";
        $callsoap .= "<u:AddMessage xmlns:u=\"urn:samsung.com:service:MessageBoxService:1\\\">\r\n";
        $callsoap .= "<MessageType>text/xml</MessageType>\r\n";
        $callsoap .= "<MessageID>1334799348</MessageID>\r\n";
        $callsoap .= "<Message>\r\n";
        $callsoap .= "&lt;Category&gt;Incoming Call&lt;/Category&gt;\r\n";
        $callsoap .= "&lt;DisplayType&gt;Maximum&lt;/DisplayType&gt;\r\n";
        $callsoap .= "&lt;CallTime&gt;\r\n";
        $callsoap .= "&lt;Date&gt;$calldate&lt;/Date&gt;\r\n";
        $callsoap .= "&lt;Time&gt;$calltime&lt;/Time&gt;\r\n";
        $callsoap .= "&lt;/CallTime&gt;\r\n";
        $callsoap .= "&lt;Callee&gt;\r\n";
        $callsoap .= "&lt;Name&gt;An: $cont4&lt;/Name&gt;\r\n";
        $callsoap .= "&lt;Number&gt;Nr: $cont5&lt;/Number&gt;\r\n";
        $callsoap .= "&lt;/Callee&gt;\r\n";
        $callsoap .= "&lt;Caller&gt;\r\n";
        $callsoap .= "&lt;Name&gt;Von: $cont2&lt;/Name&gt;\r\n";
        $callsoap .= "&lt;Number&gt;Nr: $cont3&lt;/Number&gt;\r\n";
        $callsoap .= "&lt;/Caller&gt;\r\n";
        $callsoap .= "</Message>\r\n";
        $callsoap .= "</u:AddMessage>\r\n";
        $callsoap .= "</s:Body>\r\n";
        $callsoap .= "</s:Envelope>\r\n";

        $size = length($callsoap);
        $head .= "POST /PMR/control/MessageBoxService HTTP/1.1\r\n";
        $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
        $head .= "SOAPACTION: \"urn:samsung.com:service:MessageBoxService:1#AddMessage\"\r\n";
        $head .= "Cache-Control: no-cache\r\n";
        $head .= "Host: $TV:52235\r\n";
        $head .= "Content-Length: $size\r\n";
        $head .= "Connection: Close\r\n";
        $head .= "\r\n";

        $message .= $head;
        $message .= $callsoap;
   }

if ( $kind eq 3 ){ # SMS
        $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
        $callsoap .= "<s:Envelope s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" >\r\n";
        $callsoap .= "<s:Body>\r\n";
        $callsoap .= "<u:AddMessage xmlns:u=\"urn:samsung.com:service:MessageBoxService:1\\\">\r\n";
        $callsoap .= "<MessageType>text/xml</MessageType>\r\n";
        $callsoap .= "<MessageID>1334799348</MessageID>\r\n";
        $callsoap .= "<Message>\r\n";
        $callsoap .= "&lt;Category&gt;SMS&lt;/Category&gt;\r\n";
        $callsoap .= "&lt;DisplayType&gt;Maximum&lt;/DisplayType&gt;\r\n";
        $callsoap .= "&lt;ReceiveTime&gt;\r\n";
        $callsoap .= "&lt;Date&gt;$calldate&lt;/Date&gt;\r\n";
        $callsoap .= "&lt;Time&gt;$calltime&lt;/Time&gt;\r\n";
        $callsoap .= "&lt;/ReceiveTime&gt;\r\n";
        $callsoap .= "&lt;Receiver&gt;\r\n";
        $callsoap .= "&lt;Name&gt;An: $cont4&lt;/Name&gt;\r\n";
        $callsoap .= "&lt;Number&gt;Nr: $cont5&lt;/Number&gt;\r\n";
        $callsoap .= "&lt;/Receiver&gt;\r\n";
        $callsoap .= "&lt;Sender&gt;\r\n";
        $callsoap .= "&lt;Name&gt;Von: $cont2&lt;/Name&gt;\r\n";
        $callsoap .= "&lt;Number&gt;Nr: $cont3&lt;/Number&gt;\r\n";
        $callsoap .= "&lt;/Sender&gt;\r\n";
	$callsoap .= "&lt;Body&gt;Inhalt: $body&lt;/Body&gt;\r\n";
        $callsoap .= "</Message>\r\n";
        $callsoap .= "</u:AddMessage>\r\n";
        $callsoap .= "</s:Body>\r\n";
        $callsoap .= "</s:Envelope>\r\n";

        $size = length($callsoap);
        $head .= "POST /PMR/control/MessageBoxService HTTP/1.1\r\n";
        $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
        $head .= "SOAPACTION: \"urn:samsung.com:service:MessageBoxService:1#AddMessage\"\r\n";
        $head .= "Cache-Control: no-cache\r\n";
        $head .= "Host: $TV:52235\r\n";
        $head .= "Content-Length: $size\r\n";
        $head .= "Connection: Close\r\n";
        $head .= "\r\n";

        $message .= $head;
        $message .= $callsoap;
   }

if ( $kind eq 4 ){ # Termin
        $callsoap .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
        $callsoap .= "<s:Envelope s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" >\r\n";
        $callsoap .= "<s:Body>\r\n";
        $callsoap .= "<u:AddMessage xmlns:u=\"urn:samsung.com:service:MessageBoxService:1\\\">\r\n";
        $callsoap .= "<MessageType>text/xml</MessageType>\r\n";
        $callsoap .= "<MessageID>1334799348</MessageID>\r\n";
        $callsoap .= "<Message>\r\n";
        $callsoap .= "&lt;Category&gt;Schedule Reminder&lt;/Category&gt;\r\n";
        $callsoap .= "&lt;DisplayType&gt;Maximum&lt;/DisplayType&gt;\r\n";
        $callsoap .= "&lt;StartTime&gt;\r\n";
        $callsoap .= "&lt;Date&gt;$cont2&lt;/Date&gt;\r\n";
        $callsoap .= "&lt;Time&gt;$cont3&lt;/Time&gt;\r\n";
        $callsoap .= "&lt;/StartTime&gt;\r\n";
	$callsoap .= "&lt;Owner&gt;\r\n";
	$callsoap .= "&lt;Name&gt;Fr: $cont4&lt;/Name&gt;\r\n";
	$callsoap .= "&lt;Number&gt;Nr: $cont5&lt;/Number&gt;\r\n";
	$callsoap .= "&lt;/Owner&gt;\r\n";
	$callsoap .= "&lt;Subject&gt;Betreff: $cont6&lt;/Subject&gt;\r\n";
        $callsoap .= "&lt;EndTime&gt;\r\n";
        $callsoap .= "&lt;Date&gt;$cont7&lt;/Date&gt;\r\n";
        $callsoap .= "&lt;Time&gt;$cont8&lt;/Time&gt;\r\n";
        $callsoap .= "&lt;/EndTime&gt;\r\n";
        $callsoap .= "&lt;Location&gt;Ort: $cont9&lt;/Location&gt;\r\n";
        $callsoap .= "&lt;Body&gt;Inhalt: $body&lt;/Body&gt;\r\n";
        $callsoap .= "</Message>\r\n";
        $callsoap .= "</u:AddMessage>\r\n";
        $callsoap .= "</s:Body>\r\n";
        $callsoap .= "</s:Envelope>\r\n";

        $size = length($callsoap);
        $head .= "POST /PMR/control/MessageBoxService HTTP/1.1\r\n";
        $head .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
        $head .= "SOAPACTION: \"urn:samsung.com:service:MessageBoxService:1#AddMessage\"\r\n";
        $head .= "Cache-Control: no-cache\r\n";
        $head .= "Host: $TV:52235\r\n";
        $head .= "Content-Length: $size\r\n";
        $head .= "Connection: Close\r\n";
        $head .= "\r\n";

        $message .= $head;
        $message .= $callsoap;
}

if ( $kind ne 0 ){
	connection($message, $TV);
   }else{
	return "Unknown argument $name, choose one of mute volume call sms date";
   }
}

1;

=pod
=begin html

<a name="STV"></a>

<h3>STV</h3>
<ul><p>
This module supports Samsung TV devices with few commands. It's developed and tested with Samsung LE39B650.<br>
</p>
 <b>Define</b><br>
  <code>define &lt;name&gt; STV &lt;host&gt;]</code><br>
  <p>
  Example:<br>
  define Television1 STV 192.168.178.20 <br>
  </p>
 <b>Set</b><br>
  set &lt;name&gt; &lt;value&gt; &lt;nummber&gt;<br>where value is one of:<br><br>
  <ul>
  <li><code>mute</code> </li>
  <li><code>volume </code> </li>
  <li><code>call</code> </li>
  <li><code>sms  </code> </li>
  <li><code>date </code> </li>
  </ul>
   <br>Example:<br>
  set &lt;name&gt; mute <br>
  set &lt;name&gt; volume 20 <br>
  set &lt;name&gt; call Peter 012345678 Phone 87654321 <br><br>
  
 <b>Get</b><br>
   <ul>N/A</ul><br>
</ul>
   
=end html
=cut
