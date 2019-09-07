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

  } elsif($param =~ m/^memusage/) {
    return fhemdebug_memusage($param);

  } elsif($param =~ m/^timerList/) {
    return fhemdebug_timerList($param);

  } elsif($param =~ m/^addTimerStacktrace/) {
    $param =~ s/addTimerStacktrace\s*//;
    $addTimerStacktrace = $param;
    return;

  } else {
    return "Usage: fhemdebug {enable | disable | status | memusage | ".
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
fhemdebug_memusage($)
{
  my ($param) = @_;
  eval "use Devel::Size";
  return $@ if($@);

  $Devel::Size::warn = 0;
  my @param = split(" ", $param);
  my $max = 50;
  my $elName = "%main::";
  $max = pop(@param) if(@param > 1 && $param[$#param] =~ m/^\d+$/);
  $elName = pop(@param) if(@param > 1);
  my %ts;

  my $el;
  my $cmd = "\$el = \\$elName";
  eval $cmd;
  return $@ if($@);


  my $elName2 = $elName;
  if($elName ne "%main::") {
    if($elName =~ m/^%\{(\$.*)\}$/) {
      $elName = $1;
      $elName2 = $elName;
      $elName2 =~ s/'/\\'/g;
    } else {
      $elName =~ s/%/\$/;
      $elName2 = $elName;
    }
  }

  no warnings;
  if(ref $el eq "HASH") {
    for my $k (keys %{$el}) {
      next if($elName eq "%main::" && 
                ($k =~ m/[^A-Z0-9_:]/i ||
                 $k =~ m/^\d+$/ || 
                 $k =~ m/::$/ || 
                 exists &{$k}));

      if($elName eq "%main::") {
        my $t = '@';
        if(eval "ref \\$t$k" eq "ARRAY") {
          $cmd = "\$ts{'$t$k'} = Devel::Size::total_size(\\$t$k)";
          eval $cmd;
        }
        $t = '%';
        if(eval "ref \\$t$k" eq "HASH") {
          $cmd = "\$ts{'$t$k'} = Devel::Size::total_size(\\$t$k)";
          eval $cmd;
        }
        $t = '$';
        if(eval "ref \\$t$k" eq "SCALAR") {
          $cmd = "\$ts{'$t$k'} = Devel::Size::total_size(\\$t$k)";
          eval $cmd;
        }
      } else {
        my $k2 = "{$elName\{'$k'}}";
        my $k3 = "{$elName2\{\\'$k\\'}}";
        my $k4 = "$elName\{$k}";
        my $k5 = "$elName2\{\\'$k\\'}";
        my $t = '@';
        if(eval "ref \\$t$k2" eq "ARRAY") {
          $cmd = "\$ts{'$t$k3'} = Devel::Size::total_size(\\$t$k2)";
          eval $cmd;
        }
        $t = '%';
        if(eval "ref \\$t$k2" eq "HASH") {
          $cmd = "\$ts{'$t$k3'} = Devel::Size::total_size(\\$t$k2)";
          eval $cmd;
        }
        if(eval "ref \\$k4" eq "SCALAR") {
          $cmd = "\$ts{'$k5'} = Devel::Size::total_size(\\$k4)";
          eval $cmd;
        }
      }

    }
  } else {
    $ts{$elName} = Devel::Size::total_size($el);
  }
  use warnings;

  my @sts = sort { $ts{$b} == $ts{$a} ? $a cmp $b :
                  $ts{$b} <=> $ts{$a} } keys %ts;
  my @ret;
  for(my $i=0; $i < @sts; $i++) {
    push @ret, sprintf("%4d. %-30s %8d", $i+1, $sts[$i], $ts{$sts[$i]});
    last if(@ret >= $max);
  }
  return join("\n", @ret);
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

    <li>memusage [datastructure] [nr]<br>
      Dump the name of the first nr datastructures with the largest memory
      footprint. Dump only datastructure, if specified.<br>
      <b>Notes</b>:
      <ul>
        <li>this function depends on the Devel::Size module, so this must be
          installed first.</li>
        <li>the function will only display globally visible data (no module or
          function local variables).</li>
      </ul>
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
