######################################################
# CUL InfraRed handler as FHM-Module
#
# (c) Olaf Droegehorn / DHS-Computertechnik GmbH
# 
# Published under GNU GPL License
######################################################
# $Id$
package main;

use strict;
use warnings;

sub CUL_IR_Define($$);
sub CUL_IR_Undef($$);
sub CUL_IR_Initialize($);
sub CUL_IR_Parse($$);
sub CUL_IR_SendCmd($$);
sub CUL_IR_Set($@);
sub CUL_IR_Attr(@);


my %sets = (
  "irLearnForSec" => "",
  "irSend" => ""
);


sub
CUL_IR_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^I............";
  $hash->{DefFn}     = "CUL_IR_Define";
  $hash->{UndefFn}   = "CUL_IR_Undef";  
  $hash->{ParseFn}   = "CUL_IR_Parse";
  $hash->{SetFn}     = "CUL_IR_Set";
  $hash->{AttrFn}       = "CUL_IR_Attr";  
  $hash->{AttrList}  = "do_not_notify:1,0 ignore:0,1 " .
                       "loglevel:0,1,2,3,4,5,6 learnprefix learncount " .
                       "Button.* Group.* irReceive:OFF,ON,ON_NR";
}


#############################
sub
CUL_IR_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $testhash = "";

  my $u = "wrong syntax: define <name> CUL_IR <IODEV:CUL/CUN_Device>";

  return $u if(int(@a) < 3);

  #Assign CUL/CUN within definition as IODev
  for my $p (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {
  
      my $cl = $defs{$p}{Clients};
      $cl = $modules{$defs{$p}{TYPE}}{Clients} if(!$cl);

    if((defined($cl) && $cl =~ m/:CUL_IR:/) &&
       $defs{$p}{NAME} eq $a[2]) {    
          $hash->{IODev} = $defs{$p}; 
          last;  
        }
    }
    if(!$hash->{IODev}) {
      Log 3, "No I/O device found for $hash->{NAME}";
      return "Wrong IODev specified or IODev doesn't support CUL_IR";
  }
  
  #Check if we have already an CUL_IR Device for IODEV
  foreach my $name (keys %{ $modules{CUL_IR}{defptr} }) {
     $testhash = ($modules{CUL_IR}{defptr}{$name})
        if($modules{CUL_IR}{defptr}{$name}->{IODev} == $hash->{IODev});
  }
    if ($testhash) {    #found another CUL_IR for this IODEV!!
      Log 2, "CUL_IR already defined for this I/O device";
      return "CUL_IR already defined for this I/O device, it's: $testhash->{NAME}";
    }  

    #Everything is fine, let's finish definition
  $modules{CUL_IR}{defptr}{("IR_" . $a[2])} = $hash;
  $hash->{STATE} = "Initialized";
  if (!$attr{$hash->{NAME}}{'learnprefix'}) {
      $attr{$hash->{NAME}}{'learnprefix'} = "A";
  }
  if (!$attr{$hash->{NAME}}{'learncount'}) {
      $attr{$hash->{NAME}}{'learncount'} = 0;
  }
  
     Log 4, "Sending $hash->{IODev}->{NAME}: Ir";
  my $msg = CallFn($hash->{IODev}->{NAME}, "GetFn", $hash->{IODev}, (" ", "raw", "Ir"));
     Log 4, "Answer from $hash->{IODev}->{NAME}: $msg";

  if ($msg =~ m/raw => 00/) {
        $hash->{irReceive} = "OFF";
    } elsif ($msg =~ m/raw => 01/) {
         $hash->{irReceive} = "ON";
     } elsif ($msg =~ m/raw => 02/) {
         $hash->{irReceive} = "ON_NR";
    } elsif ($msg =~ m/No answer/) {
          $hash->{irReceive} = "NoAnswer";
  } else {
      Log 2, "CUL_IR IODev device didn't answer Ir command correctly: $msg";
      $hash->{irReceive} = "UNKNOWN";
  }
   
  return undef;
}

#############################
sub
CUL_IR_Undef($$)
{
  my ($hash, $name) = @_;

  # As after a rename the $name my be different from the $defptr{$n}
  # we look for the hash.
  foreach my $name (keys %{ $modules{CUL_IR}{defptr} }) {
    delete($modules{CUL_IR}{defptr}{$name})
      if($modules{CUL_IR}{defptr}{$name} == $hash);
  }

  return undef;
}


