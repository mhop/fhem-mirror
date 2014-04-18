# $Id$
##############################################################################
#
#     67_ECMDDevice.pm
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

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub ECMDDevice_Get($@);
sub ECMDDevice_Set($@);
sub ECMDDevice_Attr($@);
sub ECMDDevice_Define($$);

###################################
sub
ECMDDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = ".+"; 
  
  $hash->{GetFn}     = "ECMDDevice_Get";
  $hash->{SetFn}     = "ECMDDevice_Set";
  $hash->{DefFn}     = "ECMDDevice_Define";
  $hash->{ParseFn}   = "ECMDDevice_Parse";

  $hash->{AttrFn}    = "ECMDDevice_Attr";
  $hash->{AttrList}  = "IODev class ".
                        $readingFnAttributes;
}

###################################
sub
ECMDDevice_AnalyzeCommand($$)
{
        my ($hash, $ecmd)= @_;
        Log3 $hash, 5, "ECMDDevice: Analyze command >$ecmd<";
        return AnalyzePerlCommand(undef, $ecmd);
}

#############################
sub
ECMDDevice_GetDeviceParams($)
{
        my ($hash)= @_;
        my $classname= $hash->{fhem}{classname};
        my $IOhash= $hash->{IODev};
        if(defined($IOhash->{fhem}{classDefs}{$classname}{params})) {
                my $params= $IOhash->{fhem}{classDefs}{$classname}{params};
                return split("[ \t]+", $params);
        }
        return;
}

#############################
sub
ECMDDevice_DeviceParams2Specials($)
{
        my ($hash)= @_;
        my %specials= (
                "%NAME" => $hash->{NAME},
                "%TYPE" => $hash->{TYPE}
        );
        my @deviceparams= ECMDDevice_GetDeviceParams($hash);
        foreach my $param (@deviceparams) {
                $specials{"%".$param}= $hash->{fhem}{params}{$param};
        }
        return %specials;
}

sub
ECMDDevice_ReplaceSpecials($%)
{
        my ($s, %specials)= @_;

        # perform macro substitution
        foreach my $special (keys %specials) {
          $s =~ s/$special/$specials{$special}/g;
        }
        return $s;
}

###################################
sub
ECMDDevice_Changed($$$)
{
        my ($hash, $cmd, $value)= @_;

        if(defined($value) && $value ne "") {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, $cmd, $value);

          my $state= $cmd;
          $state.= " $value";
          readingsBulkUpdate($hash, "state", $state);

          readingsEndUpdate($hash, 1);

          my $name= $hash->{NAME};
          Log3 $hash, 4 , "ECMDDevice $name $state";

          return $state;
        }

}

###################################
sub
ECMDDevice_PostProc($$$)
{
  my ($hash, $postproc, $value)= @_;

  if($postproc) {
        my %specials= ECMDDevice_DeviceParams2Specials($hash);
        my $command= ECMDDevice_ReplaceSpecials($postproc, %specials);
	$_= $value;
	Log3 $hash, 5, "Postprocessing \"" . escapeLogLine($value) . "\" with perl command $command.";
	$value= AnalyzePerlCommand(undef, $command);
	Log3 $hash, 5, "Postprocessed value is \"" . escapeLogLine($value) . "\".";
  }
  return $value;
}


###################################

sub
ECMDDevice_Get($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        my $type= $hash->{TYPE};
        return "get $name needs at least one argument" if(int(@a) < 2);
        my $cmdname= $a[1];

        my $IOhash= $hash->{IODev};
        my $classname= $hash->{fhem}{classname};
        if(!defined($IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname})) {
                my $gets= $IOhash->{fhem}{classDefs}{$classname}{gets};
                return "$name error: unknown argument $cmdname, choose one of " .
                  (join " ", sort keys %$gets);
        }

        my $ecmd= $IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{cmd};
        my $expect= $IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{expect};
        my $params= $IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{params};
        my $postproc= $IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{postproc};

        my %specials= ECMDDevice_DeviceParams2Specials($hash);
        # add specials for command
        if($params) {
                shift @a; shift @a;
                my @params= split('[\s]+', $params);
                return "Wrong number of parameters." if($#a != $#params);

                my $i= 0;
                foreach my $param (@params) {
                        Log3 $hash, 5, "Parameter %". $param . " is " . $a[$i];
                        $specials{"%".$param}= $a[$i++];
                }
        }
        $ecmd= ECMDDevice_ReplaceSpecials($ecmd, %specials);

        my $r = ECMDDevice_AnalyzeCommand($hash, $ecmd);

        my $v= IOWrite($hash, $r, $expect);

	$v= ECMDDevice_PostProc($hash, $postproc, $v);

        return ECMDDevice_Changed($hash, $cmdname, $v);
}


