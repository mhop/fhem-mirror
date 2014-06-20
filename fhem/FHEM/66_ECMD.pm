# $Id$

##############################################################################
#
#     66_ECMD.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

#
# Potential future extensions: add support for PARTIALly received datagrams
# http://forum.fhem.de/index.php/topic,24280.msg174330.html#msg174330


use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use DevIo;


sub ECMD_Attr($@);
sub ECMD_Clear($);
#sub ECMD_Parse($$$$$);
sub ECMD_Read($);
sub ECMD_ReadAnswer($$);
#sub ECMD_Ready($);
sub ECMD_Write($$$);


use vars qw {%attr %defs};

#####################################
sub
ECMD_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{WriteFn} = "ECMD_Write";
  $hash->{ReadFn}  = "ECMD_Read";
  $hash->{Clients} = ":ECMDDevice:";

# Consumer
  $hash->{DefFn}   = "ECMD_Define";
  $hash->{UndefFn} = "ECMD_Undef";
  $hash->{GetFn}   = "ECMD_Get";
  $hash->{SetFn}   = "ECMD_Set";
  $hash->{AttrFn}  = "ECMD_Attr";
  $hash->{AttrList}= "classdefs logTraffic:0,1,2,3,4,5 timeout";
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
  
  DevIo_CloseDev($hash);

  $hash->{Protocol}= $protocol;
  my $devicename= $a[3];
  $hash->{DeviceName} = $devicename;

  my $ret = DevIo_OpenDev($hash, 0, undef);
  return $ret;
}


#####################################
sub
ECMD_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  # deleting port for clients
  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash) {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $hash, $lev, "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
ECMD_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $msg = undef;

  ECMD_Clear($hash);
 
  $hash->{STATE} = "Initialized" if(!$hash->{STATE});

  return undef;
}

#####################################
sub
dq($) 
{
  my ($s)= @_;
  $s= "<nothing>" unless(defined($s));
  return "\"" . escapeLogLine($s) . "\"";
}

sub
ECMD_Log($$$)
{
  my ($hash, $loglevel, $logmsg)= @_;
  my $name= $hash->{NAME};
  $loglevel= AttrVal($name, "logTraffic", undef) unless(defined($loglevel)); 
  return unless(defined($loglevel)); 
  Log3 $hash, $loglevel , "$name: $logmsg";
}

#####################################
sub
ECMD_SimpleRead($) 
{
  my $hash = shift;
  my $answer= DevIo_SimpleRead($hash);
  ECMD_Log $hash, undef, "read " . dq($answer);
  return $answer;
}

sub
ECMD_SimpleWrite($$) 
{
  my ($hash, $msg) = @_;
  ECMD_Log $hash, undef, "write " . dq($msg);
  DevIo_SimpleWrite($hash, $msg, 0);
}

