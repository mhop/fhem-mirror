
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
  TEMP_COLD => 0,
  TEMP_LOW => 1,
  TEMP_OK => 2,
  TEMP_HIGH => 3,
  TEMP_HOT => 4,
};
my $tempIn_offset=0;
my $tempOut_offset=+5;
my $tempOutForecastLimit=28;

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
    { roll => "wohn.rollTerrR", dir=>"W", typ=>"no", temp=>"tempWohn",   tempSoll=>20, win=>"wohn.fenTerr", block=>"",          state=>STATE_IDLE, },
    { roll => "wohn.rollTerrL", dir=>"W", typ=>"n",  temp=>"tempWohn",   tempSoll=>20, win=>"",             block=>"",          state=>STATE_IDLE, },
    { roll => "wohn.rollSofa",  dir=>"S", typ=>"n",  temp=>"tempWohn",   tempSoll=>20, win=>"",             block=>"",          state=>STATE_IDLE, },
    { roll => "ess.roll",       dir=>"S", typ=>"n",  temp=>"tempWohn",   tempSoll=>20, win=>"",             block=>"",          state=>STATE_IDLE, },
    { roll => "kuch.rollBar",   dir=>"S", typ=>"n",  temp=>"tempKueche", tempSoll=>20, win=>"",             block=>"",          state=>STATE_IDLE, },
    { roll => "kuch.rollStr",   dir=>"O", typ=>"n",  temp=>"tempKueche", tempSoll=>20, win=>"",             block=>"",          state=>STATE_IDLE, },
    { roll => "arb.rollTerr",   dir=>"W", typ=>"no", temp=>"tempStudio", tempSoll=>20, win=>"",             block=>"blockRoll", state=>STATE_IDLE, },
    { roll => "arb.rollWeg",    dir=>"S", typ=>"n",  temp=>"tempStudio", tempSoll=>20, win=>"",             block=>"",          state=>STATE_IDLE, },
    { roll => "bad.roll",       dir=>"S", typ=>"n",  temp=>"tempBad",    tempSoll=>22, win=>"",             block=>"",          state=>STATE_IDLE, },
    { roll => "schlaf.rollWeg", dir=>"S", typ=>"s",  temp=>"tempSchlaf", tempSoll=>18, win=>"",             block=>"",          state=>STATE_IDLE, },
    { roll => "schlaf.rollStr", dir=>"O", typ=>"so", temp=>"tempSchlaf", tempSoll=>18, win=>"",             block=>"",          state=>STATE_IDLE, },
);


my $tc=0;
my @blocktime=localtime;
my $blocktimerRunning=0;
#my @schlitzblocktime=localtime;
#my $schlitzBlocktimerRunning=0;
my $delaySec=11;

#------------------------------------------

sub myfhem($)
{
    #Log 1, "@_";
    fhem("@_");
}

#------------------------------------------

sub findRoll($)
{
    my($name) = @_;
    my $r=0;

    for $r (@rolls) {
        if ($r->{roll} eq $name) {
            return $r;
        }
    }
    return undef;
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
	    SchlitzBlockStart($r);
            myfhem("define rc".$i." at +".$t1." set ".$r->{roll}." closes");
            myfhem("define ru".$i." at +".$t2." set ".$r->{roll}." up 6");
            $r->{state}=STATE_SCHLITZ;
            return 1;
        }
    }
    return 0;
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
            return 1;
        }
    }
    return 0;
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
            return 1;
        }
    }
    return 0;
}

#------------------------------------------

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
	    #Dbg("later:$t");
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
		        Dbg("Wechsel auf sonnig");
	        }
	    }
	    $wettalt=$wett;
    }
    if($blocktimerRunning) {
	    if(!IsLater("$blocktime[2]:$blocktime[1]")) {
	        return(1);
	    } else {
	        $blocktimerRunning=0;
            Dbg("Sonnigblockierung Ende");
        }
    }
    return(0);
}

sub SchlitzBlockStart($)
{
    my ($r) = @_;
    @{$r->{bt}}=localtime;
    @{$r->{bt}}[2]+=2; # +2Std
    if(@{$r->{bt}}[2]>23) { @{$r->{bt}}[2]=23; } # da nachts keine sonne scheint egal
    $r->{btr}=1;
    Dbg("Schlitzblockstart $r->{roll}");
}

