#
#
# 66_ECMD.pm
# written by Dr. Boris Neubert 2011-01-15
# e-mail: omega at online dot de
#
##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


#sub ECMD_Attr(@);
sub ECMD_Clear($);
#sub ECMD_Parse($$$$$);
#sub ECMD_Read($);
sub ECMD_ReadAnswer($$);
#sub ECMD_Ready($);
sub ECMD_Write($$);

sub ECMD_OpenDev($$);
sub ECMD_CloseDev($);
sub ECMD_SimpleWrite(@);
sub ECMD_SimpleRead($);
sub ECMD_Disconnected($);

use vars qw {%attr %defs};

#####################################
sub
ECMD_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{WriteFn} = "ECMD_Write";
  #$hash->{ReadFn} = "ECMD_Read";
  $hash->{Clients}= ":ECMDDevice:";

# Consumer
  $hash->{DefFn}   = "ECMD_Define";
  $hash->{UndefFn} = "ECMD_Undef";
  $hash->{GetFn}   = "ECMD_Get";
  $hash->{SetFn}   = "ECMD_Set";
  $hash->{AttrFn}  = "ECMD_Attr";
  $hash->{AttrList}= "classdefs nonl loglevel:0,1,2,3,4,5";
}

#####################################
sub
ECMD_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  my $name = $a[0];
  my $protocol = $a[2];

  if(@a < 4 || @a > 4 || (($protocol ne "telnet") && ($protocol ne "serial"))) {
    my $msg = "wrong syntax: define <name> ECMD telnet <ipaddress[:port]> or define <name> ECMD serial <devicename[\@baudrate]>";
    Log 2, $msg;
    return $msg;
  }

  ECMD_CloseDev($hash);

  $hash->{Protocol}= $protocol;
  my $devicename= $a[3];
  $hash->{DeviceName} = $devicename;

  my $ret = ECMD_OpenDev($hash, 0);
  return $ret;
}


#####################################
sub
ECMD_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  ECMD_CloseDev($hash);
  return undef;
}

#####################################
sub
ECMD_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);

  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close();
    delete($hash->{TCPDev});

  } elsif($hash->{USBDev}) {
    $hash->{USBDev}->close() ;
    delete($hash->{USBDev});

  }
  ($dev, undef) = split("@", $dev); # Remove the baudrate
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});


}

########################
sub
ECMD_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $protocol = $hash->{Protocol};
  my $name = $hash->{NAME};
  my $devicename = $hash->{DeviceName};


  $hash->{PARTIAL} = "";
  Log 3, "ECMD opening $name (protocol $protocol, device $devicename)"
        if(!$reopen);

  if($hash->{Protocol} eq "telnet") {


    # This part is called every time the timeout (5sec) is expired _OR_
    # somebody is communicating over another TCP connection. As the connect
    # for non-existent devices has a delay of 3 sec, we are sitting all the
    # time in this connect. NEXT_OPEN tries to avoid this problem.
    if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
      return;
    }

    my $conn;
    eval {
	local $SIG{ALRM} = sub { die 'Timed Out'; }; 
	alarm 10;
	$conn = IO::Socket::INET->new(PeerAddr => $devicename, timeout => 5);
    };
    alarm 0;
    $conn= undef if $@;
