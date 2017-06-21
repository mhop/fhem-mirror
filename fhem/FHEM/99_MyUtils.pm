package main;
use strict;
use warnings;
use POSIX;
use feature "state"; 

sub MyUtils_Initialize($$)
{
    my ($hash) = @_;
}

use constant {
  STATE_IDLE => 0,
  STATE_HOCH => 1,
  STATE_RUNTER => 2,
  STATE_SCHLITZ => 3,
};


my @rolls = (
    { roll => "wohn.rollTerrR", dir=>"W", typ=>"n", temp=>"tempWohn",   tempSoll=>20, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "wohn.rollTerrL", dir=>"W", typ=>"n", temp=>"tempWohn",   tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "wohn.rollSofa",  dir=>"S", typ=>"n", temp=>"tempWohn",   tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "ess.roll",       dir=>"S", typ=>"n", temp=>"tempWohn",   tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollBar",   dir=>"S", typ=>"n", temp=>"tempKueche", tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollStr",   dir=>"O", typ=>"n", temp=>"tempKueche", tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "arb.rollTerr",   dir=>"W", typ=>"n", temp=>"tempStudio", tempSoll=>20, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "arb.rollWeg",    dir=>"S", typ=>"n", temp=>"tempStudio", tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "bad.roll",       dir=>"S", typ=>"n", temp=>"tempBad",    tempSoll=>22, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollWeg", dir=>"S", typ=>"s", temp=>"tempSchlaf", tempSoll=>18, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollStr", dir=>"O", typ=>"s", temp=>"tempSchlaf", tempSoll=>18, win=>"wohn.fenTerr", state=>STATE_IDLE, },
);


my @rollHoch = (
  "bad.roll", 
  "arb.rollWeg", 
  "arb.rollTerr",
  "kuch.rollStr",
  "kuch.rollBar",
  "ess.roll",
  "wohn.rollSofa",
  "wohn.rollTerrL",
  "wohn.rollTerrR"
);


my @rollRunter = ( 
  "wohn.rollTerrR", 
  "wohn.rollTerrL",
  "wohn.rollSofa", 
  "ess.roll", 
  "kuch.rollBar", 
  "kuch.rollStr", 
  "arb.rollTerr", 
  "arb.rollWeg", 
  "bad.roll", 
  "schlaf.rollWeg", 
  "schlaf.rollStr"
);

my @rollWeck = ( 
  "schlaf.rollWeg", 
  "schlaf.rollStr"
);

my @rollTest = ( 
  "wohn.rollTerrR"
);

my @rollSchlaf = ( 
  "schlaf.rollWeg", 
  "schlaf.rollStr"
);

my @rollArb = ( 
  "arb.rollTerr", 
  "arb.rollWeg", 
);

my $tc=0;
my @blocktime=localtime;
my $blocktimerRunning=0;
my $delaySec=11;

#------------------------------------------

sub myfhem($) {
    #Log 1, "@_";
    fhem("@_");
}

#------------------------------------------

sub RollCheckSkip($$)
{
    my($cmd, $roll) = @_;
    my $skip=0;
    if ($cmd eq "closes") {
       if ($roll eq "wohn.rollTerrR") {
          if (Value("wohn.fenTerr") eq "Open") { 
              $skip=1; 
          }
      }
   }
   return $skip
}

#------------------------------------------

sub RollCmd($$$)
{
    my ($cmd, $roll, $delay) = @_;
    if(RollCheckSkip($cmd, $roll)==0) {
        myfhem ("define r".int(rand(10000))." at +".$delay." set ".$roll." ".$cmd);
    }
}

#------------------------------------------
     
sub RollGroup(\@$$)
{
    my ($rolls, $cmd, $delay) = @_;
    #Log 1, "RollGroup ## cmd:$cmd del:$delay";
    my $i;
    my @myrolls;
   @myrolls=@$rolls;

    $i=0;
    for my $r (@myrolls) {
	my @tparts = gmtime($i*$delay+1);
        my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
        my $skip=0;
        #$t="00:00:".sprintf("%02d", $i*5);
        #Log 1, "time $t";
        if ($cmd eq "closes") {
           if ($r eq "wohn.rollTerrR") {
              if (Value("wohn.fenTerr") eq "Open") {
                 $skip=1;
              }
           }
        }
        if($skip==0) {
	    myfhem ("define r".$i." at +".$t." set ".$r." ".$cmd);
        }
	$i=$i+1;
    }
}

#------------------------------------------

