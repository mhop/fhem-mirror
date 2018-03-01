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
  $hash->{AttrList} = "disable:0,1 disabledForIntervals";
}


##########################
sub
cmdalias_Define($$$)
{
  my ($hash, $def) = @_;

  if($def !~ m/^([^ ]*) cmdalias ([^ ]*)(.*) AS (.*)$/s) {
    my $msg =
      "wrong syntax: define <name> cmdalias <cmd> [parameter] AS command...";
    return $msg;
  }
  my ($name, $alias, $param, $newcmd) = ($1, $2, $3, $4);
  $param =~ s/^ *//;
  # Checking for misleading regexps
  return "Bad regexp: starting with *" if($param =~ m/^\*/);
  eval { qr/^$param$/ };
  return "$name: Bad regexp in $param: $@" if($@);
  $alias = lc($alias);
  $hash->{ALIAS} = $alias;
  $hash->{PARAM} = $param;
  $hash->{NEWCMD} = $newcmd;
  $hash->{STATE} = "defined";

  $cmdalias{$alias}{Alias}{$name} = $hash;
  $cmdalias{$alias}{OrigFn} = $cmds{$alias}{Fn}
    if($cmds{$alias} && 
       $cmds{$alias}{Fn} &&
       $cmds{$alias}{Fn} ne "CommandCmdAlias");
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
    my $doesMatch = $param =~ m/^$h->{PARAM}$/s; # Match multiline, #77285
    if($h->{InExec} && $doesMatch) {
      Log3 $n, 3, "cmdalias $n called recursively, skipping execution";
      next;
    }
    if($doesMatch && !IsDisabled($h->{NAME})) {
      my %specials= ("%EVENT" => $param);
      my $exec = EvalSpecials($h->{NEWCMD}, %specials);
      $h->{InExec} = 1;
      my $r =  AnalyzeCommandChain($cl, $exec);
      delete $h->{InExec};
      return $r;
    }
  }
  return undef if(!$a->{OrigFn});
  no strict "refs";
  return &{$a->{OrigFn} }($cl, $param, $alias);
  use strict "refs";
}

1;

=pod
=item command
=item summary    create new FHEM commands or replace internal ones
=item summary_DE neue FHEM Befehle definieren oder existierende &auml;ndern
=begin html

<a name="cmdalias"></a>
<h3>cmdalias</h3>
<ul>
  create new FHEM commands or replace internal ones.
  <br><br>

  <a name="cmdaliasdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; cmdalias &lt;cmd_to_be_replaced or new_cmd&gt;
                 [parameter] AS &lt;existing_cmd&gt;</code><br>
    <br>

    parameter is optional and is a regexp which must match the command
    entered.
    If it matches, then the specified &lt;existing_command&gt; will be
    executed, which is a FHEM command (see <a href="#command">FHEM command
    types</a> for details). Like in <a href="#notify">notify</a>, $EVENT or
    $EVTPART may be used, in this case representing the
    command arguments as whole or the unique words entered.<br>
  </ul>

  Notes:<ul>
  <li>recursion is not allowed.</li>
  <li>if there are multiple definitions, they are checked/executed in
  alphabetically sorted &lt;name&gt; oder.</li>
  </ul>
  Examples:
  <ul><code>
    define s1 cmdalias shutdown update AS save;;shutdown<br>
    define s2 cmdalias set lamp .* AS { Log 1, "$EVENT";; fhem("set $EVENT") }
  </code></ul>

  <a name="cmdaliasattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
  </ul>
</ul>

=end html
=cut

