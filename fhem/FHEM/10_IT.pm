######################################################
# InterTechno Switch Manager as FHM-Module
#
# (c) Olaf Droegehorn / DHS-Computertechnik GmbH
# (c) Björn Hempel
# 
# Published under GNU GPL License
#
# $Id$
#
######################################################
package main;

use strict;
use warnings;

use SetExtensions;

my %codes = (
  "XMIToff" => "off",
  "XMITon"  => "on", # Set to previous dim value (before switching it off)
  "00" => "off",
  "01" => "dim06%",
  "02" => "dim12%",
  "03" => "dim18%",
  "04" => "dim25%",
  "05" => "dim31%",
  "06" => "dim37%",
  "07" => "dim43%",
  "08" => "dim50%",
  "09" => "dim56%",
  "0a" => "dim62%",
  "0b" => "dim68%",
  "0c" => "dim75%",
  "0d" => "dim81%",
  "0e" => "dim87%",
  "0f" => "dim93%",
  "10" => "dim100%",
  "XMITdimup" 	=> "dimup",
  "XMITdimdown" => "dimdown",
  "99" => "on-till",
);

my %codes_he800 = (
  "XMIToff" => "off",
  "XMITon"  => "on", # Set to previous dim value (before switching it off)
  "00" => "off",
  #"01" => "last-dim-on",
  "02" => "dim12%",
  "03" => "dim25%",
  "04" => "dim37%",
  "05" => "dim50%",
  "06" => "dim62%",
  "07" => "dim75%",
  "08" => "dim87%",
  "09" => "dim100%",
  "XMITdimup" 	=> "dimup",
  "XMITdimdown" => "dimdown",
  "99" => "on-till",
);

my %it_c2b;

my %it_c2b_he800;

my $it_defrepetition = 6;   ## Default number of InterTechno Repetitions

my %models = (
    itremote    => 'sender',
    itswitch    => 'simple',
    itdimmer    => 'dimmer',
    ev1527      => 'ev1527',
);

my %bintotristate=(
  "00" => "0",
  "01" => "F",
  "10" => "D",
  "11" => "1"
);
my %bintotristateV3=(
  "10" => "1",
  "01" => "0",
  "00" => "D"
);
my %bintotristateHE=(
  "10" => "1",
  "01" => "0",
  "11" => "2",
  "00" => "D"
);
my %ev_action = (
  "on"  => "0011",
  "off" => "0000"
);

sub bin2dec {
	unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}
sub bin2dec64 {
	unpack("N", pack("B32", substr("0" x 64 . shift, -64)));
}
sub
IT_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    $it_c2b{$codes{$k}} = $k;
  }

  foreach my $k (keys %codes_he800) {
    $it_c2b_he800{$codes_he800{$k}} = $k;
  }

  $hash->{Match}     = "^i......";
  $hash->{SetFn}     = "IT_Set";
  #$hash->{StateFn}   = "IT_SetState";
  $hash->{DefFn}     = "IT_Define";
  $hash->{UndefFn}   = "IT_Undef";
  $hash->{ParseFn}   = "IT_Parse";
  $hash->{AttrFn}    = "IT_Attr";
  $hash->{AttrList}  = "IODev ITfrequency ITrepetition ITclock switch_rfmode:1,0 do_not_notify:1,0 ignore:0,1 protocol:V1,V3,HE_EU,SBC_FreeTec,HE800 unit group dummy:1,0 " .
                       "$readingFnAttributes " .
                       "model:".join(",", sort keys %models);

  $hash->{AutoCreate}=
        { "IT.*" => { GPLOT => "", FILTER => "%NAME",  autocreateThreshold => "2:30"} };
}

#####################################
sub
IT_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  return undef;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  return "Undefined value $val" if(!defined($it_c2b{$val}));
}