#    return "Error: timeout." if ( $@ && $@ =~ /Timed Out/ );
#    return "Error: Eval corrupted: $@" if $@;
    if($conn) {
      delete($hash->{NEXT_OPEN})

    } else {
      Log(3, "Can't connect to $devicename: $!") if(!$reopen);
      $readyfnlist{"$name.$devicename"} = $hash;
      $hash->{STATE} = "disconnected";
      $hash->{NEXT_OPEN} = time()+60;
      return "";
    }

    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$devicename"});
    $selectlist{"$name.$devicename"} = $hash;

  } else {

    my $baudrate;
    ($devicename, $baudrate) = split("@", $devicename);

    my $po;
    if ($^O=~/Win/) {
     require Win32::SerialPort;
     $po = new Win32::SerialPort ($devicename);
    } else  {
     require Device::SerialPort;
     $po = new Device::SerialPort ($devicename);
    }

    if(!$po) {
      return undef if($reopen);
      Log(3, "Can't open $devicename: $!");
      $readyfnlist{"$name.$devicename"} = $hash;
      $hash->{STATE} = "disconnected";
      return "";
    }

    $hash->{USBDev} = $po;
    if( $^O =~ /Win/ ) {
      $readyfnlist{"$name.$devicename"} = $hash;
    } else {
      $hash->{FD} = $po->FILENO;
      delete($readyfnlist{"$name.$devicename"});
      $selectlist{"$name.$devicename"} = $hash;
    }

    if($baudrate) {
      $po->reset_error();
      Log 3, "ECMD setting $name baudrate to $baudrate";
      $po->baudrate($baudrate);
      $po->databits(8);
      $po->parity('none');
      $po->stopbits(1);
      $po->handshake('none');

      # This part is for some Linux kernel versions whih has strange default
      # settings.  Device::SerialPort is nice: if the flag is not defined for your
      # OS then it will be ignored.
      $po->stty_icanon(0);
      #$po->stty_parmrk(0); # The debian standard install does not have it
      $po->stty_icrnl(0);
      $po->stty_echoe(0);
      $po->stty_echok(0);
      $po->stty_echoctl(0);

      # Needed for some strange distros
      $po->stty_echo(0);
      $po->stty_icanon(0);
      $po->stty_isig(0);
      $po->stty_opost(0);
      $po->stty_icrnl(0);
    }

    $po->write_settings;


  }

  if($reopen) {
    Log 1, "ECMD $name ($devicename) reappeared";
  } else {
    Log 3, "ECMD device opened";
  }

  $hash->{STATE}= "";       # Allow InitDev to set the state
  my $ret  = ECMD_DoInit($hash);

  if($ret) {
    Log 1,  "$ret";
    ECMD_CloseDev($hash);
    Log 1, "Cannot init $name ($devicename), ignoring it";
  }

  DoTrigger($name, "CONNECTED") if($reopen);
  return $ret;
}

#####################################
sub
ECMD_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $msg = undef;

  ECMD_Clear($hash);
  #ECMD_SimpleWrite($hash, "version");
  #my ($err,$version)= ECMD_ReadAnswer($hash, "version");
  #return "$name: $err" if($err);
  #Log 2, "ECMD version: $version";
  #$hash->{VERSION} = $version;

  $hash->{STATE} = "Initialized" if(!$hash->{STATE});

  return undef;
}

########################
sub
ECMD_SimpleWrite(@)
{
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);

  $msg .= "\n" unless($nonl);
  $hash->{USBDev}->write($msg) if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg)     if($hash->{TCPDev});

  select(undef, undef, undef, 0.001);
}

########################
sub
ECMD_SimpleRead($)
{
  my ($hash) = @_;

  if($hash->{USBDev}) {
    return $hash->{USBDev}->input();
  }

  if($hash->{TCPDev}) {
    my $buf;
    if(!defined(sysread($hash->{TCPDev}, $buf, 1024))) {
      ECMD_Disconnected($hash);
      return undef;
    }

    return $buf;
  }
  return undef;
}

#####################################
# This is a direct read for commands like get
sub
ECMD_ReadAnswer($$)
{
  my ($hash, $arg) = @_;

  #Log 5, "ECMD reading answer for get $arg...";

  return ("No FD", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my ($data, $rin) = ("", '');
  my $buf;
  my $to = 3;                                         # 3 seconds timeout
  $to = $hash->{RA_Timeout} if($hash->{RA_Timeout});  # ...or less
  #Log 5, "Timeout is $to seconds";
  for(;;) {

        return ("Error: device lost when reading answer for get $arg", undef)
                if(!$hash->{FD});

        vec($rin, $hash->{FD}, 1) = 1;
        my $nfound = select($rin, undef, undef, $to);
        if($nfound < 0) {
                next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
                my $err = $!;
                ECMD_Disconnected($hash);
                return("Error reading answer for get $arg: $err", undef);
        }
        return ("Error: timeout reading answer for get $arg", undef)
              if($nfound == 0);

      $buf = ECMD_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

      if($buf) {
        chomp $buf; # remove line break
        Log 5, "ECMD (ReadAnswer): $buf";
        $data .= $buf;
        }
       return (undef, $data)
  }
}

#####################################
sub
ECMD_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

#####################################
sub
ECMD_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  $hash->{RA_Timeout} = 0.1;
  for(;;) {
    my ($err, undef) = ECMD_ReadAnswer($hash, "clear");
    last if($err && $err =~ m/^Error/);
  }
  delete($hash->{RA_Timeout});
}

