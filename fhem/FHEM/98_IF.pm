##############################################
# $Id:$
package main;
use strict;
use warnings;
use POSIX;

sub CommandIF($$);
sub GetBlockIf ($$);
sub CmdIf($);
sub ReplaceReadingsIf($);
sub ReplaceAllReadingsIf($$);
sub ParseCommandsIf($);
sub EvalAllIf($);
sub InternalIf($$$);
sub ReadingValIf($$$);


#####################################
sub
IF_Initialize($$)
{
  my %lhash = ( Fn=>"CommandIF",
                Hlp=>"(<condition>) (<FHEM commands>) ELSE (<FHEM commands>), executes FHEM commands depending on the condition"); 
  $cmds{IF} = \%lhash;
}

sub 
GetBlockIf ($$)
{
  my ($cmd,$match) = @_;
  my $count=0;
  my $first_pos=0;
  my $last_pos=0;
  my $err="";
  while($cmd =~ /$match/g) {
    if (substr($cmd,pos($cmd)-1,1) eq substr($match,2,1)) {
      $count++;
      $first_pos=pos($cmd) if ($count == 1);
    } elsif (substr($cmd,pos($cmd)-1,1) eq substr($match,4,1)) {
      $count--;
      
    }
    if ($count < 0)
    {
      $err="right bracket without left bracket";
      return ("",substr($cmd,pos($cmd)-1),$err,"");
    }
    
    if ($count == 0) {
      $last_pos=pos($cmd);
      last;
    }
  }
  if ($count > 0) {
    $err="no right bracket";
    return ("",substr($cmd,$first_pos-1),$err);
  }
  if ($first_pos) {
    return (substr($cmd,0,$first_pos-1),substr($cmd,$first_pos,$last_pos-$first_pos-1),"",substr($cmd,$last_pos));
  } else {
    return ($cmd,"","","");
  }
}

sub
InternalIf($$$)
{
  my ($name,$internal,$regExp)=@_;
  my $r="";
  my $element;
    $r=$defs{$name}{$internal};
    if ($regExp) {
      $element = ($r =~  /$regExp/) ? $1 : "";
    } else {
      $element=$r;
    }
    return($element);
}

sub
ReadingValIf($$$)
{
  my ($name,$reading,$regExp)=@_;
  my $r="";
  my $element;
    $r=$defs{$name}{READINGS}{$reading}{VAL};
    if ($regExp) {
      $element = ($r =~  /$regExp/) ? $1 : "";
    } else {
      $element=$r;
    }
    return($element);
}

sub
ReplaceReadingIf($)
{
  my ($element) = @_;
  my $beginning;
  my $tailBlock;
  my $err;
  my $regExp="";
  my ($name,$reading,$format)=split(":",$element);
  my $internal="";
  if ($name) {
    return ($name,"unknown Device") if(!$defs{$name});
    if ($reading) {
      if (substr($reading,0,1) eq "\&") {
        $internal = substr($reading,1);
        return ($name.":".$internal,"unknown internal") if(!$defs{$name}{$internal});
      } else {
          return ($name.":".$reading,"unknown reading") if(!$defs{$name}{READINGS}{$reading});
      }
      if ($format) {
        if ($format eq "d") {
          $regExp = '(-?\d+(\.\d+)?)';
        } elsif (substr($format,0,1) eq '[') {
            ($beginning,$regExp,$err,$tailBlock)=GetBlockIf($format,'[\[\]]');
            return ($regExp,$err) if ($err);
            return ($regExp,"no round brackets in regular expression") if ($regExp !~ /.*\(.*\)/);
          } else {
            return($format,"unknown expression format");
          }  
      } 
      if ($internal) {
        return("InternalIf('$name','$internal','$regExp')","");
      } else {
        return("ReadingValIf('$name','$reading','$regExp')","");
      }
    } else {
      return("InternalIf('$name','STATE','$regExp')","");
    }
  }
}