sub
ECMD_SimpleExpect($$$)
{
  my ($hash, $msg, $expect) = @_;
 
  ECMD_Log $hash, undef, "write " . dq($msg) . ", expect $expect";
  my $answer= DevIo_Expect($hash, $msg, AttrVal($hash->{NAME}, "timeout", 3.0));
  
  if(defined($answer)) {
    ECMD_Log $hash, undef, "read " . dq($answer);
    if($answer !~ m/^$expect$/) {
    ECMD_Log $hash, 1, "unexpected answer " . dq($answer) . " received (wrote " . 
         dq($msg) . ", expected $expect)";
    }
  } else {
    ECMD_Log $hash, 1, "no answer received (wrote " . 
         dq($msg) . ", expected $expect)";
  }
  
  return $answer;
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
  DevIo_TimeoutRead($hash, 0.1);
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
  my ($answer, $err);

  return "No get $cmd for dummies" if(IsDummy($name));

  if($cmd eq "raw") {
        return "get raw needs an argument" if(@a< 3);
        #my $nonl= AttrVal($name, "nonl", 0);
        my $ecmd= join " ", @args;
        #ecmd .= "\n" unless($nonl);
        $ecmd= AnalyzePerlCommand(undef, $ecmd);
        $answer= ECMD_SimpleExpect($hash, $ecmd, ".*");
  }  else {
        return "get $cmd: unknown command ";
  }

  $hash->{READINGS}{$cmd}{VAL} = $answer;
  $hash->{READINGS}{$cmd}{TIME} = TimeNow();

  return "$name $cmd => $answer";
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
                Log3 $hash, 1, $err;
                return $err;
        }

        # try and open the class definition file
        if(!open(CLASSDEF, $filename)) {
                my $err= "$name: cannot open file $filename for class $classname.";
                Log3 $hash, 1, $err;
                return $err;
        }
        my @classdef= <CLASSDEF>;
        close(CLASSDEF);

        # add the class definition
        Log3 $hash, 5, "$name: adding new class $classname from file $filename";
        $hash->{fhem}{classDefs}{$classname}{filename}= $filename;

        # format of the class definition:
        #       params <params>                         parameters for device definition
        #       get <cmdname> cmd {<perlexpression>}    defines a get command
        #       get <cmdname> params <params>           parameters for get command
        #       get <cmdname> expect regex              expected regex for get command
        #       get <cmdname> postproc { <perl command> } postprocessor for get command
        #       set <cmdname> cmd {<perlexpression>}    defines a set command
        #       set <cmdname> expect regex              expected regex for set command
        #       set <cmdname> params <params>           parameters for get command
        #       set <cmdname> postproc { <perl command> } postprocessor for set command
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
                Log3 $hash, 5, "$name: evaluating >$line<";
                # split line into command and definition
                my ($cmd, $def)= split("[ \t]+", $line, 2);
                #if($cmd eq "nonl") {
                #        Log3 $hash, 5, "$name: no newline";
                #        $hash->{fhem}{classDefs}{$classname}{nonl}= 1;
                #}
                
                #
                # params
                #
                if($cmd eq "params") {
                        Log3 $hash, 5, "$name: parameters are $def";
                        $hash->{fhem}{classDefs}{$classname}{params}= $def;
                #
                # reading
                #
                } elsif($cmd eq "reading") {
                        my ($readingname, $spec, $arg)= split("[ \t]+", $def, 3);
                        #
                        # match
                        #
                        if($spec eq "match") {
                                if($arg !~ m/^"(.*)"$/s) {
                                        Log3 $hash, 1, "$name: match for reading $readingname is not enclosed in double quotes.";
                                        next;
                                }
                                $arg = $1;
                                Log3 $hash, 5, "$name: reading $readingname will match $arg";
                                 $hash->{fhem}{classDefs}{$classname}{readings}{$readingname}{match}= $arg;
                        # 
                        # postproc
                        #
                        } elsif($spec eq "postproc") {
                                if($arg !~ m/^{.*}$/s) {
                                        Log3 $hash, 1, "$name: postproc command for reading $readingname is not a perl command.";
                                        next;
                                }
                                $arg =~ s/^(\\\n|[ \t])*//;           # Strip space or \\n at the beginning
                                $arg =~ s/[ \t]*$//;
                                Log3 $hash, 5, "$name: reading $readingname postprocessor defined as $arg";
                                $hash->{fhem}{classDefs}{$classname}{readings}{$readingname}{postproc}= $arg;
                        #
                        # anything else
                        #
                        } else {
                                Log3 $hash, 1, 
                                         "$name: illegal spec $spec for reading $readingname for class $classname in file $filename.";
                        }
                #
                # set, get
                #
                } elsif($cmd eq "set" || $cmd eq "get") {
                        my ($cmdname, $spec, $arg)= split("[ \t]+", $def, 3);
                        if($spec eq "params") {
                                if($cmd eq "set") {
                                        Log3 $hash, 5, "$name: set $cmdname has parameters $arg";
                                        $hash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{params}= $arg;
                                } elsif($cmd eq "get") {
                                        Log3 $hash, 5, "$name: get $cmdname has parameters $arg";
                                        $hash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{params}= $arg;
                                }
                        } elsif($spec eq "cmd") {
                                if($arg !~ m/^{.*}$/s) {
                                        Log3 $hash, 1, "$name: command for $cmd $cmdname is not a perl command.";
                                        next;
                                }
                                $arg =~ s/^(\\\n|[ \t])*//;           # Strip space or \\n at the beginning
                                $arg =~ s/[ \t]*$//;
                                if($cmd eq "set") {
                                        Log3 $hash, 5, "$name: set $cmdname command defined as $arg";
                                        $hash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{cmd}= $arg;
                                } elsif($cmd eq "get") {
                                        Log3 $hash, 5, "$name: get $cmdname command defined as $arg";
                                        $hash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{cmd}= $arg;
                                }
                        } elsif($spec eq "postproc") {
                                if($arg !~ m/^{.*}$/s) {
                                        Log3 $hash, 1, "$name: postproc command for $cmd $cmdname is not a perl command.";
                                        next;
                                }
                                $arg =~ s/^(\\\n|[ \t])*//;           # Strip space or \\n at the beginning
                                $arg =~ s/[ \t]*$//;
                                if($cmd eq "set") {
                                        Log3 $hash, 5, "$name: set $cmdname postprocessor defined as $arg";
                                        $hash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{postproc}= $arg;
                                } elsif($cmd eq "get") {
                                        Log3 $hash, 5, "$name: get $cmdname postprocessor defined as $arg";
                                        $hash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{postproc}= $arg;
                                }
                        } elsif($spec eq "expect") {
                                if($arg !~ m/^"(.*)"$/s) {
                                        Log3 $hash, 1, "$name: expect for $cmd $cmdname is not enclosed in double quotes.";
                                        next;
                                }
                                $arg = $1;
                                if($cmd eq "set") {
                                        Log3 $hash, 5, "$name: set $cmdname expects $arg";
                                        $hash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{expect}= $arg;
                                } elsif($cmd eq "get") {
                                        Log3 $hash, 5, "$name: get $cmdname expects $arg";
                                        $hash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{expect}= $arg;
                                }
                        } else {
                                Log3 $hash, 1, 
                                         "$name: illegal spec $spec for $cmd $cmdname for class $classname in file $filename.";
                        }
                } else {
                        Log3 $hash, 1, "$name: illegal tag $cmd for class $classname in file $filename.";
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
  DevIo_CloseDev($hash);
  DevIo_OpenDev($hash, 1, undef);

  return undef;
}