#############################
sub
CUL_IR_Parse($$)
{
  my ($iohash, $msg) = @_;
  my $myhash = "";
  my $found  = 0;
      
  foreach my $name (keys %{ $modules{CUL_IR}{defptr} }) {
     $myhash = ($modules{CUL_IR}{defptr}{$name})
        if($modules{CUL_IR}{defptr}{$name}->{IODev} == $iohash);
  }

    if(!$myhash) {
        Log 4, "IR-Message from $iohash->{NAME}: $msg";
      Log 2, "No CUL_IR device found for $iohash->{NAME}, please define a new one";
      return "UNDEFINED CUL_IR_$iohash->{NAME} CUL_IR $iohash->{NAME}";
  }

     Log 4, "IR-Reception: $msg";

    # Search for Button-Group
  foreach my $name (keys %{ $attr{$myhash->{NAME}} }) {
       if ($name =~ m/^Group.*/) {
           my ($ir, $cmd) = split("[ \t]", $attr{$myhash->{NAME}}{$name}, 2);
           if ($msg =~ m/$ir.*/) {
              if (!$cmd) {
                 Log 5, "Group found; IR:$ir Def:-";
               } else {
                  Log 5, "Group found; IR:$ir Def:$cmd";
                  AnalyzeCommandChain(undef, $cmd);
               }
           }
      }
  }

    # Search for single Button(s)
  foreach my $name (keys %{ $attr{$myhash->{NAME}} }) {
       if ($name =~ m/^Button.*/) {
           my ($ir, $cmd) = split("[ \t]", $attr{$myhash->{NAME}}{$name}, 2);
           if ($msg eq $ir) {
               $found++;
               if (!$cmd) {
                 Log 5, "Button found; IR:$ir Def:-";
               } else {
                 Log 5, "Button found; IR:$ir Def:$cmd";
                 AnalyzeCommandChain(undef, $cmd);
               }
           }
      }
  }
  
  if (!$found) {    # No Button identified yet !!
      if (!$myhash->{irLearn}) {  # OK, No Learning, then leave
          return "";
      } else {    # Let's learn Buttons
          my $buttonname = "";
          if (!$attr{$myhash->{NAME}}{'learncount'}) {
              $attr{$myhash->{NAME}}{'learncount'} = 0;
          }
          if (!$attr{$myhash->{NAME}}{'learnprefix'}) {    # is the learnprefix there?
              $buttonname = sprintf("Button%03d", $attr{$myhash->{NAME}}{'learncount'});      
          } else {
                $buttonname = sprintf("Button%s%03d", $attr{$myhash->{NAME}}{'learnprefix'}, $attr{$myhash->{NAME}}{'learncount'});      
            }
            $attr{$myhash->{NAME}}{'learncount'}++;    
            $attr{$myhash->{NAME}}{$buttonname} = $msg;
      }
  }

  return "";
}

sub
CUL_IR_RemoveIRLearn($)
{
  my $hash = shift;
  delete($hash->{irLearn});
}

