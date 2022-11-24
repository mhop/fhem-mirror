##############################################
# $Id$
package main;

use strict;
use warnings;
use B qw(svref_2object);

my $fhemdebug_enabled;
my $main_callfn;
my $main_readingsEndUpdate;
my $main_setReadingsVal;

sub
fhemdebug_Initialize($){
  $cmds{"fhemdebug"}{Fn} = "fhemdebug_Fn";
  $cmds{"fhemdebug"}{Hlp} =
    "{enable | disable | status | timerList | ".
    "addTimerStacktrace | utf8check | sizeInFile}";
}

sub fhemdebug_utf8check($$$$);


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

  } elsif($param =~ m/^forceEvents ([0|1])/) { #123655
    local $SIG{__WARN__} = sub { };
    if($1) {
      $main_readingsEndUpdate = \&readingsEndUpdate;
      $main_setReadingsVal = \&setReadingsVal;
      *readingsEndUpdate = sub($$){ 
        my $dt = $_[1];
        $dt = 1 if(AttrVal($_[0]->{NAME}, "forceEvents", 0));
        &{$main_readingsEndUpdate}($_[0], $dt);
      };
      *setReadingsVal = sub($$$$) {
        DoTrigger($_[0]->{NAME}, "$_[1]: $_[2]")
          if($_[1] && $_[1] eq "IODev" &&
             AttrVal($_[0]->{NAME}, "forceEvents", 0));
        &{$main_setReadingsVal}(@_);
      };
    } else {
      *readingsEndUpdate = $main_readingsEndUpdate;
      *setReadingsVal = $main_setReadingsVal;
    }

  } elsif($param =~ m/^utf8check/) { #125866
    my (@ret, %visited, $ret);
    fhemdebug_utf8check("def", \%defs, \@ret, \%visited);
    fhemdebug_utf8check("attr", \%attr, \@ret, \%visited);
    fhemdebug_utf8check("modules", \%modules, \@ret, \%visited);
    return "Checked ".int(keys %visited)." elements\n".
           (int(@ret) ?  "Strings with utf8-flag set:\n".join("\n", @ret) :
                         "Found no strings with utf8-flag");

  } elsif($param =~ m/^sizeInFile *(\d*)$/) {
    my $top = $1 ? $1 : 20;
    my %s;
    for my $d (keys %defs) {
      next if($defs{$d}{TEMPORARY});
      $s{$d} = length(CommandList(undef, "-r $d"));
      $s{$d} += length($d)+length($defs{$d}{FUUID})+10 if($defs{$d}{FUUID});
    }

    my $total = 26;
    my @out = map { $total += $s{$_}; sprintf("%6d: %s", $s{$_}, $_) }
                    sort { $s{$b}<=>$s{$a} } keys %s;
    return join("\n", @out[0..$top-1])."\nTotal: $total";

  } else {
    return "Usage: fhemdebug {enable | disable | status | ".
              "timerList | addTimerStacktrace {0|1} | forceEvents {0|1} | ".
              " utf8check | sizeInFile [num] }";
  }
  return;
}

sub
fhemdebug_utf8check($$$$)
{
  my ($prefix, $hp, $rp, $vp) = @_;

  if(ref($rp) ne "ARRAY") {
    Log 1, "utf8check problems at $prefix";
    return;
  }
  for my $key (sort keys %{$hp}) {
    my $path = $prefix."::".$key;
    next if($vp->{$path} || index($prefix,"::$key") > 0);
    $vp->{$path} = 1;
    my $val = $hp->{$key};

    push( @{$rp}, "Key: ".$prefix."::".$key)
      if(utf8::is_utf8($key) || $key =~ m/[^\x00-\xFF]/);

    my $rv = ref($val);
    if($rv eq "HASH") {
      fhemdebug_utf8check($path, $val, $rp, $vp);

    } elsif(!defined($val) || $rv eq "ARRAY") {

    } elsif(utf8::is_utf8($val) || $val =~ m/[^\x00-\xFF]/) {
      push @{$rp}, "Key: ".$path." Value:".$hp->{$key};

    }
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
    my $fnName = $h->{FN};
    if(ref($fnName) ne "") {
      my $cv = svref_2object($fnName);
      $fnName = $cv->GV->NAME if($cv); # get function name
    }
    push(@res, sprintf("%s.%05d %s %s %s",
      FmtDateTime($tt), int(($tt-int($tt))*100000), 
      $fnName,
      ($h->{ARG} && ref($h->{ARG}) eq "HASH" && $h->{ARG}{NAME} ? 
       $h->{ARG}{NAME} : ""),
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

    <li>sizeInFile [&lt;num&gt;]<br>
      returns the name of the devices requiring the most space in storage.
      If [&lt;num&gt;] is omitted, the top 20 is returned.<br>
      Note: the total wont include the comment lines.
      </li>

    <li>utf8check<br>
      returns the list of strings with the internal utf8-bit set.
      Such strings may cause various problems.
      </li>


  </ul>
</ul>

=end html
=cut
