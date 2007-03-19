#############################################
# Low Budget ALARM System
##############################################
# ATTENTION! This is more a toy than a professional alarm system! 
# You must know what you do! 
##############################################
#  
# Concept:
# 1x Signal Light (FS20 allight) to show the status (activated/deactivated)
# 2x Sirene (in/out) (FS20 alsir1 alsir2 )
# 2x PIRI-2 (FS20 piriu pirio)
# 1x Sender (FS20 alsw) to activate/deactivate the system. 
# Tip: use the KeyMatic CAC with pin code or
# optional a normal sender (FS20 alsw2)
# 
# Add something like the following lines to the configuration file :
#   	notifyon alsw {MyAlsw()}
#   	notifyon alsw2 {MyAlswNoPin()}
#	notifyon piriu {MyAlarm()}
#	notifyon pirio {MyAlarm()}
# and put this file in the <modpath>/FHZ1000 directory.
#
# Martin Haas
##############################################


package main;
use strict;
use warnings;

sub
ALARM_Initialize($$)
{
  my ($hash) = @_;
}


##############################################
# Switching Alarm System on or off
sub
MyAlsw()
{
  my $ON="set allight on; setstate alsw on";
  my $OFF="set allight off; set alsir1 off; set alsir2 off; setstate alsw off";

	if ( -e "/var/tmp/alertsystem")
	{		
		unlink "/var/tmp/alertsystem";
		#Paranoia
		for (my $i = 0; $i < 2; $i++ )
		{
                                fhem "$OFF";
		};
                Log 2, "alarm system is OFF";
	} else	{
		system "touch /var/tmp/alertsystem";
		#Paranoia
		for (my $i = 0; $i < 2; $i++ )
		{
                         fhem "$ON"
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
                                die "test$i: more than $timedout sec";
                        }
                }
        system "touch -t 200601010101 /var/tmp/alontest*";
        Log 2, "ok, let's switch the alarm system...";

#if you only allow to activate (and not deactivate) with this script:
	# if ( -e "/var/tmp/alertsystem") { die "deactivating alarm system not allowed"};

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

                my $timer=180;  # time until the sirene will be quiet
                my $ON1="set alsir1 on-for-timer $timer";
                my $ON2="set alsir2 on-for-timer $timer";


                #Paranoia
                for (my $i = 0; $i < 2; $i++ )
                {
                        fhem "$ON1";
                        fhem "$ON2";
                }
                Log 2, "ALARM! #################" ;


                # have fun
                my @lights=("stuwz1", "stuwz2", "nachto", "nachtu", "stoliba" ,"stlileo");
                my @rollos=("rolu4", "rolu5", "roloadi", "rololeo", "roloco", "rolowz", "rolunik1", "rolunik2");

                foreach my $light (@lights) {
                        fhem "set $light on"
                }

                foreach my $rollo (@rollos) {
                        fhem "set $rollo on"
                }
        }
}

1;
