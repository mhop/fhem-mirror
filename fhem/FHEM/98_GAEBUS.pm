#############################################
# $Id$
# derived from 00_TUL.pm
#
# 17.07.2015 : A.Goebel : initiale Version mit loop, readingname via attribut, keine writes
# 21.07.2015 : A.Goebel : start implementation for "set .. write"
# 23.07.2015 : A.Goebel : event-on-change-reading added to attributes
# 08.09.2015 : A.Goebel : limit number of socket-open retries in GetUpdates loop
# 10.09.2015 : A.Goebel : fix html code of commandref
# 11.09.2015 : A.Goebel : add attribute "ebusWritesEnable:0,1"
# 11.09.2015 : A.Goebel : add set w~ commands to set attributes for writing 
# 11.09.2015 : A.Goebel : add set <write-reading> command to write to ebusd
# 13.09.2015 : A.Goebel : increase timeout for reads from ebusd from 1.8 to 5.0
# 14.09.2015 : A.Goebel : use utf-8 coding to display values from ".csv" files
# 14.09.2015 : A.Goebel : add optional parameter [FIELD[.N]] of read from ebusd to reading name
# 15.09.2015 : A.Goebel : get rid of perl warnings when attribute value is empty
# 16.09.2015 : A.Goebel : allow write to parameters protected by #install
# 21.09.2015 : A.Goebel : implement BlockingCall Interface
# 07.10.2015 : A.Goebel : beautify and complete commandref
# 12.10.2015 : A.Goebel : fix handling of timeouts in BlockingCall Interface (additional parameter in doEbusCmd forces restart (no shutdown restart))
#                         timeout for reads increased
# 19.10.2015 : A.Goebel : add attribute disable to disable loop to collect readings
# 05.11.2015 : A.Goebel : add support for "h" (broadcast update) commands from csv, handle them equal to (r)ead
# 09.11.2015 : A.Goebel : add support for multiple readings generated from one command to ebusd
#                         ebusd may return a list of values like "52.0;43.0;8.000;41.0;45.0;error"
#                         defining a reading "VL;RL;dummy;VLWW;RLWW" will create redings VL, RL, VLWW and RLWW
# 04.12.2015 : A.Goebel : add event-min-interval to attributes
# 14.12.2015 : A.Goebel : add read possible commmands for ebusd using "find -f" instead of reading the ".csv" files directly ("get ebusd_find")
# 25.01.2016 : A.Goebel : fix duplicate log entries for readings
# 05.02.2016 : A.Goebel : add valueFormat attribute
# 18.08.2016 : A.Goebel : fix workarround for perl warning with keys of hash reference
# 30.08.2016 : A.Goebel : add reading "state_ebus" containing output from "state" of ebusd
# 16.09.2016 : A.Goebel : add reset "state_ebus" if ebus is not connected
# 06.10.2016 : A.Goebel : add valueFormat can now be used to access all values returned from one read
# 11.10.2016 : A.Goebel : add implement hex write from ebusctl
# 11.10.2016 : A.Goebel : add set initial reading name after "set" to "class~variable"
# 11.10.2016 : A.Goebel : fix "set hex" is only available if ebusWritesEnabled is '1'
# 13.10.2016 : A.Goebel : fix "set hex" referres to "ebusctl hex"
# 13.10.2016 : A.Goebel : fix "class" is now optional for ebusctl
# 18.10.2016 : A.Goebel : fix removed content of <comment> from attribute names for readings
# 31.10.2016 : A.Goebel : fix rename hex to ebusd_hex
# 31.10.2016 : A.Goebel : fix set for writings without comments did not work
# 26.12.2016 : A.Goebel : fix handling for non "userattr" attributes
# 27.12.2016 : A.Goebel : fix handling if ebusctl reports "usage:"
# 27.12.2016 : A.Goebel : fix scan removed from supported classes
# 13.12.2017 : A.Goebel : add "+f" as additional ebus command to disable "-f" for this request
# 03.01.2019 : A.Goebel : fix mask tilde in set/get
# 03.01.2019 : A.Goebel : fix change regexp for parsing commands from "/^w$delimiter.{1,7}$delimiter.*/" to "/^w$delimiter[^$delimiter]{1,}$delimiter.*/" to support "feuerung" as class
# 28.02.2019 : A.Goebel : fix port 8888 was hardcoded in GAEBUS_OpenDev, use $port instead (highlighted by user freetz)
# 21.03.2019 : A.Goebel : add support for find -p 
# 03.01.2019 : A.Goebel : add support for $readingFnAttributes as suggested by Hanjo
# 05.01.2020 : A.Goebel : fix supress sprintf warnings in valueFormat evaluation
# 09.01.2020 : A.Goebel : fix to skip readings named "dummy"
# 09.01.2020 : A.Goebel : fix handling for valueFormat, give exact number of parameters to sprintf and shift all of them
# 16.01.2020 : A.Goebel : add ignore error messages returned by ebusd
# 05.02.2020 : A.Goebel : change substitute tilde by slash in attribute names (delimiter)
# 16.02.2020 : A.Goebel : fix also request broadcast messages periodic call (fix from Tomy) 
# 20.01.2021 : A.Goebel : fix remove deprecated attribute loglevel
# 05.04.2022 : A.Goebel : fix support "_" in class names (eg. vr_70) / add $init_done
# 11.04.2022 : A.Goebel : change attributes mapNames and mapClass to support "_" in class and variable names
# 11.04.2022 : A.Goebel : add use helper hash to hold information for scheduled readings
# 11.04.2022 : A.Goebel : del longAttributesCount (all installations should be migrated now)

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use IO::Socket;
use IO::Select;
use Encode;
use Blocking;

sub GAEBUS_Attr(@);

sub GAEBUS_OpenDev($$);
sub GAEBUS_CloseDev($);
sub GAEBUS_Disconnected($);
sub GAEBUS_Shutdown($);

sub GAEBUS_doEbusCmd($$$$$$$);
sub GAEBUS_GetUpdates($);

sub GAEBUS_GetUpdatesDoit($);
sub GAEBUS_GetUpdatesDone($);
sub GAEBUS_GetUpdatesAborted($);

sub GAEBUS_State($);

my %gets = (    # Name, Data to send to the GAEBUS, Regexp for the answer
);

my %sets = (
  #"reopen"    => []
);

my %setsForWriting = ();
my %getsForWriting = ();

my $allSetParams           = "";
my $allSetParamsForWriting = "";
my $allGetParams           = "";
my $allGetParamsForWriting = "";
my $delimiter              = "_";

my $attrsDefault = "do_not_notify:1,0 disable:1,0 dummy:1,0 showtime:1,0 ebusWritesEnabled:0,1 valueFormat:textField-long $readingFnAttributes mapClass mapVar";
my %ebusCmd  = ();

