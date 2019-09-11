##############################################
# $Id$
package main;

use strict;
use warnings;

my $fhemdebug_enabled;
my $main_callfn;

sub
fhemdebug_Initialize($){
  $cmds{"fhemdebug"}{Fn} = "fhemdebug_Fn";
  $cmds{"fhemdebug"}{Hlp} = "{start|stop|status}";
}

sub
fhemdebug_Fn($$)
{
  my ($cl,$param) = @_;

  if($param eq "enable") {
    return "fhemdebug is already enabled" if($fhemdebug_enabled);
    local $SIG{__WARN__} = sub { };
    $main_callfn = \&CallFn;
    *CallFn = \&fhemdebug_CallFn;
    $fhemdebug_enabled = 1;
    return undef;

  } elsif($param eq "disable") {
    return "fhemdebug is already disabled" if(!$fhemdebug_enabled);
    local $SIG{__WARN__} = sub { };
    *CallFn = $main_callfn;
    $fhemdebug_enabled = 0;
    return undef;

  } elsif($param eq "status") {
    return "fhemdebug is ".($fhemdebug_enabled ? "enabled":"disabled");

  } elsif($param =~ m/^timerList/) {
    return fhemdebug_timerList($param);

  } elsif($param =~ m/^addTimerStacktrace/) {
    $param =~ s/addTimerStacktrace\s*//;
    $addTimerStacktrace = $param;
    return;

  } else {
    return "Usage: fhemdebug {enable | disable | status | ".
                        "timerList | addTimerStacktrace {0|1} }";
  }
}

sub
fhemdebug_CheckDefs($@)
{
  my ($txt, $dev, $n) = @_;
  foreach my $d (keys %defs) {
    if(!defined($d)) {
      Log 1, "ERROR: undef \$defs entry found ($txt $dev $n)";
      delete($defs{undef});
      next;
    }
    if($d eq "") {
      Log 1, "ERROR: '' \$defs entry found ($txt $dev $n)";
      delete($defs{''});
      next;
    }
    if(ref $defs{$d} ne "HASH") {
      Log 1, "ERROR: \$defs{$d} is not a HASH ($txt $dev $n)";
      delete($defs{$d});
      next;
    }
    if(!$defs{$d}{TYPE}) {
      Log 1, "ERROR: >$d< has no TYPE, but following keys: >".
                            join(",", sort keys %{$defs{$d}})."<".
                            "($txt $dev $n)";
      delete($defs{$d});
      next;
    }
  }
}

sub
fhemdebug_CallFn(@)
{
  #Log 1, "fhemdebug_CallFn $_[0] $_[1];

  if(wantarray) {
    fhemdebug_CheckDefs("before", @_);
    no strict "refs";
    my @ret = &{$main_callfn}(@_);
    use strict "refs";
    fhemdebug_CheckDefs("after", @_);
    return @ret;

  } else {
    fhemdebug_CheckDefs("before", @_);
    no strict "refs";
    my $ret = &{$main_callfn}(@_);
    fhemdebug_CheckDefs("after", @_);
    use strict "refs";
    return $ret;

  }
}

sub
fhemdebug_timerList($)
{
  my ($param) = @_;
  my @res;

  for my $h (@intAtA) {
    my $tt = $h->{TRIGGERTIME};
    push(@res, sprintf("%s.%05d %s%s",
      FmtDateTime($tt), int(($tt-int($tt))*100000), $h->{FN},
      $h->{STACKTRACE} ? $h->{STACKTRACE} : ""));
  }
  return join("\n", @res);
}

1;

=pod
=item command
=item summary    try to localize FHEM error messages
=item summary_DE Hilfe bei der Lokalisierung von Fehlermeldungen
=begin html

<a name="fhemdebug"></a>
<h3>fhemdebug</h3>
<ul>
  <code>fhemdebug &lt;command&gt;</code><br>
  <br>
  where &lt;command&gt; is one of
  <ul>
    <li>enable/disable/status<br>
      fhemdebug produces debug information in the FHEM Log to help localize
      certain error messages. Currently following errors are examined:
      <ul>
      - Error: &gt;...&lt; has no TYPE, but following keys: &gt;...&lt;<br>
      </ul>
      As it frequently examines internal data-structures, it uses a lot of CPU,
      it is not recommended to enable it all the time. A FHEM restart after
      disabling it is not necessary.<br>
      </li>

    <li>timerList<br>
      show the list of InternalTimer calls.
      </li>

    <li>addTimerStacktrace {1|0}<br>
      enable or disable the registering the stacktrace of each InternalTimer
      call. This stacktrace will be shown in the timerList command.
      </li>

  </ul>
</ul>

=end html
=cut