#############################
sub
IT_Do_On_Till($@)
{
  my ($hash, $name, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-till command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my @lt = localtime;
  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($hms_now ge $hms_till) {
    Log 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
    return "";
  }

  my @b = ("on");
  IT_Set($hash, $name, @b);
  my $tname = $hash->{NAME} . "_till";
  CommandDelete(undef, $tname) if($defs{$tname});
  CommandDefine(undef, "$tname at $hms_till set $name off");

}

###################################
sub
IT_Set($@)
{
  my ($hash, $name, @a) = @_;

  my $ret = undef;
  my $na = int(@a);
  my $message;

  return "no set value specified" if($na < 1);
  # return, if this is a dummy device
  return "Dummydevice $hash->{NAME}: will not set data" if(IsDummy($hash->{NAME}));

  my $list = "";
  $list .= "off:noArg on:noArg " if( AttrVal($name, "model", "") ne "itremote" );

  my $c = $it_c2b{$a[0]};
 

  if ($hash->{READINGS}{protocol}{VAL} eq "V3") {
      if($na > 1 && $a[0] eq "dim") {  
            $a[0] = ($a[1] eq "0" ? "off" : sprintf("dim%02d%%",$a[1]) );
            
            splice @a, 1, 1;
            $na = int(@a);
      } elsif ($na == 2 && ($a[0] =~ /dim/)) {
        return "Bad time spec" if($na == 2 && $a[1] !~ m/^\d*\.?\d+$/);
  
        my $val;    
        
        #$a[0] = ($a[1] eq "0" ? "off" : sprintf("dim%02d%%",$a[1]) );
        #splice @a, 1, 1;
        #$na = int(@a);
        if($na == 2) {                                # Timed command. 
          $c = sprintf("%02X", (hex($c) | 0x20)); # Set the extension bit 
          ########################
          # Calculating the time.
          LOOP: for(my $i = 0; $i <= 12; $i++) {
            for(my $j = 0; $j <= 15; $j++) {
              $val = (2**$i)*$j*0.25;
              if($val >= $a[1]) {
                if($val != $a[1]) {
                  Log3 $name, 2, "$name: changing timeout to $val from $a[1]";
                }
                $c .= sprintf("%x%x", $i, $j);
                last LOOP;
              }
            }
          }
           Log3 $hash ,2, "$name: NOT Implemented now!";
           return "Specified timeout too large, max is 15360" if(length($c) == 2);
        }
      }
      $list = (join(" ", sort keys %it_c2b) . " dim:slider,0,6.25,100")
        if( AttrVal($name, "model", "") eq "itdimmer" );
  } elsif ($hash->{READINGS}{protocol}{VAL} eq "EV1527") {                 # EV1527
    #Log3 $hash, 2, "Set ignored for EV1527 (1527X) devices";
    return "";
  } elsif ($hash->{READINGS}{protocol}{VAL} eq "HE800") {
    $c = $it_c2b_he800{$a[0]};
    if($na > 1 && $a[0] eq "dim") {  
            $a[0] = ($a[1] eq "0" ? "off" : sprintf("dim%02d%%",$a[1]) );
            
            splice @a, 1, 1;
            $na = int(@a);
    }
    $list = (join(" ", sort keys %it_c2b_he800) . " dim:slider,0,12.5,100")
        if( AttrVal($name, "model", "") eq "itdimmer" );
  } else {
    $list .= "dimup:noArg dimdown:noArg on-till" if( AttrVal($name, "model", "") eq "itdimmer" );
  }
  #if ($hash->{READINGS}{protocol}{VAL} eq "HE800") {
  #  $list .= " learn_on_codes:noArg learn_off_codes:noArg";
  #}

  return SetExtensions($hash, $list, $name, @a) if( $a[0] eq "?" );
  return SetExtensions($hash, $list, $name, @a) if( !grep( $_ =~ /^\Q$a[0]\E($|:)/, split( ' ', $list ) ) );

  return IT_Do_On_Till($hash, $name, @a) if($a[0] eq "on-till");
  return "Bad time spec" if($na == 2 && $a[1] !~ m/^\d*\.?\d+$/);


  my $io = $hash->{IODev};
  my $v = $name ." ". join(" ", @a);
  ## Log that we are going to switch InterTechno
  Log3 $hash, 2, "$io->{NAME} IT_set: $v";
  my (undef, $cmd) = split(" ", $v, 2);	# Not interested in the name...
  
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{XMIT}";
  foreach my $n (keys %{ $modules{IT}{defptr}{$code} }) {
    my $lh = $modules{IT}{defptr}{$code}{$n};
    
    #$lh->{STATE} = $cmd;
    if ($hash->{READINGS}{protocol}{VAL} eq "HE800") {
        my $count = $hash->{"count"};
        $count = $count + 1;
        if ($count > 3) {
          $count = 0;
        }
        $hash->{"count"}  = $count;
     # }
    }
    if ($hash->{READINGS}{protocol}{VAL} eq "V3" || $hash->{READINGS}{protocol}{VAL} eq "HE800") {
      if( AttrVal($name, "model", "") eq "itdimmer" ) {
        if ($cmd eq "on") {
          my $lastDimVal = $hash->{READINGS}{lastDimValue}{VAL};
          if ($lastDimVal ne "") {
              #$cmd = $lastDimVal;
              #readingsSingleUpdate($lh, "state", $lastDimVal,1);
              readingsSingleUpdate($lh, "dim", substr($lastDimVal, 3, -1),1);
           } else {
              readingsSingleUpdate($lh, "dim", "100",1);
           }
           readingsSingleUpdate($lh, "state", "on",1);
        } elsif ($cmd eq "off") {
          readingsSingleUpdate($lh, "dim", "0",1);
          readingsSingleUpdate($lh, "state", "off",1);
        } else {
          if ($cmd eq "dim100%") {
            $lh->{STATE} = "on";
            readingsSingleUpdate($lh, "state", "on",1);
          } elsif ($cmd eq "dim00%") {
            $lh->{STATE} = "off";
            readingsSingleUpdate($lh, "lastDimValue", "",1);
            readingsSingleUpdate($lh, "state", "off",1);
          #} elsif ($cmd eq "last-dim-on") {
          #  $cmd = AttrVal($name, "lastDimValue", "");
          #  readingsSingleUpdate($lh, "state", $cmd,1);
          } else {
            readingsSingleUpdate($lh, "state", $cmd,1);
          }
          if ($cmd eq "dimup") {
                readingsSingleUpdate($lh, "lastDimValue", "dim100%",1);
          } elsif ($cmd eq "dimdown") {
                if ($hash->{READINGS}{protocol}{VAL} eq "HE800") {
                    readingsSingleUpdate($lh, "lastDimValue", "dim12%",1);
                } else {
                    readingsSingleUpdate($lh, "lastDimValue", "dim06%",1);
                }
          } else {
                readingsSingleUpdate($lh, "lastDimValue", $cmd,1);
          }
        }
      } else {
        readingsSingleUpdate($lh, "state", $cmd,1);
      }
    } else {
      readingsSingleUpdate($lh, "state", $cmd,1);
      if( AttrVal($name, "model", "") eq "itdimmer" ) {
        readingsSingleUpdate($lh,"dim",$cmd,1);
      }
    }
  }


  Log3 $hash, 5, "$io->{NAME} IT_set: Type=" . $io->{TYPE} . ' Protocol=' . $hash->{READINGS}{protocol}{VAL};

  if ($io->{TYPE} ne "SIGNALduino") {
	# das IODev ist kein SIGNALduino

	## Do we need to change RFMode to SlowRF??
	if(defined($attr{$name}) && defined($attr{$name}{"switch_rfmode"})) {
		if ($attr{$name}{"switch_rfmode"} eq "1") {				# do we need to change RFMode of IODev
			my $ret = CallFn($io->{NAME}, "AttrFn", "set", ($io->{NAME}, "rfmode", "SlowRF"));
		}
	}
	## Do we need to change ITClock ??	}
	if(defined($attr{$name}) && defined($attr{$name}{"ITclock"})) {
		#$message = "isc".$attr{$name}{"ITclock"};
		#CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", $message));
		$message = $attr{$name}{"ITclock"};
		CallFn($io->{NAME}, "SetFn", $io, ($hash->{NAME}, "ITClock", $message));
		Log3 $hash, 2, "IT set ITclock: $message for $io->{NAME}";
	}

	## Do we need to change ITrepetition ??	
	if(defined($attr{$name}) && defined($attr{$name}{"ITrepetition"})) {
		$message = "isr".$attr{$name}{"ITrepetition"};
		CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", $message));
		Log3 $hash,4, "IT set ITrepetition: $message for $io->{NAME}";
	}

	## Do we need to change ITfrequency ??	
	if(defined($attr{$name}) && defined($attr{$name}{"ITfrequency"})) {
		my $f = $attr{$name}{"ITfrequency"}/26*65536;
		my $f2 = sprintf("%02x", $f / 65536);
		my $f1 = sprintf("%02x", int($f % 65536) / 256);
		my $f0 = sprintf("%02x", $f % 256);

		my $arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
		Log3 $hash, 2, "Setting ITfrequency (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz";
		CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", "if$f2$f1$f0"));
	}
  }
	
  if ($hash->{READINGS}{protocol}{VAL} eq "V3") {
    if( AttrVal($name, "model", "") eq "itdimmer" ) {
      my @itvalues = split(' ', $v);
      if ($itvalues[1] eq "dimup") {
        $a[0] = "dim100%";
        readingsSingleUpdate($hash, "state", $itvalues[1],1);
        readingsSingleUpdate($hash, "dim", 100, 1);
        $message = "is".uc(substr($hash->{XMIT},0,length($hash->{XMIT})-5).$hash->{READINGS}{group}{VAL}."D".$hash->{READINGS}{unit}{VAL}."1111");
      } elsif ($itvalues[1] eq "dimdown") {
        $a[0] = "dim06%";
        readingsSingleUpdate($hash, "state", $itvalues[1],1);
        readingsSingleUpdate($hash, "dim", 6, 1);
        $message = "is".uc(substr($hash->{XMIT},0,length($hash->{XMIT})-5).$hash->{READINGS}{group}{VAL}."D".$hash->{READINGS}{unit}{VAL}."0000");
      } elsif ($itvalues[1] =~ /dim/) {
        my $dperc = substr($itvalues[1], 3, -1);
        my $dec = (15*$dperc)/100;
        my $bin = sprintf ("%b",$dec);
        while (length($bin) < 4) {
          # suffix 0
          $bin = '0'.$bin;   
        }
        readingsSingleUpdate($hash, "dim", $dperc, 1);
        if ($dperc == 0) {  
          $message = "is".uc(substr($hash->{XMIT},0,length($hash->{XMIT})-5).$hash->{READINGS}{group}{VAL}."0".$hash->{READINGS}{unit}{VAL});
        } else {
          $message = "is".uc(substr($hash->{XMIT},0,length($hash->{XMIT})-5).$hash->{READINGS}{group}{VAL}."D".$hash->{READINGS}{unit}{VAL}.$bin);
        }
	
      } else {
        my $stateVal;
        if ($a[0] eq "off") { 
          $stateVal = "0"; 
        } else {
          $stateVal = $hash->{$c};
          readingsSingleUpdate($hash, "lastDimValue", "",1);
        }
        $message = "is".uc(substr($hash->{XMIT},0,length($hash->{XMIT})-5).$hash->{READINGS}{group}{VAL}.$stateVal.$hash->{READINGS}{unit}{VAL});
      }
    } else {
      $message = "is".uc(substr($hash->{XMIT},0,length($hash->{XMIT})-5).$hash->{READINGS}{group}{VAL}.$hash->{$c}.$hash->{READINGS}{unit}{VAL});
    }
  } elsif ($hash->{READINGS}{protocol}{VAL} eq "HE_EU") {
    
    my $masterVal = "11";
    if ($hash->{READINGS}{mode}{VAL} eq "master") {
      if ($hash->{$c} eq "01") {
        $masterVal = "01";
      }
    }
    $message = "ise".uc(substr($hash->{XMIT},0,length($hash->{XMIT})-7).$hash->{$c}.$masterVal.$hash->{READINGS}{unit}{VAL});
  } elsif ($hash->{READINGS}{protocol}{VAL} eq "HE800") {
    my $cVal;
    my $mode;
    my @mn;
    my $msg;

    my %he800MapingTable = (
       12 => 2,
       25 => 3,
       37 => 4,
       50 => 5,
       62 => 6,
       75 => 7,
       87 => 8,
       100 => 9,
    );

    (undef, $cVal) = split(" ", $v, 2);	# Not interested in the name...

    my @key = (9, 6, 3, 8, 10, 0, 2, 12, 4, 14, 7, 5, 1, 15, 11, 13, 9); # cryptokey 

    my $rollingCode = $hash->{"count"};
    if ($rollingCode > 3) {
      $rollingCode = 0;
    }
    my $oldMode = 0;
    if ($cVal eq "on") {
      my $sendVal = $hash->{READINGS}{"on_" . $rollingCode}{VAL};
      if (defined $sendVal && $sendVal ne "" && $sendVal ne "0") {
        $message = "ish".uc($sendVal);
        $oldMode = 1;
        Log3 $hash,4, "Use old Mode sendVal $sendVal ";
      } else {
        readingsSingleUpdate($hash, "lastDimValue", "",1);
        $mode = 1;
      }
    } elsif ($cVal eq "off") {
      my $sendVal = $hash->{READINGS}{"off_" . $rollingCode}{VAL};
      if (defined $sendVal && $sendVal ne "" && $sendVal ne "0") {
        $message = "ish".uc($sendVal);
        $oldMode = 1;
        Log3 $hash,4, "Use old Mode sendVal $sendVal ";
      } else {
        $mode = 0;
      }
    } else {
      Log3 $hash,5, "mode is DIM MODE: $v Model: " . AttrVal($name, "model", "");
      # DIM Mode
      if( AttrVal($name, "model", "") eq "itdimmer" ) {

          my @itvalues = split(' ', $v);
          if ($itvalues[1] eq "dimup") {
            readingsSingleUpdate($hash, "state", $itvalues[1],1);
            readingsSingleUpdate($hash, "dim", 100, 1);
            $mode = 9;
          } elsif ($itvalues[1] eq "dimdown") {
            readingsSingleUpdate($hash, "state", $itvalues[1],1);
            readingsSingleUpdate($hash, "dim", 12, 1);
            $mode = 2;
          } else {
         
              if ($itvalues[1] =~ /dim/) {
                my $dperc = substr($itvalues[1], 3, -1);
                #my $dperc = $itvalues[2]; 
                my $dec = $he800MapingTable{$dperc};
                my $bin = sprintf ("%b",$dec);
                while (length($bin) < 4) {
                  # suffix 0
                  $bin = '0'.$bin;   
                }
                readingsSingleUpdate($hash, "dim", $dperc, 1);
                if ($dperc == 0) { 
                  $mode = 0;
                } else {
                  $mode = $dec;
                }
	          }
          }
      
      }
    }
    #}
    if ($oldMode == 0) {
        Log3 $hash,5, "mode is $mode";
        my @XMIT_split = split(/_/,$hash->{XMIT});
        my $receiverID = $XMIT_split[1];
        my $transmitterID = $XMIT_split[0];
        #encrypt
        $mn[0] = $XMIT_split[1];                 # mn[0] = iiiib i=receiver-ID
        $mn[1] = ($rollingCode << 2) & 15;    # 2 lowest bits of rolling-code
        if ($mode > 0) {                      # ON or OFF
            $mn[1] |= 2;		      # mn[1] = rrs0b r=rolling-code, s=ON/OFF, 0=const 0?
        }                                                             
        $mn[2] = $transmitterID & 15;         # mn[2..5] = ttttb t=txID in nibbles -> 4x ttttb
        $mn[3] = ($transmitterID >> 4) & 15;
        $mn[4] = ($transmitterID >> 8) & 15;
        $mn[5] = ($transmitterID >> 12) & 15;
        if ($mode >= 2 && $mode <= 9) {       # mn[6] = dpppb d = dim ON/OFF, p=%dim/10 - 1
            $mn[6] = $mode - 2;               # dim: 0=10%..7=80%
            $mn[6] |= 8;                      # dim: ON
        } else {
            $mn[6] = 0;                       # dim: OFF
        }

        #XOR encryption 2 rounds
        for (my $r=0; $r<=1; $r++){           # 2 encryption rounds
            $mn[0] = $key[ $mn[0]-$r+1];       # encrypt first nibble
            my $i = 0;
            for ($i=1; $i<=5 ; $i++){      # encrypt 4 nibbles
                $mn[$i] = $key[($mn[$i] ^ $mn[$i-1])-$r+1];   # crypted with predecessor & key
            }
        }
                    
        $mn[6] = $mn[6] ^ 9;                  # no  encryption


        $msg = ($mn[6] << 0x18) | ($mn[5] << 0x14) |       # copy the encrypted nibbles in output buffer
               ($mn[4] << 0x10) | ($mn[3] << 0x0c) |
               ($mn[2] << 0x08) | ($mn[1] << 0x04) | $mn[0];
        $msg = ($msg >> 2) | (($msg & 3) << 0x1a);         # shift 2 bits right & copy lowest 2 bits of cbuf[0] in msg bit 27/28
        $msg = ~$msg & 0xFFFFFFF;
                    
        my $bin1=sprintf("%024b",$msg);
        while (length($bin1) < 28) {
          # suffix 0
          $bin1 = '0'.$bin1;   
        }
        my $bin = $bin1;# . $bin3;
        Log3 $hash,4, "msg $msg - bin1 $bin1";
        $message = "ish".uc($bin);
    }
  } else {
    $message = "is".uc($hash->{XMIT}.$hash->{$c});
  }

  
  if ($io->{TYPE} ne "SIGNALduino") {
	# das IODev ist kein SIGNALduino
	## Send Message to IODev and wait for correct answer
	my $msg = CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", $message));
	Log3 $hash,5,"IT_Set: GetFn(raw): message = $message Antwort = $msg";
	if ($msg =~ m/raw => $message/) {
		Log 4, "ITSet: Answer from $io->{NAME}: $msg";
	} else {
		Log 2, "IT IODev device didn't answer is command correctly: $msg";
	}
	## Do we need to change ITrepetition back??	
        if(defined($attr{$name}) && defined($attr{$name}{"ITrepetition"})) {
        	$message = "isr".$it_defrepetition;
        	CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", $message));
		Log3 $hash, 2, "IT set ITrepetition back: $message for $io->{NAME}";
	}

        ## Do we need to change ITfrequency back??	
        if(defined($attr{$name}) && defined($attr{$name}{"ITfrequency"})) {
        	Log3 $hash,4 ,"Setting ITfrequency back to 433.92 MHz";
        	CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", "if0"));
        }
	
	## Do we need to change ITClock back??	
	if(defined($attr{$name}) && defined($attr{$name}{"ITclock"})) 
        {
        	Log3 $hash, 2, "Setting ITClock back to 420";
        	#CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", "sic250"));
        	CallFn($io->{NAME}, "SetFn", $io, ($hash->{NAME}, "ITClock", "420"));
        }
	
	## Do we need to change RFMode back to HomeMatic??
	if(defined($attr{$name}) && defined($attr{$name}{"switch_rfmode"})) {
		if ($attr{$name}{"switch_rfmode"} eq "1") {			# do we need to change RFMode of IODev
			my $ret = CallFn($io->{NAME}, "AttrFn", "set", ($io->{NAME}, "rfmode", "HomeMatic"));
	 	}
	}
	
  } else {  	# SIGNALduino
	
	my $SignalRepeats = AttrVal($name,'ITrepetition', '6');
	my $ITClock = AttrVal($name,'ITclock', undef);
	my $protocolId;
	if (defined($ITClock)) {
		$ITClock = '#C' . $ITClock;
	} else {
		$ITClock = '';
	}
	if ($hash->{READINGS}{protocol}{VAL} eq "V3") {
		$protocolId = 'P17#';
	} else {
		# IT V1
		$protocolId = 'P3#';
	}
	Log3 $hash, 4, "$io->{NAME} IT_set: sendMsg=$protocolId" . substr($message,2) . '#R' . $SignalRepeats . $ITClock;
	IOWrite($hash, 'sendMsg', $protocolId . substr($message,2) . '#R' . $SignalRepeats . $ITClock);
  }
  return $ret;
}


#############################
sub
IT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  # calculate transmit code from IT A-P rotary switches
  if($a[2] =~ /^([A-O])(([0]{0,1}[1-9])|(1[0-6]))$/i) {
      my %it_1st = (
          "A","0000","B","F000","C","0F00","D","FF00","E","00F0","F","F0F0",
          "G","0FF0","H","FFF0","I","000F","J","F00F","K","0F0F","L","FF0F",
          "M","00FF","N","F0FF","O","0FFF","P","FFFF"
          );
      my %it_2nd = (
          1 ,"0000",2 ,"F000",3 ,"0F00",4 ,"FF00",5 ,"00F0",6 ,"F0F0",
          7 ,"0FF0",8 ,"FFF0",9 ,"000F",10,"F00F",11,"0F0F",12,"FF0F",
          13,"00FF",14,"F0FF",15,"0FFF",16,"FFFF"
          );
      
      $a[2] = $it_1st{$1}.$it_2nd{int($2)}."0F";
      defined $a[3] or $a[3] = "FF";
      defined $a[4] or $a[4] = "F0";
      defined $a[5] or $a[5] = "0F";
      defined $a[6] or $a[6] = "00";
  }
  # calculate transmit code from FLS 100 I,II,III,IV rotary switches
  if($a[2] =~ /^(I|II|III|IV)([1-4])$/i) {
      my %fls_1st = ("I","0FFF","II","F0FF","III","FF0F","IV","FFF0" );
      my %fls_2nd = (1 ,"0FFF",2 ,"F0FF",3 ,"FF0F",4 ,"FFF0");
      
      $a[2] = $fls_1st{$1}.$fls_2nd{int($2)}."0F";
      defined $a[3] or $a[3] = "FF";
      defined $a[4] or $a[4] = "F0";
      defined $a[5] or $a[5] = "0F";
      defined $a[6] or $a[6] = "00";
  }

  my $u = "wrong syntax: define <name> IT 10-bit-housecode " .
                        "off-code on-code [dimup-code] [dimdown-code] or for protocol V3 " .
                        "define <name> IT <26 bit Address> <1 bit group bit> <4 bit unit>";

  return $u if(int(@a) < 3);

  my $housecode;
  
  my $oncode;
  my $offcode;
  my $unitCode;
  my $groupBit;
  my $name = $a[0];

   
  if ($a[3] eq "HE800") {
    # OLD, do not use anymore
    $housecode = $a[2];
    $hash->{READINGS}{protocol}{VAL}  = 'HE800';
    $hash->{"count"}  = '0';
    $oncode = "N/A";
    $offcode = "N/A";
    $unitCode="N/A";
    #return "FALSE";
  } elsif ($a[2] eq "HE800") {
    $housecode = ($a[3] + 0) . "_" . ($a[4] + 0);
    $hash->{READINGS}{protocol}{VAL}  = 'HE800';
    $hash->{"count"}  = '0';
    $oncode = "N/A";
    $offcode = "N/A";
    $unitCode="N/A";
    #return "FALSE";
  } elsif (length($a[2]) == 26) {
    # Is Protocol V3
    return "Define $a[0]: wrong ITv3-Code format: specify a 26 digits 0/1 "
  		if( ($a[2] !~ m/^[0-1]{26}$/i) );
    return "Define $a[0]: wrong Bit Group format: specify a 1 digits 0/1 "
  		if( ($a[3] !~ m/^[0-1]{1}$/i) );
    return "Define $a[0]: wrong Unit format: specify 4 digits 0/1 "
  		if( ($a[4] !~ m/^[0-1]{4}$/i) );
    #return "Define $a[0]: wrong on/off/dimm format: specify a 1 digits 0/1/d "
    #	if( ($a[3] !~ m/^[d0-1]{1}$/i) );
    $housecode=$a[2].$a[3].$a[4];
    $groupBit=$a[3];
    $unitCode=$a[4];
    $oncode = 1;
    $offcode = 0;
    $hash->{READINGS}{protocol}{VAL} = 'V3';
    $hash->{READINGS}{unit}{VAL} = $unitCode;
    $hash->{READINGS}{group}{VAL} = $groupBit;
  } elsif (length($a[2]) == 46) { # HE_EU
    return "Define $a[0]: wrong IT-Code format: specify a 29 digits 0/1 "
  		if( ($a[2] !~ m/^[0-1]{46}$/i) );
    return "Define $a[0]: wrong group format: specify a 1 digits 0/1 "
    	if( ($a[3] !~ m/^[0-1]{1}$/i) );
    return "Define $a[0]: wrong unit format: specify a 7 digits 0/1 "
    	if( ($a[4] !~ m/^[0-1]{7}$/i) );
    $housecode = $a[2].$a[4];
    $groupBit = $a[3];
    $unitCode=$a[4];
    if ($groupBit == "1") {
      # looks like a master key
      $hash->{READINGS}{mode}{VAL} = "master";
      $oncode = "01";
      $offcode = "00";
    } else {
      $hash->{READINGS}{mode}{VAL} = "single";
      $oncode = "10";
      $offcode = "01";
    }
    $hash->{READINGS}{unit}{VAL} = $unitCode;
    $hash->{READINGS}{protocol}{VAL}  = 'HE_EU';
  } elsif (length($a[2]) == 10 && (substr($a[2],0,4) eq '1527' || AttrVal($name, "model", "") eq "ev1527" || length($a[3]) == 4)) {
    # Is Protocol EV1527
    #Log3 $hash,2,"ITdefine 1527: $name a3=" . $a[3];
    $housecode = $a[2];
    $oncode = $a[3];
    $oncode = '0000' if (length($a[3]) != 4); 
    $offcode = $a[4];
    $offcode = '0000' if (length($a[4]) != 4);
    $hash->{READINGS}{protocol}{VAL}  = 'EV1527';
  } elsif (length($a[2]) == 8) {                  # SBC, FreeTec
    return "Define $a[0]: wrong IT-Code format: specify a 8 digits 0/1/f "
        if( ($a[2] !~ m/^[f0-1]{8}$/i) );
    return "Define $a[0]: wrong ON format: specify a 4 digits 0/1/f "
       if( ($a[3] !~ m/^[f0-1]{4}$/i) );
    return "Define $a[0]: wrong OFF format: specify a 4 digits 0/1/f "
       if( ($a[4] !~ m/^[f0-1]{4}$/i) );
    $housecode = $a[2];
    $oncode = $a[3];
    $offcode = $a[4];
    $hash->{READINGS}{protocol}{VAL}  = 'SBC_FreeTec';
  } else {
    #Log3 $hash,2,"ITdefine v1: $name";
    return "Define $a[0]: wrong IT-Code format: specify a 10 digits 0/1/f "
  		if( ($a[2] !~ m/^[f0-1]{10}$/i) );
    return "Define $a[0]: wrong ON format: specify a 2 digits 0/1/f/d "
    	if( ($a[3] !~ m/^[df0-1]{2}$/i) );

    return "Define $a[0]: wrong OFF format: specify a 2 digits 0/1/f/d "
    	if( ($a[4] !~ m/^[df0-1]{2}$/i) );
    $housecode = $a[2];
    $oncode = $a[3];
    $offcode = $a[4];
    $hash->{READINGS}{protocol}{VAL}  = 'V1';
  }


  $hash->{XMIT} = lc($housecode);
  $hash->{$it_c2b{"on"}}  = lc($oncode);
  $hash->{$it_c2b{"off"}}  = lc($offcode);
  
  
  if (int(@a) > 5) {
  	return "Define $a[0]: wrong dimup-code format: specify a 2 digits 0/1/f/d "
    	if( ($a[5] !~ m/^[df0-1]{2}$/i) );
		$hash->{$it_c2b{"dimup"}}  = lc($a[5]);
   
	  if (int(@a) == 7) {
  		return "Define $a[0]: wrong dimdown-code format: specify a 2 digits 0/1/f/d "
	    	if( ($a[6] !~ m/^[df0-1]{2}$/i) );
    	$hash->{$it_c2b{"dimdown"}}  = lc($a[6]);
  	}
  } else {
		$hash->{$it_c2b{"dimup"}}  = "00";
   	$hash->{$it_c2b{"dimdown"}}  = "00";
  }
  
  my $code = lc($housecode);
  my $ncode = 1;
  
  $hash->{CODE}{$ncode++} = $code;
  $modules{IT}{defptr}{$code}{$name}   = $hash;
  
  AssignIoPort($hash);
}

