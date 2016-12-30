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

  } else {
    return "Usage: fhemdebug {enable|disable|status}";
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

1;

=pod
=item command
=item summary    try to localize FHEM error messages
=item summary_DE Hilfe bei der Lokalisierung von Fehlermeldungen
=begin html

<a name="fhemdebug"></a>
<h3>fhemdebug</h3>
<ul>
  <code>fhemdebug {enable|disable|status}</code><br>
  <br>
  fhemdebug produces debug information in the FHEM Log to help localize
  certain error messages. Currently following errors are examined:
  <ul>
  - Error: &gt;...&lt; has no TYPE, but following keys: &gt;...&lt;<br>
  </ul>
  As it frequently examines internal data-structures, it uses a lot of CPU,
  it is not recommended to enable it all the time. A FHEM restart after
  disabling it is not necessary.<br>

</ul>

=end html
=cut