#####################################
sub
ECMD_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  return if(!defined($hash->{FD}));                 # Already deleted o

  Log 1, "$dev disconnected, waiting to reappear";
  ECMD_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}

#####################################
sub
ECMD_Get($@)
{
  my ($hash, @a) = @_;

  return "get needs at least one parameter" if(@a < 2);

  my $name = $a[0];
  my $cmd= $a[1];
  my $arg = ($a[2] ? $a[2] : "");
  my @args= @a; shift @args; shift @args;
  my ($msg, $err);

  return "No get $cmd for dummies" if(IsDummy($name));

  if($cmd eq "raw") {
        return "get raw needs an argument" if(@a< 3);
        my $nonl= AttrVal($name, "nonl", 0);
        my $ecmd= join " ", @args;
        Log 5, $ecmd;
        ECMD_SimpleWrite($hash, $ecmd, $nonl);
        ($err, $msg) = ECMD_ReadAnswer($hash, "raw");
        return $err if($err);
  }  else {
        return "get $cmd: unknown command ";
  }

  $hash->{READINGS}{$cmd}{VAL} = $msg;
  $hash->{READINGS}{$cmd}{TIME} = TimeNow();

  return "$name $cmd => $msg";
}

#####################################
sub
ECMD_EvalClassDef($$$)
{
        my ($hash, $classname, $filename)=@_;
        my $name= $hash->{NAME};

        # refuse overwriting existing definitions
        if(defined($hash->{fhem}{classDefs}{$classname})) {
                my $err= "$name: class $classname is already defined.";
                Log 1, $err;
                return $err;
        }

        # try and open the class definition file
        if(!open(CLASSDEF, $filename)) {
                my $err= "$name: cannot open file $filename for class $classname.";
                Log 1, $err;
                return $err;
        }
        my @classdef= <CLASSDEF>;
        close(CLASSDEF);

        # add the class definition
        Log 5, "$name: adding new class $classname from file $filename";
        $hash->{fhem}{classDefs}{$classname}{filename}= $filename;

        # format of the class definition:
        #       params <params>                         parameters for device definition
        #       get <cmdname> cmd {<perlexpression>}    defines a get command
        #       get <cmdname> params <params>           parameters for get command
        #       set <cmdname> cmd {<perlexpression>}    defines a set command
        #       set <cmdname> params <params>           parameters for get command
        #       all lines are optional
        #
        # eaxmple class definition 1:
        #       get adc cmd {"adc get %channel"}
        #       get adc params channel
        #
        # eaxmple class definition 1:
        #       params btnup btnstop btndown
        #       set up cmd {"io set ddr 2 ff\nio set port 2 1%btnup\nwait 1000\nio set port 2 00"}
        #       set stop cmd {"io set ddr 2 ff\nio set port 2 1%btnstop\nwait 1000\nio set port 2 00"}
        #       set down cmd {"io set ddr 2 ff\nio set port 2 1%btndown\nwait 1000\nio set port 2 00"}

	my $cont= "";
        foreach my $line (@classdef) {
                # kill trailing newline
                chomp $line;
                # kill comments and blank lines
                $line=~ s/\#.*$//;
                $line=~ s/\s+$//;
		$line= $cont . $line;
		if($line=~ s/\\$//) { $cont= $line; undef $line; }
                next unless($line);
		$cont= "";
                Log 5, "$name: evaluating >$line<";
                # split line into command and definition
                my ($cmd, $def)= split("[ \t]+", $line, 2);
                if($cmd eq "nonl") {
                        Log 5, "$name: no newline";
                        $hash->{fhem}{classDefs}{$classname}{nonl}= 1;
                }
                elsif($cmd eq "params") {
                        Log 5, "$name: parameters are $def";
                        $hash->{fhem}{classDefs}{$classname}{params}= $def;
                } elsif($cmd eq "set" || $cmd eq "get") {
                        my ($cmdname, $spec, $arg)= split("[ \t]+", $def, 3);
                        if($spec eq "params") {
                                if($cmd eq "set") {
                                        Log 5, "$name: set $cmdname has parameters $arg";
                                        $hash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{params}= $arg;
                                } elsif($cmd eq "get") {
                                        Log 5, "$name: get $cmdname has parameters $arg";
                                        $hash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{params}= $arg;
                                }
                        } elsif($spec eq "cmd") {
                                if($arg !~ m/^{.*}$/s) {
                                        Log 1, "$name: command for $cmd $cmdname is not a perl command.";
                                        next;
                                }
                                $arg =~ s/^(\\\n|[ \t])*//;           # Strip space or \\n at the beginning
                                $arg =~ s/[ \t]*$//;
                                if($cmd eq "set") {
                                        Log 5, "$name: set $cmdname command defined as $arg";
                                        $hash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{cmd}= $arg;
                                } elsif($cmd eq "get") {
                                        Log 5, "$name: get $cmdname command defined as $arg";
                                        $hash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{cmd}= $arg;
                                }
                        } elsif($spec eq "postproc") {
                                if($arg !~ m/^{.*}$/s) {
                                        Log 1, "$name: postproc command for $cmd $cmdname is not a perl command.";
                                        next;
                                }
                                $arg =~ s/^(\\\n|[ \t])*//;           # Strip space or \\n at the beginning
                                $arg =~ s/[ \t]*$//;
                                if($cmd eq "set") {
                                        Log 5, "$name: set $cmdname postprocessor defined as $arg";
                                        $hash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{postproc}= $arg;
                                } elsif($cmd eq "get") {
                                        Log 5, "$name: get $cmdname postprocessor defined as $arg";
                                        $hash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{postproc}= $arg;
                                }
                        }
                } else {
                        Log 1, "$name: illegal tag $cmd for class $classname in file $filename.";
                }
        }

        # store class definitions in attribute
        $attr{$name}{classdefs}= "";
        my @a;
        foreach my $c (keys %{$hash->{fhem}{classDefs}}) {
                push @a, "$c=$hash->{fhem}{classDefs}{$c}{filename}";
        }
        $attr{$name}{"classdefs"}= join(":", @a);

        return undef;
}

#####################################
sub
ECMD_Attr($@)
{

  my @a = @_;
  my $hash= $defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "classdefs") {
        my @classdefs= split(/:/,$a[3]);
        delete $hash->{fhem}{classDefs};

        foreach my $classdef (@classdefs) {
                my ($classname,$filename)= split(/=/,$classdef,2);
                ECMD_EvalClassDef($hash, $classname, $filename);
        }
  }

  return undef;
}


