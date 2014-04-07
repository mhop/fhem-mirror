##############################################################################
#
# 51_Netzer.pm
#
##############################################################################
# Modul for Netzer access
#
#
# 
##############################################################################

package main;
use strict;
use warnings;
use POSIX;
use Scalar::Util qw(looks_like_number);
use IO::File;

#vorhandene Ports
my @ports = ( "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m" );

sub Netzer_Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}    = "Netzer_Define";
  $hash->{ReadFn}  =  "Netzer_Read";
  $hash->{GetFn}    = "Netzer_Get";
  $hash->{SetFn}    = "Netzer_Set";
  $hash->{AttrFn}   = "Netzer_Attr";
  $hash->{UndefFn}  = "Netzer_Undef";
  $hash->{ExceptFn} = "Netzer_Except";
  $hash->{AttrList} = "poll_interval" .
					  " Port_a:in,out,cnt" . " Port_b:in,out,cnt" . " Port_c:in,out,cnt" .
					  " Port_d:in,out,PWM" .
					  " Port_e:in,out,ADC" . " Port_f:in,out,ADC" .
					  " Port_g:in,out"     . " Port_h:in,out"     . " Port_i:in,out" .
					  " Port_j:in,out,PWM" .
					  " Port_k:in,out"     . " Port_l:in,out"     . " Port_m:in,out";
}
#############################################
sub Netzer_Define($$) {
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);
 my $menge = int(@args);
 if (int(@args) < 2) {
  return "Define: to less arguments. Usage:\n" .
         "define <name> Netzer <Host>:<port>";
 }
 #Pruefen, ob GPIO bereits verwendet
 foreach my $dev (devspec2array("TYPE=$hash->{TYPE}")) {
   if ($args[2] eq InternalVal($dev,"DeviceName","")) {
     return "IP-Address $args[2] already used by $dev";
   }
 }
 my $name = $args[0];
 $hash->{DeviceName} = $args[2];
 Netzer_conn($hash); 
 # create default attributes
 #my $msg = CommandAttr(undef, $name . ' direction input');
 #return $msg if ($msg);
 return undef;
}
#############################################
sub Netzer_Get($;$) {
  my (@a) = @_;
  my $hash = $a[0]; 
  my $name = $hash->{NAME};
  my ($port,$cnt) = split("_", $a[2]) if ( defined($a[2]) );
  my $function = $attr{$name}{"Port_".$port} if defined($port) && defined($attr{$name}{"Port_".$port});
  my $buf = "";
  if ( !( defined($a[2]) ) ) {
     foreach (@ports) {
	   if(defined($attr{$name}) && defined($attr{$name}{"Port_".$_})) {
	     my $function = $attr{$name}{"Port_".$_};
	     if ($function =~ m/^(PWM|ADC)$/i) {
		    $buf = $_."=?\r\n";
			Netzer_send($hash, $buf);
		 } elsif ($function =~ m/^(cnt)$/i) {
		    $buf = "z".$_."=?\r\n";
			Netzer_send($hash, $buf);			
		 }
	   }
	 }
     $buf = "x=?\r\n";
  } elsif ( defined($port) && grep( /^$port$/, @ports ) && defined($cnt) && $cnt eq "counter" && defined($function) && $function eq "cnt" ) {
     $buf = "z" . $port ."=?\r\n";
  } elsif ( defined($port) && grep( /^$a[2]$/, @ports ) && $port ne "?" ) {
     $buf = $a[2]."=?\r\n";
  } else {
     my $list = "";
     foreach (@ports) {
	   #next if (wenn port nicht genutzt werden soll);
	   $list .= " " unless ($list eq "");
	   $list .= $_ . ':noArg';
	   $list .= " " . $_ . "_counter:noArg" if( defined($attr{$name}) && defined($attr{$name}{"Port_".$_}) && $attr{$name}{"Port_".$_} eq "cnt" ); 
     }
     return 'Unknown argument ' . $a[2] . ', choose one of ' . $list;
  }
  Netzer_send($hash, $buf);
  return;
}
#############################################
sub Netzer_Set($@) {
  my ($hash, @a) = @_;
  my $name = $a[0];
  my $port = $a[1] if (defined ($a[1]));
  my $val  = $a[2] if (defined ($a[2]));
  ($port, my $cnt) = split("_", $port) if defined($port) && $port =~ m/(_counter)$/;
  my $function = $attr{$name}{"Port_".$port} if defined($port) && defined($attr{$name}{"Port_".$port});
  if ( defined($function) && (  ( $function=~ m/^(PWM|out)$/i && !defined($cnt) ) || ( $function=~ m/^(cnt)$/i && defined($cnt) ) ) ) {
	 my $msg = "$name: wrong value ". (defined($val)?"$val ":"") . "for Port_$a[1], valid values: 0-";  
	 my $buf = undef;
	 if ( $function eq "cnt" && defined($cnt) ) {
	   return $msg . "32767" if !defined($val) || $val > 32767 || $val < 0;
	   $buf = "z" . $port;
	 } else {
	   return $msg . "1023"  if ($function eq "PWM" && (!defined($val) || $val > 1023  || $val < 0));
	   return $msg . "1"     if ($function eq "out" && (!defined($val) || $val > 1     || $val < 0));
       $buf = $port;
	 }
	 $val = sprintf("%x",$val);
	 $buf .= "=$val\r\n";
     Netzer_send($hash, $buf);
  }  else {
     my $list = "";
     foreach (@ports) {
	   if(defined($attr{$name}) && defined($attr{$name}{"Port_".$_})) {
	     my $function = $attr{$name}{"Port_".$_};
	     if ($function eq "out") {
		   $list .= " " unless ($list eq "");
		   $list .= $_ . ':0,1';
		 } elsif ($function eq "PWM") {
		   $list .= " " unless ($list eq "");
		   $list .= $_ . ':slider,0,1,1023';
		 } elsif ($function eq "cnt") {
		   $list .= " " unless ($list eq "");
		   $list .= $_ . "_counter" ;
		 } 
	   }
	 }
     return 'Unknown argument ' . (defined($port)?$port:"") . (defined($cnt)?"_$cnt":"") . ', choose one of ' . $list;
  }
  return;
}
#############################################
sub Netzer_Attr(@) {
 my (undef, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = '';
 #Log3 $name, 1, "Name: $name Attr: $attr Wert: $val";
 
 if ($attr eq 'poll_interval') {
   if ( defined($val) ) {
     if ( looks_like_number($val) && $val > 0) {
       RemoveInternalTimer($hash);
       InternalTimer(1, 'Netzer_Poll', $hash, 0);
     } else {
       $msg = "$hash->{NAME}: Wrong poll intervall defined. poll_interval must be a number > 0";
     }    
   } else { #wird auch aufgerufen wenn $val leer ist, aber der attribut wert wird auf 1 gesetzt
     RemoveInternalTimer($hash);
   }
 }
 
 if (!$val) {
     delete ($hash->{READINGS}{$attr."_counter"}) if defined($hash->{READINGS}{$attr."_counter"}); 
 } elsif ($val =~ m/^(in|out)$/) {
     delete ($hash->{READINGS}{$attr."_counter"}) if defined($hash->{READINGS}{$attr."_counter"});
 } elsif ($attr =~ m/^(Port_[a-c])$/) {
    $msg = "$hash->{NAME}: $attr wrong function $val. Use in, out or cnt" if $val !~ m/^(cnt)$/;
	delete ($hash->{READINGS}{$attr."_counter"}) if defined($hash->{READINGS}{$attr."_counter"}) && $val !~ m/^(cnt)$/;
 } elsif ($attr =~ m/^(Port_[d|j])$/) {
    $msg = "$hash->{NAME}: $attr wrong function $val. Use in, out or PWM" if $val !~ m/^(PWM)$/;
	delete ($hash->{READINGS}{$attr."_counter"}) if defined($hash->{READINGS}{$attr."_counter"});
 } elsif ($attr =~ m/^(Port_[e|f])$/) {
    $msg = "$hash->{NAME}: $attr wrong function $val. Use in, out or ADC" if $val !~ m/^(ADC)$/;
	delete ($hash->{READINGS}{$attr."_counter"}) if defined($hash->{READINGS}{$attr."_counter"});
 }
 return ($msg) ? $msg : undef; 
 }
#############################################
sub Netzer_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 1024*1024);
  if(!defined($ret) || $ret <= 0) {
     Netzer_conn($hash);
     return;
  } else {
     chomp ($buf);
	 my @msg = split(" ", $buf);
	 readingsBeginUpdate($hash);
	 foreach (@msg) {
	 #abfangen wenn mehrere botschafen
       my ($port, $val) = split("=", $_);
	   $val =~ s/ //g;
	   $val = hex($val);
       my $sval;
       #my ($bufc) = $_ =~ /(\d+)/;
       if ($port eq "x") {
          for (my $i = 0; $i <= 12; $i++) {
		     next if defined($attr{$name}{"Port_".$ports[$i]}) && $attr{$name}{"Port_".$ports[$i]} =~ m/^(PWM|ADC)$/;
             $sval = hex($val) & (1 << $i);
             $sval = $sval == 0 ? "0" :"1";
             readingsBulkUpdate($hash, 'Port_'.$ports[$i] , $sval) if (ReadingsVal($name,'Port_'.$ports[$i],0) ne $sval);
          }
       } elsif ( grep( /^$port$/, @ports ) ) {
          readingsBulkUpdate($hash, 'Port_'.$port , $val);
       } elsif ( grep( ($port =~ s/z// ), @ports ) ) {
          readingsBulkUpdate($hash, 'Port_'.$port.'_counter' , ($val > 32767?"overflow":$val));
       } 
  }	   
     readingsBulkUpdate($hash, 'received', $buf);
     #readingsBulkUpdate($hash, 'zeichenmenge', $ret);
     readingsEndUpdate($hash, 1);
  }
}
#############################################
sub Netzer_Poll($) {#Update of all Readings
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Netzer_Get($hash);
  my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
  if ($pollInterval > 0) {
    InternalTimer(gettimeofday() + ($pollInterval * 60), 'Netzer_Poll', $hash, 0);
    }
  return;
} 
#############################################
sub Netzer_Undef($$) {
  my ($hash, $arg) = @_;
  if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
    RemoveInternalTimer($hash);
  }
  Netzer_disconn($hash,0);
  return undef; 
}
#############################################
sub Netzer_send($$) {
  my ($hash, $buf) = @_;
  my $cnt= length ($buf);
  if (not defined($hash->{CD})) {
    Log3 $hash, 1, "$hash->{NAME}: Verbindung unterbrochen, versuche Verbindungsaufbau";
    Netzer_conn($hash);
  }
  if ($hash->{CD}) {
    syswrite($hash->{CD}, $buf, $cnt) ;
  } else {
    Log3 $hash, 1, "$hash->{NAME}: Daten konnten nicht gesendet werden";
  }
}
#############################################
sub Netzer_conn($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
 
  Netzer_disconn($hash,0);
  my $timeout = $hash->{TIMEOUT} ? $hash->{TIMEOUT} : 3;
  my $conn = IO::Socket::INET->new(PeerAddr=>"$hash->{DeviceName}", Timeout => $timeout);
  if($conn) {  
    $hash->{STATE} = "Connected";
 
    $hash->{FD}    = $conn->fileno();
    $hash->{CD}    = $conn;         # sysread / close won't work on fileno
    $hash->{CONNECTS}++;
    $selectlist{$name} = $hash;
    Log(GetLogLevel($name,3), "$name: connected to $hash->{DeviceName}");
  } else {
    Netzer_disconn($hash, 1);
  }
}
############################################# 
sub Netzer_disconn($$) {
  my ($hash, $connect) = @_;
  my $name   = $hash->{NAME};
  return if( !$hash->{CD} );
  close($hash->{CD}) if($hash->{CD});
  delete($hash->{FD});
  delete($hash->{CD});
  delete($selectlist{$name});
  $hash->{STATE} = "Disconnected";
  if($connect) {
    Log3 $name, 4, "$name: Connect failed.";
  } else {
    Log3 $name, 4, "$name: Disconnected";
  }
}

