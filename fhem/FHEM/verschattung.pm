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
    { roll => "wohn.rollTerrR", dir=>"W", typ=>"n", temp=>"tempWohn",   tempSoll=>20, tempSchalt=>-1, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "wohn.rollTerrL", dir=>"W", typ=>"n", temp=>"tempWohn",   tempSoll=>20, tempSchalt=>-1, win=>"",             state=>STATE_IDLE, },
    { roll => "wohn.rollSofa",  dir=>"S", typ=>"n", temp=>"tempWohn",   tempSoll=>20, tempSchalt=>-1, win=>"",             state=>STATE_IDLE, },
    { roll => "ess.roll",       dir=>"S", typ=>"n", temp=>"tempWohn",   tempSoll=>20, tempSchalt=>-1, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollBar",   dir=>"S", typ=>"n", temp=>"tempKueche", tempSoll=>20, tempSchalt=>-1, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollStr",   dir=>"O", typ=>"n", temp=>"tempKueche", tempSoll=>20, tempSchalt=>-1, win=>"",             state=>STATE_IDLE, },
    { roll => "arb.rollTerr",   dir=>"W", typ=>"n", temp=>"tempStudio", tempSoll=>20, tempSchalt=>-1, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "arb.rollWeg",    dir=>"S", typ=>"n", temp=>"tempStudio", tempSoll=>20, tempSchalt=>-1, win=>"",             state=>STATE_IDLE, },
    { roll => "bad.roll",       dir=>"S", typ=>"n", temp=>"tempBad",    tempSoll=>23, tempSchalt=>-1, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollWeg", dir=>"S", typ=>"s", temp=>"tempSchlaf", tempSoll=>18, tempSchalt=>-1, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollStr", dir=>"O", typ=>"s", temp=>"tempSchlaf", tempSoll=>18, tempSchalt=>-1, win=>"wohn.fenTerr", state=>STATE_IDLE, },
);

my @schatten = (
    { roll => "wohn.rollTerrR", dir=>"W", typ=>"n", temp=>"tempWohn",   tempSoll=>20, win=>"wohn.fenTerr", },
    { roll => "wohn.rollTerrL", dir=>"W", typ=>"n", temp=>"tempWohn",   tempSoll=>20, win=>"",             },
    { roll => "wohn.rollSofa",  dir=>"S", typ=>"n", temp=>"tempWohn",   tempSoll=>20, win=>"",             },
    { roll => "ess.roll",       dir=>"S", typ=>"n", temp=>"tempWohn",   tempSoll=>20, win=>"",             },
    { roll => "kuch.rollBar",   dir=>"S", typ=>"n", temp=>"tempKueche", tempSoll=>20, win=>"",             },
    { roll => "kuch.rollStr",   dir=>"O", typ=>"n", temp=>"tempKueche", tempSoll=>20, win=>"",             },
    { roll => "arb.rollTerr",   dir=>"W", typ=>"n", temp=>"tempStudio", tempSoll=>20, win=>"wohn.fenTerr", },
    { roll => "arb.rollWeg",    dir=>"S", typ=>"n", temp=>"tempStudio", tempSoll=>20, win=>"",             },
    { roll => "bad.roll",       dir=>"S", typ=>"n", temp=>"tempBad",    tempSoll=>23, win=>"",             },
    { roll => "schlaf.rollWeg", dir=>"S", typ=>"s", temp=>"tempSchlaf", tempSoll=>18, win=>"",             },
    { roll => "schlaf.rollStr", dir=>"O", typ=>"s", temp=>"tempSchlaf", tempSoll=>18, win=>"wohn.fenTerr", },
);

my @rollStates = {
    { state=>STATE_IDLE }, # "wohn.rollTerrR", 
    { state=>STATE_IDLE }, # "wohn.rollTerrL", 
    { state=>STATE_IDLE }, # "wohn.rollSofa",  
    { state=>STATE_IDLE }, # "ess.roll",       
    { state=>STATE_IDLE }, # "kuch.rollBar",   
    { state=>STATE_IDLE }, # "kuch.rollStr",   
    { state=>STATE_IDLE }, # "arb.rollTerr",   
    { state=>STATE_IDLE }, # "arb.rollWeg",    
    { state=>STATE_IDLE }, # "bad.roll",       
    { state=>STATE_IDLE }, # "schlaf.rollWeg", 
    { state=>STATE_IDLE }, # "schlaf.rollStr", 
};

#my %rollStates = (
#  lastWeatherCode => 0,
#  lastWaetherCodeTime => 0,
#  timerNum => 0,
#    );
    

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
my $tempHystOffset=-0.9;
my $tempHighOffset=0.3;

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

    #local $" = ', ';
    #print "@myrolls  $cmd\n";
    
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
#   Log 1, "################";
   my ($cmd, $delay) = @_;
