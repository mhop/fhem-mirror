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

use constant {
  TEMP_IDLE => 0,
  TEMP_COLD => 1,
  TEMP_LOW => 2,
  TEMP_HIGH => 3,
};

# CheckSkip
use constant {
  SKIP_NO => 0,
  SKIP_ALL => 1,
  SKIP_DOWN => 2,
};

# CheckWeather
use constant {
  WEATHER_SUNNY => 0,
  WEATHER_CLOUDY => 1,
  WEATHER_BAD => 2,
};

# dir: Himmelsrichtung des Fensters
# typ: n-normal, s-schlaf bis wecken geschlossen, o-nachts offen
my @rolls = (
    { roll => "wohn.rollTerrR", dir=>"W", typ=>"n",  temp=>"tempWohn",   tempSoll=>20, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "wohn.rollTerrL", dir=>"W", typ=>"n",  temp=>"tempWohn",   tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "wohn.rollSofa",  dir=>"S", typ=>"n",  temp=>"tempWohn",   tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "ess.roll",       dir=>"S", typ=>"n",  temp=>"tempWohn",   tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollBar",   dir=>"S", typ=>"n",  temp=>"tempKueche", tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollStr",   dir=>"O", typ=>"n",  temp=>"tempKueche", tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "arb.rollTerr",   dir=>"W", typ=>"n",  temp=>"tempStudio", tempSoll=>20, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "arb.rollWeg",    dir=>"S", typ=>"n",  temp=>"tempStudio", tempSoll=>20, win=>"",             state=>STATE_IDLE, },
    { roll => "bad.roll",       dir=>"S", typ=>"n",  temp=>"tempBad",    tempSoll=>22, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollWeg", dir=>"S", typ=>"s",  temp=>"tempSchlaf", tempSoll=>18, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollStr", dir=>"O", typ=>"so", temp=>"tempSchlaf", tempSoll=>18, win=>"",             state=>STATE_IDLE, },
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
  "schlaf.rollWeg"
#  "schlaf.rollStr"
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

my $tempIn_offset=0;
my $tempOut_offset=+5;

#------------------------------------------

sub myfhem($)
{
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


sub RollGroup2(\@$$)
{
    my ($typ, $cmd, $delay) = @_;
    #Log 1, "RollGroup ## cmd:$cmd del:$delay";
    my $i=0;
    my $r=0;

    for $r (@rolls) {
        if (index($r->{typ}, $typ) != -1) {
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
   #&RollGroup(\@rollWeck, "up 5", $delay);
   &RollGroup(\@rollWeck, "opens", $delay);
   myfhem("define weckwachat at +03:00:00 set wach 1");
}

#------------------------------------------

sub Dbg($) {
    if(Value("DebugRoll") eq "1") {
	Log 1,$_[0];
    }
}

#------------------------------------------

sub getDelayTime($)
{
    my ($delay_sec) = @_;
    my @tparts = gmtime($delay_sec);
    my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
    return($t);
}

#------------------------------------------

sub RollRunterSchlitz($$$)
{
    my ($r, $skipRunter, $ndelay) = @_;
    $ndelay ||= 0;

    if ($skipRunter==SKIP_NO || $skipRunter==SKIP_DOWN ) {
        if ($r->{state}!=STATE_SCHLITZ) {
            my $t1=getDelayTime($ndelay*$delaySec);
            my $t2=getDelayTime($ndelay*$delaySec+39);
            my $i=$tc++;

            Dbg("RollChg: $r->{roll} - runter schlitz($ndelay)\n");
            myfhem("define rc".$i." at +".$t1." set ".$r->{roll}." closes");
            myfhem("define ru".$i." at +".$t2." set ".$r->{roll}." up 6");
            $r->{state}=STATE_SCHLITZ;
        }
    }
}

#------------------------------------------

sub RollHoch($$$)
{
    my ($r, $skipHoch, $ndelay) = @_;
    $ndelay ||= 0;

    if ($skipHoch==SKIP_NO) {
        if ($r->{state}!=STATE_HOCH) {
            my $t1=getDelayTime($ndelay*$delaySec);
            my $i=$tc++;

            Dbg("RollChg: $r->{roll} - hoch($ndelay)\n");
            myfhem("define ro".$i." at +".$t1." set ". $r->{roll} ." opens");
            $r->{state}=STATE_HOCH;
        }
    }
}

#------------------------------------------

sub RollRunter($$$)
{
    my ($r, $skipRunter, $ndelay) = @_;
    $ndelay ||= 0;

    if ($skipRunter==SKIP_NO) {
        if ($r->{state}!=STATE_RUNTER) {
            my $t1=getDelayTime($ndelay*$delaySec);
            my $i=$tc++;

            Dbg("RollChg: $r->{roll} - runter($ndelay)\n");
            myfhem("define rc".$i." at +".$t1." set ".$r->{roll}." closes");
            $r->{state}=STATE_RUNTER;
        }
    }
}

#------------------------------------------

sub getWeather($)
{
    my ($wett)=@_;
    if($wett==30|| $wett==32 || $wett==34 || $wett==36) { # sonnig, heiter, heiss
	    return(WEATHER_SUNNY);
    }
    # cloudy: 26, 27, 28 29
    return(WEATHER_BAD);
}

sub IsSunny($)
{
    my ($wett)=@_;
    if($wett==30|| $wett==32 || $wett==34 || $wett==36) { # sonnig, heiter, heiss
	    return(1);
    }
    return(0);
}

#------------------------------------------

sub IsLater($)
{
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
	    $wettalt=$wett;
    }
    if($blocktimerRunning) {
	    if(!IsLater("$blocktime[2]:$blocktime[1]")) {
	        return(1);
	    } else {
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
    my $tempI=TEMP_IDLE; my $tempO=TEMP_IDLE;

    if ($temp    > $tempSoll+$tempIn_offset+0.5)  { $tempI=TEMP_HIGH; }
    if ($temp    < $tempSoll+$tempIn_offset-0.5)  { $tempI=TEMP_LOW; }
    if ($tempOut > $tempSoll+$tempOut_offset+0.5) { $tempO=TEMP_HIGH; }
    if ($tempOut < $tempSoll+$tempOut_offset-0.5) { $tempO=TEMP_LOW; }
    if ($tempOut < $tempSoll+$tempOut_offset-1.5) { $tempO=TEMP_COLD; }
    return($tempI, $tempO);
}

#------------------------------------------

# Sonne scheint ins Fenster ?
sub checkSunIn($$$$$)
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
    my $skipRunter=SKIP_NO; my $skipHoch=SKIP_NO;

    if ($winstate eq "Open") {
        # Offene Fenster nicht mit Rollaeden verschliessen
        $skipRunter=SKIP_ALL;
    } elsif (index($typ, "o") != -1) {
        Dbg("Skip0: t:$typ w:$winstate r:$skipRunter h:$skipHoch");

        # bei typ o nur auf schlitz schliessen
        $skipRunter=SKIP_DOWN;
    }
    # Zur Schlafzeit nicht oeffnen
    if (index($typ, "s") != -1) {
        #Dbg("Skip1: t:$typ w:winstate r:$skipRunter h:$skipHoch");
	    if($wach eq "0") {
            #Dbg("Skip2: t:$typ w:winstate r:$skipRunter h:$skipHoch");

	        $skipHoch=SKIP_ALL;
	    }
    }
    #Dbg("Skip: t:$typ w:winstate r:$skipRunter h:$skipHoch");
    return($skipRunter, $skipHoch);
}

#------------------------------------------

sub RollCheck()
{
    state $tagalt=0;
    state $wachalt=0;
    my $r;
    my $ndelay = 0;
    my $tempOut= ReadingsVal("myWH1080", "Temp-outside", 99);
    my $twil   = Value("twil");
    my $light  = ReadingsVal("twil", "light", 0);
    my $wett   = ReadingsVal("wetter", "code", 99);
    my $sr     = Value("sonnenrichtung");
    my $sunny  = IsSunny($wett);
    my $dawn   = 0;

    setTagHell($twil, $light);
    my $tag=Value("tag");
    my $wach=Value("wach");
    # Nach wechsel von sonne auf !sonne blockert ?
    my $sonneblock=IsWetterSonneWait($wett);
    if($twil>=7) { # ss-weather
      $dawn=1;
    }

    Dbg("RollCheck to:$tempOut twil:$twil light:$light wett:$wett sr:$sr block:$sonneblock\n");

    for $r ( @rolls ) {
        #Dbg("--------r:g ".$r->{roll}." / ".$r->{temp});

        my $tempIn=ReadingsVal($r->{temp},"temperature", 99);
        my($tempI, $tempO)=checkTemps($tempIn, $tempOut, $r->{tempSoll}); # Temperatur klassifizieren
        my $sunIn=checkSunIn($twil, $sr, $r->{dir}, $sonneblock, $sunny); # Sonne scheint ins Fenster ?
        # Offene Fenster nicht mit Rollaeden verschliessen, zur Schlafenszeit nicht öffnen
        my ($skipRunter, $skipHoch)=checkSkip(Value($r->{win}), $r->{typ}, $wach);
        Dbg("RollCheck:$r->{roll}-tempLevI,O:$tempI,$tempO tempI,O:$tempIn,$tempOut so:$sunIn wett:$wett sr:$sr "
             . "twil:$twil tag:$tag wach:$wach skipR,H:$skipRunter,$skipHoch st:$r->{state}");
        if (!$tag) {
            RollRunter($r, $skipRunter, $ndelay++);
        } elsif ($dawn) {
            RollHoch($r, $skipHoch, $ndelay++);
        } elsif ($tempI==TEMP_HIGH && (($sunIn && ($tempO!=TEMP_IDLE &&  $tempO>TEMP_COLD)) || $tempO==TEMP_HIGH)) {
            RollRunterSchlitz($r, $skipRunter, $ndelay++);
        } elsif (    ($tempI==TEMP_LOW && $tempO==TEMP_LOW) 
                  || (!$sunIn && ($tempO!=TEMP_IDLE && $tempO<TEMP_HIGH))) {
            RollHoch($r, $skipHoch, $ndelay++);
        } elsif ( ($tag && !$tagalt) || ($wach && !$wachalt) ) { # bei Tagesbeginn und im Temp-hysteresebereich -> hoch
            RollHoch($r, $skipHoch, $ndelay++);
        }
    } # for $r
    $tagalt=$tag;
    $wachalt=$wach;
}

#------------------------------------------

sub Untoggle($)
{
    my ($obj) = @_;
    if (Value($obj) eq "toggle"){
	    if (OldValue($obj) eq "off") {
	        {fhem ("setstate ".$obj." on")}
	    } else {
	        {fhem ("setstate ".$obj." off")}
	    }
    }
    else {
	    {fhem ("setstate ".$obj." ".Value($obj))}
    }
}


1;