#####################################
sub
ECMD_Reopen($)
{
  my ($hash) = @_;
  ECMD_CloseDev($hash);
  ECMD_OpenDev($hash, 1);

  return undef;
}

#####################################
sub
ECMD_Set($@)
{
        my ($hash, @a) = @_;
        my $name = $a[0];

        # usage check
        my $usage= "Usage: set $name classdef <classname> <filename> OR set $name reopen";
        if((@a == 2) && ($a[1] eq "reopen")) {
                return ECMD_Reopen($hash);
        }

        return $usage if(@a != 4);
        return $usage if($a[1] ne "classdef");

        # from the definition
        my $classname= $a[2];
        my $filename= $a[3];

        return ECMD_EvalClassDef($hash, $classname, $filename);
}

#####################################
sub
ECMD_Write($$)
{
  my ($hash,$msg) = @_;
  my $answer;
  my @r;
  my @ecmds= split "\n", $msg;
  my $nonl= AttrVal($hash->{NAME}, "nonl", 0);
  foreach my $ecmd (@ecmds) {
        Log 5, "$hash->{NAME} sending $ecmd";
        ECMD_SimpleWrite($hash, $ecmd, $nonl);
        $answer= ECMD_ReadAnswer($hash, "$ecmd");
        push @r, $answer;
        Log 5, $answer;
  }
  return join("\n", @r);
}