#############################
sub
IT_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    
    foreach my $dname (keys %{ $modules{IT}{defptr}{$c} }) {
      delete($modules{IT}{defptr}{$c}{$dname})
        if($modules{IT}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

sub
IT_Parse($$)
{
  my ($hash, $msg) = @_;
  my $ioname = $hash->{NAME};
  my $housecode;
  my $transmittercode;
  my $dimCode;
  my $unitCode;
  my $groupBit;
  my $onoffcode;
  my $def;
  my $newstate;
  my @list;
  if ((substr($msg, 0, 1)) ne 'i') {
    Log3 $hash,4,"$ioname IT: message not supported by IT \"$msg\"!";
    return undef;
  }
  if (length($msg) != 7 && length($msg) != 12 && length($msg) != 17 && length($msg) != 19 && length($msg) != 20) {
    Log3 $hash,3,"$ioname IT: message \"$msg\" (" . length($msg) . ") too short!";
    return undef;
  }
  Log3 $hash,4,"$ioname IT: message \"$msg\" (" . length($msg) . ")";
  my $bin = undef;
  my $isDimMode = 0;
  if (length($msg) == 17) { # IT V3
        my $bin1=sprintf("%024b",hex(substr($msg,1,length($msg)-1-8)));
        while (length($bin1) < 32) {
          # suffix 0
          $bin1 = '0'.$bin1;   
        }
        my $bin2=sprintf("%024b",hex(substr($msg,1+8,length($msg)-1)));
        while (length($bin2) < 32) {
          # suffix 0
          $bin2 = '0'.$bin2;   
        }
        $bin = $bin1 . $bin2;
        Log3 $hash,4,"$ioname ITv3: bin message \"$bin\" (" . length($bin) . ")";
  } elsif (length($msg) == 19 ) { # IT V3 Dimm
        my $bin1=sprintf("%024b",hex(substr($msg,1,length($msg)-1-8-8)));
        while (length($bin1) < 32) {
          # suffix 0
          $bin1 = '0'.$bin1;   
        }
        my $bin2=sprintf("%024b",hex(substr($msg,1+2,length($msg)-1-8-2)));
        while (length($bin2) < 32) {
          # suffix 0
          $bin2 = '0'.$bin2;   
        }
        my $bin3=sprintf("%024b",hex(substr($msg,1+8+2,length($msg)-1)));
        while (length($bin3) < 32) {
          # suffix 0
          $bin3 = '0'.$bin3;   
        }
        $bin = substr($bin1 . $bin2 . $bin3,24,length($bin1 . $bin2 . $bin3)-1);
        Log3 $hash,4,"$ioname ITv3dimm: bin message \"$bin\" (" . length($bin) . ")";
  } elsif (length($msg) == 20 && (substr($msg, 1, 1)) eq 'h') { # HomeEasy EU
        #Log3 undef,3,"HEX Part1: " . substr($msg,2,8);
        my $bin1=sprintf("%024b",hex(substr($msg,2,8)));
        while (length($bin1) < 32) {
          # suffix 0
          $bin1 = '0'.$bin1;   
        }
        #Log3 undef,3,"HEX Part2: " . substr($msg,2+8,7);
        my $bin2=sprintf("%024b",hex(substr($msg,2+8,7)));
        #$bin2 = substr($bin2,4);
        while (length($bin2) < 28) {
          # suffix 0
          $bin2 = '0'.$bin2;   
        }
        $bin = $bin1 . $bin2;# . $bin3;
  } elsif (length($msg) == 12 && (substr($msg, 1, 1)) eq 'h') { # HomeEasy HE800
        my $bin1=sprintf("%024b",hex(substr($msg,2,8)));
        while (length($bin1) < 32) {
          # suffix 0
          $bin1 = '0'.$bin1;   
        }
        $bin = $bin1;# . $bin3;
  } else { # IT
        $bin=sprintf("%024b",hex(substr($msg,1,length($msg)-1)));
  }

  if ((length($bin) % 2) != 0) {
    # suffix 0 
    $bin = '0'.$bin;
  }
  my $binorg = $bin;
  my $msgcode="";
  if (length($msg) == 12 && (substr($msg, 1, 1)) eq 'h') { # HomeEasy HE800;
    $msgcode=substr($bin, 0, 28);
  } elsif (length($msg) == 20 && (substr($msg, 1, 1)) eq 'h') { # HomeEasy EU;
    $msgcode=substr($bin, 0, 57);
  } else {
    while (length($bin)>=2) {
      if (length($msg) == 7) {
        if (substr($bin,0,2) != "10") {
          $msgcode=$msgcode.$bintotristate{substr($bin,0,2)};
        } else {
          if (length($msgcode) >= 10) {
            Log3 $hash,5,"$ioname IT Parse bintotristate: msgcode=$msgcode, unknown tristate in onoff-code. is evtl a EV1527 sensor";
            # $msgcode = substr($msgcode,0,10) . '00';
            $msgcode = substr($msgcode,0,10) . $bintotristate{substr($binorg,20,2)} . $bintotristate{substr($binorg,22,2)};
          } else {
            $msgcode = "";
          }
          last;
          #Log3 $hash,4,"$ioname IT:unknown tristate in \"$bin\"";
          #return "unknown tristate in \"$bin\""
        }
      } elsif (length($msg) == 20 && (substr($msg, 1, 1)) eq 'h') { # HomeEasy EU
        $msgcode=$msgcode.$bintotristateHE{substr($bin,0,2)};
      } else {
        $msgcode=$msgcode.$bintotristateV3{substr($bin,0,2)};
      }
      $bin=substr($bin,2,length($bin)-2);
    }
  }
  
  Log3 $hash,4,"$ioname IT: msgcode \"$msgcode\" (" . length($msgcode) . ") bin = $binorg";
  
  my $isEV1527 = undef;
  if (length($msg) == 7) {
    if ($msgcode) {    # ITv1 or SBC_FreeTec
      if (substr($msg,6, 1) eq '0' && substr($msgcode,8,2) ne 'FF') {   # SBC_FreeTec
        $housecode=substr($msgcode,0,8);
        $onoffcode=substr($msgcode,length($msgcode)-4,4);
        Log3 $hash,5,"$ioname IT: SBC_FreeTec housecode = $housecode  onoffcode = $onoffcode";
      } else {       # ITv1
        $housecode=substr($msgcode,0,10);
        $onoffcode=substr($msgcode,length($msgcode)-2,2);
        Log3 $hash,5,"$ioname IT: V1 housecode = $housecode  onoffcode = $onoffcode";
      }
    } else {
      $isEV1527 = 1;
      $housecode = '1527x' . sprintf("%05x", oct("0b".substr($binorg,0,20)));
      $onoffcode = substr($binorg, 20);
      Log3 $hash,5,"$ioname IT: EV1527 housecode = $housecode  onoffcode = $onoffcode";
    }
  } elsif (length($msg) == 17 || length($msg) == 19) {
    $groupBit=substr($msgcode,26,1);
    $onoffcode=substr($msgcode,27,1);
    $unitCode=substr($msgcode,28,4);
    $housecode=substr($msgcode,0,26).$groupBit.$unitCode;
    if (length($msg) == 19) {
      $dimCode=substr($msgcode,32,4);
    }
  } elsif (length($msg) == 20 && (substr($msg, 1, 1)) eq 'h') { # HomeEasy EU
    $onoffcode=substr($msgcode,46,2);
    $groupBit=substr($msgcode,48,2);
    $unitCode=substr($msgcode,50,7);
    $housecode=substr($msgcode,0,46).$unitCode;
  } elsif (length($msg) == 12 && (substr($msg, 1, 1)) eq 'h') { # HomeEasy HE800
    #$housecode=substr($msgcode,0,6).substr($msgcode,26,2);
    #$onoffcode=0;

    Log3 $hash,4,"$ioname IT: msg:" . $msg . " msgcode:" . substr($msg, 2, 8) ;
    my $msgVal = hex(substr($msg, 2, 8));
    my @mn;
    my $receiverID; 
    my $mode;
    my @ikey = (5, 12, 6, 2, 8, 11, 1, 10, 3, 0, 4, 14, 7, 15, 9, 13);  #invers cryptokey (exchanged index & value)

    Log3 $hash,4,"$ioname IT: HEX:" . $msg . " DEC:" . $msgVal ;
    $msgVal = ~($msgVal >> 4) & 0xFFFFFFF;
    Log3 $hash,4,"$ioname IT: DEC:" . $msgVal ;

    $msgVal = (($msgVal << 2) & 0x0FFFFFFF) | (($msgVal & 0xC000000) >> 0x1a);        # shift 2 bits left & copy bit 27/28 to bit 1/2
    Log3 $hash,4,"$ioname IT: DEC:" . $msgVal ;
    $mn[0] = $msgVal & 0x0000000F;
    $mn[1] = ($msgVal & 0x000000F0) >> 0x4;
    $mn[2] = ($msgVal & 0x00000F00) >> 0x8;
    $mn[3] = ($msgVal & 0x0000F000) >> 0xc;
    $mn[4] = ($msgVal & 0x000F0000) >> 0x10;
    $mn[5] = ($msgVal & 0x00F00000) >> 0x14;
    $mn[6] = ($msgVal & 0x0F000000) >> 0x18;

    $mn[6] = $mn[6] ^ 9; # no decryption

    Log3 $hash,4,"$ioname IT: mn: @mn";

    # XOR decryption 2 rounds
    my $r = 0;
    for ($r=0; $r<=1; $r++){                    # 2 decryption rounds
            my $i = 5;
	    for ($i=5; $i>=1 ; $i--){             # decrypt 4 nibbles
		    $mn[$i] = (($ikey[$mn[$i]]-$r) & 0x0F) ^ $mn[$i-1];    # decrypted with predecessor & key
	    }
	    $mn[0] = ($ikey[$mn[0]]-$r) & 0x0F;                #decrypt first nibble
    }

    Log3 $hash,4,"$ioname IT: mn: @mn ";

    $receiverID = $mn[0];
    $mode = ((($mn[1]>>1) & 1) + ($mn[6] & 0x7) + (($mn[6] & 0x8) >> 3));
    my $rollingCode = ($mn[1] >> 2);
    my $transmitterID = (($mn[5] << 12) + ($mn[4] << 8) + ($mn[3] << 4) + $mn[2]);

    $housecode = $transmitterID . "_" . $receiverID;
    $transmittercode = $transmitterID;
    $unitCode = $receiverID;
    $onoffcode = $mode; 

    Log3 $hash,4,"receiverID    : " . $receiverID ; # receiver-ID [0]1..15, 0=Broadcast 1-15 (HE844A button# 1-4 & MASTER=0, HE850 UNIT# 1-15, HE853 = 1)
    Log3 $hash,4,"OFF/ON/DIM    : " . $mode ; # 0=OFF 1=ON, 2=10%dim..9=80%dim (no 90%dim!)
    Log3 $hash,4,"Rolling-Code  : " . $rollingCode ; # rolling-code 0-3 (differentiate new message from repeated message)
    Log3 $hash,4,"Transmitter-ID: " . $transmitterID ; # unique transmitter-ID    [0]1..65535    (0 valid?, 65535 or lower limit?)

  } else {
    Log3 $hash,4,"$ioname IT: Wrong IT message received: $msgcode";
    return undef;
  }
  
  if(!defined($modules{IT}{defptr}{lc("$housecode")})) {
    if(length($msg) == 7) {
      Log3 $hash,4,"$ioname IT: $housecode not defined (Switch code: $onoffcode)";
      #return "$housecode not defined (Switch code: $onoffcode)!";
      
      my $tmpOffCode;
      my $tmpOnCode;
      if (!defined($isEV1527)) { # itv1
        if ($onoffcode eq "F0") { # on code IT
          Log3 $hash,3,"$ioname IT: For autocreate please use the on button.";
          return undef;
        } 
        $tmpOffCode = "F0";
        $tmpOnCode = "0F";
        if ($onoffcode eq "FF") { # on code IT
          $tmpOnCode = "FF";
        }
      } else {    # ev1527
        $tmpOffCode = $ev_action{'off'};
        #$tmpOnCode = $ev_action{'on'};
        $tmpOnCode = $onoffcode;
      }
      if (length($housecode) == 8){
        $tmpOffCode = '1000';
        $tmpOnCode = '0100';
      }
      return "UNDEFINED IT_$housecode IT $housecode $tmpOnCode $tmpOffCode" if(!$def);
    } elsif (length($msg) == 20) { # HE_EU
      my $isGroupCode = '0';
      if (($onoffcode == '01' && $groupBit == '01') || ($onoffcode == '00' && $groupBit == '11')) {
        # Group Code found
        $isGroupCode = '1';
      }
      Log3 $hash,2,"$ioname IT: $housecode not defined (Address: ".substr($msgcode,0,46)." Unit: $unitCode Switch code: $onoffcode GroupCode: $isGroupCode)";
      #return "$housecode not defined (Address: ".substr($msgcode,0,26)." Group: $groupBit Unit: $unitCode Switch code: $onoffcode)!";
      return "UNDEFINED IT_$housecode IT " . substr($msgcode,0,46) . " $isGroupCode $unitCode" if(!$def);
    } elsif (length($msg) == 12 && (substr($msg, 1, 1)) eq 'h') { # HE800
      Log3 $hash,2,"$ioname IT: $housecode not defined (HE800)";
      return "UNDEFINED IT_HE800_$housecode IT " . "HE800 $transmittercode $unitCode" if(!$def);
    } else {
      Log3 $hash,2,"$ioname IT: " . substr($msgcode,0,26) . " not defined (Address: ".substr($msgcode,0,26)." Group: $groupBit Unit: $unitCode Switch code: $onoffcode)";
      my $tmpHouseCode = substr($msgcode,0,26);
      my $decCode = bin2dec($tmpHouseCode);
      return "UNDEFINED IT_V3_$decCode IT " . substr($msgcode,0,26) . " $groupBit $unitCode" if(!$def);
    }
  }
  $def=$modules{IT}{defptr}{lc($housecode)};
#$lh->{"learn"}  = 'ON';
  foreach my $name (keys %{$def}) {
    if (length($msg) == 17 || length($msg) == 19) {
      if ($def->{$name}->{READINGS}{group}{VAL} != $groupBit || $def->{$name}->{READINGS}{unit}{VAL} != $unitCode) {
        next;
      }
    } elsif (length($msg) == 7 && !defined($isEV1527) && AttrVal($name, "model", "") eq "ev1527") {
      $onoffcode = substr($binorg, 20);
      $def->{$name}->{READINGS}{protocol}{VAL}  = 'EV1527';
      Log3 $hash,4,"$ioname IT EV1527: " . $def->{$name}{NAME} . ', on code=' . $def->{$name}->{$it_c2b{"on"}} . ", Switch code=$onoffcode";
    }
    if ($def->{$name}->{READINGS}{protocol}{VAL}  eq 'HE800') {

      my %he800MapingTable = (
       2 => 12,
       3 => 25,
       4 => 37,
       5 => 50,
       6 => 62,
       7 => 75,
       8 => 87,
       9 => 100,
      );

      if ($onoffcode == 0) {
        # OFF
        my $actState = $hash->{READINGS}{state}{VAL};
        $newstate="off";
        if( AttrVal($name, "model", "") eq "itdimmer" ) {
            readingsSingleUpdate($def->{$name},"dim",0,1);
        }
      } elsif ($onoffcode == 1) {
        # On
        $newstate="on";
        if( AttrVal($name, "model", "") eq "itdimmer" ) {
            my $lastDimVal = $def->{$name}->{READINGS}{lastDimValue}{VAL};
            if (defined $lastDimVal && $lastDimVal ne "") {
                my $dperc = substr($lastDimVal, 3, -1);
                readingsSingleUpdate($def->{$name},"dim",$dperc,1);
                readingsSingleUpdate($def->{$name}, "lastDimValue", "",1);
            } else {
                readingsSingleUpdate($def->{$name},"dim",100,1);
            }
        }
      } else {
        my $binVal = $he800MapingTable{$onoffcode};
        $binVal =  int($binVal);
        
        $newstate = sprintf("dim%02d%%",$binVal);
        readingsSingleUpdate($def->{$name},"dim",$binVal,1);
        readingsSingleUpdate($def->{$name}, "lastDimValue", $newstate,1);
        Log3 $hash,4,"$ioname HE800: onoffcode $onoffcode   newstate " . $newstate;
        #if ($binVal == 100) {
        #    $newstate="on";
        #} els
        if ($binVal == 0) {
            $newstate="off";
        } 
      }
    } elsif ($def->{$name}->{$it_c2b{"on"}} eq lc($onoffcode)) {
      $newstate="on";
      if( AttrVal($name, "model", "") eq "itdimmer" ) {
        my $lastDimVal = $def->{$name}->{READINGS}{lastDimValue}{VAL};
        if (defined $lastDimVal && $lastDimVal ne "") {
            my $dperc = substr($lastDimVal, 3, -1);
            readingsSingleUpdate($def->{$name},"dim",$dperc,1);
            readingsSingleUpdate($def->{$name}, "lastDimValue", "",1);
        } else {
            readingsSingleUpdate($def->{$name},"dim",100,1);
        }
      }
    } elsif ($def->{$name}->{$it_c2b{"off"}} eq lc($onoffcode)) {
      $newstate="off";
      if( AttrVal($name, "model", "") eq "itdimmer" ) {
        readingsSingleUpdate($def->{$name},"dim",0,1);
      }
    } elsif ($def->{$name}->{$it_c2b{"dimup"}} eq lc($onoffcode)) {
      $newstate="dimup";
      if( AttrVal($name, "model", "") eq "itdimmer" ) {
        readingsSingleUpdate($def->{$name},"dim","dimup",1);
      }
    } elsif ($def->{$name}->{$it_c2b{"dimdown"}} eq lc($onoffcode)) {
      $newstate="dimdown";
      if( AttrVal($name, "model", "") eq "itdimmer" ) {
        readingsSingleUpdate($def->{$name},"dim","dimdown",1);
      }
    } elsif ('d' eq lc($onoffcode)) {
      # dim
      my $binVal = ((bin2dec($dimCode)+1)*100)/16;
      $binVal =  int($binVal);
      $newstate = sprintf("dim%02d%%",$binVal);
      
      readingsSingleUpdate($def->{$name},"dim",$binVal,1);
      readingsSingleUpdate($def->{$name}, "lastDimValue", $newstate,1);
      if ($binVal == 100) {
        $newstate="on";
      } elsif ($binVal == 0) {
        $newstate="off";
      } 
    } else {
      Log3 $def->{$name}{NAME},3,"$ioname IT: Code $onoffcode not supported by $def->{$name}{NAME}.";
      next;
    }
    Log3 $def->{$name}{NAME},3,"$ioname IT: $def->{$name}{NAME} ".$def->{$name}->{STATE}."->".$newstate;
    push(@list,$def->{$name}{NAME});
    readingsSingleUpdate($def->{$name},"state",$newstate,1);
  }
  return @list;
}


sub IT_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};

	#Log3 $hash, 4, "$name IT_Attr: Calling Getting Attr sub with args: $cmd $aName = $aVal";
		
	if( $aName eq 'model' && $aVal eq 'ev1527') {
		#Log3 $hash, 4, "$name IT_Attr: ev1527";
		$hash->{READINGS}{protocol}{VAL}  = 'EV1527';
	}
	return undef;
}

