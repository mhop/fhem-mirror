package main;
use strict;
use warnings;
use POSIX;
sub
MyUtils_Initialize($$)
{
    my ($hash) = @_;
}

my @rollHoch = (
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

sub RollAll($$) {
   #Log 1, "################";
   my ($cmd, $delay) = @_;
   #Log 1, "c:$cmd d:$delay";
   #&RollGroup(\@rollAlle, $cmd, $delay);
   if($cmd eq "closes") {
     &RollGroup(\@rollRunter, $cmd,$delay);
   }
   else {
     &RollGroup(\@rollHoch, $cmd,$delay);
  }
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