sub
ReplaceAllReadingsIf($$)
{
  my ($tailBlock,$evalFlag)= @_;
  my $block="";
  my $beginning;
  my $err;
  my $cmd="";
  my $ret="";
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockIf($tailBlock,'[\[\]]');
    return ($block,$err) if ($err);
    if ($block ne "") {
      if ($block =~ /:/ or ($block =~ /[a-z]/i and $block =~ /^[a-z0-9._]*$/i))
      {
        ($block,$err)=ReplaceReadingIf($block);
        return ($block,$err) if ($err);
        if ($evalFlag) {
          my $ret = eval $block;
          return($block." ",$@) if ($@);
  #        return($eval,"no reading value") if (!$ret);
          $block=$ret;
        }
      } else {
        $block="[".$block."]";
      }
    }
    $cmd.=$beginning.$block;
  }
  return ($cmd,"");
}

sub
EvalAllIf($)
{
  my ($tailBlock)= @_;
  my $eval="";
  my $beginning;
  my $err;
  my $cmd="";
  my $ret="";
  
  while ($tailBlock ne "") {
    ($beginning,$eval,$err,$tailBlock)=GetBlockIf($tailBlock,'[\{\}]');
    return ($eval,$err) if ($err);
    if ($eval) {
        my $ret = eval $eval;
        return($eval." ",$@) if ($@);
        $eval=$ret;
     }
    $cmd.=$beginning.$eval;
  }
  return ($cmd,"");
}