###################################
sub
CUL_IR_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set CUL_IR\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
      if(!defined($sets{$a[1]}));

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join("", @a);
  my $ll = GetLogLevel($name,3);
  my $ret = "";
  my $reccommand = "";

  if($type eq "irLearnForSec") { ####################################
    return "Usage: set $name irLearnForSec <seconds_active>"
        if(!$arg || $arg !~ m/^\d+$/);
    $hash->{irLearn} = 1;
    InternalTimer(gettimeofday()+$arg, "CUL_IR_RemoveIRLearn", $hash, 1);
  } 
  
  if($type eq "irSend") { ####################################
    return "Usage: set $name irSend <IR-Code | ButtonName>"
        if(!$arg || $arg !~ m/^\w+$/); 
        CUL_IR_SendCmd ($hash, $arg);
  } 

  return $ret;
}

    
###################################
sub
CUL_IR_SendCmd($$)
{
  my ($hash, $arg) = @_;
  my $l4 = GetLogLevel($hash->{NAME},4);
  my $found  = 0;
  my $ir;
  my $cmd;
  my $bcmd;

  if ($arg =~ m/^Button.*/) {        #Argument is a ButtonName
      # Search for single Button(s)
      foreach my $name (keys %{ $attr{$hash->{NAME}} }) {
           if ($name eq $arg) {
               ($ir, $bcmd) = split("[ \t]", $attr{$hash->{NAME}}{$name}, 2);
               $found++;
           }
      }
      if (!$found) { 
          Log 2, "$hash->{NAME}->irSend: No Button found with name $arg, please define/learn a new one";
          return "$hash->{NAME}: Unknown button name $arg";
      }
      $cmd = sprintf("Is%s", substr($ir, 1));
  } else {
      if (length ($arg) == 12) {
          if ($arg  =~ m/^[0-9A-F]+$/) {
              $cmd = sprintf("Is%s", $arg);
          } else {
                  Log 2, "$hash->{NAME}->irSend: Wrong IR-Code";
                  return "$hash->{NAME}: Wrong IR-Code";
          }
      } elsif (length ($arg) == 13) {
              if (substr($arg, 0, 1) eq "I") {
                  if (substr($arg, 1) =~ m/^[0-9A-F]+$/) {
                      $cmd = sprintf("Is%s", substr($arg, 1));
                  } else {
                          Log 2, "$hash->{NAME}->irSend: Wrong IR-Code";
                          return "$hash->{NAME}: Wrong IR-Code";
                  }
              } else {
                  Log 2, "$hash->{NAME}->irSend: Wrong IR-Code";
                  return "$hash->{NAME}: Wrong IR-Code";
              }
      } else {
              Log 2, "$hash->{NAME}->irSend: Wrong IR-Code";
              return "$hash->{NAME}: Wrong IR-Code";
      }
          
  }
  Log $l4, "$hash->{NAME} SEND $cmd";
  IOWrite($hash, "", $cmd);
}

sub
CUL_IR_Attr(@)
{
  my @a = @_;

  if($a[2] eq "irReceive") {

    my $name = $a[1];
    my $hash = $defs{$name};
    my $reccommand = "";

    if($a[3] eq "OFF") {
        $reccommand = "00";
    } elsif ($a[3] eq "ON") {
        $reccommand = "01";
    } else {
        $reccommand = "02";        
    }

      my $io = $hash->{IODev};
            
      Log 4, "Sending $io->{NAME}: Ir$reccommand";
      my $msg = CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", "Ir".$reccommand));
      Log 4, "Answer from $io->{NAME}: $msg";

    if ($msg =~ m/raw => 00/) {
          $hash->{irReceive} = "OFF";
      } elsif ($msg =~ m/raw => 01/) {
          $hash->{irReceive} = "ON";
      } elsif ($msg =~ m/raw => 02/) {
          $hash->{irReceive} = "ON_NR";
      } elsif ($msg =~ m/No answer/) {
          $hash->{irReceive} = "NoAnswer";
      } else {
          Log 2, "CUL_IR IODev device didn't answer Ir command correctly: $msg";
          $hash->{irReceive} = "UNKNOWN";
      }

    Log 2, "Switched $name irReceive to $hash->{irReceive}";

  }
 
  return undef;
}

1;

=pod
=begin html