#####################################
sub
GAEBUS_Initialize($)
{
  my ($hash) = @_;

# Normal devices
  $hash->{DefFn}      = "GAEBUS_Define";
  $hash->{UndefFn}    = "GAEBUS_Undef";
  $hash->{GetFn}      = "GAEBUS_Get";
  $hash->{SetFn}      = "GAEBUS_Set";
  #$hash->{StateFn}    = "GAEBUS_SetState";
  $hash->{AttrFn}     = "GAEBUS_Attr";
  $hash->{AttrList}   = $attrsDefault;
  $hash->{ShutdownFn} = "GAEBUS_Shutdown";


  %sets = ( "reopen" => [] );
  %gets = ( "ebusd_find" => [], "ebusd_info" => [] );
  %setsForWriting = ();
  %getsForWriting = ( "ebusd_hex" => [] );

  GAEBUS_initParams($hash);

}

#####################################
sub
GAEBUS_splitAttribute (@)
{
  my ($hash, $oneattr) = @_;
  my $name = $hash->{NAME};

  my $mapClass = ((defined ($attr{$name}{mapClass}) and ($attr{$name}{mapClass} ne "")) ? $attr{$name}{mapClass} : "[^$delimiter]+");
  my $mapVar   = ((defined ($attr{$name}{mapVar})   and ($attr{$name}{mapVar} ne ""))   ? $attr{$name}{mapVar}   : "[^$delimiter]+");

  my @result = ("", "", "", "", "");
  my @pattern = 
    ("[^$delimiter]+",
    $mapClass,
    $mapVar,
    "[^$delimiter]+"
    );

    #Log3 ($hash, 3, "$name splitAttribute params $oneattr");

  for (my $i=0; $i <4; $i++) {
    #Log3 ($hash, 5, "$name $i $oneattr $pattern[$i]\n");
    if ( $oneattr =~ /^($pattern[$i])/ ) {
      #Log3 ($hash, 5, "$name case 1 ");
       $result[$i] = $1;
       $oneattr =~ s/$result[$i]${delimiter}*//;
     } elsif ( $oneattr =~ /^([^$delimiter]+)/ ) {
       #Log3 ($hash, 5, "$name case 2 ");
       $result[$i] = $1;
       $oneattr =~ s/$result[$i]${delimiter}*//;
     }

     #Log3 ($hash, 5, "$name got $i >$result[$i]< rest $oneattr\n");

  }

  #Log3 ($hash, 3, "$name splitAttribute ".join("|", @result)."\n");
  return (@result);

}
#####################################
sub
GAEBUS_initParams ($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # bulid set and get Params and store them in 
  #   $allSetParams
  #   $allSetParamsForWriting
  #   $allGetParams
  #   $allGetParamsForWriting
  #
  # create helper for ebus commands
  # store "r_", "u_" and "w_" attributes in helper structure

  $allSetParams = "";
  foreach my $setval (sort keys %sets) 
  {
    Log3 ($hash, 4, "$name Initialize params for set: $setval");
    if ( (@{$sets{$setval}}) > 0)
    {
          $allSetParams .= $setval.":".join (",", @{$sets{$setval}})." ";
    }
    else
    {
          $allSetParams .= $setval." ";
    }
    #Log3 ($hash, 2, "$name Initialize: $setval:$allSetParams");
  }

  $allSetParamsForWriting = "";
  foreach my $setval (sort keys %setsForWriting) 
  {
    Log3 ($hash, 4, "$name Initialize params for setsForWriting: $setval");
    if ( (@{$setsForWriting{$setval}}) > 0)
    {
          $allSetParamsForWriting .= $setval.":".join (",", @{$setsForWriting{$setval}})." ";
    }
    else
    {
          $allSetParamsForWriting .= $setval." ";
    }
    #Log3 ($hash, 2, "$name Initialize: $setval:$allSetParamsForWriting");
  }

  $allGetParams = "";
  foreach my $getval (sort keys %gets) 
  {
    Log3 ($hash, 4, "$name Initialize params for get: $getval");
    if ( (@{$gets{$getval}}) > 0)
    {
          $allGetParams .= $getval.":".join (",", @{$gets{$getval}})." ";
    }
    else
    {
          $allGetParams .= $getval." ";
    }
    #Log3 ($hash, 2, "$name Initialize: $getval:$allGetParams");
  }


  $allGetParamsForWriting = "";
  foreach my $setval (sort keys %getsForWriting) 
  {
    Log3 ($hash, 4, "$name Initialize params for getsForWriting: $setval");
    if ( (@{$getsForWriting{$setval}}) > 0)
    {
          $allGetParamsForWriting .= $setval.":".join (",", @{$getsForWriting{$setval}})." ";
    }
    else
    {
          $allGetParamsForWriting .= $setval." ";
    }
    #Log3 ($hash, 2, "$name Initialize: $setval:$allSetParamsForWriting");
  }

  # create helper for ebus commands
  # store "r_", "u_" and "w_" attributes in helper structure
  # $hash->{helper}{ebus}{<attributeName>}
  # $hash->{helper}{ebus}{<attributeName>}{io} = "r|w"
  # $hash->{helper}{ebus}{<attributeName>}{class} = "bai|mc|mc_1|..."
  # $hash->{helper}{ebus}{<attributeName>}{var} = "simpleVar|varIncludingDelimiter"
  #
  
  $hash->{helper}{ebus} = ();
  foreach my $oneattr (sort keys %{$attr{$name}})
  {
    # only for "r" commands and broadcasts ("u")
    if ($oneattr =~ /^[ru]$delimiter[^$delimiter]{1,}$delimiter.*/)
    {
      my ($io,$class,$var,$comment) = GAEBUS_splitAttribute ($hash, $oneattr);

      $hash->{helper}{ebus}{$oneattr} = ();
      $hash->{helper}{ebus}{$oneattr}{io} = $io;
      $hash->{helper}{ebus}{$oneattr}{class} = $class;
      $hash->{helper}{ebus}{$oneattr}{var} = $var;

      Log3 ($hash, 4, "$name Initialize: $oneattr -> $io|$class|$var|$comment|");
    }
  }

}

#####################################
sub
GAEBUS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 3) {
    my $msg = "wrong syntax: define <name> GAEBUS <device-addr>[:<port>] [interval]";
    Log (2, $msg);
    return $msg;
  }

  GAEBUS_CloseDev($hash);

  my $name     = $a[0];
  my $devaddr  = $a[2];
  my $interval = $a[3];

  $hash->{DeviceName}    = $hash->{NAME};
  $hash->{DeviceAddress} = $devaddr;
  $hash->{Interval}      = defined ($interval) ? int ($interval) : 150;
  $hash->{UpdateCnt}     = 0;
  
  my $ret = GAEBUS_OpenDev($hash, 0);

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+5, "GAEBUS_GetUpdates", $hash, 0);

  return undef;
}