sub
ParseCommandsIf($)
{
  my($tailBlock) = @_;
  my $currentBlock="";
  my $beginning="";
  my $err="";
  my $parsedCmd="";
  my $pos=0;

  while ($tailBlock ne "") {
    if ($tailBlock=~ /^\s*\{/) { # perl block
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockIf($tailBlock,'[\{\}]'); 
      return ($currentBlock,$err) if ($err);
      return($currentBlock, 'use "'." instead of '") if ($currentBlock =~ /'/);
      $parsedCmd.="{".$currentBlock."}";
    }
    if ($tailBlock =~ /^\s*IF/) {
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockIf($tailBlock,'[\(\)]'); #condition
      return ($currentBlock,$err) if ($err);
      $parsedCmd.=$beginning."(".$currentBlock.")";
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockIf($tailBlock,'[\(\)]'); #if case
      return ($currentBlock,$err) if ($err);
      $parsedCmd.=$beginning."(".$currentBlock.")";
      if ($tailBlock =~ /^\s*ELSE/) {
        ($beginning,$currentBlock,$err,$tailBlock)=GetBlockIf($tailBlock,'[\(\)]'); #else case
        return ($currentBlock,$err) if ($err);
      $parsedCmd.=$beginning."(".$currentBlock.")";
      }
    } else { #repalce Readings if no IF command
      if ($tailBlock =~ /^\s*\(/) { # remove bracket  
        ($beginning,$currentBlock,$err,$tailBlock)=GetBlockIf($tailBlock,'[\(\)]'); 
        return ($currentBlock,$err) if ($err);
        $tailBlock=substr($tailBlock,pos($tailBlock)) if ($tailBlock =~ /^\s*,/g);
      } elsif ($tailBlock =~ /,/g) {
          $pos=pos($tailBlock)-1;
          $currentBlock=substr($tailBlock,0,$pos);
          $tailBlock=substr($tailBlock,$pos+1);
        } else {
          $currentBlock=$tailBlock;
          $tailBlock="";
        }
       if ($currentBlock ne "") {
         return($currentBlock, 'use "'." instead of '") if ($currentBlock =~ /'/);
         ($currentBlock,$err)=ReplaceAllReadingsIf($currentBlock,1);
         return ($currentBlock,$err) if ($err);
         ($currentBlock,$err)=EvalAllIf($currentBlock);
         $currentBlock =~ s/;/;;;;/g;
         return ($currentBlock,$err) if ($err);
         $parsedCmd.=$currentBlock;
         $parsedCmd.=";;" if ($tailBlock);
       } else {
         $parsedCmd.=";;" if ($tailBlock);
       }
    }
  }
  return($parsedCmd,"");
}

sub
CmdIf($)
{
  my($cmd) = @_;
  my $cond="";
  my $err="";
  my $if_cmd="";
  my $else_cmd="";
  my $tail;
  my $tailBlock;
  my $eval="";
  my $beginning;
  
  $cmd =~ s/\n//g;
  return($cmd, "no left bracket") if ($cmd !~ /^ *\(/);
  ($beginning,$cond,$err,$tail)=GetBlockIf($cmd,'[\(\)]');
  return ($cond,$err) if ($err); 
  ($cond,$err)=ReplaceAllReadingsIf($cond,0);
  return ($cond,$err) if ($err); 
  return ($cmd,"no condition") if ($cond eq "");
  if ($tail =~ /^\s*\(/) {
    ($beginning,$if_cmd,$err,$tail)=GetBlockIf($tail,'[\(\)]');
    return ($if_cmd,$err) if ($err);
    ($if_cmd,$err)=ParseCommandsIf($if_cmd);
    return ($if_cmd,$err) if ($err);
    return ($cmd,"no commands") if ($if_cmd eq "");
  } else {
    return($tail, "no left bracket");
  }
  return ($if_cmd,$err) if ($err);
  if (length($tail)) {
    $tail =~ /^\s*ELSE/g;
    if (pos($tail)) {
      $tail=substr($tail,pos($tail));
      if (!length($tail)) {
        return ($tail,"no else block");
      }
    } else {
      return ($tail,"expected ELSE");
    }
    if ($tail =~ /^\s*\(/) {
      ($beginning,$else_cmd,$err,$tail)=GetBlockIf($tail,'[\(\)]');
       return ($else_cmd,$err) if ($err);
       ($else_cmd,$err)=ParseCommandsIf($else_cmd);
       return ($else_cmd,$err) if ($err);
    } else {
      return($tail, "no left bracket");
    }
    return ($else_cmd,$err) if ($err);
  }
  my $perl_cmd="{if(".$cond.")";
  $perl_cmd .="{fhem('".$if_cmd."')}";
  $perl_cmd .= "else{fhem('".$else_cmd."')}" if ($else_cmd);
  $perl_cmd.="}";
  return($perl_cmd,"");
}

sub
CommandIF($$)
{
  my ($cl, $param) = @_;
  return "Usage: IF (<condition>) (<FHEM commands>) ELSE (<FHEM commands>)\n" if (!$param);
  my $ret;
  #print ("vor IF:$param\n");
  my ($cmd,$err)=CmdIf($param);
  #print ("nach IF:$cmd\n");
  if ($err ne "") {
    $ret="IF: $err: $cmd";
  } else {
    $ret = AnalyzeCommandChain(undef,$cmd);
    use strict "refs";
  }
  return $ret;
}  


1;

=pod
=begin html

<a name="IF"></a>
<h3>IF</h3>
<ul>
  <code>IF (&lt;condition&gt;) (&lt;FHEM commands1&gt;) ELSE (&lt;FHEM commands2&gt;)</code><br>
  <br>
  Executes &lt;FHEM commands1&gt; if &lt;condition&gt; is true, else &lt;FHEM commands2&gt; are executed.<br>
  <br>
  IF can be used anywhere where FHEM commands can be used.<br>
  <br>
  The ELSE-case is optional.<br>
  <br>
  The &lt;condition&gt; is the same as in perl-if.<br>
  <br>
  In addition, readings can be specified in the form:<br>
  <br>
  [&lt;device&gt;:&lt;reading&gt;:&lt;format&gt;|[&lt;regular expression&gt;]]<br>
  <br>
  In addition, internals can be specified with & in the form:<br>
  <br>
  [&lt;device&gt;:&&lt;internal&gt;:&lt;format&gt;|[&lt;regular expression&gt;]]<br>
  <br>
  &lt;format&gt; and [&lt;regular expression&gt;] are filter options und are optional.<br>
  <br>
  possible &lt;format&gt;:<br>
  <br>
  'd' for decimal number<br>
  <br>
  If only the state of a device is to be used, then only the device can be specified:<br>
  <br>
  <code>[&lt;device&gt;]</code> corresponsed to <code>[&lt;device&gt;:&STATE]</code><br>
  <br>
  <b>Examples:</b><br>
  <br>
  IF in combination with at-module, Reading specified in the condition:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:humidity] > 70) (set switch1 off) ELSE (set switch1 on)<br></code>
  <br>
  IF state query of the device "outdoor" in the condition:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor] eq "open") (set switch1 on)<br></code>
  <br>
  corresponds with details of the internal:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:&STATE] eq "open") (set switch1 on)<br></code>
  <br>
  If the reading "state" to be queried, then the name of reading is specified without &:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:state] eq "open") (set switch1 on)<br></code>
  <br>
  Nested IF commands (It can be entered in the DEF input on multiple lines with indentation for better representation):<br>
  <br>
  <code>define test notify lamp <br>
  IF ([lampe] eq "on") (<br>
  <ol>
    IF ([outdoor:humidity] < 70)<br>
    <ol>(set lamp off)</ol>
    ELSE<br>
    <ol>(set lamp on)</ol>
  </ol>
  ) ELSE<br>
    <ol>(set switch on)</ol><br>
  </code>
  Filter by numbers in Reading "temperature":<br>
  <br>
  <code>define settemp at 22:00 IF ([tempsens:temperature:d] >= 10) (set heating on)<br></code>
  <br>
  Filter by "on" and "off" in the status of the device "move":<br>
  <br>
  <code>define activity notify move IF ([move:&STATE:[(on|off)] eq "on" and $we) (set lamp off)<br></code>
  <br>
  Example of the use of Readings in the then-case:<br>
  <br>
  <code>define temp at 18:00 IF ([outdoor:temperature] > 10) (set lampe [dummy])<br></code>
  <br>
  If an expression is to be evaluated first in a FHEM command, then it must be enclosed in braces.<br>
  For example, if at 18:00 clock the outside temperature is higher than 10 degrees, the desired temperature is increased by 1 degree:<br>
  <br>
  <code>define temp at 18:00 IF ([outdoor:temperature] > 10) (set thermostat desired-temp {[thermostat:desired-temp:d]+1})<br></code>
  <br>
  Multiple commands are separated by a comma instead of a semicolon, thus eliminating the doubling, quadrupling, etc. of the semicolon:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:humidity] > 10) (set switch1 off,set switch2 on) ELSE (set switch1 on,set switch2 off)<br></code>
  <br>
  If a comma in FHEM expression occurs, this must be additionally bracketed so that the comma is not recognized as a delimiter:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:humidity] > 10) ((set switch1,switch2 off))<br></code>
  <br>
  IF in combination with a define at multiple set commands:<br>
  <br>
  <code>define check at *10:00 IF ([indoor] eq "on") (define a_test at +00:10 set lampe1 on;;set lampe2 off;;set temp desired 20)<br></code>
  <br>
  The comma can be combined as a separator between the FHEM commands with double semicolon, eg:<br>
  <br>
  <code>define check at *10:00 IF ([indoor] eq "on") (set lamp1 on,define a_test at +00:10 set lampe2 on;;set lampe3 off;;set temp desired 20)<br></code>
  <br>
  Time-dependent switch: In the period 20:00 to 22:00 clock the light should go off when it was on and I leave the room:<br>
  <br>
  <code>define n_lamp_off notify sensor IF ($hms gt "20:00" and $hms lt "22:00" and [sensor] eq "absent") (set lamp:FILTER=STATE!=off off)<br></code>
  <br>
  Combination of Perl and FHEM commands ($NAME and $EVENT can also be used):<br>
  <br>
  <code>define mail notify door:open IF ([alarm] eq "on")({system("wmail $NAME:$EVENT")},set alarm_signal on)<br></code>
