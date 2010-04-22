<?php

##################################################################################
#### pgm3 -- a PHP-webfrontend for fhem.pl 

### Look at http://www.fhemwiki.de for more information


###### required settings
	$fhem="localhost"; #only php5 is supported! On which machine is fhem runnning??
					# it needs not to be on the same machine as fhem
					# if it is not localhost then the fhem.cfg must
					# run global: "attr global port <nr> global"
	$fhemport="7072";		# port of fhem.pl
	$logpath="/var/tmp/";		# where are your logs? Use a writabel nfs-share if pgm3 and fhem are not on the same machine
	$AbsolutPath="/var/www/"; # where ist your pgm3?

###### DBlog instead of Filelogs -- only for experienced Users!
## Look at contrib/dblog and http://fhemwiki.de for further information
       $DBUse="0"; # Wanna use DB-Logging instead of File-Logging? Use 1 for ye s and 0 for no.                                                                 
        $DBNode="localhost";    # On which machine is your db running?          
        $DBName="fhem"; # Whats the name of your DB for fhem?                   
        $DBUser="USER";     # Enter the username to connect to the DB.              
        $DBPass="PASSWD";     # Enter the password which is needed to connect to the DB


##################################################################################
###### nice to have





#####	logrotate of hms, ks300, fht
	# this is only possible, if the webserver (e.g.wwwrun) has the rights ro write the
	# files from fhem.pl. If you want that then run fhem.pl as wwwrun too.
	# if 'yes' then only the needed lines are in the logfiles, the rest will be deleted.
	$logrotate='yes';	# yes/no default='yes'


## Kioskmode. Only show but don't switch anything. Values: on/off
	$kioskmode='off';


## Webcams
        $showwebcam=0;                  #shows webcam-Urls or other pictures (0/1)
        $webcamwidth='150';             # the width of the shown picture
	$wgetpath="/usr/bin/wget";      # you need the package wget for http, ftp...
	$webcamroom='donthide';		# existing room. Otherwise it will either
					# be in ALL or wiht 'donthide' not hided
        $webcam[0]='http://webcam/IMAGE.JPG';
        $webcam[1]='http://webcam2/IMAGE.JPG';
        #$webcam[1]='http://www.bostream.nu/hoganas/OutsideTempHistory.gif';
       #$webcam[1]='IMAGE.PNG';        # Supported are Webcams with http:// ftp:// ....
                                       # and Images wich must be copied to <pgm3>/tmp/

#       $webcam[2]='http://...';
#       ...


# Weather				# Google-Api. It requires an Internet Connection
	$enableweather=0;		# show the google-weather?
	$weathercity='Linden';
	$weathercountry='Germany';
	$weatherlang='de';
	#$weatherlang='en';
	$weatherroom='donthide';	# existing room. Otherwise it will either
					# be in ALL or with 'donthide' not hided


##############################################################################################
## FHZ-DEVICES
	$show_general=1; 		#field to type FHZ1000-orders 0/1 Default:1
	$show_fs20pulldown=1; 		#Pull-Down for the FS20 Devices 0/1 Default:1
	$show_fhtpulldown=1; 		#Pull-Down for the FHT-Devices 0/1 Default:1
	$show_logpulldown=1; 		#Pull-Down for Log-files and FS20 (grep fhem.log)
	$logsort='| sort -r';		#sort the Log-Output how you want;

##############################################################################################
# ATTENTION: the changes of sizes only affects after the next build of pictures!           
# or delete the old pictures: rm <pgm>/tmp/*                                    
##############################################################################################
## FS20-Device, adjust it if you have e.g. long titles
	$imgmaxxfs20=85;  		#Size of the pictures, default=85
        $imgmaxyfs20=85; 		# default=85 
	$fs20fontsizetitel=10;  	# default=10 
	$fs20maxiconperline=9; 	# default=9

					#room. Write e.g. "attr rolowz room wzo" 
					#into your fhem.cfg and restart fhem.pl
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
        $imgmaxxfht=725;  			#Size of the pictures Default: 725
        $imgmaxyfht=52;
        $show_desiredtemp=1;                    # show the desired_temp as a graphic (0/1)
        $desR='255'; $desG='255'; $desB='255';  # Color of desired-temp-line Red/Green/Blue (Default: 255/255/255) 
        $show_actuator=1;                       # show the actuator-value as a graphic (0/1)
        $actR='255'; $actG='247'; $actB='200';  # Color of Actuator-line Red/Green/Blue (Default: 255/247/200)
        $FHTyrange='14:31';                     # Temperature in gnuplot. Default 14 to 31 (Celsius)
        $FHTy2range='0:70';                     # Actuator in gnuplot. Default 0 to 70 (Percent)
        $maxcount='510';                        # Maximum count of pixel (from right to left) (Default:460)
        $XcorrectDate=380;                      # Text of e.g. Date from the right side (Default:380)
        $XcorrectMainText=32;                   # Text of main text from the right side (Default: 32)
        $logrotateFHTlines=8200;                # automatic Logrotate; $logrotate must be 'yes'.
                                                # Default:8200
                                                # read docs/logrotate if you want adjust it manually!
                                                # otherwise the system will slow down
                                                # pgm3 (user www-data) needs the rights to write the logs
                                                # from fhem.pl (user = ???)




