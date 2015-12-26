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
    { roll => "wohn.rollTerrR", dir=>"W", typ=>"n", temp=>"tempWohn",   tempS=>21, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "wohn.rollTerrL", dir=>"W", typ=>"n", temp=>"tempWohn",   tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "wohn.rollSofa",  dir=>"S", typ=>"n", temp=>"tempWohn",   tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "ess.roll",       dir=>"S", typ=>"n", temp=>"tempWohn",   tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollBar",   dir=>"S", typ=>"n", temp=>"tempKueche", tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollStr",   dir=>"O", typ=>"n", temp=>"tempKueche", tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "arb.rollTerr",   dir=>"W", typ=>"n", temp=>"tempStudio", tempS=>21, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "arb.rollWeg",    dir=>"S", typ=>"n", temp=>"tempStudio", tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "bad.roll",       dir=>"S", typ=>"n", temp=>"tempBad",    tempS=>23, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollWeg", dir=>"S", typ=>"s", temp=>"tempSchlaf", tempS=>18, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollStr", dir=>"O", typ=>"s", temp=>"tempSchlaf", tempS=>18, win=>"wohn.fenTerr", state=>STATE_IDLE, },
);

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

sub myfhem($) {
    #Log 1, "@_";
    fhem("@_");
}

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

sub RollCmd($$$)
{
    my ($cmd, $roll, $delay) = @_;
    if(RollCheckSkip($cmd, $roll)==0) {
        myfhem ("define r".int(rand(10000))." at +".$delay." set ".$roll." ".$cmd);
    }
}
     
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

sub RollTest() {
     &RollGroup(\@rollTest, "closes", 1);
}

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


sub RollWeck($) {
   my ($delay) = @_;
   &RollGroup(\@rollWeck, "up 5", $delay);
   myfhem("define weckwachat at +03:00:00 set wach 1");
#   myfhem("set wach 1");
}

#------------------------------------------

sub Dbg($) {
    Log 1,$_[0];
}

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

sub RollHoch($;$) {
    my ($roll, $delay) = @_;
    $delay ||= 0; 
    
    my @tparts = gmtime($delay);
    my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
    my $i=$tc++;

    Dbg("RollChg: $roll - hoch($delay)\n");
    myfhem("define r".$i." at +".$t." set ".$roll." opens");
}

sub RollRunter($;$) {
    my ($roll, $delay) = @_;
    $delay ||= 0; 
    
    my @tparts = gmtime($delay);
    my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
    my $i=$tc++;

    Dbg("RollChg: $roll - runter($delay)\n");
    myfhem("define r".$i." at +".$t." set ".$roll." closes");
}

sub IsSunny($) {
    my ($wett)=@_;
    if($wett==30 || $wett==31 || $wett==32 || $wett==33 || $wett==34 || $wett==35 || $wett==36) { # sonnig, heiter, heiss
	return(1);
    }
    return(0);
}

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

sub RollCheck() {
#    Dbg("RollCheck\n");
    my $temp=20;
    my $r;
    my $i=0;
    my $delay=11;
    my $tag=0;

    my $tempOut=ReadingsVal("wetter", "temp_c", 99);

    my $twil=Value("twil");
    if($twil>=3 && $twil<10) { # civil
	$tag=1;
    }

    my $wett=ReadingsVal("wetter", "code", 99);
    my $sr=Value("sonnenrichtung");

    # Nach wechsel von sonne auf !sonne blockert ? 
    my $sonneblock=IsWetterSonneWait($wett); 

    for $r ( @rolls ) {

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
	if( ($temp>$r->{tempS} && $tempOut>($r->{tempS}-3)) || $temp>($r->{tempS}+2) ) {
	    $tempH=1;
	}
	if( $temp<$r->{tempS}-1 ) {
	    $tempL=1;
	}

	# Sonne scheint ins Fenster ?
        if($twil>=5 && $twil<7) { # nur, wenn der Sonnenstand ueber 'weather' liegt
	    # bei hoher Raum- und Aussentemperatur immer unten lassen
	    if($temp > ($r->{tempS}+2) && $tempOut > $r->{tempS}) { 
		$sonne=1;
	    }
	    elsif (index($sr, $r->{dir}) != -1) { # Sonnenrichtung ins Fenster
		if($sonneblock) {
		    $sonne=1;
                }
		elsif(IsSunny($wett)) {
		    $sonne=1;
		}
		#Dbg("son3, $sonne");	
	    }
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

        #Dbg("RollCheck:$r->{roll}-tempH:$tempH temp:$temp tempO:$tempOut so:$sonne wett:$wett sr:$sr twil:$twil tag:$tag fen:$fen skipR:$skipRunter skipH:$skipHoch st:$r->{state}");

	if( $tag and $sonne and $tempH) {
            if($r->{state}!=STATE_SCHLITZ) {
                if(!$skipHoch && !$skipRunter) {
                    RollRunterSchlitz($r->{roll}, $ndelay);
                }
                $r->{state}=STATE_SCHLITZ;
	    }
	}
	
	if(($tag && !$sonne)||($tag && $tempL)) {
            if($r->{state}!=STATE_HOCH) {
                if(!$skipHoch) {
                    RollHoch($r->{roll}, $ndelay); 
		    $r->{state}=STATE_HOCH;
		}
	    }
	}

	if(!$tag) {
            if($r->{state}!=STATE_RUNTER) {
		if(!$skipRunter) {
                    RollRunter($r->{roll}, $ndelay);
		}
                $r->{state}=STATE_RUNTER;
	    }
	}
	$i=$i+1;
    } # for
}


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
