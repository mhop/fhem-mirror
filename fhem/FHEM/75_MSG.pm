####################################################
# $Id$
####################################################
#
# History:
#
# 2015-05-09: Move mail related code to MSGMail, 
#             and  file related code to MSGFile,
#             rewrite to use delegates for compatibility
# 2015-05-07: Determine which SSL implementation to use
# 2015-05-06: Tidy up code for restructuring
# 2015-05-05: Remove dependency on Switch
# 2012      : Created by rbente
#
package main;

use strict;
use warnings;

my %sets = (
    "send"  => "MSG",
    "write" => "MSG",
);

sub MSG_Initialize($)
{
    my ($hash) = @_;

    $hash->{SetFn}    = "MSG_Set";
    $hash->{DefFn}    = "MSG_Define";
    $hash->{AttrList} = "loglevel:0,1,2,3,4,5,6";
}

sub MSG_Set($@)
{
    my ($hash, @a) = @_;
    return "Unknown argument $a[1], choose one of  ->  " . join(" ", sort keys %sets)
      if (!defined($sets{ $a[1] }));

    my $name = shift @a;

    return "no set value specified" if (int(@a) < 1);

    return "Unknown argument ?" if ($a[0] eq "?");

    # Check, if we have send or wait as parameter
    if (($a[0] eq "send") || ($a[0] eq "write"))
    {

        # Check if the device is defined that we like to use as frontend
        return "Please define $a[1] first" if (!defined($defs{ $a[1] }));

        if (!defined($defs{ $a[1] }{TYPE}))
        {
            return "TYPE for $defs{$a[1]} not defined";
        }
        elsif ($defs{ $a[1] }{TYPE} eq "MSGFile")
        {
            fhem("set $a[1] write");
        }
        elsif ($defs{ $a[1] }{TYPE} eq "MSGMail")
        {
            fhem("set $a[1] send");
        }
        else
        {
            return "MSG Filetype $defs{$a[1]}{TYPE} unknown";
        }
    }    ###> END if(($a[0] eq "send") || ($a[0] eq "write"))
    my $v = join(" ", @a);
    Log GetLogLevel($name, 2), "MSG set $name $v";

    # update stats
    $hash->{CHANGED}[0]            = $v;
    $hash->{STATE}                 = $v;
    $hash->{READINGS}{state}{TIME} = TimeNow();
    $hash->{READINGS}{state}{VAL}  = $v;
    return undef;
}

sub MSG_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $errMSG_ = "wrong syntax: define <name> MSG";

    return $errMSG_ if (@a != 2);

    $hash->{STATE} = "ready";
    $hash->{TYPE}  = "MSG";
    return undef;
}

1;

=pod
=begin html

<a name="MSG"></a>
<h3>MSG</h3>
<ul>
  The MSG device is deprecated.<br><br>
  It used to be the backend device for I/O-handling of <a href="#MSGMail">MSGMail</a>
  and <a href="#MSGFile">MSGFile</a> devices.
  The MSG device can still be used for this purpose, but actually delegates send and
  write commands to the <a href="#MSGMail">MSGMail</a> and <a href="#MSGFile">MSGFile</a>
  devices, respectively.<br><br>
  Before removing a deprecated MSG device from an installation, make sure to change
  code in user functions, accordingly.
  <br><br>
  <a name="MSGdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; MSG </code><br><br>
  Specifies the MSG device. This is no longer required since 
  <a href="#MSGFile">MSGFile</a> and <a href="#MSGMail">MSGMail</a>
  devices provide all necessary functionality.
  </ul>
  <br>
  <a name="MSGset"></a>
  <b>Set</b>
  <ul>
  <code>set &lt;name&gt; send|write &lt;devicename&gt;</code><br><br>
  </ul>
  Notes:
  <ul>
  To process the data, both 'send' and 'write' can be used.<br>
  The MSG device will delegate the command to the device specified 
  by 'devicename' and automatically use 'send' for 
  <a href="#MSGMail">MSGMail</a> and 'write' for 
  <a href="#MSGFile">MSGFile</a> devices.
  <br>
  <br><br>
  	Examples:
  	<ul>
  		<code>define myMsg MSG</code>
  	</ul>
  </ul>
  <a name="MSGVattr"></a>
  <b>Attributes</b>
    <ul>
      <li><a href="#loglevel">loglevel</a></li>
    </ul>
  </ul>
<br><br>

=end html
=cut