##############################################################################################
## HMS-Devices
        $imgmaxxhms=725;  #Size of the pictures. Default:  725
        $imgmaxyhms=52;
        $maxcountHMS='575';                     # Maximum count of pixel (from right to left) (Default:575)
        $XcorrectMainTextHMS=25;                # Text of main text from the right side (Default:)
	$showdewpoint='yes';                    # Dewpoint (german: taupunkt)
        $logrotateHMSlines=1500;                # automatic Logrotate; $logrotate must be 'yes'.
                                                # Default:1500
                                                # read docs/logrotate if you want adjust it manually!
                                                # otherwise the system will slow down
                                                # pgm3 (user www-data) needs the rights to write the logs
                                                # from fhem.pl (user = ???)

##############################################################################################
## KS300-Device
        $imgmaxxks=725;                 #Size of the pictures  Default: 725

        $imgmaxyks=52;
        $showbft=1;                     # Display values additionaly in Beafort. Values: 0 /1 Default:1
        $maxcountKS='575';              # Maximum count of pixel (from right to left) (Default:575)
        $showdewpointks300='yes';       # Dewpoint (german: taupunkt)
        $XcorrectMainTextKS=45;         # Text of main text from the right side (Default: 35)

        $logrotateKS300lines=13000;      # automatic Logrotate; $logrotate must be 'yes'.
                                        # Default: 13000
                                        # read docs/logrotate if you want adjust it manually
                                        # otherwise the system will slow down
                                        # pgm3 (user www-data) needs the rights to write the logs
                                        # from fhem.pl (user = ???)

##############################################################################################
## USERDEF
#
# Create your own graphics! If you have separate Programs (e.g. wired devices) then create your own 
# logfile and tell pgm3  to use it.
# We only need a data/time-field in the form <date>_<time>, e.g. 2007-10-13_13:45:14
# and a field with a numeric value e.g. 0.0

#Example: 
####################################################
# 2007-10-13_13:45:14 solarI Is: 0.0 Vs: 4.5 T: 22
####################################################
# Field1: 2007-10-13_13:45:14
# Field2: solarI
# Field3: Is:
# Field4: 0.0
#...
# Field1 must be the date/time-field. Then tell pgm3 with $userdef[x]['valuefield'] (see below)
# the field with the needed value. It is possible to create several graphics with one logfile.


# Do you want user defined graphics? 1/0 Default: 0	
$UserDefs=0;

#####################
## Userdef: 0

# the sortnumbers must be complete. eg. 0 1 2 3 or 2 0 3 1 and so on
#$sortnumber=0;	

# No blanks or other special signs!!
#$userdef[$sortnumber]['name']='SolarV';	

#In which field are the values?? See the example above
#$userdef[$sortnumber]['valuefield']=4;	

#Type of Device [temperature | piri | fs20] pgm3 will try to generate a gnuplot picture
#$userdef[$sortnumber]['gnuplottype']='temperature';	

# example, path to the logfile with the entrys like above
#$userdef[$sortnumber]['logpath']=$logpath.'/lse_solarV.log';   

#$userdef[$sortnumber]['room']='garden';

# Semantic eg. Voltage
#$userdef[$sortnumber]['semlong']='Voltage'; 	

# Semantic short e.g. V
#$userdef[$sortnumber]['semshort']='V';

#Size of the pictures. Default:  725
#$userdef[$sortnumber]['imagemax']=725;
#$userdef[$sortnumber]['imagemay']=52;

# Maximum count of pixel (from right to left) (Default:575)
#$userdef[$sortnumber]['maxcount']=575;

 # Text of main text from the right side (Default:)
#$userdef[$sortnumber]['XcorrectMainText']=25;               