#   Log 1, "c:$cmd d:$delay";
#   &RollGroup(\@rollAlle, $cmd, $delay);
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
#   myfhem("set wach 1");
}

#------------------------------------------

sub Dbg($) {
    if(Value("DebugRoll") eq "1") {
	Log 1,$_[0];
    }
}

#------------------------------------------

 sub RollRunterSchlitz($;$) {
    my ($roll, $delay) = @_;
    $delay ||= 0; 
    
    my @tparts = gmtime($delay);
    my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
    my @tparts2 = gmtime($delay+40);
    my $t2=sprintf ("%02d:%02d:%02d",@tparts2[2,1,0]);
    my $i=$tc++;

    Dbg("RollChg: $roll - runter schlitz($delay)\n");
    myfhem("define r".$i." at +".$t." set ".$roll." closes");
    myfhem("define ru".$i." at +".$t2." set ".$roll." up 6");
}

sub CalcDelay()
{
    my ($delay) = @_;
    $delay ||= 0; 
    
    my @tparts = gmtime($delay);
    my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
    my @tparts2 = gmtime($delay+40);
    my $t2=sprintf ("%02d:%02d:%02d",@tparts2[2,1,0]);
    my $n=$tc++;
}


sub RollRunterSchlitzNeu($;$) {
    my ($r, $rs, $delay) = @_;
    $delay ||= 0; 
    
    if($rs->{state}!=STATE_SCHLITZ) {
	my ($t1, $t2, $n)=CalcDelay($delay);

	Dbg("RollChg: $roll - runter schlitz($delay)\n");
	myfhem("define r".$n." at +".$t1." set ".$r->{roll}." closes");
	myfhem("define ru".$n." at +".$t2." set ".$r->{roll}." up 6");
    }
    $rs->{state}=STATE_SCHLITZ;
}

#------------------------------------------

sub RollHoch($;$) {
    my ($roll, $delay) = @_;
    $delay ||= 0; 
    
    my @tparts = gmtime($delay);
    my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
    my $i=$tc++;

    Dbg("RollChg: $roll - hoch($delay)\n");
    myfhem("define r".$i." at +".$t." set ".$roll." opens");
}

sub RollHoch2($;$) {
    my ($roll, $delay) = @_;
    $delay ||= 0; 
    
    if($rs->{state}!=STATE_HOCH) {
	my ($t1, $t2, $n)=CalcDelay($delay);

	Dbg("RollChg: $roll - hoch($delay)\n");
	myfhem("define r".$n." at +".$t1." set ".$r->{roll}." opens");
    }
    $rs->{state}=STATE_HOCH;
}


#------------------------------------------

sub RollRunter($;$) {
    my ($roll, $delay) = @_;
    $delay ||= 0; 
    
    my @tparts = gmtime($delay);
    my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
    my $i=$tc++;

    Dbg("RollChg: $roll - runter($delay)\n");
    myfhem("define r".$i." at +".$t." set ".$roll." closes");
}