#####################################
sub
GAEBUS_Undef($$)
{
  my ($hash, $arg) = @_;
  GAEBUS_CloseDev($hash); 

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
}

#####################################
sub GAEBUS_Shutdown($)
{
  my ($hash) = @_;
  GAEBUS_CloseDev($hash); 
  return undef;
}

#####################################
sub
GAEBUS_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set GAEBUS\" needs at least one parameter" if(@a < 2);

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join(" ", @a);


  #Log3 ($hash, 2, "$name: set $arg  $type invalid parameter");

  if ($type eq "reopen") {
    Log3 ($hash, 3, "$name reopen");
    GAEBUS_CloseDev($hash);
    GAEBUS_OpenDev($hash,0);
    return undef;
  }


  # handle commands defined in %sets

  if (defined ($sets{$type}))
  {
    unless (grep {$_ eq $arg} @{$sets{$type}})
    {
        return "invalid parameter";
    }

    my $attrname = $type.$delimiter.$arg;
    $attrname =~ s/\#install/install/;
    #my ($io,$class,$var,$comment) = split ($delimiter, $attrname, 4);
    my ($io,$class,$var,$comment) = GAEBUS_splitAttribute ($hash, $attrname);
    my $shortAttrname = join ($delimiter, ($io, $class, $var));

    #Log3 ($hash, 3, "$name: set $attrname");
    Log3 ($hash, 3, "$name: set for reading $attrname");

    addToDevAttrList($name, $shortAttrname);

    if (! defined $attr{$name}{$attrname}) {
        if ($class eq "") {
          #$attr{$name}{$shortAttrname} = $var;
          GAEBUS_Attr("set", $name, $shortAttrname, $var);
        } else {
          #$attr{$name}{$shortAttrname} = join ("-", ($class, $var));
          GAEBUS_Attr("set", $name, $shortAttrname, join ("-", ($class, $var)));
        }
    }

    return undef;
  }


  #
  # extend possible parameters by the readings defined for writing in attributes
  #


  my %writings = ();

  my $actSetParams = "$allSetParams ";

  my $ebusWritesEnabled = (defined($attr{$name}{"ebusWritesEnabled"})) ? $attr{$name}{"ebusWritesEnabled"} : 0;

  if ($ebusWritesEnabled) {
    $actSetParams .= "$allSetParams$allSetParamsForWriting " if ($ebusWritesEnabled);

    foreach my $oneattr (sort keys %{$attr{$name}})
    {
      my $readingname    = $attr{$name}{$oneattr};
      my $readingcmdname = $oneattr;
      $readingname       =~ s/ .*//;
      $readingname       =~ s/:.*//;
  
      # only for "w" commands
      if ($oneattr =~ /^w$delimiter[^$delimiter]{1,}$delimiter.*/ or $oneattr =~ /^w$delimiter[^$delimiter]{1,}install$delimiter.*/)
      {
        unless ($readingname =~ /^\s*$/ or $readingname eq "1")
        {
          $writings{$readingname} = $readingcmdname;
          #Log3 ($name, 2, "$name SetParams $readingname");
        }
      }
  
      #Log3 ($name, 4, "$name Set attr name $readingname");
      #Log3 ($name, 4, "$name Set attr cmd  $readingcmdname");
    }
    $actSetParams .= join (" ", sort keys %writings);


    # handle write commands (which were defined above)

    if (defined ($setsForWriting{$type}))
    {
      unless (grep {$_ eq $arg} @{$setsForWriting{$type}})
      {
        return "invalid parameter";
      }

      my $attrname = $type.$delimiter.$arg;
      $attrname =~ s/\#install/install/;
      #my ($io,$class,$var,$comment) = split ($delimiter, $attrname, 4);
      my ($io,$class,$var,$comment) = GAEBUS_splitAttribute ($hash, $attrname);
      my $shortAttrname = join ($delimiter, ($io, $class, $var));

      Log3 ($hash, 3, "$name: set for writing $attrname");

      addToDevAttrList($name, $shortAttrname);

      if (! defined $attr{$name}{$attrname}) {
        if ($class eq "") {
          $attr{$name}{$shortAttrname} = $var;
        } else {
          $attr{$name}{$shortAttrname} = join ("-", ($class, $var));
        }
      }

      return undef;
    }

    if (defined ($writings{$type}))
    {
      foreach my $oneattr (sort keys %{$attr{$name}})
      {
        next unless ($oneattr =~ /^w.*$delimiter[^$delimiter]{1,}$delimiter.*$/ or $oneattr =~ /^w.*$delimiter[^$delimiter]{1,}install$delimiter.*$/);
     
        my $readingname    = $attr{$name}{$oneattr};
        next if ($readingname ne $type);

        my $answer = GAEBUS_doEbusCmd ($hash, "w", $readingname, $oneattr, $arg, "", 0);
        return "$answer";
      }
    }

  }

  #$actSetParams =~ s,$delimiter,&sim;,g;
  return "Unknown argument $type, choose one of " . $actSetParams
    if(!defined($sets{$type}));

  return undef;
}

