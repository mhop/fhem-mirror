################################################################
# $Id$
################################################################

package main;
use strict;
use warnings;
use POSIX;

sub CommandJsonList2($$);

#####################################
sub
JsonList2_Initialize($$)
{
  my %lhash = ( Fn=>"CommandJsonList2",
                Hlp=>"[<devspec>],list definitions as JSON" );
  $cmds{jsonlist2} = \%lhash;
}


#####################################
sub
JsonList2_Escape($)
{
  my $a = shift;
  return "null" if(!defined($a));
  my %esc = (
    "\n" => '\n',
    "\r" => '\r',
    "\t" => '\t',
    "\f" => '\f',
    "\b" => '\b',
    "\"" => '\"',
    "\\" => '\\\\',
    "\'" => '\\\'',
  );
  $a =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/eg;
  return $a;
}

sub
JsonList2_dumpHash($$$$$$)
{
  my ($arrp, $name, $h, $isReading, $si, $attr) = @_;
  my $ret = "";
  
  my @arr = grep { $si || $_ !~ m/^\./ } sort keys %{$h};
  @arr = grep { !ref($h->{$_}) } @arr if(!$isReading);
  if($attr) {
    @arr = grep { $attr eq $_ } @arr;
  }

  for(my $i2=0; $i2 < @arr; $i2++) {
    my $k = $arr[$i2];
    $ret .= "      \"".JsonList2_Escape($k)."\": ";
    if($isReading) {
      $ret .= "{ \"Value\":\"".JsonList2_Escape($h->{$k}{VAL})."\",";
      $ret .=   " \"Time\":\"".JsonList2_Escape($h->{$k}{TIME})."\" }";
    } else {
      $ret .= "\"".JsonList2_Escape($h->{$k})."\"";
    }
    $ret .= "," if($i2 < int(@arr)-1);
    $ret .= "\n" if(int(@arr)>1);
  }
  return if($attr && !$ret);
  push(@{$arrp}, "    \"$name\": {".(int(@arr)>1 ? "\n" : "")."$ret    }");
}

#####################################
sub
CommandJsonList2($$)
{
  my ($cl, $param) = @_;
  my @d;
  my $ret;
  my $cnt=0;
  my $si = AttrVal("global", "showInternalValues", 0);
  my $attr;

  if($param) {
    my @arg = split(" ", $param);
    $attr = $arg[1];
    @d = devspec2array($arg[0]);

  } else {
    @d = keys %defs;
    $param="";

  }

  $ret  = "{\n";
  $ret .= "  \"Arg\":\"".JsonList2_Escape($param)."\",\n",
  $ret .= "  \"Results\": [\n";

  for(my $i1 = 0; $i1 < int(@d); $i1++) {
    my $d = $d[$i1];
    next if(IsIgnored($d));

    my $h = $defs{$d};
    my $n = $h->{NAME};
    next if(!$h || !$n);

    my @r;
    if(!$attr) {
      push(@r,"    \"PossibleSets\":\"".JsonList2_Escape(getAllSets($n))."\"");
      push(@r,"    \"PossibleAttrs\":\"".JsonList2_Escape(getAllAttr($n))."\"");
    }
    JsonList2_dumpHash(\@r, "Internals", $h,             0, $si, $attr);
    JsonList2_dumpHash(\@r, "Readings",  $h->{READINGS}, 1, $si, $attr);
    JsonList2_dumpHash(\@r, "Attributes",$attr{$d},      0, $si, $attr);

    next if(!@r);
    $ret .= ",\n" if($cnt);
    $ret .= "  {\n";
    $ret .= "    \"Name\":\"".JsonList2_Escape($n)."\",\n".join(",\n",@r)."\n";
    $ret .= "  }";
    $cnt++;
  }

  $ret .= "  ],\n";
  $ret .= "  \"totalResultsReturned\":$cnt\n";
  $ret .= "}\n";
  return $ret;
}

1;

=pod

=begin html

<a name="JsonList2"></a>
<h3>JsonList2</h3>
<ul>
  <code>jsonlist [&lt;devspec&gt;] [&lt;value&gt;]</code>
  <br><br>
  This is a command, to be issued on the command line (FHEMWEB or telnet
  interface). Can also be called via HTTP by
  <ul>
  http://fhemhost:8083/fhem?cmd=jsonlist2&XHR=1
  </ul>
  Returns an JSON tree of the internal values, readings and attributes of the
  requested definitions.<br>
  If value is specified, then output only the corresponding internal (like DEF,
  TYPE, etc), reading (actuator, measured-temp) or attribute for all devices
  from the devspec.<br><br>
  <b>Note</b>: the old command jsonlist (without the 2 as suffix) is deprecated
  and will be removed in the future<br>
</ul>

=end html

=begin html_DE

<a name="JsonList2"></a>
<h3>JsonList2</h3>
<ul>
  <code>jsonlist [&lt;devspec&gt;]</code>
  <br><br>
  Dieses Befehl sollte in der FHEMWEB oder telnet Eingabezeile ausgef&uuml;hrt
  werden, kann aber auch direkt &uuml;ber HTTP abgerufen werden &uuml;ber 
  <ul>
  http://fhemhost:8083/fhem?cmd=jsonlist2&XHR=1
  </ul>
  Es liefert die JSON Darstellung der internen Variablen, Readings und
  Attribute zur&uuml;ck.<br>

  Wenn value angegeben ist, dann wird nur der entsprechende Internal (DEF,
  TYPE, usw), Reading (actuator, measured-temp) oder Attribut
  zur&uuml;ckgeliefert f&uuml;r alle Ger&auml;te die in devspec angegeben sind.
  <br><br>
  <b>Achtung</b>: die alte Version dieses Befehls (jsonlist, ohne 2 am Ende) is
  &uuml;berholt, und wird in der Zukunft entfernt.<br>
</ul>

=end html_DE
=cut