1;

=pod
=item summary    supports Intertechno protocol version 1 and version 3 devices
=item summary_DE unterstuetzt Intertechno Protocol Version 1 und Version 3 Geraete
=begin html

<a name="IT"></a>
<h3>IT - InterTechno</h3>
<ul>
  The InterTechno 433MHZ protocol is used by a wide range of devices, which are either of
  the sender/sensor or the receiver/actuator category.
  Right now, we are able to SEND and RECEIVE InterTechno commands.
  Supported are devices like switches, dimmers, etc. through an <a href="#CUL">CUL</a> or <a href="#SIGNALduino">SIGNALduino</a> device, 
  this must be defined first.<br>
  This module supports Intertechno protocol version 1 and version 3.
  Newly found devices are added into the category "IT" by autocreate.
  Hint: IT protocol 1 devices are created on pressing the on-button.

  <br><br>

  <a name="ITdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; IT &lt;housecode&gt; &lt;on-code&gt; &lt;off-code&gt;
    [&lt;dimup-code&gt;] [&lt;dimdown-code&gt;] </code>
    <br>or<br>
    <code>define &lt;name&gt; IT &lt;ITRotarySwitches|FLS100RotarySwitches&gt; </code>
    <br>or<br>
    <code>define &lt;name&gt; IT &lt;address 26 Bit&gt; &lt;group bit&gt; &lt;unit Code&gt;</code>
    <br>or<br>
    <code>define &lt;name&gt; IT HE800 &lt;Transmitter ID&gt; &lt;Receiver ID&gt;</code>
    <br><br>

   The value of housecode is a 10-digit InterTechno Code, consisting of 0/1/F as it is
   defined as a tri-state protocol. These digits depend on the device you are using.
   <br>
   Bit 11 and 12 are used for switching/dimming. As different manufacturers are using
   different bit-codes you can specifiy here the 2-digit code for off/on/dimup/dimdown
   in the same form: 0/1/F.
	<br>
   The value of ITRotarySwitches consists of the value of the alpha switch A-P and
   the numeric switch 1-16 as set on the intertechno device. E.g. A1 or G12.