#####################################
sub
GAEBUS_Get($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  my $arg = (defined($a[2]) ? $a[2] : "");
  my $rsp;
  my $varname = $a[0];
  my $type    = $a[1];

  my $readingname = ""; 
  my $readingcmdname  = ""; 

  return "\"get GAEBUS\" needs at least one parameter" if(@a < 2);

  if ($type eq "ebusd_hex")
  {
    Log3 ($hash, 4, "$name Get $type $arg");

    my $answer = GAEBUS_doEbusCmd ($hash, "h", "", "", "$arg", "", 0);

    return $answer;
  }

  # extend possible parameters by the readings defined in attributes

  my %readings = ();
  my %readingsCmdaddon = ();
  my $actGetParams .= "$allGetParams reading:";
  foreach my $oneattr (sort keys %{$attr{$name}})
  {
    my ($readingnameX, $cmdaddon) = split (" ", $attr{$name}{$oneattr}, 2);
    $cmdaddon = "" unless (defined ($cmdaddon));

    next unless defined ($readingnameX);
    next if ($readingnameX =~ /^\s*$/);
    next if ($readingnameX eq "1");

    my ($readingname, $doCntNo) = split (":", $readingnameX, 2); # split name from cycle number
    $doCntNo = 1 unless (defined ($doCntNo));

    #my $readingname    = $attr{$name}{$oneattr};
    my $readingcmdname = $oneattr;
    $readingname       =~ s/ .*//;
    $readingname       =~ s/:.*//;

    # only for "r" and "u" commands
    if ($oneattr =~ /^[ru]$delimiter[^$delimiter]{1,}$delimiter.*/)
    {
      $readings{$readingname} = $readingcmdname;
      $readingsCmdaddon{$readingname} = $cmdaddon;
        
      #Log3 ($name, 2, "$name GetParams $readingname");
    }

    #Log3 ($name, 4, "$name Get attr name $readingname");
    #Log3 ($name, 4, "$name Get attr cmd  $readingcmdname");
  }
  $actGetParams .= join (",", sort keys %readings);

  my $ebusWritesEnabled = (defined($attr{$name}{"ebusWritesEnabled"})) ? $attr{$name}{"ebusWritesEnabled"} : 0;

  if ($ebusWritesEnabled) {
    $actGetParams .= " ".join (" ", (sort keys %getsForWriting));
  }

  # handle "read" parameters and update Reading

  if ($a[1] eq "reading")
  {
    my $readingname = $a[2];
    my $readingcmdname = $readings{$readingname};
    my $cmdaddon = $readingsCmdaddon{$readingname};

    Log3 ($name, 4, "$name Get name $readingname");
    Log3 ($name, 4, "$name Get cmd r $readingcmdname");

    my $answer = GAEBUS_doEbusCmd ($hash, "r", $readingname, $readingcmdname, "", $cmdaddon, 0);

    #return "$answer";
    return undef;

  }

  if ($a[1] eq "ebusd_find")
  {
    Log3 ($name, 4, "$name Get $a[1]");

    my $answer = GAEBUS_doEbusCmd ($hash, "f", "", "", "", "", 0);

    return $answer;
  }

  if ($a[1] eq "ebusd_info")
  {
    Log3 ($name, 4, "$name Get $a[1]");

    my $answer = GAEBUS_doEbusCmd ($hash, "i", "", "", "", "", 0);

    return $answer;
  }

  # other read commands

  # UTF-8 tilde replacement
  #if (defined($a[1])) { $a[1] =~ s,\xe2\x88\xbc,$delimiter,g };
  #if (defined($a[2])) { $a[2] =~ s,\xe2\x88\xbc,$delimiter,g };

  if ($a[1] =~ /^[ru]$delimiter/ ) 
  {
    my $readingname = "";
    my $readingcmdname = $a[1].$delimiter.$a[2];

    Log3 ($name, 3, "$name get cmd v $readingcmdname");

    my $answer = GAEBUS_doEbusCmd ($hash, "v", $readingname, $readingcmdname, "", "", 0);
    #return (defined($answer ? $answer : ""));
    return "$answer";

  }

  # handle commands from %gets and show result from ebusd


  #$actGetParams =~ s,$delimiter,&sim;,g;
  return "Unknown argument $a[1], choose one of " . $actGetParams
      if(!defined($gets{$a[1]}));


  #return "No $a[1] for dummies" if(IsDummy($varname));

  return "nix"; 
}

#####################################
sub
GAEBUS_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

########################
sub
GAEBUS_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);
  
  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close();
    delete($hash->{TCPDev});

  }

  #delete($selectlist{"$name.$dev"});
  #delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
  $hash->{STATE} = "closed";
  readingsSingleUpdate ($hash,  "state_ebus", "unknown", 1);
}

########################
sub
GAEBUS_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  my $host = $hash->{DeviceAddress};
  my $port = 8888;
  if($host =~ m/^(.+):(.+)$/) { # host[:port]
    $host = $1;
    $port = $2;
  }

  $hash->{PARTIAL} = "";
  Log3 $hash, 3, "GAEBUS opening $name device $host($port)"
        if($reopen == 0);

  # This part is called every time the timeout (5sec) is expired _OR_
  # somebody is communicating over another TCP connection. As the connect
  # for non-existent devices has a delay of 3 sec, we are sitting all the
  # time in this connect. NEXT_OPEN tries to avoid this problem.

  if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
    Log3 $hash, 5, "GAEBUS NEXT_OPEN prevented opening $name device $host($port)";
    return;
  }

  my $conn = new IO::Socket::INET (
    PeerAddr => "$host",
    PeerPort => "$port",
    Proto    => 'tcp',
    Reuse    => 0,
    Timeout  => 10
    );

  if(defined ($conn)) {
    delete($hash->{NEXT_OPEN});

  } else {
    Log(3, "Can't connect to $dev: $!") if(!$reopen);

    #$readyfnlist{"$name.$dev"} = $hash;

    $hash->{STATE} = "disconnected";
    $hash->{NEXT_OPEN} = time()+60;
    return "";
  }

  my $sel = new IO::Select($conn);

  $hash->{DevType} = 'EBUSD';
  $hash->{TCPDev} = $conn;
  $hash->{FD} = $conn->fileno();
  $hash->{SELECTOR} = $sel;

  #delete($readyfnlist{"$name.$dev"});
  #$selectlist{"$name.$dev"} = $hash;

  if($reopen) {
    Log3 $hash, 1, "GAEBUS $dev reappeared ($name)";
  } else {
    Log3 $hash, 3, "GAEBUS device opened ($name)";
  }

  #$hash->{STATE}="Initialized";
  $hash->{STATE}="Connected";

  DoTrigger($name, "CONNECTED") if($reopen);
  return 0;
}

sub
GAEBUS_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  return if(!defined($hash->{FD}));                 # Already deleted or RFR

  Log3 $hash, 1, "$dev disconnected, waiting to reappear";
  GAEBUS_CloseDev($hash);
  #$readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}

