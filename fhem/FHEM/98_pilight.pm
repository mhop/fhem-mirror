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
  $hash->{AttrList}  = "protocol housecode number systemcode unitcode id remote_ip remote_port useOldVersion rawCodeOn rawCodeOff follow-on-for-timer";
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
  
  my $command = $a[1];
  my $c_timer= "";
  if(defined($a[2])) { $c_timer=$a[2]; }
  
  Log 3, "pilight command: $command";

  if($command eq "on") 
  {
    $rc = commit($hash, 1);
  } 
  elsif($command eq "on-for-timer")
  {
    InternalTimer(gettimeofday()+$c_timer, "pilight_on_timeout",$hash, 0);
    # on-for-timer is now a on.
    $rc = commit($hash, 1);
  }
#  elsif
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

###################################
sub 
pilight_on_timeout($)
{
  my ($hash) = @_;
  my @a;

  $a[0]=$hash->{NAME};
  $a[1]="off"; 

  pilight_Set($hash,@a);

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
  my $rawCodeOn = AttrVal($name, "rawCodeOn", $hash->{rawCodeOn});
  my $rawCodeOff = AttrVal($name, "rawCodeOff", $hash->{rawCodeOff});
  my $housecode = AttrVal($name, "id", AttrVal($name, "housecode", $hash->{housecode}));
  my $unit = AttrVal($name, "unitcode", $hash->{unitcode});
  my $systemcode = AttrVal($name, "systemcode", '0');
  my $param = $on ? "on" : "off";
  my $remote_ip = AttrVal($name, "remote_ip", '127.0.0.1');
  my $remote_port = AttrVal($name, "remote_port", '5000');
  my $useOldVersion = AttrVal($name, "useOldVersion", undef);
  my ($socket,$client_socket);
  
  # flush after every write
  $| = 1;
  
  $socket = new IO::Socket::INET (
  PeerHost => $remote_ip,
  PeerPort => $remote_port,
  Proto => 'tcp',
  ); 

  if (!$socket) { 
	Log 3, "pilight: ERROR. Can't open socket to pilight-daemon: $! See: https://github.com/andreas-fey/fhem-pilight/issues/3\n";
        return undef
  };


  my $data = $useOldVersion ? '{ "message": "client sender" }' : '{ "action": "identify" }';
  $socket->send($data);
  $socket->recv($data,1024);

  $data =~ s/\n/ /g;
  if ( $data !~ /accept client/ && $data !~ /success/)  # "accept client" < v6, 
  { 
      Log 3, "pilight: ERROR. No handshake with pilight-daemon. Received: >>>$data<<<\n";
      return undef
  };

  my $code = "{\"protocol\":[ \"$protocol\" ],";
  if( $protocol eq 'raw')
  {
    switch( $param ) {
      case 'on' 		{ $code = $code . "\"code\":\"$rawCodeOn\""} # on
      case 'off' 		{ $code = $code . "\"code\":\"$rawCodeOff\""} #off	
    }
  }
  else
  {
      switch( $protocol ) {
	case 'kaku_switch' 	{ $code = $code . "\"id\":$housecode, \"unit\":$unit,\"$param\":1"}
	case 'quigg_switch' 	{ $code = $code . "\"id\":$housecode, \"unit\":$unit,\"$param\":1"}
	case 'quigg_gt7000' 	{ $code = $code . "\"id\":$housecode, \"unit\":$unit,\"$param\":1"}
	case 'quigg_gt1000' 	{ $code = $code . "\"id\":$housecode, \"unit\":$unit,\"$param\":1"}
	case 'elro'        	{ $code = $code . "\"systemcode\":$systemcode, \"unitcode\":$unit,\"$param\":1"}
	case 'elro_he'     	{ $code = $code . "\"systemcode\":$systemcode, \"unitcode\":$unit,\"$param\":1"}
	case 'elro_hc'     	{ $code = $code . "\"systemcode\":$systemcode, \"unitcode\":$unit,\"$param\":1"}
	case 'silvercrest'     	{ $code = $code . "\"systemcode\":$systemcode, \"unitcode\":$unit,\"$param\":1"}
	case 'pollin'     	{ $code = $code . "\"systemcode\":$systemcode, \"unitcode\":$unit,\"$param\":1"}
	case 'brennenstuhl'    	{ $code = $code . "\"systemcode\":$systemcode, \"unitcode\":$unit,\"$param\":1"}
	case 'mumbi'     	{ $code = $code . "\"systemcode\":$systemcode, \"unitcode\":$unit,\"$param\":1"}
	case 'impuls'     	{ $code = $code . "\"systemcode\":$systemcode, \"programcode\":$unit,\"$param\":1"}
	case 'rsl366'     	{ $code = $code . "\"systemcode\":$systemcode, \"programcode\":$unit,\"$param\":1"}
	case 'intertechno_old'  { $code = $code . "\"id\":$systemcode, \"unit\":$unit,\"$param\":1"}
	case 'clarus_switch'    { $code = $code . "\"id\":\"$systemcode\", \"unit\":$unit,\"$param\":1"}
	case 'rev1_switch' 	{ $code = $code . "\"id\":\"$systemcode\", \"unit\":$unit,\"$param\":1"}
	case 'rev2_switch'	{ $code = $code . "\"id\":\"$systemcode\", \"unit\":$unit,\"$param\":1"}
	case 'rev3_switch'	{ $code = $code . "\"id\":\"$systemcode\", \"unit\":$unit,\"$param\":1"}
	}
  }
  $code = $code . '}';
		  
  $data = $useOldVersion ? "{ \"message\": \"send\", \"code\": $code}" : "{ \"action\": \"send\", \"code\": $code}";
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
    Supported protocols: kaku_switch, quigg_*, elro_he, elro_hc, silvercrest, pollin, brennenstuhl, mumbi, impuls, rsl366, rev1_switch, rev2_switch, clarus_switch, raw, and intertechno_old. If you need more, just write an issue!<br/><br/>
    Example:
    <ul>
      <code>define Weihnachtsbaum pilight kaku_switch</code><br>
      <code>attr Weihnachtsbaum housecode 12323578</code><br>
      <code>attr Weihnachtsbaum unitcode 0</code><br>
    </ul>
    <br/>
	If your pilight server does not run on localhost, please set both the attributes <b>remote_ip</b> and <b>remote_port</b>. If you are running pilight >3.0, then please <b>define the port used by pilight</b> settings: http://www.pilight.org/getting-started/settings/; fhem-plight uses 5000 by default.
    <br/>
    <b>This version is written for pilight 6.0. If you run a prior version, please set the following attribute:</b>
      <code> attr Weihnachtsbaum useOldVersion 1</code>
  </ul>

  <a name="pilight_Attr"></a>
  <h4>Attributes</h4> 
  <ul>
    <li><a name="protocol"><code>attr &lt;name&gt; protocol &lt;string&gt;</code></a>
                <br />Protocol used in pilight, e.g. "kaku_switch"</li>
    <li><a name="housecode"><code>attr &lt;name&gt; housecode &lt;string&gt;</code></a>
                <br />Housecode used in pilight (for protocol kaku*, clarus_switch, rev1_switch, rev2_switch, rev3_switch, quigg_switch, quigg_gt1000, quigg_gt7000)</li>
    <li><a name="systemcode"><code>attr &lt;name&gt; systemcode &lt;string&gt;</code></a>
                <br />Systemcode of your switch (for protocol elso, elro_he, elro_hc, silvercrest, impuls, rsl366, pollin, mumbi, brennenstuhl, intertechno_old)</li>
    <li><a name="unitcode"><code>attr &lt;name&gt; unitcode &lt;string&gt;</code></a>
                <br />Unit code/device code used in pilight (all protocols)</li>
    <li><a name="rawCodeOn/rawCodeOff"><code>attr &lt;name&gt; rawCode &lt;string&gt;</code></a>
                <br />Raw code to send on/off-command with protocol "raw"</li>
    <li><a name="remote_ip"><code>attr &lt;name&gt; remote_ip &lt;string&gt;</code></a>
                <br />Remote IP of you pilight server (127.0.0.1 is default)</li>
    <li><a name="remote_port"><code>attr &lt;name&gt; remote_port &lt;string&gt;</code></a>
                <br />Remote port of you pilight server (5000 is default)</li>
    <li><a name="rawCodeOn"><code>attr &lt;name&gt; rawCodeOn &lt;string&gt;</code></a>
                <br />Raw command to send to switch device ON (only used with protocol 'raw')</li>
    <li><a name="rawCodeOff"><code>attr &lt;name&gt; rawCodeOff &lt;string&gt;</code></a>
                <br />Raw command to send to switch device OFF (only used with protocol 'raw')</li>
  </ul>
</ul>

=end html
=cut