</ul>

=end html
=begin html_DE

<a name="IF"></a>
<h3>IF</h3>
<ul>
  <code>IF (&lt;Bedingung&gt;) (&lt;FHEM-Kommandos1&gt;) ELSE (&lt;FHEM-Kommandos2&gt;)</code><br>
  <br>
  Es werden <code>&lt;FHEM-Kommandos1&gt;</code> ausgeführt, wenn <code>&lt;Bedingung&gt;</code> erfüllt ist, sonst werden <code>&lt;FHEM-Kommanodos2&gt;</code> ausgeführt.<br>
  <br>
  Beim IF-Befehl handelt es sich um einen FHEM-Befehl. Der Befehl kann überall dort genutzt werden, wo FHEM-Befehle vorkommen dürfen.
  Im Gegensatz zu Perl-if bleibt man auf der FHEM-Ebene und muss nicht auf die Perl-Ebene, um FHEM-Befehle mit Hilfe der fhem-Funktion auszuführen.<br>
  <br>
  IF ist kein eigenständig arbeitendes Modul, sondern ein FHEM-Befehl, der in Kombination mit anderen Modulen, wie z. B. notify oder at, sinnvoll eingesetzt werden kann.<br>
  <br>
  In der Bedingung des IF-Befehls wird die vollständige Syntax des Perl-if unterstützt. Mögliche Operatoren sind u. a.:<br>
  <br>
  ++ -- Inkrementieren, Dekrementieren<br>
  ** Potenzierung<br>
  ! ~ logische und bitweise Negation<br>
  =~ !~ Bindung an Seite reguläre Ausdrücke<br>
  * / % x Multiplikation, Division, Modulo-Operation, Zeichenkettenwiederholung<br>
  + - . Addition, Subtraktion, Zeichenkettenaddition<br>
  < <= > >= lt le gt ge Vergleich größer/kleiner<br>
  == != eq ne Gleichheit/Ungleichheit<br>
  & bitweises UND<br>
  | ^ bitweises ODER - inklusiv/exklusiv<br>
  && logisches UND<br>
  || logisches ODER<br>
  not                            logische Negation<br>
  and                            logisches UND<br>
  or xor                         logisches ODER (inklusiv/exklusiv)<br>