#############################
sub
ECMDDevice_Set($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        my $type= $hash->{TYPE};
        return "set $name needs at least one argument" if(int(@a) < 2);
        my $cmdname= $a[1];

        my $IOhash= $hash->{IODev};
        my $classname= $hash->{fhem}{classname};
        if(!defined($IOhash->{fhem}{classDefs}{$classname}{sets}{$cmdname})) {
		my $sets= $IOhash->{fhem}{classDefs}{$classname}{sets};
                return "Unknown argument $cmdname, choose one of " . join(' ', sort keys %$sets);
        }

        my $ecmd= $IOhash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{cmd};
        my $expect= $IOhash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{expect};
        my $params= $IOhash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{params};
        my $postproc= $IOhash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{postproc};

        my %specials= ECMDDevice_DeviceParams2Specials($hash);
        # add specials for command
        if($params) {
                shift @a; shift @a;
                my @params= split('[\s]+', $params);
                return "Wrong number of parameters." if($#a != $#params);

                my $i= 0;
                foreach my $param (@params) {
                        $specials{"%".$param}= $a[$i++];
                }
        }
        $ecmd= ECMDDevice_ReplaceSpecials($ecmd, %specials);

        my $r = ECMDDevice_AnalyzeCommand($hash, $ecmd);

        my $v= IOWrite($hash, $r, $expect);

	$v= ECMDDevice_PostProc($hash, $postproc, $v);

        ECMDDevice_Changed($hash, $cmdname, $v); # was: return ECMDDevice_Changed($hash, $cmdname, $v);
        return undef;

}

#############################
sub
ECMDDevice_Parse($$)
{
  # we never come here if $msg does not match $hash->{MATCH} in the first place
  
  # NOTE: we will update all matching readings for all devices, not just the first!
  
  my ($IOhash, $msg) = @_;        # IOhash points to the ECMD, not to the ECMDDevice

  my @matches;
  my $name= $IOhash->{NAME};
  
  #Debug "Trying to find a match for \"" . escapeLogLine($msg) ."\"";
  # walk over all clients
  foreach my $d (keys %defs) {
    my $hash= $defs{$d};
    if($hash->{TYPE} eq "ECMDDevice" && $hash->{IODev} eq $IOhash) {
      my $classname= $hash->{fhem}{classname};
      my $classDef= $IOhash->{fhem}{classDefs}{$classname};
      #Debug "  Checking device $d with class $classname...";
      next unless(defined($classDef->{readings}));
      #Debug "   Trying to find a match in class $classname...";
      my %specials= ECMDDevice_DeviceParams2Specials($hash);
      # we run over all readings in that classdef
      foreach my $r (keys %{$classDef->{readings}}) {
        my $regex= ECMDDevice_ReplaceSpecials($classDef->{readings}{$r}{match}, %specials);
        #Debug "      Trying to match reading $r with regular expressing \"$regex\".";
        if($msg =~ m/$regex/) {
          # we found a match
          Log3 $IOhash, 5, "$name: match regex $regex for reading $r of device $d with class $classname";
          push @matches, $d;
          my $postproc= $classDef->{readings}{$r}{postproc};
          my $value= ECMDDevice_PostProc($hash, $postproc, $msg);
          Log3 $hash, 5, "postprocessed value is $value";
          ECMDDevice_Changed($hash, $r, $value);
        }
      }
    }  
  }
  
  return @matches if(@matches);
  return "UNDEFINED ECMDDevice message $msg";  
  
}

#####################################
sub
ECMDDevice_AssignClass($$@)
{
    my ($hash,$classname,@a)= @_;
    
    my $name= $hash->{NAME};
    
    my $IOhash= $hash->{IODev};
    if(!defined($IOhash)) {
            my $err= "ECMDDevice $name error: no I/O device.";
            Log3 $hash, 1, $err;
            return $err;
    }
           
    
    if(!defined($IOhash->{fhem}{classDefs}{$classname}{filename})) {
            my $err= "ECMDDevice $name error: unknown class $classname (I/O device is " 
                      . $IOhash->{NAME} . ").";
            Log3 $hash, 1, $err;
            return $err;
    }

    $hash->{fhem}{classname}= $classname;
    
    my @prms= ECMDDevice_GetDeviceParams($hash);
    my $numparams= 0;
    $numparams= $#prms+1 if(defined($prms[0]));
    #Log 5, "ECMDDevice $classname requires $numparams parameter(s): ". join(" ", @prms);

    # verify identical number of parameters
    if($numparams != $#a+1) {
            my $err= "$name error: wrong number of parameters";
            Log3 $hash, 1, $err;
            return $err;
    }

    # set parameters
    for(my $i= 0; $i< $numparams; $i++) {
            $hash->{fhem}{params}{$prms[$i]}= $a[$i];
    }
    
    return undef; # OK
}

#####################################
sub
ECMDDevice_Attr($@)
{

  my @a = @_;
  my $hash= $defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "class") {
    my ($classname,@prms)= split " ", $a[3];
    return ECMDDevice_AssignClass($hash, $classname, @prms);
  } else {
    return undef;
  }
}