# automatic Logrotate; $logrotate must be 'yes'.
# Default:2200
# read docs/logrotate if you want adjust it manually!
# otherwise the system will slow down
# pgm3 (user www-data) needs the rights to write the logs
# of fhem.pl (user = ???)
#$userdef[$sortnumber]['logrotatelines']=2200;  


########################
# example: 
#define solarpumpe.log FileLog /var/tmp/solarpumpe.log solarpumpe:.*(on|off).*
$sortnumber=0;
$userdef[$sortnumber]['name']='PiriO';	
$userdef[$sortnumber]['name']='SolarPumpe';	
$userdef[$sortnumber]['valuefield']=3;	
$userdef[$sortnumber]['gnuplottype']='fs20';	
$userdef[$sortnumber]['logpath']='/mnt/fhz/solarpumpe.log';   
$userdef[$sortnumber]['room']='cellar';
$userdef[$sortnumber]['semlong']='Solarpumpe'; 	
$userdef[$sortnumber]['semshort']='';
$userdef[$sortnumber]['imagemax']=725;
$userdef[$sortnumber]['imagemay']=52;
$userdef[$sortnumber]['maxcount']=575;
$userdef[$sortnumber]['XcorrectMainText']=25;               
$userdef[$sortnumber]['logrotatelines']=50;  


##########################
# example: 
#define rolu1.log FileLog /var/tmp/rolu1.log rolu1:.*(on|off|dimup|dimdown).*
#$sortnumber=2;
#$userdef[$sortnumber]['name']='Rolu1';	
#$userdef[$sortnumber]['valuefield']=3;	
#$userdef[$sortnumber]['gnuplottype']='fs20';	
#$userdef[$sortnumber]['logpath']='/var/tmp/rolu1.log';   
#$userdef[$sortnumber]['room']='wgu';
#$userdef[$sortnumber]['semlong']='Rolladen'; 	
#$userdef[$sortnumber]['semshort']='';
#$userdef[$sortnumber]['imagemax']=725;
#$userdef[$sortnumber]['imagemay']=52;
#$userdef[$sortnumber]['maxcount']=575;
#$userdef[$sortnumber]['XcorrectMainText']=25;               
#$userdef[$sortnumber]['logrotatelines']=30;  

##########################
# example: 
#define rolu1.log FileLog /var/tmp/rolu1.log rolu1:.*(on|off|dimup|dimdown).*
$sortnumber=1;
$userdef[$sortnumber]['name']='allight';	
$userdef[$sortnumber]['valuefield']=3;	
$userdef[$sortnumber]['gnuplottype']='fs20';	
$userdef[$sortnumber]['logpath']='/mnt/fhz/allight.log';   
$userdef[$sortnumber]['room']='alarm';
$userdef[$sortnumber]['semlong']='Alarm light'; 	
$userdef[$sortnumber]['semshort']='';
$userdef[$sortnumber]['imagemax']=725;
$userdef[$sortnumber]['imagemay']=52;
$userdef[$sortnumber]['maxcount']=575;
$userdef[$sortnumber]['XcorrectMainText']=25;               
$userdef[$sortnumber]['logrotatelines']=30;  
##########################


#$sortnumber=2;
#$userdef[$sortnumber]['name']='tARV';
#$userdef[$sortnumber]['valuefield']=3;
#$userdef[$sortnumber]['gnuplottype']='temperature';
#$userdef[$sortnumber]['logpath']='/mnt/fhz/t_arv.log';
##$userdef[$sortnumber]['logpath']='/mnt/fhz/allight.log';
#$userdef[$sortnumber]['room']='Hautpg';
#$userdef[$sortnumber]['semlong']='tARV';
#$userdef[$sortnumber]['semshort']='°C';
#$userdef[$sortnumber]['imagemax']=725;
#$userdef[$sortnumber]['imagemay']=52;
##$userdef[$sortnumber]['maxcount']=575;
#$userdef[$sortnumber]['XcorrectMainText']=25;
#$userdef[$sortnumber]['logrotatelines']=2200;




# example: 
#define rolu1.log FileLog /var/tmp/rolu1.log rolu1:.*(on|off|dimup|dimdown).*
#$sortnumber=5;
#$userdef[$sortnumber]['name']='FS10';	
#$userdef[$sortnumber]['valuefield']=2;	
#$userdef[$sortnumber]['gnuplottype']='temperature';	
#$userdef[$sortnumber]['logpath']='/var/tmp/wspd_7.gnu';   
#$userdef[$sortnumber]['timeformat']='%Y/%m/%d %H:%M:%S';   
#$userdef[$sortnumber]['room']='hidden';
#$userdef[$sortnumber]['semlong']='FS10'; 	
#$userdef[$sortnumber]['semshort']='°C';
#$userdef[$sortnumber]['imagemax']=725;
#$userdef[$sortnumber]['imagemay']=52;
#$userdef[$sortnumber]['maxcount']=575;
#$userdef[$sortnumber]['XcorrectMainText']=25;               
#$userdef[$sortnumber]['logrotatelines']=3300;  
#################
## Userdef: x
#
#$userdef[x]['name']='';	
#........ 