sub
GAEBUS_Attr(@)
{
  my @a = @_;
  my ($action, $name, $attrname, $attrval) = @a;
  my $hash = $defs{$name};

  Log3 ($hash, 2, "$name GAEBUS_Attr($a[0],$a[1],$a[2],<$a[3]>)");

  $attrval = "" unless defined ($attrval);

  my $userattr = defined($attr{$name}{userattr}) ? $attr{$name}{userattr} : "";

  if ($action eq "del")
  {
    #my $userattr = $attr{$name}{userattr};
    #Log3 ($hash, 2, ">$userattr<>$attrname<");
    if ( " $userattr " =~ / $attrname / ) 
    {
      #Log3 ($hash, 2, "match");
      # " a" or "^a$"
      $userattr =~ s, *$attrname,,;
      if ($userattr eq "")
      {
        delete($attr{$name}{userattr});
      }
      else
      {
        $attr{$name}{userattr} = $userattr;
      }

    }

    # delete reading if attribute name contains $delimiter

    if ($attrname =~ /^.*$delimiter/) {
      my $reading = $attr{$name}{$attrname};
      $reading    =~ s, .*,,;
      $reading    =~ s,:.*,,;

      foreach my $r (split /;/, $reading) {
        Log3 ($name, 3, "$name: delete reading: $r");
        delete($defs{$name}{READINGS}{$r});
      }
    }

    if ($attrname eq "valueFormat" and defined ($hash->{helper}{$attrname})) {
      delete ($hash->{helper}{$attrname});
    }

    # delete helper if attribute is removed
    if ($attrname =~ /^[ru]$delimiter[^$delimiter]{1,}$delimiter.*/)
    {
      delete $hash->{helper}{ebus}{$attrname};
    }

    return undef;
  }
  elsif ($action eq "set")
  {
    if ($attrname eq "valueFormat") {
      my $attrVal = $attrval;
      if( $attrVal =~ m/^{.*}$/s && $attrVal =~ m/=>/ && $attrVal !~ m/\$/ ) {
        my $av = eval $attrVal;
        if( $@ ) {
          Log3 ($hash->{NAME}, 3, $hash->{NAME} ."set $attrname: ". $@);
        } else {
          $attrVal = $av if( ref($av) eq "HASH" );
        }
        $hash->{helper}{$attrname} = $attrVal;

        foreach my $key (keys %{ $hash->{helper}{$attrname} }) {
          Log3 ($hash->{NAME}, 4, $hash->{NAME} ." $key ".$hash->{helper}{$attrname}{$key});
        }

      } else {
        # if valueFormat is not verified sucessfully ... the helper is deleted (=not used)
        delete $hash->{helper}{$attrname};
      }
      return undef;
    } 

    if ( " $userattr " =~ / $attrname / ) 
    {
      # this is an attribute form "userattr"

      if (defined $attr{$name}{$attrname}) 
      {
        my $oldreading = $attr{$name}{$attrname};
        $oldreading    =~ s, .*,,;
        $oldreading    =~ s,:.*,,;
        my $newreading = $attrval;
        $newreading    =~ s, .*,,;
        $newreading    =~ s,:.*,,;

        my @or = split /;/, $oldreading;
        my @nr = split /;/, $newreading;

        for (my $i=0; $i <= $#or; $i++)
        {
          if ($or[$i] ne $nr[$i])
          {
            #Log3 ($name, 2, "$name: adjust reading: $or[$i]");

            if (defined($defs{$name}{READINGS}{$or[$i]}))
            {
              if (defined ($nr[$i] and $nr[$i] ne "dummy" ))
              {
                unless ($nr[$i] =~ /^1*$/)  # matches "1" or ""
                {
                  #Log3 ($name, 2, "$name: change attribute $attrname ($or[$i] -> $nr[$i])");

                  $defs{$name}{READINGS}{$nr[$i]}{VAL}  = $defs{$name}{READINGS}{$or[$i]}{VAL};
                  $defs{$name}{READINGS}{$nr[$i]}{TIME} = $defs{$name}{READINGS}{$or[$i]}{TIME};
                }
              }

              delete($defs{$name}{READINGS}{$or[$i]});
          
            }
          }
        }
      }
    }

    # we are still in set
    
    # refresh helper if mapClass or mapVar is set
    if ($attrname eq "mapClass" or $attrname eq "mapVar") 
    {
      Log3 ($hash, 4, "$name GAEBUS_Attr reinin helper");
      $attr{$name}{$attrname} = $attrval;
      GAEBUS_initParams($hash);
    }

    # attributes used for the update loop
    if ($attrname =~ /^[ru]$delimiter[^$delimiter]{1,}$delimiter.*/)
    {

      $attr{$name}{$attrname} = $attrval;
      Log3 ($hash, 4, "$name GAEBUS_Attr init helper for $attrname");
      my ($io,$class,$var,$comment) = GAEBUS_splitAttribute ($hash, $attrname);

      $hash->{helper}{ebus}{$attrname} = ();
      $hash->{helper}{ebus}{$attrname}{io} = $io;
      $hash->{helper}{ebus}{$attrname}{class} = $class;
      $hash->{helper}{ebus}{$attrname}{var} = $var;
    }
 
  }


 
  return undef;
}

sub 
GAEBUS_State($)
{
  my $hash           = shift;
  my $name           = $hash->{NAME};
  my $state          = ""; 
  my $actMessage     = "";

  if (($hash->{STATE} eq "Connected") and ($hash->{TCPDev}->connected()) )
  {

    my $timeout = 10;
    
    syswrite ($hash->{TCPDev}, "state\n");
    if ($hash->{SELECTOR}->can_read($timeout))
    {
      sysread ($hash->{TCPDev}, $actMessage, 4096);
      $actMessage =~ s/\n$/ /g;
      $actMessage =~ s/ {1,}$//;
      if ($actMessage =~ /^signal acquired/) {
        $state = "ok";
      }
        
    }
    else
    {
      $state = "no answer";
      Log3 ($name, 2, "$name state $state ($actMessage)");
    }

  }

  return ($state, $actMessage);
}

sub 
GAEBUS_doEbusCmd($$$$$$$)
{
  my $hash           = shift;
  my $action         = shift; # "r" = get reading, "v" = verbose mode, 
                              # "w" = write to ebus, "f" = execute find to read in config, "i" = execute info 
                              # "h" = read with command specified in hex
  my $readingname    = shift;
  my $readingcmdname = shift;
  my $writeValues    = shift;
  my $cmdaddon       = shift;
  my $inBlockingCall = shift;
  my $actMessage     = "";
  my $name = $hash->{NAME};

  if (($hash->{STATE} ne "Connected") or (!$hash->{TCPDev}->connected()) )
  {
    Log3 ($name, 2, "$name device closed. Try to reopen");
    GAEBUS_CloseDev($hash);
    GAEBUS_OpenDev($hash,0);

    if ($hash->{STATE} ne "Connected") {
      if ($inBlockingCall) {
        return "";
      }
      else {
        return undef;
      }
    }
  }

  #my $timeout = 1.8;
  my $timeout = 15.0;
  $timeout = 10.0 if ($action eq "v");
  $timeout = 10.0 if ($action eq "w");


  #my ($io,$class,$var,$comment) = split ($delimiter, $readingcmdname, 4);
  my ($io,$class,$var,$comment) = GAEBUS_splitAttribute ($hash, $readingcmdname);
  #$class = $mapClass{$class} if (defined ($mapClass{$class}));

  my $cmd = "";

  if ($action eq "w") {

    $class =~ s/install/#install/;

    $cmd = "$io ";
    $cmd .= "-c $class " if ($class ne "");
    $cmd .= "$var ";
    $cmd .= "$writeValues";

  } elsif ($action eq "f") {

    $cmd = "find -f -r -w -p";

  } elsif ($action eq "i") {

    $cmd = "info";

  } elsif ($action eq "r") {

    my $force = " -f "; 
    $force = "" if ($io eq "u");

    if ($cmdaddon =~ /\+f/) { 
      $force = "";
      $cmdaddon =~ s/\+f//;
    }

    $cmd = "r ";
    $cmd .= "$force";
    $cmd .= "-c $class " if ($class ne "");
    $cmd .= "$var ";
    $cmd .= "$cmdaddon";

  } elsif ($action eq "v") {

    $cmd = "r ";
    $cmd .= " -f " if ($io ne "u");
    $cmd .= "-v ";
    $cmd .= "-c $class " if ($class ne "");
    $cmd .= "$var ";

    #$cmd =~ s/^h /r /; # obsolete

  } elsif ($action eq "h") {

    $cmd = "hex $writeValues";
  }
  

  Log3 ($name, 3, "$name execute $cmd");

  if ($hash->{SELECTOR}->can_read(0.1))
  {
    sysread ($hash->{TCPDev}, $actMessage, 4096);
    $actMessage =~ s/\n//g;
    Log3 ($name, 2, "$name old answer $actMessage\n");
    $actMessage = "";
  }

  syswrite ($hash->{TCPDev}, $cmd."\n");
  if (0 and $hash->{SELECTOR}->can_read($timeout))
  {
    #Log3 ($name, 2, "$name try to read");
    sysread ($hash->{TCPDev}, $actMessage, 4096);
    $actMessage =~ s/\n//g;
    #$actMessage =~ s/;/ /g;
  }

  if ($hash->{SELECTOR}->can_read($timeout)) {

    my $rbuffer = "";
   
    while ($hash->{SELECTOR}->can_read(0.1) and sysread ($hash->{TCPDev}, $rbuffer, 4096)) {
      $actMessage .= $rbuffer;

      if ( $rbuffer =~ /\n\n$/ )
      {
        #Log3 ($name, 3, "$name answer terminated by empty line");
        last;
      }
 
    }
    #$actMessage =~ s/\n//g;

    # handle usage messages

    if ($actMessage =~ /^usage:/)
    {
      $actMessage = "usage: syntay error";
    }


    #Log3 ($name, 3, "$name answer $action $readingname $actMessage");

  }
  else
  {
    #return "timeout reading answer for ($readingname) $cmd";

    Log3 ($name, 2, "$name: timeout reading answer for $cmd");

    return "";
  }

  if ($action eq "f")
  {
    #Log3 ($name, 3, "$name find process answer.");

    %sets = ( "reopen" => [] );
    %gets = ( "ebusd_find" => [], "ebusd_info" => [] );
    %setsForWriting = ();
    %getsForWriting = ( "ebusd_hex" => [] );

    my %mapClass = ();
    my %mapVar = ();

    my $cnt = 0;
    foreach my $line (split /\n/, $actMessage) {
      $cnt++;

      $line =~ s/ /./g; # no blanks in names and comments

      #Log3 ($name, 3, "$name line $line");
      # exract original values before the below substitute
      my ($io, $class, $var, $o_comment, @o_params) = split (",", $line, 5);

      $line =~ s,$delimiter,.,g; # clean up the delimiter within the text

      #Log3 ($name, 5, "$name $line");

      # only comment and params use substitution of $delimiter by "."
      my ($t_io, $t_class, $t_var, $comment, @params) = split (",", $line, 5);

      #Log3 ($name, 3, "$name class $class");
      if ($class ne $t_class) 
      {
        # class contained $delimiter which was replaced by "." above
        $mapClass{$class} = $t_class;
      }
      if ($var ne $t_var) 
      {
        # var contained $delimiter which was replaced by "." above
        $mapVar{$var} = $t_var;
      }

      $io =~ s/[0-9]//g;

      # drop "memory" and "scan.*"
      next if ($class eq "memory");
      next if ($class =~ /^scan/);


      push @{$sets{"r".$delimiter.$class}}, $var.$delimiter.$comment if ($io =~ /r/);
      push @{$sets{"u".$delimiter.$class}}, $var.$delimiter.$comment if ($io =~ /u/);

      push @{$setsForWriting{"w".$delimiter.$class}}, $var.$delimiter.$comment if ($io =~ /w/);

      push @{$gets{"r".$delimiter.$class}}, $var.$delimiter.$comment if ($io =~ /r/);
      push @{$gets{"u".$delimiter.$class}}, $var.$delimiter.$comment if ($io =~ /u/);

    }

    $attr{$name}{mapClass} = join ("|", keys(%mapClass));
    $attr{$name}{mapVar} = join ("|", keys(%mapVar));
    #Log3 ($name, 4, "$name mapClass $attr{$name}{mapClass}");
    #Log3 ($name, 4, "$name mapVar $attr{$name}{mapVar}");

    GAEBUS_initParams($hash);

    Log3 ($name, 3, "$name find done.");
    return "$cnt definitions processed";

  }
  if ($action eq "i" or $action eq "h")
  {
    #Log3 ($name, 3, "$name info done.");
    return "$actMessage";
    
  }

  $actMessage =~ s/\n//g;
  $actMessage =~ s/\|//g;
  Log3 ($name, 3, "$name answer $action $readingname $actMessage");

  my @values = split /;/, $actMessage;
  my @targetreading = defined ($readingname) ? split /;/, $readingname : ();

  if ($inBlockingCall)
  {
    if ($actMessage =~ /^ERR: no data stored/) {
      # handle below
    } elsif ($actMessage =~ /^ERR: /) {
      return ("lasterror|$actMessage");
    } 

    $actMessage = "";

    foreach my $r (@targetreading)
    {
      if ($r eq "dummy") {
        shift @values;
      } else {
        # shift is done in GAEBUS_valueFormat
        my $v = GAEBUS_valueFormat ($hash, $r, \@values);
        $actMessage .= $r."|".$v."|";
      }
    }

    $actMessage =~ s/\|$//;

    # readings will be updated in main fhem process
    return $actMessage;
  }

  if ($action eq "r" and not $actMessage =~ /^ERR: /)
  {
    readingsBeginUpdate ($hash);

    foreach my $r (@targetreading)
    {
      if ($r eq "dummy") {
        shift @values;
      } else {
        # shift is done in GAEBUS_valueFormat
        my $v = GAEBUS_valueFormat ($hash, $r, \@values);
        readingsBulkUpdate ($hash, $r, $v);
      }
      #shift @values;
    }

    readingsEndUpdate($hash, 1);
  }

  return $actMessage;

}

sub 
GAEBUS_GetUpdates($)
{
  my ($hash) = @_;

  my $name = $hash->{NAME};

  if (defined($attr{$name}{disable}) and ($attr{$name}{disable} == 1)) {
    Log3 $hash, 4, "$name GetUpdates2 is disabled";

    GAEBUS_CloseDev($hash) if (defined ($hash->{FD}));
 
    InternalTimer(gettimeofday()+$hash->{Interval}, "GAEBUS_GetUpdates", $hash, 0);
    return;
 
  } else {
    Log3 $hash, 4, "$name start GetUpdates2";
 
  }

  # $init_done = 0 --> startup in progress
  # $init_done = 1 --> startup finished

  if ($init_done == 0) {
    Log3 $hash, 3, "$name wait until init_done is set";
    InternalTimer(gettimeofday()+5, "GAEBUS_GetUpdates", $hash, 0);
    return;
  }

  $hash->{UpdateCnt} = $hash->{UpdateCnt} + 1;

  $hash->{helper}{RUNNING_PID} = BlockingCall("GAEBUS_GetUpdatesDoit", $name, "GAEBUS_GetUpdatesDone", 120, "GAEBUS_GetUpdatesAborted", $hash) 
    unless(exists($hash->{helper}{RUNNING_PID}));

}

sub 
GAEBUS_GetUpdatesDoit($)
{
  my ($string) = (@_);
  my ($name)   = $string;
  my ($hash) = $defs{$name};

  my $readingname = "";
  my $tryOpenCnt  = 2; # no of tries to open the device, before giving up

  my $readingsToUpdate = "";

  # don't use socket inherited from fhem by BlockingCall.pm
  delete($hash->{TCPDev});
  $hash->{STATE} = "pleaseReconnect";
  my $ret = GAEBUS_OpenDev($hash, 0);
  if (($hash->{STATE} ne "Connected") or (!$hash->{TCPDev}->connected()) )
  {
    return "$name";
  }

  # syncronize with ebusd

  my ($state, $actMessage) = GAEBUS_State($hash);
  if ($state ne "ok") {
    Log3 ($name, 2, "$name: ebusd no connection or signal state($state)");
    return "$name";
  }
  Log3 ($name, 5, "$name: ebusd state($actMessage)");
  $actMessage =~ s/,.*//;
  $readingsToUpdate .= "|state_ebus|".$actMessage;

  if (0) {
  foreach my $oneattr (keys %{$attr{$name}})
  {
    # only for "r" commands and broadcasts ("u")
    if ($oneattr =~ /^[ru]$delimiter[^$delimiter]{1,}$delimiter.*/)
    {

      my ($readingnameX, $cmdaddon) = split (" ", $attr{$name}{$oneattr}, 2);
      $cmdaddon = "" unless (defined ($cmdaddon));

      next unless defined ($readingnameX);
      next if ($readingnameX =~ /^\s*$/);
      next if ($readingnameX eq "1");

      my ($readingname, $doCntNo) = split (":", $readingnameX, 2); # split name from cycle number
      $doCntNo = 1 unless (defined ($doCntNo));

      Log3 ($name, 5, "$name GetUpdates: $readingname:$doCntNo");

      #Log3 ($name, 2, "$name check modulo ".$hash->{UpdateCnt}." mod $doCntNo -> ".($hash->{UpdateCnt} % $doCntNo));
      if (($hash->{UpdateCnt} % $doCntNo) == 0)
      {
        $readingsToUpdate .= "|".GAEBUS_doEbusCmd ($hash, "r", $readingname, $oneattr, "", $cmdaddon, 1);
      }

      # limit number of reopens if ebusd cannot be reached
      if (($hash->{STATE} ne "Connected") or (!$hash->{TCPDev}->connected()) )
      {
        if (--$tryOpenCnt <= 0) 
        {
          Log3 ($name, 2, "$name: not connected, stop GetUpdates loop");
          last;
        }
      }

    }
  }
  }

  # $hash->{helper}{ebus}{<attributeName>}
  # $hash->{helper}{ebus}{<attributeName>}{io} = "r|w"
  # $hash->{helper}{ebus}{<attributeName>}{class} = "bai|mc|mc_1|..."
  # $hash->{helper}{ebus}{<attributeName>}{var} = "simpleVar|varIncludingDelimiter"
  #
  foreach my $oneread (sort keys %{ $hash->{helper}{ebus}})
  {

    if ($hash->{helper}{ebus}{$oneread}{io} eq "r" or $hash->{helper}{ebus}{$oneread}{io} eq "u") 
    # only for "r" commands and broadcasts ("u")
    {

      my ($readingnameX, $cmdaddon) = split (" ", $attr{$name}{$oneread}, 2);
      $cmdaddon = "" unless (defined ($cmdaddon));

      next unless defined ($readingnameX);
      next if ($readingnameX =~ /^\s*$/);
      next if ($readingnameX eq "1");

      my ($readingname, $doCntNo) = split (":", $readingnameX, 2); # split name from cycle number
      $doCntNo = 1 unless (defined ($doCntNo));

      Log3 ($name, 5, "$name GetUpdates: $readingname:$doCntNo");

      #Log3 ($name, 2, "$name check modulo ".$hash->{UpdateCnt}." mod $doCntNo -> ".($hash->{UpdateCnt} % $doCntNo));
      if (($hash->{UpdateCnt} % $doCntNo) == 0)
      {
        $readingsToUpdate .= "|".GAEBUS_doEbusCmd ($hash, "r", $readingname, $oneread, "", $cmdaddon, 1);
      }

      # limit number of reopens if ebusd cannot be reached
      if (($hash->{STATE} ne "Connected") or (!$hash->{TCPDev}->connected()) )
      {
        if (--$tryOpenCnt <= 0) 
        {
          Log3 ($name, 2, "$name: not connected, stop GetUpdates loop");
          last;
        }
      }
    }
  }


  # returnvalue for BlockingCall ... done routine
  return $name.$readingsToUpdate;


}

sub 
GAEBUS_GetUpdatesDone($)
{
  my ($string) = @_;

  return unless(defined($string));

  my @a = split("\\|",$string);
  my ($hash) = $defs{$a[0]};
  my $name = $hash->{NAME};

  delete($hash->{helper}{RUNNING_PID});

  #Log3 ($name, 2, "$name: GetUpdatesDoit returned $string");
 
  readingsBeginUpdate ($hash);
  for (my $i = 1; $i < $#a; $i = $i + 2) 
  {
    #my $v = GAEBUS_valueFormat ($hash, $$a[$i], $a[$i+1]);
    #readingsBulkUpdate ($hash, $a[$i], $v);
    readingsBulkUpdate ($hash, $a[$i], $a[$i+1]);
  }
  readingsEndUpdate($hash, 1);
  
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{Interval}, "GAEBUS_GetUpdates", $hash, 0);

}


sub 
GAEBUS_GetUpdatesAborted($)
{
  my ($hash) = @_;

  delete($hash->{helper}{RUNNING_PID});

  Log3 $hash->{NAME}, 3, "BlockingCall for ".$hash->{NAME}." was aborted";

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{Interval}, "GAEBUS_GetUpdates", $hash, 0);
}

