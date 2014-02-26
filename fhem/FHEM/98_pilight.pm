##############################################
package main;

use strict;
use warnings;
use IO::Socket::INET;
use Switch;

sub
pilight_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "pilight_Set";
  $hash->{DefFn}     = "pilight_Define";
  $hash->{AttrList}  = "protocol housecode number systemcode unitcode id remote_ip remote_port";
}

# housecode == id und number == unitcode
###################################
sub
pilight_Set($@)
{
  my ($hash, @a) = @_;
  my $rc = undef;
  
  return "no set value specified" if(int(@a) < 2);
  return "on off" if($a[1] eq "?");
  
  shift @a;
  my $command = shift @a;
  
  Log 3, "pilight command: $command";

  if($command eq "on") 
  {
    $rc = commit($hash, 1);
  } 
  else
  {
    $rc = commit($hash, 0);
  }
  
  if ($rc) {
     $hash->{CHANGED}[0] = $command;
     $hash->{STATE} = $command;
     $hash->{READINGS}{state}{TIME} = TimeNow();
     $hash->{READINGS}{state}{VAL} = $command;
  };
  
  return undef;
}

sub
pilight_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> <protocol>";
  return $u if(int(@a) < 2);
  
  $hash->{protocol} = $a[2];

  #for backward compartibility

  $hash->{housecode} = (int(@a) > 2) ? $a[3] : '';
  $hash->{unitcode}  = (int(@a) > 2) ? $a[4] : '';
  
  return undef;
}


sub commit
{
  my ($hash, $on) = @_;
  my $name   = $hash->{NAME};
  my $protocol = $hash->{protocol};
  my $housecode = AttrVal($name, "id", AttrVal($name, "housecode", $hash->{housecode}));
  my $unit = AttrVal($name, "unitcode", $hash->{unitcode});
  my $systemcode = AttrVal($name, "systemcode", '0');
  my $param = $on ? "on" : "off";
  my $remote_ip = AttrVal($name, "remote_ip", '127.0.0.1');
  my $remote_port = AttrVal($name, "remote_port", '5000');
  my ($socket,$client_socket);
  
  # flush after every write
  $| = 1;
  
  $socket = new IO::Socket::INET (
  PeerHost => $remote_ip,
  PeerPort => $remote_port,
  Proto => 'tcp',
  ); 
  
  if (!$socket) { 
	Log 3, "pilight: ERROR. Can't open socket to pilight-daemon: $!\n";
        return undef
  };

  my $data = '{ "message": "client sender" }';
  $socket->send($data);
  $socket->recv($data,1024);
  
  $data =~ s/\n/ /g;
  if ( $data !~ /accept client/ ) {
	Log 3, "pilight: ERROR. No handshake with pilight-daemon. Received: >>>$data<<<\n";
        return undef
  };

  my $code = "{\"protocol\":[ \"$protocol\" ],";
  switch( $protocol ) {
	case 'kaku_switch' { $code = $code . "\"id\":\"$housecode\", \"unit\":\"$unit\",\"$param\":\"1\""}
	case 'elro'        { $code = $code . "\"systemcode\":\"$systemcode\", \"unitcode\":\"$unit\",\"$param\":\"1\""}
  }
  $code = $code . '}';
		  
  $data = "{ \"message\": \"send\", \"code\": $code}";
  Log 3, "pilight data: $data";

  $socket->send($data);
  $socket->close();
  
  return 1;
}

1;

=pod
=begin html

<a name="pilight"></a>
<h3>pilight</h3>
<ul>
  <a name="pilight_define"></a>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; pilight &lt;protocol&gt;</code>
    <br/>
    <br/>
    Defines a module for setting pilight compartible switches on or off. See <a href="http://www.sweetpi.de/blog/258/funksteckdosen-mit-dem-raspberry-pi-und-pilight-schalten">Sweetpi</a>.<br><br>
    Supported protocols: kaku_switch, elso. If you need more, just contact me!<br/><br/>
    Example:
    <ul>
      <code>define Weihnachtsbaum pilight kaku_switch</code><br>
      <code>attr Weihnachtsbaum housecode 12323578</code><br>
      <code>attr Weihnachtsbaum unitcode 0</code><br>
    </ul>
    <br/>
	If your pilight server does not run on localhost, please set both the attributes <b>remote_ip</b> and <b>remote_port</b>.
    <br/>
  </ul>

  <a name="pilight_Attr"></a>
  <h4>Attributes</h4> 
  <ul>
    <li><a name="protocol"><code>attr &lt;name&gt; protocol &lt;string&gt;</code></a>
                <br />Protocol used in pilight, e.g. "kaku_switch"</li>
    <li><a name="user"><code>attr &lt;name&gt; housecode &lt;string&gt;</code></a>
                <br />Housecode used in pilight (for protocol kaku*)</li>
    <li><a name="user"><code>attr &lt;name&gt; unitcode &lt;string&gt;</code></a>
                <br />Unit code/device code used in pilight (for protocol kaku* or elso)</li>
    <li><a name="systemcode"><code>attr &lt;name&gt; systemcode &lt;string&gt;</code></a>
                <br />Systemcode of your switch (for protocol elso)</li>
    <li><a name="numer"><code>attr &lt;name&gt; remote_ip &lt;string&gt;</code></a>
                <br />Remote IP of you pilight server (127.0.0.1 is default)</li>
    <li><a name="numer"><code>attr &lt;name&gt; remote_port &lt;string&gt;</code></a>
                <br />Remote port of you pilight server (5000 is default)</li>
  </ul>
</ul>

=end html
=cut
