##############################################
# $Id$
package main;

use strict;
use warnings;

my @events;
my @logs;
sub FhemTestUtils_gotLog($);
sub FhemTestUtils_resetLogs();
sub FhemTestUtils_gotEvent($);
sub FhemTestUtils_resetEvents();

sub
FhemTestUtils_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FhemTestUtils_Define";
  $hash->{NotifyFn} = "FhemTestUtils_Notify";
}

sub
FhemTestUtils_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> FhemTestUtils" if(int(@a) != 2);
  $logInform{$a[0]} = sub() { push @logs, $_[1] };
  return undef;
}


sub
FhemTestUtils_Notify($$)
{
  my ($ntfy, $dev) = @_;

  my $events = deviceEvents($dev, 0);
  my $n = $dev->{NAME};
  #map { print "$n:$_\n" } @{$events};
  return if(!$events); # Some previous notify deleted the array.
  push @events, map { "$n:$_" } @{$events};
  return undef;
}


sub
FhemTestUtils_gotEvent($)
{
  my ($arg) = @_;
  return grep /$arg/,@events;
}

sub
FhemTestUtils_resetEvents()
{
  @events=();
}

sub
FhemTestUtils_gotLog($)
{
  my ($arg) = @_;
  return grep /$arg/,@logs;
}

sub
FhemTestUtils_resetLogs()
{
  @logs=();
}

sub 
FhemTestUtils_getLogTime
{
  my $arg = shift;

  foreach my $line (@logs) {
    if($line =~ m/^([0-9\.]+ [0-9:\.]+)\s.*$arg/ms) {
      my @a = split("[\. :]", $1);
      my $time =  mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
      $time += $a[6]/1000 if(@a == 7); # attrg global mseclog is active
      return $time;
    }
  }
  return;
}


1;

=pod
=item helper
=item summary    Utility functions for testing FHEM modules
=item summary_DE Hilfsfunktionen, um FHEM Module zu testen
=begin html

<a name="FhemTestUtils"></a>
<h3>FhemTestUtils</h3>
<ul>

  An instance of this module will be automatically defined, if fhem.pl is
  called with the -t option.
  The module will collect all events and Log messages, so a test program is
  able to check, if an event or log message was generated.<br>
  Available functions:
  <ul>
    <li>FhemTestUtils_gotEvent($)<br>
      Return the events matching the regexp argument (with grep).
      </li>
    <li>FhemTestUtils_gotLog($)<br>
      Return the logs matching the regexp argument (with grep).
      Note, that loglevel filtering with verbose ist still active.
      </li>
    <li>FhemTestUtils_getLogTime($)<br>
      Return the timestamp of the first log matching the argument.
      </li>
    <li>FhemTestUtils_resetEvents()<br>
      Reset the internal event buffer.
      </li>
    <li>FhemTestUtils_resetLogs()<br>
      Reset the internal log buffer.
      </li>
  </ul>

  <br><br>
  <a name="FhemTestUtilsdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FhemTestUtils</code>
  </ul>
  <br>

  <a name="FhemTestUtilsset"></a>
  <b>Set</b> <ul>N/A</ul><br>
  <a name="FhemTestUtilsget"></a>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="FhemTestUtilsattr"></a>
  <b>Attributes</b> <ul>N/A</ul><br>

</ul>

=end html


=cut