#####################################

1;

=pod
=begin html

<a name="ECMD"></a>
<h3>ECMD</h3>
<ul>
  Any physical device with request/response-like communication capabilities
  over a TCP connection can be defined as ECMD device. A practical example
  of such a device is the AVR microcontroller board AVR-NET-IO from
  <a href="http://www.pollin.de">Pollin</a> with
  <a href="http://www.ethersex.de/index.php/ECMD">ECMD</a>-enabled
  <a href="http://www.ethersex.de">Ethersex</a> firmware.<p>

  A physical ECMD device can host any number of logical ECMD devices. Logical
  devices are defined as <a href="#ECMDDevice">ECMDDevice</a>s in fhem.
  ADC 0 to 3 and I/O port 0 to 3 of the above mentioned board
  are examples of such logical devices. ADC 0 to 3 all belong to the same
  device class ADC (analog/digital converter). I/O port 0 to 3 belong to the device
  class I/O port. By means of extension boards you can make your physical
  device drive as many logical devices as you can imagine, e.g. IR receivers,
  LC displays, RF receivers/transmitters, 1-wire devices, etc.<p>

  Defining one fhem module for any device class would create an unmanageable
  number of modules. Thus, an abstraction layer is used. You create a device class
  on the fly and assign it to a logical ECMD device. The
  <a href="#ECMDClassdef">class definition</a>
  names the parameters of the logical device, e.g. a placeholder for the number
  of the ADC or port, as well as the get and set capabilities. Worked examples
  are to be found in the documentation of the <a href="#ECMDDevice">ECMDDevice</a> device.
  <br><br>

  Note: this module requires the Device::SerialPort or Win32::SerialPort module
  if the module is connected via serial Port or USB.
  <br><br>

  <a name="ECMDdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ECMD telnet &lt;IPAddress:Port&gt;</code><br><br>
    or<br><br>
    <code>define &lt;name&gt; ECMD serial &lt;SerialDevice&gt;[&lt;@BaudRate&gt;]</code>
    <br><br>

    Defines a physical ECMD device. The keywords <code>telnet</code> or
    <code>serial</code> are fixed.<br><br>

    Examples:
    <ul>
      <code>define AVRNETIO ECMD telnet 192.168.0.91:2701</code><br>
      <code>define AVRNETIO ECMD serial /dev/ttyS0</code><br>
      <code>define AVRNETIO ECMD serial /sev/ttyUSB0@38400</code><br>
    </ul>
    <br>
  </ul>

  <a name="ECMDset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; classdef &lt;classname&gt; &lt;filename&gt;</code>
    <br><br>
    Creates a new device class <code>&lt;classname&gt;</code> for logical devices.
    The class definition is in the file <code>&lt;filename&gt;</code>. You must
    create the device class before you create a logical device that adheres to
    that definition.
    <br><br>
    Example:
    <ul>
      <code>define AVRNETIO classdef /etc/fhem/ADC.classdef</code><br>
    </ul>
    <br>
    <code>set &lt;name&gt; reopen</code>
    <br><br>
    Closes and reopens the device. Could be handy if connection is lost and cannot be
    reestablished automatically.
    <br><br>
  </ul>


  <a name="ECMDget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; raw &lt;command&gt;</code>
    <br><br>
    Sends the command <code>&lt;command&gt;</code> to the physical ECMD device
    <code>&lt;name&gt;</code> and reads the response.
  </ul>
  <br><br>

  <a name="ECMDattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>classdefs<br>A colon-separated list of &lt;classname&gt;=&lt;filename&gt;.
    The list is automatically updated if a class definition is added. You can
    directly set the attribute.</li>
    <li>nonl<br>A newline (\n) is automatically appended to every command string sent to the device
    unless this attribute is set. Please note that newlines (\n) in a command string are interpreted
    as separators to split the command string into several commands and are never literally sent.</li>
  </ul>
  <br><br>


  <a name="ECMDClassdef"></a>
  <b>Class definition</b>
  <br><br>
  <ul>

        The class definition for a logical ECMD device class is contained in a text file.
        The text file is made up of single lines. Empty lines and text beginning with #
        (hash) are ignored. Therefore make sure not to use hashes in commands.<br>

        The following commands are recognized in the device class definition:<br><br>
        <ul>
                <li><code>params &lt;parameter1&gt; [&lt;parameter2&gt; [&lt;parameter3&gt; ... ]]</code><br><br>
                Declares the names of the named parameters that must be present in the
                <a href="#ECMDDevicedefine">definition of the logical ECMD device</a>.
                <br><br>
                </li>

                <li><code>set &lt;commandname&gt; cmd { <a href="#perl">&lt;perl special&gt;</a> }</code>
                <br><br>
                Declares a new set command <code>&lt;commandname&gt;</code>.
                <br><br>
                </li>

                <li><code>get &lt;commandname&gt; cmd { <a href="#perl">&lt;perl special&gt;</a> }</code>
                <br><br>
                Declares a new get command <code>&lt;commandname&gt;</code>.
                <br><br>
                </li>

                <li>
		<code>set &lt;commandname&gt; postproc { &lt;perl command&gt }</code><br>
		<code>get &lt;commandname&gt; postproc { &lt;perl command&gt }</code>
                <br><br>
                Declares a postprocessor for the command <code>&lt;commandname&gt;</code>.
                <br><br>
                </li>


                <li>
                <code>set &lt;commandname&gt; params &lt;parameter1&gt; [&lt;parameter2&gt; [&lt;parameter3&gt; ... ]]</code><br>
                <code>get &lt;commandname&gt; params &lt;parameter1&gt; [&lt;parameter2&gt; [&lt;parameter3&gt; ... ]]</code>
                <br><br>
                Declares the names of the named parameters that must be present in the
                set or get command <code>&lt;commandname&gt;</code></a>. Be careful not to use a parameter name that
                is already used in the device definition (see <code>params</code> above).
                <br><br>
                </li>

        </ul>

        The perl specials in the definitions of the set and get commands can
        contain macros. Apart from the rules outlined in the <a
        href="#perl">documentation of perl specials</a> in fhem, the following
        rules apply:<br><br>
        <ul>
          <li>The character @ will be replaced with the device
          name. To use @ in the text itself, use the double mode (@@).</li>

          <li>The macro <code>%NAME</code> will expand to the device name (same
          as <code>@</code>).</li>

          <li>The macro <code>%&lt;parameter&gt;</code> will expand to the
          current value of the named parameter. This can be either a parameter
          from the device definition or a parameter from the set or get
          command.</li>

          <li>The macro substitution occurs before perl evaluates the
          expression. It is a plain text substitution.</li>

          <li>If in doubt what happens, run the commands with loglevel 5 and
          observe the log file.</li>
      </ul><br><br>

      <!--Neither apply the rules outlined in the <a href="#perl">documentation of perl specials</a>
      for the <code>&lt;perl command&gt</code> in the postprocessor definitions nor can it contain macros.
      This is to avoid undesired side effects from e.g. doubling of semicolons.<br><br>-->
      The rules outlined in the <a href="#perl">documentation of perl specials</a>
      for the <code>&lt;perl command&gt</code> in the postprocessor definitions apply.
      <b>Note:</b> Beware of undesired side effects from e.g. doubling of semicolons!

      The <code>perl command</code> acts on <code>$_</code>. The result of the perl command is the
      final result of the get or set command.
    </ul>
</ul>

=end html
=cut