sub
GAEBUS_getEbusParams(@)
{
  my ($hash, $attribute) = @_;
  my $name = $hash->{NAME};

  Log3 ($name, 3, "GAEBUS_getEbusParams got $attribute");


  return (undef);

}

sub
GAEBUS_valueFormat(@)
{
  my ($hash, $reading, $values_ref) = @_;
  my $rv = ""; 

  if (ref($hash->{helper}{valueFormat}) eq 'HASH' and defined ($reading))
  {

    if (exists($hash->{helper}{valueFormat}->{$reading})) {
      #no warnings qw( redundant );
      my $vf = $hash->{helper}{valueFormat}->{$reading};

      #local $SIG{__WARN__} = sub {
      #  Log3 ($hash->{NAME}, 2, "$hash->{NAME} valueFormat reading $reading: argument missmatch ($vf) (".join(",", @{$values_ref}).")");
      #};
      #
      my $count  = 0;
      my $count1 = () = $vf =~ /%/g;
      my $count2 = () = $vf =~ /%%/g;
      my @values = ();
      $count = $count1 - 2 * $count2;

      for (my $i=0; $i<$count; $i++) {
        push @values, ${$values_ref}[0];
        shift @{$values_ref};
      }

      return sprintf ("$vf", @values);
    }
  }

  $rv = (defined(${$values_ref}[0]) ? ${$values_ref}[0] : "");
  shift @{$values_ref};
  return $rv;

}


