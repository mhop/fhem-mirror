##############################################
# $Id$
package main;

use strict;
use warnings;
use vars qw($FW_ME);      # webname (default is fhem)

#####################################
sub
readingsChange_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "readingsChangeDefine";
  $hash->{NotifyFn} = "readingsChangeExec";
  $hash->{AttrList} ="disable:1,0 disabledForIntervals addStateEvent:1,0";
  $hash->{NotifyOrderPrefix} = "00-"; # be the first
}


#####################################
sub
readingsChangeDefine($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, @re) = split("[ \t]+", $def, 6);

  return "Usage: define <name> readingsChange ".
                "<device> <readingName> <toReplace> <replaceWith>"
        if(int(@re) != 4);
  $hash->{".re"} = \@re;

  # Checking for misleading regexps
  for(my $idx = 0; $idx < 3; $idx++) {
    my $re = $re[$idx];
    return "Bad regexp: starting with *" if($re =~ m/^\*/);
    eval { "Hallo" =~ m/^$re$/ };
    return "Bad regexp $re: $@" if($@);
  }

  if($re[3] =~ m/^{.*}/) {
    $hash->{".isPerl"} = 1;
    my %specials= ();
    my $err = perlSyntaxCheck($re[3], %specials);
    return "$re[3]: $err" if($err);
  }

  readingsSingleUpdate($hash, "state", "active", 0);
  notifyRegexpChanged($hash, $re[0]);

  return undef;
}

#####################################
sub
readingsChangeExec($$)
{
  my ($rc, $dev) = @_;

  my $SELF = $rc->{NAME};
  return "" if(IsDisabled($SELF));

  my $re = $rc->{".re"};
  my $NAME = $dev->{NAME};
  return if($NAME !~ m/$re->[0]/ || !$dev->{READINGS});

  my $events = deviceEvents($dev, AttrVal($SELF, "addStateEvent", 0));
  return if(!$events);
  my $max = int(@{$events});

  my $matched=0;
  for (my $i = 0; $i < $max; $i++) {
    my $EVENT = $events->[$i];
    next if(!defined($EVENT) || $EVENT !~ m/^([^ ]+): (.+)/);
    my ($rg, $val) = ($1, $2);
    next if($rg !~ m/$re->[1]/ || !$dev->{READINGS}{$rg});

    Log3 $SELF, 5, "Changing $NAME:$rg $val via $SELF";
    $matched++;
    if($rc->{".isPerl"}) {
      eval "\$val =~ s/$re->[2]/$re->[3]/ge";
    } else {
      eval "\$val =~ s/$re->[2]/$re->[3]/g";
    }
    $events->[$i] = "$rg: $val";
    $dev->{READINGS}{$rg}{VAL} = $val;
  }
  evalStateFormat($dev) if($matched);
  return undef;
}


1;

=pod
=item helper
=item summary    modify reading value upon change
=item summary_DE Reading-Werte modifizieren bei &Auml;nderung
=begin html

<a name="readingsChange"></a>
<h3>readingsChange</h3>
<ul>
  <br>

  <a name="readingsChangedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsChange &lt;device&gt; &lt;readingName&gt;
                &lt;toReplace&gt; &lt;replaceWith&gt;"</code>
    <br><br>
    Change the content of a reading if it changes, with the perl string
    substitute mechanism. Note: As some modules rely on the known format of
    some readings, changing such readings may cause these modules to stop
    working.
    <br><br>

    &lt;device&gt;, &lt;readingName&gt; and &lt;toReplace&gt; are regular
    expressions, and are not allowed to contain whitespace.
    If replaceWith is enclosed in {}, then the content will be executed as a
    perl expression for each match.<br>
    Notes:<ul>
      <li>after a Reading is set by a module, first the event-* attributes are
        evaluated, then userReadings, then stateFormat, then the
        readingsChange definitions (in alphabetical order), and after this the
        notifies, FileLogs, etc. again in alphabetical order.</li>
      <li>if stateFormat for the matched device is set, then it will be
        executed multiple times: once before the readingsChange, and once for
        every matching readingsChange.</li>
    </ul>
    <br><br>

    Examples:
    <ul><code>
      # shorten the reading power 0.5 W previous: 0 delta_time: 300<br>
      # to just power 0.5 W<br>
      define pShort readingsChange pm power (.*W).* $1<br>
      <br>
      # format each decimal number in the power reading to 2 decimal places<br>
      define p2dec readingsChange pm power (\d+\.\d+) {sprintf("%0.2f", $1)}
    </code></ul>
  </ul>
  <br>

  <a name="readingsChangeset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="readingsChangeget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="readingsChangeattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#addStateEvent">addStateEvent</a></li>
  </ul>
  <br>

</ul>

=end html

=cut