<br>
<b>Features:</b><br>
<br>
<ul>
 <li>Angabe von Readings und Internals ist an beliebiger Stelle möglich<br></li>
<br>
 <li>Filtern nach Zahlen oder beliebigen Ausdrücken über reguläre Ausdrücke ist möglich<br></li>
<br>
 <li>IF kann beliebig mit anderen FHEM-Befehlen kombiniert werden (at, notify usw.)<br></li>
<br>
 <li>es können beliebig viele IF-Befehle ineinander geschachtelt werden<br></li>
<br>
 <li>Syntaxprüfung: fehlende Klammern werden erkannt<br></li>
<br>
 <li>Definition über mehrere Zeilen mit Einrückung zwecks übersichtlicher Darstellung ist möglich<br></li>
<br>
 <li>Überprüfung auf Existenz von Device und Reading bzw. Internal<br></li>
<br>
 <li>Ausführung von Perl-Befehlen im dann- und sonst-Fall ist weiterhin möglich<br></li>
<br>
 <li>Auswertung von Ausdrücken in geschweiften Klammen innerhalb eines FHEM-Befehls ist möglich<br></li>
<br>
 <li>ELSE-Fall ist optional<br></li>
 </ul>
<br>
<br>
  Die Syntax für die Nutzung von Readings oder Internals (ein Internal wird durch ein & gekennzeichnet)<br>
  <br>
  <code>[&lt;device&gt;:&lt;reading&gt;:&lt;format&gt;|[&lt;regulärer Ausdruck&gt]]</code>
  bzw. <code>[&lt;device&gt;:&&lt;internal&gt;:&lt;format&gt;|[&lt;regulärer Ausdruck&gt]]<br></code>
  <br>
  <code>&lt;format&gt;</code> und <code>[&lt;regulärer Ausdruck&gt;]</code> sind Filteroptionen, sie können optional genutzt werden.<br>
  <br>
  Mögliche Formatangaben für <code>&lt;format&gt;</code> sind:<br>
  <br>
  <code>'d'</code> zum Filtern von positiven und negatien Dezimalzahlen. <code>[&lt;device&gt;:&lt;reading&gt;:d]</code> entspricht <code>[&lt;device&gt;:&lt;reading&gt;:[(-?\d+(\.\d+)?)]]<br></code>
  <br>
  Wenn nur der Status eines Devices genutzt werden soll, dann kann auch nur das Device angeben werden:<br>
  <br>
  <code>[&lt;device&gt;]</code> entspricht <code>[&lt;device&gt;:&STATE]</code><br>
  <br>
  <b>Beispiele:</b><br>
  <br>
  IF in Kombination mit at-Modul, Readingangabe in der Bedingung:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:humidity] > 70) (set switch1 off) ELSE (set switch1 on)<br></code>
  <br>
  IF Statusabfrage des Devices "outdoor" in der Bedingung:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor] eq "open") (set switch1 on)<br></code>
  <br>
  entspricht mit Angabe des Internals:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:&STATE] eq "open") (set switch1 on)<br></code>
  <br>
  Wenn der Reading "state" abgefragt werden soll, dann wird der Readingname ohne & angegeben:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:state] eq "open") (set switch1 on)<br></code>
  <br>
  Geschachtelte Angabe von zwei IF-Befehlen (kann in mehreren Zeilen mit Einrückungen zwecks übersichtlicher Darstellung in der DEF-Eingabe eingegeben werden):<br>
  <br>
  <code>define test notify lamp <br>
  IF ([lamp] eq "on") (<br>
  <ol>
    IF ([outdoor:humidity] < 70)<br>
    <ol>
      (set lamp off)<br>
    </ol>
    ELSE<br>
    <ol>
      (set lamp on)<br>
    </ol>
  </ol>
  ) ELSE<br>
    <ol>
     (set switch on)<br>
    </ol>
  <br></code>
  Filtern nach Zahlen im Reading "temperature":<br>
  <br>
  <code>define settemp at 22:00 IF ([tempsens:temperature:d] >= 10) (set heating on)<br></code>
  <br>
  Filtern nach "on" und "off" im Status des Devices "move":<br>
  <br>
  <code>define activity notify move IF ([move:&STATE:[(on|off)] eq "on" and $we) (set lamp off)<br></code>
  <br>
  Beispiel für die Nutzung von Readings im dann-Fall:<br>
  <br>
  <code>define temp at 18:00 IF ([outdoor:temperature] > 10) (set lampe [dummy])<br></code>
  <br>
  Falls bei einem FHEM-Befehl ein Ausdruck mit Readings zuvor ausgewertet werden soll, so muss er in geschweifte Klammern gesetzt werden.<br>
  Beispiel: Wenn um 18:00 Uhr die Außentemperatur höher ist als 10 Grad, dann wird die Solltemperatur um 1 Grad erhöht.<br>
  <br>
  <code>define temp at 18:00 IF ([outdoor:temperature] > 10) (set thermostat desired-temp {[thermostat:desired-temp:d]+1})<br></code>
  <br>
  Mehrerer Befehle werden durch ein Komma statt durch ein Semikolon getrennt, dadurch entfällt das Doppeln, Vervierfachen usw. des Semikolons:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:humidity] > 10) (set switch1 off,set switch2 on) ELSE (set switch1 on,set switch2 off)<br></code>
  <br>
  Falls ein Komma im FHEM-Ausdruck vorkommt, muss dieser zusätzlich geklammert werden, damit das Komma nicht als Trennzeichen erkannt wird:<br>
  <br>
  <code>define check at +00:10 IF ([outdoor:humidity] > 10) ((set switch1,switch2 off))<br></code>
  <br>
  IF in Kombination mit einem define at mit mehreren set-Befehlen (Eingabe muss wegen der Semikolons im DEF-Editor erfolgen,
  einfaches Semikolon ist nicht erlaubt - es würde vom FHEM-Parser "geschluckt" werden und beim IF nicht mehr ankommen):<br>
  <br>
  <code>define check at *10:00 IF ([indoor] eq "on") (define a_test at +00:10 set lampe1 on;;set lampe2 off;;set temp desired 20)<br></code>
  <br>
  Man kann die Problematik des Doppelns von Semikolons wie folgt umgehen:<br>
  <br>
  <code>define check at *10:00 IF ([indoor] eq "on") (define a_test at +00:10 IF (1) (set lampe1 on,set lampe2 off,set temp desired 20))<br></code>
  <br>
  Das Komma als Trennzeichen zwischen den FHEM-Befehlen lässt sich mit ;; kombinieren, z. B.:<br>
  <br>
  <code>define check at *10:00 IF ([indoor] eq "on") (set lamp1 on,define a_test at +00:10 set lampe2 on;;set lampe3 off;;set temp desired 20)<br></code>
  <br>
  Zeitabhängig schalten: In der Zeit zwischen 20:00 und 22:00 Uhr soll das Licht ausgehen, wenn es an war und ich den Raum verlasse:<br>
  <br>
  <code>define n_lamp_off notify sensor IF ($hms gt "20:00" and $hms lt "22:00" and [sensor] eq "absent") (set lamp:FILTER=STATE!=off off)<br></code>
  <br>
  Kombination von Perl und FHEM-Befehlen ($NAME sowie $EVENT können ebenso benutzt werden):<br>
  <br>
  <code>define mail notify door:open IF ([alarm] eq "on")({system("wmail $NAME:$EVENT")},set alarm_signal on)<br></code>
</ul>
=end html_DE
=cut
