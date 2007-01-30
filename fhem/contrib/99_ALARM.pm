##############################################
# Low Budget ALARM System
##############################################
# ATTENTION! This is more a toy than a real alarm system! You must know what you do! 
##############################################
#  
# Concept:
# 1x Signal Light (FS20 allight) to show the status (activated/deactivated)
# 1x Sirene (FS20 alsir1)
# 2x PIRI-2 (FS20 piriu pirio)
# 1x Sender (FS20 alsw) to activate/deactivate the system. 
# Tip: use the KeyMatic CAC with pin code
# optional a normal sender (not a Keymatic CAC) FS20 alsw2
# 
# Add something like the following lines to the configuration file :
#   	notifyon alsw {MyAlsw()}
#   	notifyon alsw2 {MyAlswNoPin()}
#	notifyon piriu {MyAlarm()}
#	notifyon pirio {MyAlarm()}
# and put this file in the <modpath>/FHEM directory.
#
# Martin Haas
##############################################


package main;
use strict;
use warnings;

sub
ALARM_Initialize($)
{
  my ($hash) = @_;

  $hash->{Category} = "none";
}


##############################################
# Switching Alarm System on or off
sub
MyAlsw()
{
  my $ON="set allight on; setstate alsw on";
  my $OFF1="set allight off";
  my $OFF2="set alsir1 off";
  my $OFF3="setstate alsw off";

	if ( -e "/var/tmp/alertsystem")
	{		
		unlink "/var/tmp/alertsystem";
		for (my $i = 0; $i < 2; $i++ )
		{
                                fhz "$OFF1";
                                fhz "$OFF2";
                                fhz "$OFF3";
		};
                Log 2, "alarm system is OFF";
	} else	{
		system "touch /var/tmp/alertsystem";
		for (my $i = 0; $i < 2; $i++ )
		{
                         fhz "$ON"
		}
                Log 2, "alarm system is ON";
	};
}


##############################################
# If you have no Keymatic then use this workaround:
# After 4x pushing a fs20-button within some seconds it will activate/deactivate the alarm system.
sub 
MyAlswNoPin()
{

my $timedout=5;

## first time
        if ( ! -e "/var/tmp/alontest1")
        {
                for (my $i = 1; $i < 4; $i++ )
                {
                        system "touch /var/tmp/alontest$i";
                        system "touch -t 200601010101 /var/tmp/alontest$i";
                }
        }


## test 4 times
        my $now= `date +%s`;
                for (my $i = 1; $i < 4; $i++ )
                {
                        my $tagx=`date -r /var/tmp/alontest$i +%s`;
                        my $testx=$now-$tagx;

                        if  ( $testx > $timedout )
                        {
                                system "touch /var/tmp/alontest$i";
                                Log 2, "test$i: more than $timedout sec\n";
                                die;
                        }
                }
        system "touch -t 200601010101 /var/tmp/alontest*";
        Log 2, "ok, let's switch the alarm system...";

#if you only allow to activate (and not deactivate) with this script:
# if ( -e "/var/tmp/alertsystem") { die; };

	MyAlsw();
}




##############################################
# ALARM! Do what you want!
sub 
MyAlarm()
{

        #alarm-system activated??
        if ( -e "/var/tmp/alertsystem")
        {


                my $timer=180;  # time until the sirene will be quit
                my $ON1="set alsir1 on-for-timer $timer";


                #Paranoia
                for (my $i = 1; $i < 3; $i++ )
                {
                        fhz "$ON1";
                }
                Log 2, "ALARM! $ON1" ;


                # have fun
                my @lights=("stuwz1", "stuwz2", "stunacht", "stonacht", "stoliba");
                my @rollos=("rolu4", "rolu5", "roloadi", "rololeo", "roloco", "rolowz", "rolunik1", "rolunik2");

                foreach my $light (@lights) {
                        fhz "set $light on"
                }

                foreach my $rollo (@rollos) {
                        fhz "set $rollo on"
                }
        }
}

1;