1;

=pod
=item device
=item summary device to communicate with ebusd (a communication bus for heating systems).
=begin html

<a name="GAEBUS"></a>
<h3>GAEBUS</h3>
<ul>

  <table>
  <tr><td>
  The GAEBUS module is the representation of a Ebus connector in FHEM.
  The GAEBUS module is designed to connect to ebusd (ebus daemon) via a socket connection (default is port 8888) <br>

  </td></tr>
  </table>

  <a name="GAEBUS"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; GAEBUS &lt;device-addr&gt;[:&lt;port&gt;] [&lt;interval&gt;];</code> <br>
    <br>
    &lt;device-addr&gt;[:&lt;port&gt;] specifies the host:port of the ebusd device. E.g.
    192.168.0.244:8888 or servername:8888. When using the standard port, the port can be omitted.
    <br><br>

    Example:<br><br>
    <code>define ebus1 GAEBUS localhost 300</code>
    <br><br>
    When initializing the object no device specific commands are known. Please call "get ebusd_find" to read in supported commands from ebusd.<br>
    After fresh restart of ebusd it may take a while until all supported devices and their commands are visible.<br>

  </ul>
  <br>

  <a name="GAEBUS"></a>
  <b>Set </b>
  <ul>
    <li>reopen<br>
        Will close and open the socket connection.
        </li><br>
    <li>[r]_&lt;class&gt; &lt;variable-name&gt;_&lt;comment&gt;<br>
        Will define a attribute with the following syntax:<br>
        [r]_&lt;class&gt;_&lt;variable-name&gt;<br>
        Valid combinations are read from ebusd (using "get ebusd_find") and are selectable.<br>
        Values from the attributes will be used as the name for the reading which are read from ebusd in the interval specified.<br>
        The content of &lt;comment$gt; is dropped and not added to the attribute name.<br>
        </li><br>
    <li>[w]_&lt;class&gt; &lt;variable-name&gt;_&lt;comment&gt;<br>
        Will define a attribute with the following syntax:<br>
        [w]_&lt;class&gt;_&lt;variable-name&gt;<br>
        They will only appear if the attribute "ebusWritesEnabled" is set to "1"<br>
        Valid combinations are read from ebusd (using "get ebusd_find") and are selectable.<br>
        Values from the attributes will be used for set commands to modify parameters for ebus devices<br>
        Hint: if the values for the attributes are prefixed by "set-" then all possible parameters will be listed in one block<br>
        The content of &lt;comment$gt; is dropped and not added to the attribute name.<br>
        </li><br>
  </ul>

  <a name="GAEBUS"></a>
  <b>Get</b>
  <ul>
    <li>ebusd_info<br>
        Execude <i>info</i> command on ebusd and show result.
        </li><br>

    <li>ebusd_find<br>
        Execude <i>find</i> command on ebusd. Result will be used to display supported "set" and "get" commands. Refresh the page in your Browser to make results visible.
        </li><br>

    <li>ebusd_hex<br>
        Will pass the input value to the "hex" command of ebusd. See "ebusctl help hex" for valid parameters.<br>
        This command is only available if "ebusWritesEnabled" is set to '1'.<br>
        </li><br>

    <li>reading &lt;reading-name&gt<br>
        Will read the actual value form ebusd and update the reading.
        </li><br>

    <li>[r]_&lt;class&gt; &lt;variable-name&gt;_&lt;comment&gt;<br>
        Will read this variable from the ebusd and show the result as a popup.<br>
        Valid combinations are read from ebusd (using "get ebusd_find") and are selectable.<br>
        </li><br>

  </ul>
  <br>

  <a name="GAEBUS"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#attrdummy">disable</a></li><br>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#verbose">verbose</a></li><br>
    <li>ebusWritesEnabled 0,1<br>
        disable (0) or enable (1) that commands can be send to ebus devices<br>
        See also description for Set and Get<br>
        If Attribute is missing, default value is 0 (disable writes)<br>
        </li><br>
    <li>mapClass<br>
        used to support "_" in class names. Set by ebusd_find.
        </li><br>
    <li>mapVar<br>
        used to support "_" in variable names. Set by ebusd_find.
        </li><br>
    <li>Attributes of the format<br>
        <code>[r]_&lt;class&gt;_&lt;variable-name&gt;</code><br>
        define variables that can be retrieved from the ebusd.
        They will appear when they are defined by a "set" command as described above.<br>
        The value assigned to an attribute specifies the name of the reading for this variable.<br>
        If ebusd returns a list of semicolon separated values then several semicolon separated readings can be defined.<br>
    "dummy" is a placeholder for a reading that will be ignored. (e.g.: temperature;dummy;pressure).<br>
        The name of the reading can be suffixed by "&lt;:number&gt;" which is a multiplicator for 
        the evaluation within the specified interval. (eg. OutsideTemp:3 will evaluate this reading every 3-th cycle)<br>
        All text followed the reading seperated by a blank is given as an additional parameter to ebusd. 
        This can be used to request a single value if more than one is retrieved from ebus.<br>
    If "+f" is given as an additional parameter this will remove the "-f" option from the ebusd request. This will return the value stored in ebusd instead of requesting it freshly.<br>
        </li><br>
    <li>Attributes of the format<br>
        <code>[w]_&lt;class&gt;_&lt;variable-name&gt;</code><br>
        define parameters that can be changed on ebus devices (using the write command from ebusctl)
        They will appear when they are defined by a "set" command as described above.<br>
        The value assigned to an attribute specifies the name that will be used in set to change a parameter for a ebus device.<br>
        </li><br>
    <li>valueFormat<br>
        Defines a map to format values within GAEBUS.<br>
        All readings can be formated using syntax of sprinf.
        Values returned from ebusd are spearated by ";" and split before valueFormat is processed. This means more than one of the return values can be assigned to one reading.
        <br>
        Example: { "temperature" => "%0.2f"; "from-to" => "%s-%s" }<br>
        </li><br>

  </ul>
  <br>
</ul>

=end html
=cut