########################

###### showgnuplot 
	# Gnuplot will automatically show the pictures.
	# There is no reason any more to deactivate Gnuplot. Values: 0/1
	$showgnuplot=1;
	$gnuplot='/usr/bin/gnuplot';		# location of gnuplot
	$pictype='png';  	



##############################################################################################
## misc
	$taillog=1; 			#make shure to have the correct rights. Values: 0/1
	$tailcount=30; 			#make shure to have the correct rights. Values: 0/1
	$tailpath="/usr/bin/tail";
	#$taillogorder=$tailpath." -$tailcount $logpath/fhem.log ";
	$taillogorder=$tailpath." -$tailcount $logpath/fhem-" . date("Y") . "-" .  date("m") . ".log "; #if you have e.g. fhem-2009-02.log  



## show Information at STARTUP. 
	$showLOGS='no';			#show the entrys of the LOGS in the 
					#fhem.cfg at startup. Default: no Values: yes/no
	$showAT='no';			#show the AT_JOBS at startup. Default: yes Values: yes/no
	$showNOTI='no';		 	#show the NOTIFICATIONS at startup. Default: no Values: yes/no
	$showHIST='yes';		#show the HISTORY (if taillog=1) at startup. Default: yes Values: yes/no
        $showPICS='no';                #if shwowebcam=1 then initial the Pics will be shown. Default: yes 
	$showWeath='yes';		# Show weather on startup? $enableweather must 1 

        $RSStitel='FHEM :-)';

	$urlreload=90;			# Automatic reloading page [sec]. Default fast: 60 slow:90
	$titel="PHP-Webmachine for fhem :-)"; #feel free to create an own title
	#$timeformat="Y-m-d H:i:s"; #English
	$timeformat="d.m.Y H:i:s"; # German
	$winsize=800;			# width of the pgm3


##### use netcat if your have problems with the stream_socket-tcp-connection
## package netcat must be installed
	$usenetcat=0;
                                                                                
##########################                                                      
##### SKINS - change your colors                                                
# Look at http://www.farb-tabelle.de/de/farbtabelle.htm for colors
## DEFAULT                                                                      
        $bodybg="bgcolor='#F5F5F5'";
        $bg1="bgcolor='#6E94B7'"; # e.g. Header  
        $bg2="bgcolor='#AFC6DB'";  # e.g. behind the buttons
        $bg4="bgcolor='#6394BD'";  # border around all
        $bg5="bgcolor='#FFFFFF'"; # between the tables
        $fontcolor1="color='#FFFFFF'";
        $fontcolor3="color='#143554'";
	# The Button needs decimal Code Instead Hex.
	# Use the column left from the HEX.
	# You must delete the old graphics after the change. "rm <pgm3>/tmp/*"
	$buttonBg_R='175';$buttonBg_G='198';$buttonBg_B='219';
	$bg1_R='110';$bg1_G='148';$bg1_B='181';
##########################                                                      
##ORANGE
        #$bodybg="bgcolor='#FFDAB9'";
        #$bg1="bgcolor='#FF8C00'";  
        #$bg2="bgcolor='#FFA500'";
        #$bg4="bgcolor='#6394BD'";
        #$bg5="bgcolor='#FFFFFF'";
        #$fontcolor1="color='#000000'";
        #$fontcolor3="color='#000000'";
	# The Button needs decimal Code Instead Hex.
	# Use the column left from the HEX on 
	# http://www.farb-tabelle.de/de/farbtabelle.htm
	# You must delete the old graphics after the change. "rm <pgm3>/tmp/*"
	#$buttonBg_R='255';$buttonBg_G='165';$buttonBg_B='0';
	#Dec-Code from $bg1:
	#$bg1_R='255';$bg1_G='140';$bg1_B='0';




##########################                                                      
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



### If DB-query is used, this is the only point of connect. ###                 
if ($DBUse=="1") {      
  @mysql_connect($DBNode, $DBUser, $DBPass) or die("Can't connect"); 
  @mysql_select_db($DBName) or die("No database found");  
}                                                                               
 

?>
