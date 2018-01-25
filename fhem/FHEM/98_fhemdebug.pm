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

  } else {
    return "Usage: fhemdebug {enable|disable|status|memusage}";
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

  my %bl = ("main::modules::MAX"=>1, HTTPMOD=>1);
  $Devel::Size::warn = 0;
  my @param = split(" ", $param);
  my $max = 50;
  my $re;
  $max = pop(@param) if(@param > 1 && $param[$#param] =~ m/^\d+$/);
  $re  = pop(@param) if(@param > 1);

  my %ts;
  my $collectSize = sub($$$)
  {
    my ($fn, $h, $mname) = @_;
    return if($h->{__IN__CS__}); # save us from endless recursion
    $h->{__IN__CS__} = 1;
    eval {
      foreach my $n (keys %$h) {
        next if(!$n || $n =~ m/^[^A-Za-z]$/);
        if($n =~ m/::$/) {
          $fn->($fn, $h->{$n}, "$mname$n");
          next;
        }
        next if(main->can("$mname$n")); # functions

        if($mname eq "main::" && 
          ($n eq "modules" || $n eq "defs" || $n eq "readyfnlist" ||
           $n eq "selectlist" || $n eq "intAt" || $n eq "attr" ||
           $n eq "ntfyHash")) {
          for my $mn (keys %{$main::{$n}}) {
            my $name = "$mname${n}::$mn";
            if($mname eq "main::" && $n eq "defs" && $bl{$defs{$mn}{TYPE}}) {
              Log 5, "$name TYPE on the blackList, skipping it";
              next;
            }
            if($bl{$name}) {
              Log 5, "$name on the blackList, skipping it";
              next;
            }
            Log 5, $name;       # Crash-debugging
            $ts{$name} = Devel::Size::total_size($main::{$n}{$mn});
          }
          
        } else {
          my $name = "$mname$n";
          if($bl{$name}) {
            Log 5, "$name (on the blackList, skipping it)";
            next;
          }
          Log 5, $name;       # Crash-debugging
          $ts{$name} = Devel::Size::total_size($h->{$n});

        }
      }
    };
    delete $h->{__IN__CS__};
    Log 1, "collectSize $mname: $@" if($@);
  };
  $collectSize->($collectSize, \%main::, "main::");

  my @sts = sort { $ts{$b} <=> $ts{$a} } keys %ts;
  my @ret;
  for(my $i=0; $i < int(@sts); $i++) {
    next if($re && $sts[$i] !~ m/$re/);
    push @ret, sprintf("%4d. %-30s %8d", $i+1,substr($sts[$i],6),$ts{$sts[$i]});
    last if(@ret >= $max);
  }
  return join("\n", @ret);
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
  <code>fhemdebug {enable|disable|status|}</code><br>
  <br>
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
      <li>The used function Devel::Size::total_size crashes perl (and FHEM) for
        functions and some other data structures. memusage tries to avoid to
        call it for such data structures, but as the problem is not identified,
        it may crash your currently running instance. It works for me, but make
        sure you saved your fhem.cfg before calling it.</li>
      <li>The known data structures modules and defs are reported in more
        detail.</li>
      </ul>
    </li>
  </ul>
</ul>

=end html
=cut
