package main;
use strict;
use warnings;
use POSIX;
sub
MyUtils_Initialize($$)
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
    { roll => "wohn.rollTerrR", dir=>"W", typ=>"n", temp=>"wohn.fht",   tempS=>21, win=>"wohn.fenTerr", state=>STATE_IDLE, },
    { roll => "wohn.rollTerrL", dir=>"W", typ=>"n", temp=>"wohn.fht",   tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "wohn.rollSofa",  dir=>"S", typ=>"n", temp=>"wohn.fht",   tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "ess.roll",       dir=>"S", typ=>"n", temp=>"wohn.fht",   tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollBar",   dir=>"S", typ=>"n", temp=>"wohn.fht",   tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "kuch.rollStr",   dir=>"O", typ=>"n", temp=>"wohn.fht",   tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "arb.rollTerr",   dir=>"W", typ=>"n", temp=>"studio.fht", tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "arb.rollWeg",    dir=>"S", typ=>"n", temp=>"studio.fht", tempS=>21, win=>"",             state=>STATE_IDLE, },
    { roll => "bad.roll",       dir=>"S", typ=>"n", temp=>"bad.fht",    tempS=>23, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollWeg", dir=>"S", typ=>"s", temp=>"schlaf.fht", tempS=>18, win=>"",             state=>STATE_IDLE, },
    { roll => "schlaf.rollStr", dir=>"O", typ=>"s", temp=>"schlaf.fht", tempS=>18, win=>"",             state=>STATE_IDLE, },
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



sub myfhem($) {
    #print "@_\n";
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

sub Dbg($) {
    Log 1,$_[0];
}


sub RollCheck() {
#    Dbg("RollCheck\n");
    my $temp=20;
    my $wett;
    my $twil;
    my $r;
    my $sr;
    my $i=0;
    my $delay=11;

    for $r ( @rolls ) {

	my $fen="Closed";
	my $tempH=0;
	my $sonne=0;
	my $tag=0;
        my $skipRunter=0;
        my $skipHoch=0;
	my @tparts = gmtime($i*$delay+1);
        my $t=sprintf ("%02d:%02d:%02d",@tparts[2,1,0]);
	my @tparts2 = gmtime($i*$delay+40);
        my $t2=sprintf ("%02d:%02d:%02d",@tparts2[2,1,0]);

#	Dbg("r:g ".$r->{roll}." / ".$r->{temp}."\n");

        $temp=ReadingsVal($r->{temp},"measured-temp", 99);
	if($temp > $r->{tempS}) {
	    $tempH=1;
	}
	
        $twil=Value("twil");
	if($twil>=3 && $twil<10) { # civil
	    $tag=1;
	}

        $wett=ReadingsVal("wetter", "code", 99);
        $sr=Value("sonnenrichtung");
        if($twil>=5 && $twil<8) { # indoor
	    if($wett==30 || $wett==32 || $wett==34 || $wett==36) { # sonnig, heiter, heiss
		if (index($sr, $r->{dir}) != -1) {
		    $sonne=1;
		}
	    }
	}

        if($r->{win} ne "") {
	    $fen=Value($r->{win});
            Dbg("test win:$r->{roll}-$fen");	
            if ($fen eq "Open") {
		Dbg("$r->{roll}:skipR");
                $skipRunter=1;
	    }
        }
        if($r->{typ} eq "s") {
	    if(Value("wach") eq "0") {
		$skipHoch=1;
            }
	}

        Dbg("RollCheck:$r->{roll}-tempH:$tempH temp:$temp so:$sonne wett:$wett sr:$sr twil:$twil tag:$tag fen:$fen skipR:$skipRunter skipH:$skipHoch");

	if( $tag and $sonne and $tempH) {
            if($r->{state}!=STATE_SCHLITZ) {
                if(!$skipHoch && !$skipRunter) { 
		    myfhem("define r".$i." at +".$t." set ".$r->{roll}." closes");
		    myfhem("define ru".$i." at +".$t2." set ".$r->{roll}." up 7");
		    Dbg("RollChg: $r->{roll} - runter schlitz\n");
                }
                $r->{state}=STATE_SCHLITZ;
	    }
	}
	
	if($tag && !$sonne) {
            if($r->{state}!=STATE_HOCH) {
                if(!$skipHoch) { 
		    myfhem("define r".$i." at +".$t." set ".$r->{roll}." opens");
		    Dbg("RollChg: $r->{roll} - hoch\n");
		    $r->{state}=STATE_HOCH;
		}
	    }
	}

	if(!$tag) {
            if($r->{state}!=STATE_RUNTER) {
		if(!$skipRunter) {
		    myfhem("define r".$i." at +".$t." set ".$r->{roll}." closes");
		    Dbg("RollChg: $r->{roll} -  runter\n");
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