sub SchlitzBlockCheck($)
{
    my ($r) = @_;
    if($r->{btr}) {
        if(!IsLater("@{$r->{bt}}[2]:@{$r->{bt}}[1]")) {
            Dbg("Schlitz blocked");
            return(0);
        } else {
            $r->{btr}=0;
            Dbg("Schlitzblock End $r->{roll}");
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

# Die maximal für den aktuellen Tag verhergesagte Temperatur bestimmen
OBsub getTempMaxForecast()
{
    # aktuellen Wert auch einbeziehen
    my $max=ReadingsVal("wetter", "tempHigh", 20);
    for (my $i=1; $i<=6; $i++) {
        my $temp = ReadingsVal("wetter", "hfc".$i."_tempHigh", 20);
        if($temp>$max) { $max=$temp; }
        #print("i:$i t:$temp, m=$max\n");
    }
    return $max;
}

#------------------------------------------

# Raum zu warm und aussentemp hoch ?
sub checkTemps($$$)
{
    my($temp, $tempOut, $tempSoll)=@_;
    my $tempI=TEMP_OK; my $tempO=TEMP_OK;

    if ($temp    > $tempSoll+$tempIn_offset+3.0)  { $tempI=TEMP_HOT; }
    if ($temp    > $tempSoll+$tempIn_offset+0.5)  { $tempI=TEMP_HIGH; }
    if ($temp    < $tempSoll+$tempIn_offset-0.5)  { $tempI=TEMP_LOW; }
    if ($tempOut > $tempSoll+$tempOut_offset+4.0) { $tempO=TEMP_HOT; }
    if ($tempOut > $tempSoll+$tempOut_offset+1.0) { $tempO=TEMP_HIGH; }
    if ($tempOut < $tempSoll+$tempOut_offset-1.0) { $tempO=TEMP_LOW; }
    if ($tempOut < $tempSoll+$tempOut_offset-1.5) { $tempO=TEMP_COLD; }
    return($tempI, $tempO);
}

#------------------------------------------

# Sonne scheint ins Fenster ?
sub checkSunIn($$$$$)
{
    my($twil, $sun_dir, $win_dir, $sunblock, $sunny)=@_;
    # Sonne scheint ins Fenster ?
    my $sun_in=0;
    my $dir_in=0;
    if($twil>=5 && $twil<7) { # nur, wenn der Sonnenstand ueber 'weather' liegt
        if (index($sun_dir, $win_dir) != -1) { # Sonnenrichtung ins Fenster
            $dir_in=1;
	        if ($sunblock) { $sun_in=1; }
	        if ($sunny)    { $sun_in=1; }
	        #Dbg("son3, $sonne");
        }
    }
    return ($sun_in, $dir_in);
}

#------------------------------------------

# Offene Fenster nicht mit Rollaeden verschliessen
sub checkSkip($)
{
    my ($r)=@_;

    my $wach=Value("wach");
    my $winstate=Value($r->{win});
    my $typ=$r->{typ};
    my $skipRunter=SKIP_NO; my $skipHoch=SKIP_NO;

    if (Value($r->{block})) {
        $skipRunter=SKIP_ALL;
        $skipHoch=SKIP_ALL;
    }
    if ($winstate eq "Open") {
        # Offene Fenster nicht mit Rollaeden verschliessen
        $skipRunter=SKIP_ALL;
    } elsif (index($typ, "o") != -1) {
        #Dbg("Skip0: t:$typ w:$winstate r:$skipRunter h:$skipHoch");

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
    my $ndelay			= 0;
    my $tempOut			= ReadingsVal("myWH1080", "Temp-outside", 40);
    my $tempOutMaxForecast	= getTempMaxForecast(); #ReadingsVal("wetter", "tempHigh", 40),
    my $twil			= Value("twil");
    my $light			= ReadingsVal("twil", "light", 0);
    my $wett			= ReadingsVal("wetter", "code", 99);

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
    for $r ( @rolls ) {
        #Dbg("--------r:g ".$r->{roll}." / ".$r->{temp});
        my $run=0;
        my $tempIn=ReadingsVal($r->{temp},"temperature", 99);
        my($tempI, $tempO)=checkTemps($tempIn, $tempOut, $r->{tempSoll}); # Temperatur klassifizieren
        my($sunIn, $sunDir) =checkSunIn($twil, $sr, $r->{dir}, $sonneblock, $sunny); # Sonne scheint ins Fenster ?
        # Offene Fenster nicht mit Rollaeden verschliessen, zur Schlafenszeit nicht Ã¶ffnen
        my ($skipRunter, $skipHoch)=checkSkip($r);
        # Bedingungen zum Fahren
        my $Hot                =            $tempO>=TEMP_HOT;
        my $WarmSun            = $sunIn  && $tempO>=TEMP_HIGH;
        my $WarmHotIn          = $sunDir && $tempO>=TEMP_HIGH                          && $tempI>=TEMP_HOT;
        my $ForecastHotSun     = $sunIn  && $tempOutMaxForecast>=$tempOutForecastLimit;
        my $ForecastHotWarmIn  = $sunDir && $tempOutMaxForecast>=$tempOutForecastLimit && $tempI>=TEMP_HIGH;
        my $Cold        =              $tempO<=TEMP_COLD;
        my $NoSunNotHot = !$sunIn &&  ($tempO<=TEMP_LOW || $tempI<=TEMP_OK);

        if (!$tag) {
            $run=RollRunter($r, $skipRunter, $ndelay++);
        } elsif ($dawn) { # Abenddämmerung
            $run=RollHoch($r, $skipHoch, $ndelay++);
        } elsif ($Hot || $WarmSun || $WarmHotIn || $ForecastHotSun || $ForecastHotWarmIn) {
            $run=RollRunterSchlitz($r, $skipRunter, $ndelay++);
        } elsif ( $Cold || $NoSunNotHot ) {
            if(!SchlitzBlockCheck($r)) { $run=RollHoch($r, $skipHoch, $ndelay++); }
        } elsif ( ($tag && !$tagalt) || ($wach && !$wachalt) ) { # bei Tagesbeginn hoch
            $run=RollHoch($r, $skipHoch, $ndelay++);
        }
#        if ($run) {
            Dbg("RollCheck: H:$Hot WS:$WarmSun WHI:$WarmHotIn FHS:$ForecastHotSun FHI:$ForecastHotWarmIn C:$Cold NSNH:$NoSunNotHot "
                . "to:$tempOut twil:$twil light:$light wett:$wett sr:$sr block:$sonneblock tomax:$tempOutMaxForecast "
                . "$r->{roll}-tempLevI,O:$tempI,$tempO tempI,O:$tempIn,$tempOut sun:$sunIn/$sunDir wett:$wett sr:$sr "
                . "twil:$twil tag:$tag/$tagalt wach:$wach/$wachalt skipR,H:$skipRunter,$skipHoch st:$r->{state}");
#        }
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
