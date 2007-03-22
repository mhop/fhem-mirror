<?php

##################################################################################
#### pgm3 -- a PHP-webfrontend for fhz1000.pl 


###### required settings
	$fhz1000="fhz"; #only php5 ! On which machine is fhz1000 runnning??
					# if it is not localhost then the fhz1000.cfg must
					# run global: "port <nr> global"
	$fhz1000port="7072";		# port of fhz1000.pl
	$logpath="/var/tmp";		# where are your logs?
	$fhz1000_pl="/home/FHZ/fhz1000/fhz1000.pl"; #only required if you are using PHP4

##################################################################################
###### nice to have


###### showgnuplot 
	# Gnuplot will automatically show the pictures.
	# There is no reason any more to deactivate Gnuplot. Values: 0/1
	$showgnuplot=1;
	$gnuplot='/usr/bin/gnuplot';		# location of gnuplot
	$pictype='png';  	

#####	logrotate of hms, ks300, fht
	# this is only possible, if the webserver (e.g.wwwrun) has the rights ro write the
	# files from fh1000.pl. If you want that then run fhz1000.pl as wwwrun too.
	# if 'yes' then only the needed lines are in the logfiles, the rest will be deleted.
	$logrotate='yes';	# yes/no default='no'


## Kioskmode. Only show but don't switch anything. Values: on/off
	$kioskmode='off';




##############################################################################################
## FHZ-DEVICES
	$show_general=1; 		#field to type FHZ1000-orders 0/1 Default:1
	$show_fs20pulldown=1; 		#Pull-Down for the FS20 Devices 0/1 Default:1
	$show_fhtpulldown=1; 		#Pull-Down for the FHT-Devices 0/1 Default:1




##############################################################################################
## FS20-Device, adjust it if you have e.g. long titles
	$imgmaxxfs20=85;  		#Size of the pictures, default=85
        $imgmaxyfs20=85; 		# default=85 
	$fs20fontsizetitel=10;  	# default=10 
	$fs20maxiconperline=9; 	# default=9
					#room. Write e.g. "attr rolowz room wzo" 
					#into your fhz1000.cfg and restart fhz1000.pl
					# this will be marked on the FS20-Button. 
	$txtroom=""; 			# default=""; example: $txtroom="room: ";
					# room hidden will not be shown

##############################################################################################
## ROOMS adjust it if you have e.g. long titles
	$showroombuttons=1; 		#default 1  Values 0/1
	$imgmaxxroom=$imgmaxxfs20;  	#Size of the pictures, default=$imgmaxxfs20
        $imgmaxyroom=30; 		# default=30 
	$roomfontsizetitel=10;  	# default=9
	$roommaxiconperline=$fs20maxiconperline; # default=$fs20maxiconperline

##############################################################################################
## FHT-Devices
	$imgmaxxfht=685;  #Size of the pictures Default: 685 
        $imgmaxyfht=52;
	$show_desiredtemp=1;			# show the desired_temp as a graphic (0/1)
	$desR='255'; $desG='255'; $desB='255';	# Color of desired-temp-line Red/Green/Blue (Default: 255/255/255)	
	$show_actuator=1;			# show the actuator-value as a graphic (0/1)
	$actR='255'; $actG='247'; $actB='200';	# Color of Actuator-line Red/Green/Blue (Default: 255/247/200)	
	$FHTyrange='15:31';			# Temperature in gnuplot. Default 15 to 31 (Celsius)
	$FHTy2range='0:70';			# Actuator in gnuplot. Default 0 to 70 (Percent)
	$maxcount='460';			# Maximum count of pixel (from right to left) (Default:460)
   	$XcorrectDate=325;			# Text of e.g. Date from the right side (Default:325)
   	$XcorrectMainText=35;			# Text of main text from the right side (Default: 35)
	$logrotateFHTlines=4300; 		# automatic Logrotate; $logrotate must be 'yes'.
						# Default:4300
						# read docs/logrotate if you want adjust it manually!
						# otherwise the system will slow down
						# pgm3 (user www-data) needs the rights to write the logs
						# from fhz1000.pl (user = ???)



##############################################################################################
## HMS-Devices
	$imgmaxxhms=685;  #Size of the pictures. Default:  685
        $imgmaxyhms=52;
	$maxcountHMS='525';			# Maximum count of pixel (from right to left) (Default:525)
   	$XcorrectMainTextHMS=25;		# Text of main text from the right side (Default:)
	$logrotateHMSlines=1200; 		# automatic Logrotate; $logrotate must be 'yes'. 
						# Default:1200
						# read docs/logrotate if you want adjust it manually!
						# otherwise the system will slow down
						# pgm3 (user www-data) needs the rights to write the logs
						# from fhz1000.pl (user = ???)

##############################################################################################
## KS300-Device
	$imgmaxxks=685;  		#Size of the pictures  Default: 685

        $imgmaxyks=52;
	$showbft=1;                     # Display values additionaly in Beafort. Values: 0 /1 Default:1
	$maxcountKS='525';		# Maximum count of pixel (from right to left) (Default:525)
   	$XcorrectMainTextKS=35;		# Text of main text from the right side (Default: 35)

	$logrotateKS300lines=2000; 	# automatic Logrotate; $logrotate must be 'yes'.
					# Default:2000
					# read docs/logrotate if you want adjust it manually
					# otherwise the system will slow down
					# pgm3 (user www-data) needs the rights to write the logs
					# from fhz1000.pl (user = ???)





##############################################################################################
## misc
	$taillog=1; 			#make shure to have the correct rights. Values: 0/1
	$taillogorder="/usr/bin/tail -20 $logpath/fhem.log"; 



## show Information at startup. 
	$showLOGS='no';			#show the LOGS at startup. Default: no Values: yes/no
	$showAT='yes';			#show the AT_JOBS at startup. Default: yes Values: yes/no
	$showNOTI='no';		 	#show the NOTIFICATIONS at startup. Default: no Values: yes/no
	$showHIST='yes';		 	#show the HISTORY (if taillog=1) at startup. Default: yes Values: yes/no



	$urlreload=90;			# Automatic reloading page [sec]. Default fast: 60 slow:90
	$titel="PHP-Webmachine for fhem :-)"; #feel free to create an own title
	$timeformat="Y-m-d H:i:s";
	$bodybg="bgcolor='#F5F5F5'"; 
	$bg1="bgcolor='#6E94B7'";
	$bg2="bgcolor='#AFC6DB'";
	$bg3="bgcolor='#F8F8F8'";
	$bg4="bgcolor='#6394BD'";
	$fontcolor1="color='#FFFFFF'";
	
	$fontcolor3="color='143554'";
	$fontcol_grap_R=20;
	$fontcol_grap_G=53;
	$fontcol_grap_B=84;
	$fontttf="Vera";
	$fontttfb="VeraBd"; 		##copyright of the fonts: docs/copyright_font
	   ## if there is now graphic try the following:
	    #	$fontttf="Vera.ttf";
	    #	$fontttfb="VeraBd.ttf";
	    # or absolut:
	    #	$fontttf="/srv/www/htdocs/fhz/include/Vera.ttf";
	    #	$fontttfb="/srv/www/htdocs/fhz/include/VeraBd.ttf";

###############################   end of settings
	putenv('GDFONTPATH=' . realpath('.')); 

?>
