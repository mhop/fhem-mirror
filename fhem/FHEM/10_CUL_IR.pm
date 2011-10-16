######################################################
# CUL InfraRed handler as FHM-Module
#
# (c) Olaf Droegehorn / DHS-Computertechnik GmbH
# 
# Published under GNU GPL License
######################################################
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