sub RollRunter2($;$) {
    my ($roll, $delay) = @_;
    $delay ||= 0; 
    
    if($rs->{state}!=STATE_RUNTER) {
	my ($t1, $t2, $n)=CalcDelay($delay);

	Dbg("RollChg: $roll - runter($delay)\n");
	myfhem("define r".$n." at +".$t." set ".$r->{roll}." closes");
    }
    $rs->{state}=STATE_HOCH;
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

sub IsSunBlocked($$)
{
    my ($sonneAn, $rs)=@_;;
    
    state $sonnealt=0;
    if($sonneAn != $sonneAnalt) {
	if($sonneAn != 0) {
	    $rs->{@blocktime}=localtime;
	    $rs->{blocktime}[2]+=2; # +2Std
	    if($rs->{blocktime}[2]>23) { $rs->$blocktime[2]=23; } # da nachts keine sonne scheint egal
	    $rs->{blocktimerRunning}=1;
	}
	$sonneAnalt=$sonneAn
    }
    if($rs->{blocktimerRunning}) {
	if(!IsLater("$rs->{blocktime}[2]:$rs->{blocktime}[1]")) {
	    return(1);
	}
	else {
	    $rs->{blocktimerRunning}=0;
	}
    }
    return(0);
}

#------------------------------------------
	 
# Nach dem Wechsel auf !sonne noch 2Std warten
sub IsWetterSonneWait($)  {
    my ($wett)=@_;

    state $wettalt=0;
    if($wett != $wettalt) {
	if(!IsSunny($wett)) {
	    if(IsSunny($wettalt)) {
		@blocktime=localtime;
		$blocktime[2]+=2; # +2Std
                if($blocktime[2]>23) { $blocktime[2]=23; } # da nachts keine sonne scheint egal
                $blocktimerRunning=1;
		Dbg("son1");	
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

sub CheckSum($)
{
    my ($r, $rs)=@_;

    my $twil=Value("twil");
    my $sonneAn=0;
    my $sonneAus=0;
    
    if($twil>=5 && $twil<7) { # nur, wenn der Sonnenstand ueber 'weather' liegt
	my $tempSoll=$r->{tempSoll};
	my $temp=ReadingsVal($r->{temp},"temperature", 99);
	my $tempOut=ReadingsVal("myWH1080", "Temp-outside", 99);
	
	# bei hoher Raum- und Aussentemperatur immer unten lassen
	if( ($temp > ($tempSoll-1)) && ($tempOut > $tempSoll) ) { 
	    $sonneAn=1;
	}
	elsif(($temp < ($tempSoll-1-$tempHyst)) && ($tempOut < ($tempSoll-$tempHyst)) ) { 
	    $sonneAus=1;
	}
	
	# Sonne scheint ins Fenster ?
	elsif (index($sr, $r->{dir}) != -1) { # Sonnenrichtung ins Fenster
	    if(IsSunny($wett)) {
		$sonneAn=1;
	    }
	    else {
	        $sonneAus=1;
	    }
	}

	if(IsSunBlocked($rs, $sonneAn)) {
	    $sonneAus=0;
	}
    }
    return ($sonneAn, $SonneAus);
}

#------------------------------------------

sub CheckTemp()
{
    my ($r, $rs)=@_;

    my $temp=ReadingsVal($r->{temp},"temperature", 99);
    my $tempSoll=$r->{tempSoll};

    if( ($temp>$tempSoll && $tempOut>($tempSoll-3)) || $temp>($tempSoll+2) ) {
	$tempH=1;
    }
    if( $temp<$tempSoll-1 ) {
	$tempL=1;
    }
}


# Offene Fenster nicht mit Rollaeden verschliessen
sub CheckSkip()
{
    my ($r, $rs)=@_;

    my $skipRunter=0;
    my $skipHoch=0;

    if($r->{win} ne "") {
	my $fen=Value($r->{win});
	#Dbg("test win:$r->{roll}-$fen");	
	if ($fen eq "Open") {
	    #Dbg("$r->{roll}:skipR");
	    $skipRunter=1;
	}
    }
    # Zur Schlafzeit nicht oeffnen
    if($r->{typ} eq "s") {
	if(Value("wach") eq "0") {
	    $skipHoch=1;
	}
    }
}

sub CheckTag()
{
    my $tag=0;
    my $twil=Value("twil");
    if ($twil>=3 && $twil<10) { # civil
	$tag=1;
        myfhem("set tag 1");
    } else {
        myfhem("set tag 0");
    }
}


sub CheckHell()
{
    my $light=ReadingsVal("twil", "light", 0);
    if ($light>=5) { # weather
        myfhem("set hell 1");
    } else {
        myfhem("set hell 0");
    }
}


sub SetRollNew()
{
    my ($tag, $sonne,$tempH, $tempL, $skipHoch, $skipRunter)=@_;

    if( $tag and $sonne and $tempH) {
	if(!$skipHoch && !$skipRunter) {
	    if($rs->{state}!=STATE_SCHLITZ) {
		RollRunterSchlitz($r, $rs, $ndelay);
	    }
	}
	$rs->{state}=STATE_SCHLITZ;
    }
	
	if(($tag && !$sonne)||($tag && $tempL)) {
            if($rs->{state}!=STATE_HOCH) {
		$tempHyst=0;
                if(!$skipHoch) {
                    RollHoch($r->{roll}, $ndelay); 
		    $rs->{state}=STATE_HOCH;
		}
	    }
	}

	if(!$tag) {
            if($rs->{state}!=STATE_RUNTER) {
		if(!$skipRunter) {
                    RollRunter($r->{roll}, $ndelay);
		}
                $rs->{state}=STATE_RUNTER;
	    }
	}
	if($tempHyst<50) {
	    $rs->{tempSchalt}=$tempSoll+$tempHyst;
        }
	$i=$i+1;

sub RollCheckNeu()
{

    for $r ( @rolls ) {
	my $rs= shift @rollStates;

	my($SonneAn, $sonnAus) = CheckSun($r, $rs);
	my($tempH, $tempL) = CheckTemp($r, $rs);
	my($skipHoch, $skipRunter) = CheckSkip($r, $rs);
	my $tag=CheckTag();
	CheckHell();
	
    }
	
}
sub RollCheck() {
    my $temp=20;
    my $r;
    my $i=0;
    my $delay=11;
    my $tag=0;

    #my $tempOut=ReadingsVal("wetter", "temp_c", 99);
    #my $tempOut=ReadingsVal("naAussen", "temperature", 99);
    my $tempOut=ReadingsVal("myWH1080", "Temp-outside", 99);

    my $twil=Value("twil");
    if ($twil>=3 && $twil<10) { # civil
	$tag=1;
        myfhem("set tag 1");
    } else {
        myfhem("set tag 0");
    }
    my $light=ReadingsVal("twil", "light", 0);
    if ($light>=5) { # weather
        myfhem("set hell 1");
    } else {
        myfhem("set hell 0");
    }
    my $wett=ReadingsVal("wetter", "code", 99);
    my $sr=Value("sonnenrichtung");

    # Nach wechsel von sonne auf !sonne blockert ? 
    my $sonneblock=IsWetterSonneWait($wett);
 
    Dbg("RollCheck to:$tempOut twil:$twil light:$light wett:$wett sr:$sr block:$sonneblock\n");

    for $r ( @rolls ) {
	my $rs= shift @rollStates;
	my $fen="Closed";
	my $tempH=0;
        my $tempL=0;
	my $sonne=0;
        my $skipRunter=0;
        my $skipHoch=0;
        my $ndelay=$i*$delay+1;
	#Dbg("--------r:g ".$r->{roll}." / ".$r->{temp});

        # Raum zu warm und aussentemp hoch ?
        #$temp=ReadingsVal($r->{temp},"measured-temp", 99);
        $temp=ReadingsVal($r->{temp},"temperature", 99);
        my $tempSoll=$r->{tempSoll};
        my $tempSchalt=$tempSoll;
        my $tempHyst=99;
        if($rs->{tempSchalt}>-1) { 
	    $tempSchalt=$rs->{tempSchalt};
	}

	if( ($temp>$tempSoll && $tempOut>($tempSoll-3)) || $temp>($tempSoll+2) ) {
	    $tempH=1;
	}
	if( $temp<$tempSoll-1 ) {
	   $tempL=1;
	}
       
# RollCheck:kuch.rollBar-tempH:1 temp:20.25 tempO:32.7 so:0 wett:32 sr:WN twil:6 tag:1 fen:Closed skipR:0 skipH:0 st:3 h:99 ts:20
	# my($SonneAn, $sonnAus) = CheckSun($r, $rs) 
	
	# Sonne scheint ins Fenster ?
        if($twil>=5 && $twil<7) { # nur, wenn der Sonnenstand ueber 'weather' liegt
	    # bei hoher Raum- und Aussentemperatur immer unten lassen
	    if($temp > ($tempSchalt+$tempHighOffset) && $tempOut > $tempSchalt+$tempHighOffset) { 
		$sonne=1;
		$tempHyst=$tempHystOffset;
	    }
	    elsif (index($sr, $r->{dir}) != -1) { # Sonnenrichtung ins Fenster
		if(IsSunny($wett)) {
		    $sonne=1;
		}
		#Dbg("son3, $sonne");	
	    }
	}

	if(IsSunBlocked($sonne)) {
	    $sonne=1;
	}

        # Offene Fenster nicht mit Rollaeden verschliessen
        if($r->{win} ne "") {
	    $fen=Value($r->{win});
            #Dbg("test win:$r->{roll}-$fen");	
            if ($fen eq "Open") {
		#Dbg("$r->{roll}:skipR");
                $skipRunter=1;
	    }
        }
        # Zur Schlafzeit nicht oeffnen
        if($r->{typ} eq "s") {
	    if(Value("wach") eq "0") {
		$skipHoch=1;
            }
	}

        Dbg("RollCheck:$r->{roll}-tempH:$tempH temp:$temp tempO:$tempOut so:$sonne wett:$wett sr:$sr twil:$twil tag:$tag fen:$fen skipR:$skipRunter skipH:$skipHoch st:$r->{state} h:$tempHyst ts:$tempSchalt");

	if( $tag and $sonne and $tempH) {
            if($rs->{state}!=STATE_SCHLITZ) {
                if(!$skipHoch && !$skipRunter) {
                    RollRunterSchlitz($r->{roll}, $ndelay);
                }
                $rs->{state}=STATE_SCHLITZ;
	    }
	}
	
	if(($tag && !$sonne)||($tag && $tempL)) {
            if($rs->{state}!=STATE_HOCH) {
		$tempHyst=0;
                if(!$skipHoch) {
                    RollHoch($r->{roll}, $ndelay); 
		    $rs->{state}=STATE_HOCH;
		}
	    }
	}

	if(!$tag) {
            if($rs->{state}!=STATE_RUNTER) {
		if(!$skipRunter) {
                    RollRunter($r->{roll}, $ndelay);
		}
                $rs->{state}=STATE_RUNTER;
	    }
	}
	if($tempHyst<50) {
	    $rs->{tempSchalt}=$tempSoll+$tempHyst;
        }
	$i=$i+1;
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