#############################
sub
ECMDDevice_Define($$)
{
        my ($hash, $def) = @_;
        my @a = split("[ \t]+", $def);

        return "Usage: define <name> ECMDDevice [<classname> [...]]"    if(int(@a) < 2);
        my $name= $a[0];
        
        AssignIoPort($hash);

        if(int(@a)> 2) {
          my $classname= $a[2];
          shift @a; shift @a; shift @a;
          return ECMDDevice_AssignClass($hash, $classname, @a);
        } else {
          return undef;
        }
}

1;

=pod
=begin html

<a name="ECMDDevice"></a>
<h3>ECMDDevice</h3>
<ul>
  <br>
  <a name="ECMDDevicedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ECMDDevice [&lt;classname&gt; [&lt;parameter1&gt; [&lt;parameter2&gt; [&lt;parameter3&gt; ... ]]]]</code>
    <br><br>

    Defines a logical ECMD device. The number of given parameters must match those given in
    the <a href="#ECMDClassdef">class definition</a> of the device class <code>&lt;classname&gt;</code>.<p>
    
    Normally, the logical ECMDDevice is attached to the latest previously defined physical ECMD device
    for I/O. Use the <code>IODev</code> attribute of the logical ECMDDevice to attach to any
    physical ECMD device, e.g. <code>attr myRelais2 IODev myAVRNETIO</code>. In such a case the correct
    reference to the class cannot be made at the time of definition of the device. Thus, you need to
    omit the &lt;classname&gt; and &lt;parameter&gt; references in the definition of the device and use the
    <code>class</code> <a href="#ECMDDeviceattr">attribute</a> instead.
    <br><br>

    Examples:
    <ul>
      <code>define myADC ECMDDevice ADC</code><br>
      <code>define myRelais1 ECMDDevice relais 8</code><br>
      <code>define myRelais2 ECMDDevice</code><br>
      <code>attr myRelais2 IODev myAVRNETIO</code><br>
      <code>attr myRelais2 class relais 8</code>
    </ul>
    <br>
  </ul>

  <a name="ECMDDeviceset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;commandname&gt; [&lt;parameter1&gt; [&lt;parameter2&gt; [&lt;parameter3&gt; ... ]]]</code>
    <br><br>
    The number of given parameters must match those given for the set command <code>&lt;commandname&gt;</code> definition in
    the <a href="#ECMDClassdef">class definition</a>.<br><br>
    If <code>set &lt;commandname&gt;</code> is invoked the perl special in curly brackets from the command definition
    is evaluated and the result is sent to the physical ECMD device.
    <br><br>
    Example:
    <ul>
      <code>set myRelais1 on</code><br>
      <code>set myDisplay text This\x20text\x20has\x20blanks!</code><br>
    </ul>
    <br>
  </ul>


  <a name="ECMDDeviceget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;commandname&gt; [&lt;parameter1&gt; [&lt;parameter2&gt; [&lt;parameter3&gt; ... ]]]</code>
    <br><br>
    The number of given parameters must match those given for the get command <code>&lt;commandname&gt;</code> definition in
    the <a href="#ECMDClassdef">class definition</a>.<br><br>
    If <code>get &lt;commandname&gt;</code> is invoked the perl special in curly brackets from the command definition
    is evaluated and the result is sent to the physical ECMD device. The response from the physical ECMD device is returned
    and the state of the logical ECMD device is updated accordingly.
    <br><br>
    Example:
    <ul>
      <code>get myADC value 3</code><br>
    </ul>
    <br>
  </ul>


  <a name="ECMDDeviceattr"></a>
  <b>Attributes</b>
  <ul>
    <li>class<br>
    If you omit the &lt;classname&gt; and &lt;parameter&gt; references in the 
    <a href="#ECMDDevicedefine">definition</a> of the device, you have to add them
    separately as an attribute. Example: <code>attr myRelais2 class relais 8</code>.</li>
    <li><a href="#verbose">verbose</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>


  <b>Example 1</b>
  <br><br>
  <ul>
        The following example shows how to access the ADC of the AVR-NET-IO board from
        <a href="http://www.pollin.de">Pollin</a> with
        <a href="http://www.ethersex.de/index.php/ECMD">ECMD</a>-enabled
        <a href="http://www.ethersex.de">Ethersex</a> firmware.<br><br>

        The class definition file <code>/etc/fhem/ADC.classdef</code> looks as follows:<br><br>
        <code>
                get value cmd {"adc get %channel\n"}  <br>
                get value params channel<br>
                get value expect "\d+\n"<br>
                get value postproc { s/^(\d+)\n$/$1/;; $_ }<br>
        </code>
        <br>
        In the fhem configuration file or on the fhem command line we do the following:<br><br>
        <code>
                define AVRNETIO ECMD telnet 192.168.0.91:2701        # define the physical device<br>
                set AVRNETIO classdef ADC /etc/fhem/ADC.classdef       # define the device class ADC<br>
                define myADC ECDMDevice ADC # define the logical device myADC with device class ADC<br>
                get myADC value 1 # retrieve the value of analog/digital converter number 1<br>
        </code>
        <br>
        The get command is evaluated as follows: <code>get value</code> has one named parameter
        <code>channel</code>. In the example the literal <code>1</code> is given and thus <code>%channel</code>
        is replaced by <code>1</code> to yield <code>"adc get 1\n"</code> after macro substitution. Perl
        evaluates this to a literal string which is send as a plain ethersex command to the AVR-NET-IO. The
        board returns something like <code>024\n</code> for the current value of  analog/digital converter number 1. The postprocessor keeps only the digits.
        <br><br>

   </ul>


  <b>Example 2</b>
  <br><br>
    <ul>
        The following example shows how to switch a relais driven by pin 3 (bit mask 0x08) of I/O port 2 on for
        one second and then off again.<br><br>

        The class definition file <code>/etc/fhem/relais.classdef</code> looks as follows:<br><br>
        <code>
                params pinmask<br>
                set on cmd {"io set ddr 2 ff\n\000ioset port 2 0%pinmask\n\000wait 1000\n\000io set port 2 00\n"}<br>
                set on expect ".*"<br>
                set on postproc {s/^OK\nOK\nOK\nOK\n$/success/; "$_" eq "success" ? "ok" : "error"; }<br>
        </code>
        <br>
        In the fhem configuration file or on the fhem command line we do the following:<br><br>
        <code>
                define AVRNETIO ECMD telnet 192.168.0.91:2701        # define the physical device<br>
                set AVRNETIO classdef relais /etc/fhem/relais.classdef       # define the device class relais<br>
                define myRelais ECMDDevice 8 # define the logical device myRelais with pin mask 8<br>
                set myRelais on # execute the "on" command<br>
        </code>
        <br>
        The set command is evaluated as follows: <code>%pinmask</code>
        is replaced by <code>8</code> to yield
        <code>"io set ddr 2 ff\n\000io set port 2 08\n\000wait 1000\n\000io set port 2 00\n\000"</code> after macro substitution. Perl
        evaluates this to a literal string. This string is split into lines (with trailing newline characters)
        <code>
        <ul>
        <li>io set ddr 2 ff\n</li>
        <li>ioset port 2 08\n</li>
        <li>wait 1000\n</li>
        <li>io set port 2 00\n</li>
        </ul>
        </code>
        These lines are sent as a plain ethersex commands to the AVR-NET-IO one by one. After
        each line the answer from the physical device is read back. They are concatenated with \000 chars and returned
        for further processing by the <code>postproc</code> command.      
	For any of the four plain ethersex commands, the AVR-NET-IO returns the string <code>OK\n</code>. They are
	concatenated. The postprocessor takes the result from <code>$_</code>,
	substitutes it by the string <code>success</code> if it is <code>OK\nOK\nOK\nOK\n</code>, and then either
	returns the string <code>ok</code> or the string <code>error</code>.
	<br><br>

   </ul>

  <b>Example 3</b>
  <br><br>
  <ul>
        The following example shows how to implement a sandbox.<br><br>

        The class definition file <code>/etc/fhem/DummyServer.classdef</code> looks as follows:<br><br>
        <code>
                reading foo match "\d+\n"<br>
                reading foo postproc { s/^(\d+).*$/$1/;; $_ }<br>
        </code>
        <br>
        In the fhem configuration file or on the fhem command line we do the following:<br><br>
        <code>
                define myDummyServer ECMD telnet localhost:9999        # define the physical device<br>
                set myDummyServer classdef DummyServer /etc/fhem/DummyServer.classdef       # define the device class DummyServer<br>
                define myDummyClient ECDMDevice DummyServer # define a logical device with device class DummyServer<br>
        </code>
        <p>
        On a Unix command line, run <code>netcat -l 9999</code>. This makes netcat listening on port 9999. Data received on that port are printed on stdout. Data input from stdin is sent to the other end of an incoming connection.<p>
        
        Start FHEM.<p>
        
        Then enter the number 4711 at the stdin of the running netcat server.<p>
               
        FHEM sees <code>4711\n</code> coming in from the netcat dummy server. The incoming string matches the regular expression of the <code>foo</code> reading. The postprocessor is used to strip any trailing garbage from the digits. The result 4711 is used to update the <code>foo</code> reading.
        <br><br>

   </ul>



</ul>




=end html
=cut
