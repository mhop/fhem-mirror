##############################################
# $Id$
# Avarage computing

package main;
use strict;
use warnings;

my %cmdalias;

##########################
sub
cmdalias_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "cmdalias_Define";
  $hash->{UndefFn}  = "cmdalias_Undefine";
  $hash->{AttrList} = "disable:0,1";
}


##########################
sub
cmdalias_Define($$$)
{
  my ($hash, $def) = @_;

  if($def !~ m/^([^ ]*) cmdalias ([^ ]*)(.*) AS (.*)$/) {
    my $msg =
      "wrong syntax: define <name> cmdalias <cmd> [parameter] AS command...";
    return $msg;
  }
  my ($name, $alias, $param, $newcmd) = ($1, $2, $3, $4);
  $param =~ s/^ *//;
  # Checking for misleading regexps
  eval { "Hallo" =~ m/^$param$/ };
  return "$name: Bad regexp in $param: $@" if($@);
  $hash->{ALIAS} = lc($alias);
  $hash->{PARAM} = $param;
  $hash->{NEWCMD} = $newcmd;
  $hash->{STATE} = "defined";

  $cmdalias{$alias}{Alias}{$name} = $hash;
  $cmdalias{$alias}{OrigFn} = $cmds{$alias}{Fn}
    if($cmds{$alias} && $cmds{$alias}{Fn} ne "CommandCmdAlias");
  $cmds{$alias}{Fn} = "CommandCmdAlias";

  return undef;
}

sub
cmdalias_Undefine($$)
{
  my ($hash, $arg) = @_;

  my $alias = $hash->{ALIAS};
  delete $cmdalias{$alias}{Alias}{$hash->{NAME}};

  if(! keys %{$cmdalias{$alias}{Alias}}) {
    if($cmdalias{$alias}{OrigFn}) {
      $cmds{$alias}{Fn} = $cmdalias{$alias}{OrigFn};
    } else {
      delete($cmds{$alias});
    }
    delete($cmdalias{$alias});
  }

  return undef;
}

sub
CommandCmdAlias($$$)
{
  my ($cl, $param, $alias) = @_;
  my $a = $cmdalias{lc($alias)};
  return "Unknown command $a, internal error" if(!$a);
  foreach my $n (sort keys %{$a->{Alias}}) {
    my $h = $a->{Alias}{$n};
    next if($h->{InExec});
    if($param =~ m/^$h->{PARAM}$/) {
      my %specials= ("%EVENT" => $param);
      my $exec = EvalSpecials($h->{NEWCMD}, %specials);
      $h->{InExec} = 1;
      my $r =  AnalyzeCommandChain(undef, $exec);
      delete $h->{InExec};
      return $r;
    }
  }
  no strict "refs";
  return &{$a->{OrigFn} }($cl, $param, $alias);
  use strict "refs";
}

1;

=pod
=begin html

<a name="cmdalias"></a>
<h3>cmdalias</h3>
<ul>
  create new commands or replace internal ones.
  <br>

  <a name="cmdaliasdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; cmdalias &lt;cmd&gt; [parameter]
                AS newcommand..."</code><br>
    <br>
    <ul>
      parameter is optional and is a regexp which must match the command
      entered.
      If it matches, then the specified newcommand will be executed, which is 
      a fhem command (see <a href="#command">Fhem command types</a> for
      details). Like in the <a href="#notify">notify</a> commands, $EVENT or
      $EVTPART may be used, in this case representing the command arguments as
      whole or the unique words entered.<br>
      Notes:<ul>
      <li>newcommand may contain cmd, but recursion is not allowed.</li>
      <li>if there are multiple definitions, they are checked/executed in
      alphabetically sorted name oder.</li>
      </ul>
      Examples:
      <ul><code>
        define s1 cmdalias shutdown update AS save;;shutdown<br>
        define s2 cmdalias set lamp .* AS { Log 1, "$EVENT";; fhem("set $EVENT") }
      </code></ul>
    </ul>
  </ul>
</ul>

=end html
=cut