<br>
   The value of FLS100RotarySwitches consist of the value of the I,II,II,IV switch
   and the numeric 1,2,3,4 swicht. E.g. I2 or IV4.
<br>
   The value of ITRotarySwitches and FLS100RotarySwitches are internaly translated
   into a houscode value.

   <ul>
   <li><code>&lt;housecode&gt;</code> is a 10 digit tri-state number (0/1/F) depending on
	 your device setting (see list below).</li>
   <li><code>&lt;on-code&gt;</code> is a 2 digit tri-state number for switching your device on;
     It is appended to the housecode to build the 12-digits IT-Message.</li>
   <li><code>&lt;off-code&gt;</code> is a 2 digit tri-state number for switching your device off;
     It is appended to the housecode to build the 12-digits IT-Message.</li>
   <li>The optional <code>&lt;dimup-code&gt;</code> is a 2 digit tri-state number for dimming your device up;
     It is appended to the housecode to build the 12-digits IT-Message.</li>
   <li>The optional <code>&lt;dimdown-code&gt;</code> is a 2 digit tri-state number for dimming your device down;
     It is appended to the housecode to build the 12-digits IT-Message.</li>
   </ul>
   <br>
   <b>HE800</b><br>
   <ul>
     <li><code>&lt;Transmitter ID&gt;</code> Eindeutige Transmitter-ID (1..65535)</li>
     <li><code>&lt;Receiver ID&gt;</code> Receiver-ID [0]1..15, 0=Broadcast 1-15 (HE844A button# 1-4 & MASTER=0, HE850 UNIT# 1-15, HE853 = 1)</li>
   </ul>
   
<br>
Examples:
    <ul>
      <code>define lamp IT 01FF010101 11 00 01 10</code><br>
      <code>define roll1 IT 111111111F 11 00 01 10</code><br>
      <code>define otherlamp IT 000000000F 11 10 00 00</code><br>
      <code>define otherroll1 IT FFFFFFF00F 11 10</code><br>
      <code>define IT_1527xe0fec IT 1527xe0fec 1001 0000</code><br>
      <code>define itswitch1 IT A1</code><br>
      <code>define lamp IT J10</code><br>
      <code>define flsswitch1 IT IV1</code><br>
      <code>define lamp IT II2</code><br>
      <code>define HE800_TID1_SW1 IT HE800 1 1</code><br>
    </ul>
 <br>
   For Intertechno protocol 3 the &lt;housecode&gt; is a 26-digits number.
   Additionaly there are a 4-digits unit code and a 1-digit group code used.
   <ul>
   <li><code>&lt;address&gt;</code> is a 26 digit number (0/1)</li>
   <li><code>&lt;group&gt;</code> is a 1 digit number (0/1)</li>
   <li><code>&lt;unit&gt;</code> is a 4 digit number (0/1)</li>
   </ul>
   <br>
Examples:
    <ul>
      <code>define myITSwitch IT 00111100110101010110011111 0 0000</code>
    </ul>
    
  </ul>
  <br>

  <a name="ITset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    dimdown
    dimup
    off
    on
    on-till           # Special, see the note
    dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50%
    dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%<br>
    <li><a href="#setExtensions">set extensions</a> are supported.</li>
</pre>
    Examples:
    <ul>
      <code>set lamp on</code><br>
      <code>set lamp1,lamp2,lamp3 on</code><br>
      <code>set lamp1-lamp3 on</code><br>
      <code>set lamp off</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>on-till requires an absolute time in the "at" format (HH:MM:SS, HH:MM
      or { &lt;perl code&gt; }, where the perl-code returns a time specification).
      If the current time is greater than the specified time, the
      command is ignored, else an "on" command is generated, and for the
      given "till-time" an off command is scheduleld via the at command.
      </li>
    </ul>
  </ul>
  <br>

  <b>Get</b> <ul>N/A</ul><br>

  <a name="ITattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Set the IO device which will be used to send signals
        for this device. An example for the physical device is a CUL.
		Note: On startup, fhem DOES NOT assign an InterTechno device to an
		IODevice! The attribute IODev needs to be used ALWAYS!</li><br>

    <a name="eventMap"></a>
    <li>eventMap<br>
        Replace event names and set arguments. The value of this attribute
        consists of a list of space separated values. Each value is a colon
        separated pair. The first part specifies the "old" value, the second
        the new/desired value. If the first character is slash(/) or comma(,)
        the values are not separated by space but by this character to
        enable spaces in values.
        Examples:<ul><code>
        attr store eventMap on:open off:closed<br>
        attr store eventMap /on-for-timer 10:open/off:closed/<br>
        set store open
        </code></ul>
        </li><br>

    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <a name="attrdummy"></a>
    <li>dummy<br>
    Set the device attribute dummy to define devices which should not
    output any radio signals. Associated notifys will be executed if
    the signal is received. Used e.g. to react to a code from a sender, but
    it will not emit radio signal if triggered in the web frontend.
    </li><br>

    <li><a href="#loglevel">loglevel</a></li><br>

    <li><a href="#showtime">showtime</a></li><br>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>

    <a name="model"></a>
    <li>model<br>
        The model attribute denotes the type of the device.
        This attribute will (currently) not be used by fhem.pl directly.
        It can be used by e.g. external programs or web interfaces to
        distinguish classes of devices and send the appropriate commands
        (e.g. "on" or "off" to a switch, "dim..%" to dimmers etc.).
        The spelling of the model should match the modelname used in the
        documentation that comes which the device. The name should consist of
        lower-case characters without spaces. Valid characters are
        <code>a-z 0-9</code> and <code>-</code> (dash),
        other characters should not be used. Here is a list of "official"
        devices:<br>
          <b>Sender/Sensor</b>: itremote<br>

          <b>Dimmer</b>: itdimmer<br>

          <b>Receiver/Actor</b>: itswitch<br>

          <b>EV1527</b>: ev1527
    </li><br>


    <a name="ignore"></a>
    <li>ignore<br>
        Ignore this device, e.g. if it belongs to your neighbour. The device
        won't trigger any FileLogs/notifys, issued commands will be silently
        ignored (no RF signal will be sent out, just like for the <a
        href="#attrdummy">dummy</a> attribute). The device won't appear in the
        list command (only if it is explicitely asked for it), nor will it
        be affected by commands which use wildcards or attributes as name specifiers
        (see <a href="#devspec">devspec</a>). You still get them with the
        "ignored=1" special devspec.
        </li><br>

  </ul>
  <br>

  <a name="ITevents"></a>
  <b>Generated events:</b>
  <ul>
     From an IT device you can receive the following events.
     <li>on</li>
     <li>off</li>
     <li>dimdown</li>
     <li>dimup<br></li>
     <li>dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50%<br>
    dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%<br></li>
      Which event is sent is device dependent and can sometimes configured on
     the device.
  </ul>
</ul>

=end html

=begin html_DE

<a name="IT"></a>
<h3>IT - InterTechno</h3>
<ul>
  Das InterTechno 433MHZ Protokoll wird von einer Vielzahl von Ger&auml;ten 
	benutzt. Diese geh&ouml;ren entweder zur Kategorie Sender/Sensoren oder zur 
	Kategorie Empf&auml;nger/Aktoren. Es ist das Senden sowie das Empfangen von InterTechno 
	Befehlen m&ouml;glich. Ger&auml;ten können z.B.  
	Schalter, Dimmer usw. sein.

  Von diesem Modul wird sowohl das Protolkoll 1 sowie das Protokoll 3 unterstützt.
  Neu empfangene Pakete werden per Autocreate in Fhem unter der Kategorie IT angelegt.
  Hinweis: IT Protokoll 1 devices werden nur beim on Befehl angelegt.

  <br><br>

  <a name="ITdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; IT &lt;housecode&gt; &lt;on-code&gt; &lt;off-code&gt;
    [&lt;dimup-code&gt;] [&lt;dimdown-code&gt;] </code>
    <br>oder<br>
    <code>define &lt;name&gt; IT &lt;ITRotarySwitches|FLS100RotarySwitches&gt; </code>
    <br>oder<br>
    <code>define &lt;name&gt; IT &lt;Adresse 26 Bit&gt; &lt;Group bit&gt; &lt;Unit Code&gt;</code>
    <br>oder<br>
    <code>define &lt;name&gt; IT HE800 &lt;Transmitter ID&gt; &lt;Receiver ID&gt;</code>
    <br><br>

   Der Wert von housecode ist abh&auml;ngig vom verwendeten Ger&auml;t und besteht aus zehn Ziffern InterTechno-Code Protokoll 1. 
   Da dieser ein tri-State-Protokoll ist, k&ouml;nnen die Ziffern jeweils 0/1/F annehmen.
   <br>
   Bit 11/12 werden f&uuml;r Schalten oder Dimmen verwendet. Da die Hersteller verschiedene Codes verwenden, k&ouml;nnen hier die 
   (2-stelligen) Codes f&uuml;r an, aus, heller und dunkler (on/off/dimup/dimdown) als tri-State-Ziffern (0/1/F) festgelegt werden.
	<br>
   Der Wert des ITRotary-Schalters setzt sich aus dem Wert des Buchstaben-Schalters A-P und dem numerischen Schalter 1-16 
   des InterTechno-Ger&auml;tes zusammen, z.B. A1 oder G12.
<br>
   Der Wert des FLS100Rotary-Schalters setzt sich aus dem Wert des Schalters I,II,II,IV und dem numerischen Schalter 1-4 
   des InterTechno-Ger&auml;tes zusammen, z.B. I2 oder IV4.
<br>
   Die Werte der ITRotary-Schalter und FLS100Rotary-Schalter werden intern in housecode-Werte umgewandelt.
<br>
   F&uuml;r Intertechno Protokoll 3 besteht der hauscode aus 26 Ziffern. Zusätzlich werden noch 4 Ziffern als Unit Code sowie eine Ziffer als Group code benötigt.
<br> 
   Neues IT Element in FHEM anlegen: define IT myITSwitch IT <Adresse 26 Bit> <Group bit> <Unit Code> 
<br> 
   <ul>
   <li><code>&lt;housecode&gt;</code> 10 Ziffern lange tri-State-Zahl (0/1/F) abh&auml;ngig vom benutzten Ger&auml;t.</li>
   <li><code>&lt;on-code&gt;</code> 2 Ziffern lange tri-State-Zahl, die den Einschaltbefehl enth&auml;lt;
     die Zahl wird an den housecode angef&uuml;gt, um den 12-stelligen IT-Sendebefehl zu bilden.</li>
   <li><code>&lt;off-code&gt;</code> 2 Ziffern lange tri-State-Zahl, die den Ausschaltbefehl enth&auml;lt;
     die Zahl wird an den housecode angef&uuml;gt, um den 12-stelligen IT-Sendebefehl zu bilden.</li>
   <li>Der optionale <code>&lt;dimup-code&gt;</code> ist eine 2 Ziffern lange tri-State-Zahl, die den Befehl zum Heraufregeln enth&auml;lt;
     die Zahl wird an den housecode angef&uuml;gt, um den 12-stelligen IT-Sendebefehl zu bilden.</li>
   <li>Der optionale <code>&lt;dimdown-code&gt;</code> ist eine 2 Ziffern lange tri-State-Zahl, die den Befehl zum Herunterregeln enth&auml;lt;
     die Zahl wird an den housecode angef&uuml;gt, um den 12-stelligen IT-Sendebefehl zu bilden.</li>
   </ul>
   <br>
   <b>HE800</b><br>
   <ul>
     <li><code>&lt;Transmitter ID&gt;</code> Eindeutige Transmitter-ID (1..65535)</li>
     <li><code>&lt;Receiver ID&gt;</code> Receiver-ID [0]1..15, 0=Broadcast 1-15 (HE844A button# 1-4 & MASTER=0, HE850 UNIT# 1-15, HE853 = 1)</li>
   </ul>
   <br>
   

Beispiele:
    <ul>
      <code>define lamp IT 01FF010101 11 00 01 10</code><br>
      <code>define roll1 IT 111111111F 11 00 01 10</code><br>
      <code>define otherlamp IT 000000000F 11 10 00 00</code><br>
      <code>define otherroll1 IT FFFFFFF00F 11 10</code><br>
      <code>define IT_1527xe0fec IT 1527xe0fec 1001 0000</code><br>
      <code>define itswitch1 IT A1</code><br>
      <code>define lamp IT J10</code><br>
      <code>define flsswitch1 IT IV1</code><br>
      <code>define lamp IT II2</code><br>
      <code>define HE800_TID1_SW1 IT HE800 1 1</code><br>
    </ul>
   <br>
   F&uuml;r Intertechno Protokoll 3 ist der &lt;housecode&gt; eine 26-stellige Zahl. Zus&auml;tzlich wird noch ein 1 stelliger Gruppen-Code, sowie 
   ein 4-stelliger unit code verwendet.
   <ul>
   <li><code>&lt;address&gt;</code> ist eine 26-stellige Nummer (0/1)</li>
   <li><code>&lt;group&gt;</code> ist eine 1-stellige Nummer (0/1)</li>
   <li><code>&lt;unit&gt;</code> ist eine 4-stellige Nummer (0/1)</li>
   </ul>
   <br>

    Beispiele:
    <ul>
      <code>define myITSwitch IT 00111100110101010110011111 0 0000</code>
    </ul>
  </ul>
  <br>

  <a name="ITset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    wobei <code>value</code> eines der folgenden Schl&uuml;sselw&ouml;rter ist:<br>
    <pre>
    dimdown
    dimup
    off
    on
    on-till           # siehe Anmerkungen
    <li>Die <a href="#setExtensions">set extensions</a> werden unterst&uuml;tzt.</li>
</pre>
    Beispiele:
    <ul>
      <code>set lamp on</code><br>
      <code>set lamp1,lamp2,lamp3 on</code><br>
      <code>set lamp1-lamp3 on</code><br>
      <code>set lamp off</code><br>
    </ul>
    <br>
    Anmerkungen:
    <ul>
      <li>on-till erfordert eine Zeitangabe im "at"-Format (HH:MM:SS, HH:MM
      oder { &lt;perl code&gt; }, wobei dieser Perl-Code eine Zeitangabe zur&uuml;ckgibt).
      Ist die aktuelle Zeit gr&ouml;&szlig;er als die Zeitangabe, wird der Befehl verworfen, 
      andernfalls wird ein Einschaltbefehl gesendet und f&uuml;r die Zeitangabe ein 
      Ausschaltbefehl mittels "at"-Befehl angelegt.
      </li>
    </ul>
  </ul>
  <br>

  <b>Get</b> <ul>N/A (nicht vorhanden)</ul><br>

  <a name="ITattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Spezifiziert das physische Ger&auml;t, das die Ausstrahlung der Befehle f&uuml;r das 
        "logische" Ger&auml;t ausf&uuml;hrt. Ein Beispiel f&uuml;r ein physisches Ger&auml;t ist ein CUL.<br>
        Anmerkung: Beim Start weist fhem einem InterTechno-Ger&auml;t kein IO-Ger&auml;t zu. 
        Das Attribut IODev ist daher IMMER zu setzen.</li><br>

    <a name="eventMap"></a>
    <li>eventMap<br>
      Ersetzt Namen von Ereignissen und set Parametern. Die Liste besteht dabei 
      aus mit Doppelpunkt verbundenen Wertepaaren, die durch Leerzeichen getrennt 
      sind. Der erste Teil des Wertepaares ist der "alte" Wert, der zweite der neue/gew&uuml;nschte. 
      Ist das erste Zeichen der Werteliste ein Komma (,) oder ein Schr&auml;gsstrich (/), wird 
      das Leerzeichen als Listenzeichen durch dieses ersetzt. Dies erlaubt die Benutzung 
      von Leerzeichen innerhalb der Werte.
      Beispiele:<ul><code>
      attr store eventMap on:open off:closed<br>
      attr store eventMap /on-for-timer 10:open/off:closed/<br>
      set store open
      </code></ul>
    </li><br>

    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <a name="attrdummy"></a>
    <li>dummy<br>
      Mit der Eigenschaft dummy lassen sich Ger&auml;te definieren, die keine physikalischen Befehle 
      senden sollen. Verkn&uuml;pfte notifys werden trotzdem ausgef&uuml;hrt. Damit kann z.B. auf Sendebefehle 
      reagiert werden, die &uuml;ber die Weboberfl&auml;che ausgel&ouml;st wurden, ohne dass der Befehl physikalisch
      gesendet wurde.
    </li><br>

    <li><a href="#loglevel">loglevel</a></li><br>

    <li><a href="#showtime">showtime</a></li><br>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>

    <a name="model"></a>
    <li>model<br>
      Hiermit kann das Modell des IT-Ger&auml;ts n&auml;her beschrieben werden. Diese 
      Eigenschaft wird (im Moment) nicht von fhem ausgewertet.
      Mithilfe dieser Information k&ouml;nnen externe Programme oder Web-Interfaces
      Ger&auml;teklassen unterscheiden, um geeignete Kommandos zu senden (z.B. "on" 
      oder "off" an Schalter, aber "dim..%" an Dimmer usw.). Die Schreibweise 
      der Modellbezeichnung sollten der dem Ger&auml;t mitgelieferten Dokumentation
      in Kleinbuchstaben ohne Leerzeichen entsprechen. 
      Andere Zeichen als <code>a-z 0-9</code> und <code>-</code> (Bindestrich)
      sollten vermieden werden. Dies ist die Liste der "offiziellen" Modelltypen:<br>
        <b>Sender/Sensor</b>: itremote<br>

        <b>Dimmer</b>: itdimmer<br>

        <b>Empf&auml;nger/Actor</b>: itswitch<br>

        <b>EV1527</b>: ev1527
    </li><br>


    <a name="ignore"></a>
    <li>ignore<br>
      Durch das Setzen dieser Eigenschaft wird das Ger&auml;t nicht durch fhem beachtet,
      z.B. weil es einem Nachbarn geh&ouml;rt. Aktivit&auml;ten dieses Ger&auml;tes erzeugen weder
      Log-Eintr&auml;ge noch reagieren notifys darauf, erzeugte Kommandos werden ignoriert
      (wie bei Verwendung des Attributes <a href="#attrdummy">dummy</a> werden keine 
      Signale gesendet). Das Ger&auml;t ist weder in der Ausgabe des list-Befehls enthalten
      (au&szlig;er es wird explizit aufgerufen), noch wird es bei Befehlen ber&uuml;cksichtigt, 
      die mit Platzhaltern in Namensangaben arbeiten (siehe <a href="#devspec">devspec</a>).
      Sie werden weiterhin mit der speziellen devspec (Ger&auml;tebeschreibung) "ignored=1" gefunden.
        </li><br>

  </ul>
  <br>

  <a name="ITevents"></a>
  <b>Erzeugte Ereignisse (Events):</b>
  <ul>
     Ein IT-Ger&auml;t kann folgende Ereignisse generieren:
     <li>on</li>
     <li>off</li>
     <li>dimdown</li>
     <li>dimup<br></li>
     Welche Ereignisse erzeugt werden ist ger&auml;teabh&auml;ngig und kann evtl. am Ger&auml;t eingestellt werden.
  </ul>
</ul>



=end html_DE

=cut