sub RollTest() {
     &RollGroup(\@rollTest, "closes", 1);
}

#------------------------------------------

sub RollAll($$) {
   my ($cmd, $delay) = @_;
#   Log 1, "c:$cmd d:$delay";
   if($cmd eq "closes") {
     &RollGroup(\@rollRunter, $cmd,$delay);
   }
   else {
     &RollGroup(\@rollHoch, $cmd,$delay);
  }
}

#------------------------------------------

sub RollWeck($) {
   my ($delay) = @_;
   &RollGroup(\@rollWeck, "up 5", $delay);
   myfhem("define weckwachat at +03:00:00 set wach 1");
}

#------------------------------------------

sub Dbg($) {
    if(Value("DebugRoll") eq "1") {
	Log 1,$_[0];
    }
}

#------------------------------------------

sub RollRunterSchlitz($$) {
    my ($r, $ndelay) = @_;
    $ndelay ||= 0; 
    
    if ($r->{state}!=STATE_SCHLITZ) {
	my @tparts = gmtime($ndelay*$delaySec);
	my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
	my @tparts2 = gmtime($ndelay*$delaySec+40);
	my $t2=sprintf ("%02d:%02d:%02d",@tparts2[2,1,0]);
	my $i=$tc++;

	Dbg("RollChg: $r->{roll} - runter schlitz($ndelay)\n");
	myfhem("define r".$i." at +".$t." set ".$r->{roll}." closes");
	myfhem("define ru".$i." at +".$t2." set ".$r->{roll}." up 6");
	$r->{state}=STATE_SCHLITZ;
    }
}

#------------------------------------------

sub RollHoch($$) {
    my ($r, $ndelay) = @_;
    $ndelay ||= 0;

    if ($r->{state}!=STATE_HOCH) {
	my @tparts = gmtime($ndelay*$delaySec);
	my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
	my $i=$tc++;
    
	Dbg("RollChg: $r->{roll} - hoch($ndelay)\n");
	myfhem("define r".$i." at +".$t." set ". $r->{roll} ." opens");
	$r->{state}=STATE_HOCH;
    }
}

#------------------------------------------

sub RollRunter($$) {
    my ($r, $ndelay) = @_;
    $ndelay ||= 0; 

    if ($r->{state}!=STATE_RUNTER) {
	my @tparts = gmtime($ndelay*$delaySec);
	my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
	my $i=$tc++;

	Dbg("RollChg: $r->{roll} - runter($ndelay)\n");
	myfhem("define r".$i." at +".$t." set ".$r->roll." closes");
	$r->{state}=STATE_RUNTER;
    }
}

#------------------------------------------

sub IsSunny($) {
    my ($wett)=@_;
    if($wett==30 || $wett==31 || $wett==32 || $wett==33 || $wett==34 || $wett==35 || $wett==36) { # sonnig, heiter, heiss
	return(1);
    }
    return(0);
}

#------------------------------------------

sub IsLater($) {
    my($t)=@_;
    #Dbg("Islater:$t");
    my @time = localtime(time);    
    if ($t =~ /(\d+):(\d+)/ and ($time[2]>=$1) and ($time[1]>=$2) ) {
	Dbg("later:$t");
	return(1);
    }
    return(0);
}

#------------------------------------------

# Nach dem Wechsel auf !sonne noch 2Std warten
sub IsWetterSonneWait($) 
{
    my ($wett)=@_;

    state $wettalt=0;
    if($wett != $wettalt) {
	if(!IsSunny($wett)) {
	    if(IsSunny($wettalt)) {
		@blocktime=localtime;
		$blocktime[2]+=2; # +2Std
                if($blocktime[2]>23) { $blocktime[2]=23; } # da nachts keine sonne scheint egal
                $blocktimerRunning=1;
		#Dbg("son1");	
	    }
	}
        else {
	}
	$wettalt=$wett;
    }
    if($blocktimerRunning) {
	if(!IsLater("$blocktime[2]:$blocktime[1]")) {
	    return(1);
	}
	else {
	    $blocktimerRunning=0;
	}
    }
    return(0);
}

#------------------------------------------

sub setTagHell($$) 
{
    my ($twil, $light) = @_;
    if ($twil>=3 && $twil<10) { # civil
        myfhem("set tag 1");
    } else {
        myfhem("set tag 0");
    }
    if ($light>=5) { # weather
        myfhem("set hell 1");
    } else {
        myfhem("set hell 0");
    }
}

#------------------------------------------