#####################################
sub
ECMD_Set($@)
{
        my ($hash, @a) = @_;
        my $name = $a[0];

        # usage check
        #my $usage= "Usage: set $name classdef <classname> <filename> OR set $name reopen";
        my $usage= "Unknown argument $a[1], choose one of reopen classdef";
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
# called from the global loop, when the select for hash->{FD} reports data
sub ECMD_Read($) 
{
  my ($hash) = @_;
  my $buf = ECMD_SimpleRead($hash);
  return if($buf eq "");
  
  ECMD_Log $hash, 5,  "Spontaneously received " . dq($buf);
  Dispatch($hash, $buf, undef);  # dispatch result to ECMDDevices
}

#####################################
sub
ECMD_Write($$$)
{
  my ($hash,$msg,$expect) = @_;
  my $name= $hash->{NAME};
  my $answer;
  my $ret= "";
  my $requestSeparator= "\000"; # AttrVal($hash, "requestSeparator", "\000");
  my $responseSeparator= ""; # AttrVal($hash, "responseSeparator", "");
  my @ecmds= split $requestSeparator, $msg;
  #my @ecmds= split "\n", $msg;
  #my $nonl= AttrVal($name, "nonl", 0);
  ECMD_Log $hash, 5, "command split into " . ($#ecmds+1) . " parts." if($#ecmds>0);
  foreach my $ecmd (@ecmds) {
        ECMD_Log $hash, 5, "sending command " . dq($ecmd);
        my $msg .= $ecmd;
        #$msg.= "\n" unless($nonl);
        if(defined($expect)) {
          $answer= ECMD_SimpleExpect($hash, $msg, $expect);
          $answer= "" unless(defined($answer));
          ECMD_Log $hash, 5, "received answer " . dq($answer);
          $answer.= $responseSeparator if($#ecmds>0);
          $ret.= $answer;
        } else {
          ECMD_SimpleWrite($hash, $msg);
        }
  }
  return $ret;
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
  <a href="http://www.ethersex.de">Ethersex</a> firmware. The original
  NetServer firmware from Pollin works as well.<p>

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
    <code>&lt;name&gt;</code> and reads the response. In the likely case that 
    the command needs to be terminated by a newline character, you have to
    resort to a <a href="#perl">&lt;perl special&gt;</a>.
    <br><br>
    Example: 
    <ul>
      <code>get AVRNETIO raw { "ip\n" }</code><br>
    </ul>
  </ul>
  <br><br>

  <a name="ECMDattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>classdefs<br>A colon-separated list of &lt;classname&gt;=&lt;filename&gt;.
    The list is automatically updated if a class definition is added. You can
    directly set the attribute.</li>
    <li>logTraffic &lt;loglevel&gt;<br>Enables logging of sent and received datagrams with the given loglevel. Control characters in the logged datagrams are escaped, i.e. a double backslash is shown for a single backslash, \n is shown for a line feed character, etc.</li>
    <li>timeout &lt;seconds&gt;<br>Time in seconds to wait for a reply from the physical ECMD device before FHEM assumes that something has gone wrong. The default is 3 seconds if this attribute is not set.</li> 
    <!--
    <li>nonl<br>A newline (\n) is automatically appended to every command string sent to the device
    unless this attribute is set. Please note that newlines (\n) in a command string are interpreted
    as separators to split the command string into several commands and are never literally sent.</li>
    -->
    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br>
  
  <a name="ECMDDatagram"></a>
  <b>Datagram monitoring and matching</b>
  <br><br>
  
  Data to and from the physical device is processed as is. In particular, if you need to send a line feed you have to include send a \n control character. On the other hand, control characters like line feeds are not stripped from the data received. This needs to be considered when defining a <a href="#ECMDClassdef">class definition</a>.<p>
  
  For debugging purposes, especially when designing a <a href="#ECMDClassdef">class definition</a>, it is advisable to turn traffic logging on. Use <code>attr myECMD logTraffic 3</code> to log all data to and from the physical device at level 3. A typical response might look like <code>21.2\n</code>, i.e. a floating point number followed by a newline.<p>
  
  Data received from the physical device is processed as it comes in chunks. If for some reason a datagram from the device is split in transit, pattern matching and processing will most likely fail.
  <br><br>
  
  <a name="ECMDConnection"></a>
  <b>Connection error handling</b>
  <br><br>
  
  This modules handles unexpected disconnects of devices as follows (on Windows only for TCP connections):<p>
  
  Disconnects are detected if and only if data from the device in reply to data sent to the device cannot be received with at most two attempts. FHEM waits at most 3 seconds (or the time specified in the <code>timeout</code> attribute, see <a href="#ECMDattr">Attributes</a>). After the first failed attempt, the connection to the device is closed and reopened again. The state of the device
  is <code>failed</code>. Then the data is sent again to the device. If still no reply is received, the state of the device is <code>disconnected</code>, otherwise <code>opened</code>. You will have to fix the problem and then use <code>set myECMD reopen</code> to reconnect to the device.<p>
  
  Please design your class definitions in such a way that the double sending of data does not bite you in any case.
  <br><br>

  <a name="ECMDClassdef"></a>
  <b>Class definition</b>
  <br><br>
  
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

            <li><code>set &lt;commandname&gt; cmd { <a href="#perl">&lt;perl special&gt;</a> }</code><br>
            <code>get &lt;commandname&gt; cmd { <a href="#perl">&lt;perl special&gt;</a> }</code>
            <br><br>
            Declares a new set or get command <code>&lt;commandname&gt;</code>. If the user invokes the set or get command <code>&lt;commandname&gt;</code>, the string that results from the execution of the &lt;perl special&gt; is sent to the physical device.<p>
            A \000 (octal representation of control char with code zero) can be used to split the command into chunks. This is required for sending multiple <a href="http://www.ethersex.de/index.php/ECMD">Ethersex commands</a> for one command in the class definition. The result string for the command is the
            concatenation of all responses received from the physical device. Use \x00 for literal zero bytes.
            <br><br>
            </li>

            <li>
            <code>set &lt;commandname&gt; expect "&lt;regex&gt;"</code><br>
            <code>get &lt;commandname&gt; expect "&lt;regex&gt;"</code>
            <br><br>
            Declares what FHEM expects to receive after the execution of the get or set command <code>&lt;commandname&gt;</code>. <code>&lt;regex&gt;</code> is a Perl regular expression. The double quotes around the regular expression are mandatory and they are not part of the regular expression itself. Particularly, broken connections can only be detected if something is expected (see <a href="#ECMDConnection">Connection error handling</a>).
            <br><br>
            </li>

            <li>
            <code>set &lt;commandname&gt; postproc { <a href="#perl">&lt;perl special&gt;</a> }</code><br>
            <code>get &lt;commandname&gt; postproc { <a href="#perl">&lt;perl special&gt;</a> }</code>
            <br><br>
            Declares a postprocessor for the command <code>&lt;commandname&gt;</code>. The data received from the physical device in reply to the get or set command <code>&lt;commandname&gt;</code> is processed by the Perl code <code>&lt;perl command&gt;</code>. The perl code operates on <code>$_</code>. Make sure to return the result in <code>$_</code> as well. The result of the perl command is shown as the result of the get or set command.
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

            <li>
            <code>reading &lt;reading&gt; match "&lt;regex&gt;"</code>
            <br><br>
            Declares a new reading named <code>&lt;reading&gt;</code>. A spontaneous data transmission from the physical device that matches the Perl regular expression <code>&lt;regex&gt;</code> is evaluated to become the value of the named reading. All ECMDDevice devices belonging to the ECMD device with readings with matching regular expressions will receive an update of the said readings.
            <br><br>
            </li>
            
            <li>
            <code>reading &lt;reading&gt; postproc { <a href="#perl">&lt;perl special&gt;</a> }</code>
            <br><br>
            Declares a postprocessor for the reading <code>&lt;reading&gt;</code>. The data received for the named reading is processed by the Perl code <code>&lt;perl command&gt;</code>. This works analogously to the <code>postproc</code> spec for set and get commands.
            <br><br>
            </li>

            

            
    </ul>

    The perl specials in the definitions above can
    contain macros:<br><br>
    <ul>
      <li>The macro <code>%NAME</code> will expand to the device name.</li>
      <li>The macro <code>%TYPE</code> will expand to the device type.</li>
      <li>The macro <code>%&lt;parameter&gt;</code> will expand to the
      current value of the named parameter. This can be either a parameter
      from the device definition or a parameter from the set or get
      command.</li>
      <li>The macro substitution occurs before perl evaluates the
      expression. It is a plain text substitution. Be careful not to use parameters with overlapping names like
      <code>%pin</code> and <code>%pin1</code>.</li>
      <li>If in doubt what happens, run the commands with loglevel 5 and
      inspect the log file.</li>
  </ul><br><br>

  The rules outlined in the <a href="#perl">documentation of perl specials</a>
  for the <code>&lt;perl command&gt</code> in the postprocessor definitions apply.
  <b>Note:</b> Beware of undesired side effects from e.g. doubling of semicolons!
</ul>

=end html
=cut
