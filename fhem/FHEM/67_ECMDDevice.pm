# $Id$##############################################################################
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
sub ECMDDevice_Define($$);

my %gets= (
);

my %sets= (
);

###################################
sub
ECMDDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "ECMDDevice_Get";
  $hash->{SetFn}     = "ECMDDevice_Set";
  $hash->{DefFn}     = "ECMDDevice_Define";

  $hash->{AttrList}  = "loglevel 0,1,2,3,4,5";
}

###################################
sub
ECMDDevice_AnalyzeCommand($)
{
        my ($ecmd)= @_;
        Log 5, "ECMDDevice: Analyze command >$ecmd<";
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

###################################
sub
ECMDDevice_Changed($$$)
{
        my ($hash, $cmd, $value)= @_;

        readingsSingleUpdate($hash, $cmd, $value, 1);

        $hash->{STATE} = "$cmd $value";

        my $name= $hash->{NAME};
        Log GetLogLevel($name, 4), "ECMDDevice $name $cmd: $value";

        return $hash->{STATE};

}

###################################
sub
ECMDDevice_PostProc($$$)
{
  my ($hash, $postproc, $value)= @_;

  # the following lines are commented out because we do not want specials to be evaluated
  # this is mainly due to the unwanted substitution of single semicolons by double semicolons
  #my %specials= ECMDDevice_DeviceParams2Specials($hash);
  #my $command= EvalSpecials($postproc, %specials);
  # we pass the command verbatim instead
  # my $command= $postproc;

  if($postproc) {
        my %specials= ECMDDevice_DeviceParams2Specials($hash);
        my $command= EvalSpecials($postproc, %specials);
	$_= $value;
	Log 5, "Postprocessing $value with perl command $command.";
	$value= AnalyzePerlCommand(undef, $command);
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
                return "$name error: unknown command $cmdname";
        }

        my $ecmd= $IOhash->{fhem}{classDefs}{$classname}{gets}{$cmdname}{cmd};
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
                        Log 5, "Parameter %". $param . " is " . $a[$i];
                        $specials{"%".$param}= $a[$i++];
                }
        }
        $ecmd= EvalSpecials($ecmd, %specials);

        my $r = ECMDDevice_AnalyzeCommand($ecmd);

        my $v= IOWrite($hash, $r);

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
                return "Unknown argument ?, choose one of " . join(' ', keys %$sets);
        }

        my $ecmd= $IOhash->{fhem}{classDefs}{$classname}{sets}{$cmdname}{cmd};
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
        $ecmd= EvalSpecials($ecmd, %specials);

        my $r = ECMDDevice_AnalyzeCommand($ecmd);

        my $v= IOWrite($hash, $r);

	$v= ECMDDevice_PostProc($hash, $postproc, $v);

#        $v= join(" ", @a) if($params);

        return ECMDDevice_Changed($hash, $cmdname, $v);

}


#############################

sub
ECMDDevice_Define($$)
{
        my ($hash, $def) = @_;
        my @a = split("[ \t]+", $def);

        return "Usage: define <name> ECMDDevice <classname> [...]"    if(int(@a) < 3);
        my $name= $a[0];
        my $classname= $a[2];

        AssignIoPort($hash);

        my $IOhash= $hash->{IODev};
        if(!defined($IOhash->{fhem}{classDefs}{$classname}{filename})) {
                my $err= "$name error: unknown class $classname.";
                Log 1, $err;
                return $err;
        }

        $hash->{fhem}{classname}= $classname;

        my @prms= ECMDDevice_GetDeviceParams($hash);
        my $numparams= 0;
        $numparams= $#prms+1 if(defined($prms[0]));
        #Log 5, "ECMDDevice $classname requires $numparams parameter(s): ". join(" ", @prms);

        # keep only the parameters
        shift @a; shift @a; shift @a;

        # verify identical number of parameters
        if($numparams != $#a+1) {
                my $err= "$name error: wrong number of parameters";
                Log 1, $err;
                return $err;
        }

        # set parameters
        for(my $i= 0; $i< $numparams; $i++) {
                $hash->{fhem}{params}{$prms[$i]}= $a[$i];
        }
        return undef;
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
    <code>define &lt;name&gt; ECMDDevice &lt;classname&gt; [&lt;parameter1&gt; [&lt;parameter2&gt; [&lt;parameter3&gt; ... ]]]</code>
    <br><br>

    Defines a logical ECMD device. The number of given parameters must match those given in
    the <a href="#ECMDClassdef">class definition</a> of the device class <code>&lt;classname&gt;</code>.
    <br><br>

    Examples:
    <ul>
      <code>define myADC ECMDDevice ADC</code><br>
      <code>define myRelais1 ECMDDevice relais 8</code><br>
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
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
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
                get value cmd {"adc get %channel"}  <br>
                get value params channel<br>
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
        is replaced by <code>1</code> to yield <code>"adc get 1"</code> after macro substitution. Perl
        evaluates this to a literal string which is send as a plain ethersex command to the AVR-NET-IO. The
        board returns something like <code>024</code> for the current value of  analog/digital converter number 1.
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
                set on cmd {"io set ddr 2 ff\nioset port 2 0%pinmask\nwait 1000\nio set port 2 00"}<br>
		set on postproc {s/^OK\nOK\nOK\nOK$/success/; "$_" eq "success" ? "ok" : "error"; }<br>
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
        <code>"io set ddr 2 ff\nioset port 2 08\nwait 1000\nio set port 2 00"</code> after macro substitution. Perl
        evaluates this to a literal string. This string is split into lines (without trailing newline characters)
        <code>
        <ul>
        <li>io set ddr 2 ff</li>
        <li>ioset port 2 08</li>
        <li>wait 1000</li>
        <li>io set port 2 00</li>
        </ul>
        </code>
        These lines are sent as a plain ethersex commands to the AVR-NET-IO one by one. Each line is terminated with
        a newline character unless <a href="#ECMDattr">the <code>nonl</code> attribute of the ECMDDevice</a> is set. After
        each line the answer from the ECMDDevice is read back. They are concatenated with newlines and returned
        for further processing, e.g. by the <code>postproc</code> command.      
	For any of the four plain ethersex commands, the AVR-NET-IO returns the string <code>OK</code>. They are
	concatenated and separated by line breaks (\n). The postprocessor takes the result from <code>$_</code>,
	substitutes it by the string <code>success</code> if it is <code>OK\nOK\nOK\nOK</code>, and then either
	returns the string <code>ok</code> or the string <code>error</code>.

   </ul>


</ul>




=end html
=cut