1;

=pod
=begin html

<a name="Netzer"></a>
<h3>Netzer</h3>
<ul>
  The <a href="http://www.mobacon.de/wiki/doku.php/en/netzer/index">Netzer</a> realizes an Ethernet interface on a PIC-based platform. As a gateway module it enables communication between standard TCP/IP sockets and serial busses like I2C, SPI and UART.
  Also up to 13 GPIO pins can be accessed. This Modul provides access to these GPIO pins on a Netzer running IO_base in Version 1.5. 
  There are two pins usable as ADC channel, two as PMW outputs, three as counter and three can generate an interrupt.
  The GPIO pins are configured a input per default. Before a port can be used as output it must be <a href="http://www.mobacon.de/wiki/doku.php/en/netzer/io">configured</a> via the embedded webpage.
  If one of the input ports is configured to send interrupt events on GPIO Server, on every event all port values will be updated.
  All ports can be read and controlled individually by the function readingsProxy.
  <br><br>

  <a name="NetzerDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Netzer &lt;host:port&gt;</code>
    <br><br>
  </ul>

  <a name="NetzerSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;port[_counter]&gt; &lt;value&gt;</code>
	<br>
	Where &lt;value&gt is a character between <code>a</code> and <code>m</code> <br> according to the port. If Port attr is <code>cnt</code> an aditional value &lt;port_counter&gt; can be set.<br>
    Only ports with corresponding attr Port_[a-m] set to <code>PWM</code> or <code>out</code> can be used.<br>
	If Port attr is:<ul>
	<li>PWM &lt;value&gt can be a number between 0 and 1023</li>
	<li>out &lt;value&gt can be a number between 0 and 1</li>
	<li>cnt &lt;port_counter&gt; &lt;value&gt can be a number between 0 and 32767</li>
    <br></ul>
  </ul>

  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; [&lt;port[_counter]&gt;]</code>
	<br>
	If no &lt;port&gt; is set, all readings will be updated.<br>
	&lt;port&gt is a character between <code>a</code> and <code>m</code><br> according to the port. If Port attr is <code>cnt</code> an aditional reading &lt;port_counter&gt; can be read.
     <br><br>
  </ul>

  <a name="NetzerAttr"></a>
  <b>Attributes</b>
  <ul>
    <a name="poll_interval"></a>
    <li>poll_interval<br>
        Set the polling interval in minutes to query the sensor for new measured values.
		Default: 5, valid values: decimal number</li><br>

    <a name="Port_&lt;port&gt;"></a>
    <li>Port_&lt;port&gt;<br>
	    <ul>
        Configuration for Netzer port.<br>
		&lt;port&gt; is a character between <code>a</code> and <code>m</code>.<br>
		<li><code>in</code>: Port is defined as input. Same behavior as no attribute. Set is not avaliable for this port.<br>
		    Can be used for all ports</li>
		<li><code>out</code>: Port is defined as output. Set is avaliable for this port with &lt;value&gt; between 0 and 1.<br>
		    Can be used for all ports</li>
		<li><code>cnt</code>: Port is defined as input. Set is not avaliable for this port.<br>
		An second reading: Port_&lt;port&gt;_counter is avaiable. 
		It can be updated with <code>get</code> an changed with <code>set</code>.<br>
		Port_&lt;port&gt;_counter &lt;value&gt; = 0-32767 or overflow if outside this range.<br>
		    Can be used for ports a,b,c</li>
		<li><code>ADC</code>: Port is defined as analog input. <code>Get</code> &lt;value&gt; is 0-1023 according the voltage on port. Set is not avaliable for this port.<br>
		    Can be used for ports e,f</li>
		<li><code>PWM</code>: Port is defined as PWM output. <code>Set</code> and <code>get</code> &lt;value&gt; is 0-1023 according the duty cycle on the port.<br>
		    Can be used for ports d,j</li>
		</ul>
        </li><br>


  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="Netzer"></a>