# Raum zu warm und aussentemp hoch ?
sub checkTemps($$$)
{
    my($temp, $tempOut, $tempSoll)=@_;
    my $tempH=0; my $tempOH=0; my $tempL=0; my$tempOL=0;
	   
    if ($temp    > $tempSoll-0) { $tempH =1; } 
    if ($temp    < $tempSoll-1) { $tempL =1; }
    if ($tempOut > $tempSoll-2) { $tempOH=1; }
    if ($tempOut < $tempSoll-3) { $tempOL=1; }
    return($tempH, $tempOH, $tempL, $tempOL);
}

#------------------------------------------

# Sonne scheint ins Fenster ?
sub checkWeather($$$$$)
{
    my($twil, $sun_dir, $win_dir, $sunblock, $sunny)=@_;
    # Sonne scheint ins Fenster ?
    my $sonne=0;
    if($twil>=5 && $twil<7) { # nur, wenn der Sonnenstand ueber 'weather' liegt
	if (index($sun_dir, $win_dir) != -1) { # Sonnenrichtung ins Fenster
	    if ($sunblock) { $sonne=1; }
	    if ($sunny)    { $sonne=1; }
	    #Dbg("son3, $sonne");	
	}
    }
    return $sonne;
}

#------------------------------------------

# Offene Fenster nicht mit Rollaeden verschliessen
sub checkSkip($$$)
{
    my ($winstate, $typ, $wach)=@_;
    # Offene Fenster nicht mit Rollaeden verschliessen
    my $skipRunter=0; my $skipHoch=0;
    if ($winstate eq "Open") {
	$skipRunter=1;
    }
    # Zur Schlafzeit nicht oeffnen
    if($typ eq "s") {
	if($wach eq "0") {
	    $skipHoch=1;
	}
    }
    return($skipRunter, $skipHoch);
}

#------------------------------------------

sub RollCheck() {
    my $r;
    my $ndelay =0;
    my $tempOut=ReadingsVal("myWH1080", "Temp-outside", 99);
    my $twil   =Value("twil");
    my $light  =ReadingsVal("twil", "light", 0);
    my $wett   =ReadingsVal("wetter", "code", 99);
    my $sr     =Value("sonnenrichtung");
    my $sunny  =IsSunny($wett);

    setTagHell($twil, $light);
    my $tag=Value("tag");
    # Nach wechsel von sonne auf !sonne blockert ? 
    my $sonneblock=IsWetterSonneWait($wett); 
    Dbg("RollCheck to:$tempOut twil:$twil light:$light wett:$wett sr:$sr block:$sonneblock\n");

    for $r ( @rolls ) {
	#Dbg("--------r:g ".$r->{roll}." / ".$r->{temp});

	# Raum zu warm und aussentemp hoch ?
        my $temp=ReadingsVal($r->{temp},"temperature", 99);
	my($tempH, $tempOH, $tempL, $tempOL)=checkTemps($temp, $tempOut, $r->{tempSoll});
	# Sonne scheint ins Fenster ?
	my $sonne=checkWeather($twil, $sr, $r->{dir}, $sonneblock, $sunny);
        # Offene Fenster nicht mit Rollaeden verschliessen
        my ($skipRunter, $skipHoch)=checkSkip(Value($r->{win}), $r->{typ}, Value("wach"));

        Dbg("RollCheck:$r->{roll}-tempH,OH,L,OL:$tempH,$tempOH,$tempL,$tempOL tempI,O:$temp,$tempOut so:$sonne wett:$wett sr:$sr twil:$twil tag:$tag skipR,H:$skipRunter,$skipHoch st:$r->{state}");


	if (!$tag) {
	    Dbg(" runter");
	    if (!$skipRunter) { RollRunter($r, $ndelay++); }
	}
	elsif ($tag && $tempH && ($sonne || $tempOH)) {
	    Dbg(" schl");
	    if (!$skipHoch && !$skipRunter) { RollRunterSchlitz($r, $ndelay++); }
	}
	elsif ($tag && ($tempL || (!$sonne && $tempOL)) ) {
	    Dbg(" hoch");
	    if (!$skipHoch) { RollHoch($r, $ndelay++); }
	}
    } # for
}

#------------------------------------------

sub Untoggle($) {
    my ($obj) = @_;
    if (Value($obj) eq "toggle"){
	if (OldValue($obj) eq "off") {
	    {fhem ("setstate ".$obj." on")}
	}
	else {
	    {fhem ("setstate ".$obj." off")}
	}
    }
    else {
	{fhem "setstate ".$obj." ".Value($obj)}
    } 
}

1;
