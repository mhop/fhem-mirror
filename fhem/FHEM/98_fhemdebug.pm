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
  my $re;
  $max = pop(@param) if(@param > 1 && $param[$#param] =~ m/^\d+$/);
  $re  = pop(@param) if(@param > 1);
  my %ts;
  my %mh = (defs=>1, modules=>1, selectlist=>1, attr=>1, readyfnlist=>1);

  my $collectSize = sub($$$$)
  {
    my ($fn, $h, $mname,$cleanUp) = @_;
    return 0 if($h->{__IN__CS__}); # save us from endless recursion
    return 0 if($h->{__IN__CSS__} && !$cleanUp);
    $h->{__IN__CSS__} = 1 if(!$cleanUp);
    $h->{__IN__CS__} = 1;
    my $sum = 0;
    foreach my $n (sort keys %$h) {
      next if(!$n || $n =~ m/^[^A-Za-z]$/ || $n eq "__IN__CS__");

      my $ref = ref $h->{$n};
      my $name = ($mname eq "main::" ? "$mname$n" : "${mname}::$n");
      $ref = "HASH" if(!$ref && $mname eq "main::" && $mh{$n});
      next if($n eq "main::" || $n eq "IODev" || 
              $ref eq "CODE" || main->can($name) || $ref =~ m/::/);
      Log 5, " Check $name / $mname / $n / $ref";     # Crash-debugging
      if($ref eq "HASH") {
        next if($mname ne "main::defs" && $h->{$n}{TYPE} && $h->{$n}{NAME});
        $sum += $fn->($fn, $h->{$n}, $name, $cleanUp); 

      } else {
        my $sz = Devel::Size::size($h->{$n});
        $ts{$name} = $sz if(!$cleanUp);
        $sum += $sz;
      }
    }
    delete($h->{__IN__CS__});
    delete($h->{__IN__CSS__}) if($cleanUp);
    $sum += Devel::Size::size($h);
    $ts{$mname} = $sum if($mname ne "main::" && !$cleanUp);
    return $sum;
  };
  $collectSize->($collectSize, \%main::, "main::", 0);
  $collectSize->($collectSize, \%main::, "main::", 1);

  my @sts = sort { $ts{$b} <=> $ts{$a} } keys %ts;
  my @ret;
  for(my $i=0; $i < @sts; $i++) {
    next if($re && $sts[$i] !~ m/$re/);
    push @ret, sprintf("%4d. %-30s %8d", $i+1,substr($sts[$i],6),$ts{$sts[$i]});
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

    <li>memusage [regexp] [nr]<br>
      Dump the name of the first nr datastructures with the largest memory
      footprint. Filter the names by regexp, if specified.<br>
      <b>Notes</b>:
      <ul>
        <li>this function depends on the Devel::Size module, so this must be
          installed first.</li>
        <li>The used function Devel::Size::size may crash perl (and FHEM) for
          functions and some other data structures. memusage tries to avoid to
          call it for such data structures, but as the problem is not
          identified, it may crash your currently running instance. It works
          for me, but make sure you saved your fhem.cfg before calling it.</li>
        <li>To avoid the crash, the size of same data is not computed, so the
          size reported is probably inaccurate, it should only be used as a
          hint.  </li>
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