<a name="CUL_IR"></a>
<h3>CUL_IR</h3>
<ul>

  The CUL_IR module interprets Infrared messages received by the CUN/CUNO/CUNOv2/TuxRadio.
  Those devices can receive Infrared Signals from basically any Remote controller and will transform
  that information in a so called Button-Code  <br><br>


  <a name="CUL_IRdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_IR &lt;<a href="#IODev">IODev</a>&gt;</code> <br>
    <br>
    &lt;<a href="#IODev">IODev</a>&gt; is the devicename of the IR-receivung device, e.g. CUNO1.<br><br>

    Your definition should look like E.g.:
    <pre>
    define IR-Dev CUL_IR CUNO1</pre>
  </ul>

  <a name="CUL_IRset"></a>
  <b>Set</b>
  <ul>
    <a name="irLearnForSec"></a>
    <li>irLearnForSec<br>
       Sets the CUL_IR device in an IR-Code Learning mode for the given seconds. Any received IR-Code will
       be stored as a Button attribute for this devices. The name of these attributes is dependent on the two
       attributes <a href="#CUL_IRattr">learncount</a> and <a href="#CUL_IRattr">learnprefix</a>.<br>
       Attention: Before learning IR-Codes the CUL_IR device needs to be set in IR-Receiving mode
       by modifying the <a href="#irReceive">irReceive</a> attribute.
     </li>
    <a name="irSend"></a>
    <li>irSend<br>
       Sends out IR-commands via the connected IODev. The IR-command can be specified as buttonname according
	   to <a href="#Button.*">Button.*</a> or as IR-Code directly. If a buttonname is specified, the
	   corresponding IR-Code will be sent out.<br>
	   Example: <br>
   	   <pre>set IR-Dev irSend ButtonA001 </pre>
	   If defining an IR-Code directly the following Code-Syntax needs to be followed:<br>
	   <pre>IRCode: &lt;PP&gt;&lt;AAAA&gt;&lt;CCCC&gt;&lt;FF&gt; </pre>
	   with P = Protocol; A = Address; C = Command; F = Flags<br>
	   With the Flags you can modify IR-Repetition. Flags between 00-0E will produce
	   0-15 IR-Repetitions.
	   You can type the IR-Code as plain as above, or with a heading "I" as learnt for the buttons.<br>
	   Example: <br>
   	   <code>set IR-Dev irSend 0A07070F0F02<br>
	   set IR-Dev irSend I0A07070F0F00 </code>

     </li>
  </ul>

  <a name="CUL_IRget"></a>
  <b>Get</b>
  <ul>N/A</ul>

  <a name="CUL_IRattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li><a href="#irReceive">irReceive</a><br>
        Configure the IR Transceiver of the &lt;<a href="#IODev">IODev</a>&gt; (the CUNO1). Available
        arguments are:
        <ul>
        <li>OFF<br>
            Switching off the reception of IR signals. This is the default.

        <li>ON<br>
            Switching on the reception of IR signals. This is WITHOUT filtering repetitions. This is
            not recommended as many remote controls do repeat their signals.

        <li>ON_NR<br>
            Switching on the reception of IR signals with filtering of repetitions. This is
            the recommended modus operandi.
        </ul>
    </li><br>

	<li><a name="Button.*"></a>Button.*<br>
        Button.* is the wildcard for all learnt IR-Codes. IR-Codes are learnt as Button-Attributes.
        The name for a learnt Button - IR-Code is compiled out of three elements:<br>
        <pre>
        Button&lt;learnprefix&gt;&lt;learncount&gt;
        </pre>
        When the CUL_IR device is set into <a href="#irLearnForSec">learning mode</a> it will generate a
        new button-attribute for each new IR-Code received.This is done according to the following syntax:<br>
        <pre>
        &lt;Button-Attribute-Name&gt; &lt;IR-Code&gt;</pre>
        Examples of learnt button-attributes with EMPTY &lt;learnprefix&gt; and &lt;learncount&gt; starting from 1:<br>
        <pre>
        Button001   I02029A000000
        Button002   I02029A000001</pre>
        To make sure that something happens when this IR-code is received later on one has to modify the attribute
        and to add commands as attribute values.
        Examples:
        <pre>
        Button001   I02029A000000   set WZ_Lamp on
        Button002   I02029A000001   set Switch on</pre>
        The syntax for this is:
        <pre>
        attr &lt;device-name&gt; &lt;attribute-name&gt; &lt;IR-Code&gt; &lt;command&gt;
        </pre>
    </li>
    <li><a name="Group.*"></a>Group.*<br>
        Group.* is the wildcard for IR-Code groups. With these attributes one can define
        IR-Code parts, which may match to several Button-IR-Codes.<br>
        This is done by defining group-attributes that contain only parts of the IR-Code.
        The syntax is:
        <pre>
        &lt;Group-Attribute-Name&gt; &lt;IR-Code&gt;</pre>
        Examples of a group-attribute is:<br>
        <pre>
        Group001   I02029A</pre>
        With this all IR-Codes starting with I02029A will match the Group001.
    </li><br>
    <li><a name="learncount"></a>learncount<br>
        learncount is used to store the next button-code-number that needs to be learned.
        By manually modifying this attribute new button sequences can be arranged.
    </li><br>
    <li><a name="learnprefix"></a>learnprefix<br>
        learnprefix is a string which will be added to the button-attribute-name. <br>
        A button-attribute-name is constructed by:
        <pre>
        Button&lt;learnprefix&gt;&lt;learncount&gt;    </pre>
        If learnprefix is empty the button-attribute-name only contains the term
        "Button" and the actual number of <a href="#learncount">learncount</a>.
    </li><br>
  </ul>
  <br>
</ul>


=end html
=cut