<h3>Netzer</h3>
<ul>
  The <a href="http://www.mobacon.de/wiki/doku.php/de/netzer/index">Netzer</a>  realisiert ein Ethernetinterface auf PIC-Basis. Es agiert als Gateway zwischen TCP/IP und verschiedenen seriellen Busses wie I2C, SPI oder UART. Es k&ouml;nnen bis zu 13 GPIO Pins angesprochen (gelesen oder geschrieben) werden.
  This Modul erm&ouml;glicht den Zugriff auf diese GPIO Pin's auf einem Netzer mit IO_base in Version 1.5. 
  Es gibt zwei als ADC nutzbare Pin's channel, 2 als PMW Ausg&auml;nge, drei als Z&auml;hler sowie drei die einen Interrupt ausl&ouml;sen k&ouml;nnen.
  Die GPIO Pin's sind standardm&auml;ßig als Eing&auml;nge konfiguriert. Bevor ein Pin anderweitig genutzt werden kann, muss er &uuml;ber die eingebaute Website entsprechend <a href="http://www.mobacon.de/wiki/doku.php/de/netzer/io">eingestellt</a> werden.
  Ist einer der Eing&auml;nge als Inerrupteingang eingestellt, werden bei jedem Interrupereignis die Weter s&auml;mtlicher Ports aktualisiert.
  <br><br>

  <a name="NetzerDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Netzer &lt;host:port&gt;</code>
    <br><br>
  </ul>

  <a name="NetzerSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;port[_counter]&gt; &lt;value&gt;</code>
	<br>
	Dabei ist &lt;value&gt ein dem Port entsprechender Buchstabe zwischen <code>a</code> und <code>m</code>. Besitzt der Port das Attribut <code>cnt</code> so kann ein weiterer Wert &lt;port_counter&gt; gesetzt werden.<br>
    Ausschließlich Port's die &uuml;ber Attribut Port_[a-m] auf <code>PWM</code> oder <code>out</code> gesetzt sind k&ouml;nnen benutzt werden.<br>
	Bei Port Attribut:<ul>
	<li>PWM &lt;value&gt kann ein Wert zwischen 0 und 1023 sein</li>
	<li>out &lt;value&gt kann ein Wert zwischen 0 und 1 sein</li>
	<li>cnt &lt;port_counter&gt; &lt;value&gt kann ein Wert zwischen 0 und 32767 sein</li>
    <br></ul>
  </ul>

  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; [&lt;port[_counter]&gt;]</code>
	<br>
	Ohne &lt;port&gt; werde alle Werte aktualisiert.<br>
	Wenn &lt;port&gt ein Buchstabe zwischen <code>a</code> und <code>m</code><br> ist, wird der Portwert aktualisiert und bei Port Attribut <code>cnt</code> kann ein weiterer Z&auml;hlerwert &lt;port_counter&gt; gelesen werden.<br>
     <br>
  </ul>

  <a name="NetzerAttr"></a>
  <b>Attributes</b>
  <ul>
    <a name="poll_interval"></a>
    <li>poll_interval<br>
      Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: Dezimalzahl
		</li><br>

    <a name="Port_&lt;port&gt;"></a>
    <li>Port_&lt;port&gt;<br>
	    <ul>
        Konfiguration des jeweiligen GPIO.<br>
		&lt;port&gt; ist ein Buchstabe zwischen <code>a</code> und <code>m</code>.<br>
		<li><code>in</code>: Port ist Eingang. Kann auch weggelassen werden, da Standard. Set ist f&uuml;r diesen Port nicht verf&uuml;gbar.<br>
		    Nutzbar f&uuml;r alle Port's</li>
		<li><code>out</code>: Port ist Ausgang. Set kann &lt;value&gt; zwischen 0 und 1 haben.<br>
		    Nutzbar f&uuml;r alle Port's</li>
		<li><code>cnt</code>: Port ist Eingang. Set ist f&uuml;r diesen Port nicht verf&uuml;gbar.<br>
		Ein weiteres Reading: Port_&lt;port&gt;_counter ist verf&uuml;gbar. 
		Dieses kann auch mit <code>get</code> gelesen und mit <code>set</code> ver&auml;ndert werden.<br>
		Port_&lt;port&gt;_counter &lt;value&gt; = 0-32767 oder overflow wenn es ausserhalb dieses Bereichs liegt.<br>
		    Nutzbar f&uuml;r Port's a,b,c</li>
		<li><code>ADC</code>: Port ist Analogeingang. <code>get</code> &lt;value&gt; ist 0-1023 entsprechend der Spannung am Port. Set ist f&uuml;r diesen Port nicht verf&uuml;gbar.<br>
		    Nutzbar f&uuml;r Port's e,f</li>
		<li><code>PWM</code>: Port ist PWM-Ausgang. <code>set</code> und <code>get</code> &lt;value&gt; ist 0-1023 entsprechend des Dutycycle am Port.<br>
		    Nutzbar f&uuml;r Port's d,j</li>
		</ul>
        </li><br>


  </ul>
  <br>
</ul>

=end html_DE

=cut