##############################################################################
#
# 51_RPI_GPIO.pm
#
##############################################################################
# Modul for Raspberry Pi GPIO access
#
# define <name> RPI_GPIO <Pin>
# where <Pin> is one of RPi's GPIO #
#
# contributed by Klaus Wittstock (2013) email: klauswittstock bei gmail punkt com
#
##############################################################################

package main;
use strict;
use warnings;
use POSIX;
use Scalar::Util qw(looks_like_number);
use IO::File;
use SetExtensions;

sub RPI_GPIO_Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}    = "RPI_GPIO_Define";
  $hash->{GetFn}    = "RPI_GPIO_Get";
  $hash->{SetFn}    = "RPI_GPIO_Set";
  $hash->{StateFn}  = "RPI_GPIO_State";  
  $hash->{AttrFn}   = "RPI_GPIO_Attr";
  $hash->{UndefFn}  = "RPI_GPIO_Undef";
  $hash->{ExceptFn} = "RPI_GPIO_Except";
  $hash->{AttrList} = "poll_interval loglevel:0,1,2,3,4,5" .
                      " direction:input,output pud_resistor:off,up,down" .
                      " interrupt:none,falling,rising,both" .
                      " toggletostate:no,yes active_low:no,yes" .
                      " debounce_in_ms restoreOnStartup:no,yes " .
                      "$readingFnAttributes";
}

my $gpiodir = "/sys/class/gpio";			#GPIO base directory
my $gpioprg = "/usr/local/bin/gpio";		#WiringPi GPIO utility

my %setsoutp = (
'on:noArg' => 0,
'off:noArg' => 0,
'toggle:noArg' => 0,
);

my %setsinpt = (
'readValue' => 0,
);  

sub RPI_GPIO_Define($$) {
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);
 my $menge = int(@args);
 if (int(@args) < 3)
 {
  return "Define: to less arguments. Usage:\n" .
         "define <name> RPI_GPIO <GPIO>";
 }

 #Prüfen, ob GPIO bereits verwendet
 foreach my $dev (devspec2array("TYPE=$hash->{TYPE}")) {
   if ($args[2] eq InternalVal($dev,"RPI_pin","")) {
     return "GPIO $args[2] already used by $dev";
   }
 }
 
 my $name = $args[0];
 $hash->{RPI_pin} = $args[2];
  
 #export Pin alte Version -> wird jetzt über direction gemacht (WiringPi Programm GPIO)
 #my $exp = IO::File->new("> /sys/class/gpio/export");
 #print $exp "$hash->{RPI_pin}";
 #$exp->close;
 #select(undef, undef, undef, 0.4);   #kurz warten bis Verzeichnis angelegt
 
 # create default attributes
 my $msg = CommandAttr(undef, $name . ' direction input');
 return $msg if ($msg);
 select(undef, undef, undef, 0.4);
 $hash->{fhem}{interfaces} = "switch";
 return undef;
}

sub RPI_GPIO_Get($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  #my $dir = $attr{$hash->{NAME}}{direction} || "output";
  my $dir = "";
  my $zustand = undef;
  my $val = fileaccess($hash, "value");
  if ( defined ($val) ) {
    if ( $val == 1) {
      if ($dir eq "output") {$zustand = "on";} else {$zustand = "high";}
    } elsif ( $val == 0 ) {
      if ($dir eq "output") {$zustand = "off";} else {$zustand = "low";}
    }    
  } else { 
    Log 1, "$hash->{NAME} GetFn: readout of Pinvalue fail"; 
  }
  $hash->{READINGS}{Pinlevel}{VAL} = $zustand;
  $hash->{READINGS}{Pinlevel}{TIME} = TimeNow();
  return "Current Value for $name: $zustand";
}

sub RPI_GPIO_Set($@) {
  my ($hash, @a) = @_;
  my $name =$a[0];
  my $cmd = $a[1];
  #my $val = $a[2];
  
  if(defined($attr{$name}) && defined($attr{$name}{"direction"})) {
      my $mt = $attr{$name}{"direction"};
      if($mt && $mt eq "output") {
	      if ($cmd eq 'toggle') {
	        my $val = fileaccess($hash, "value");     #alten Wert des GPIO direkt auslesen
	        $cmd = $val eq "0" ? "on" :"off";
	      }
if ($cmd eq 'on') {
          fileaccess($hash, "value", "1");
          #$hash->{STATE} = 'on';
          readingsBeginUpdate($hash);
		  #readingsBulkUpdate($hash, 'Pinlevel', $valalt);
		  readingsBulkUpdate($hash, 'state', "on");
		  readingsEndUpdate($hash, 1);
        } elsif ($cmd eq 'off') {
          fileaccess($hash, "value", "0");
          #$hash->{STATE} = 'off';
          readingsBeginUpdate($hash);
		  #readingsBulkUpdate($hash, 'Pinlevel', $valalt);
		  readingsBulkUpdate($hash, 'state', "off");
		  readingsEndUpdate($hash, 1);
        } else {
          my $slist = join(' ', keys %setsoutp);
          return SetExtensions($hash, $slist, @a);                          
        }           
      } else {
        if(!defined($setsinpt{$cmd})) {
          return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %setsinpt)
       } else {
        
       }
      }      
  }
  if ($cmd eq 'readValue') { #noch bei input einpflegen
     updatevalue($hash);  
  } 
}

sub RPI_GPIO_State($$$$) {	#reload readings at FHEM start
  my ($hash, $tim, $sname, $sval) = @_;
  #Log 1, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";
  if ( (AttrVal($hash->{NAME},"restoreOnStartup","on") eq "on") && ($sname ne "STATE") ) {
     if (AttrVal($hash->{NAME},"direction","") eq "output") {
		$hash->{READINGS}{$sname}{VAL} = $sval;
		$hash->{READINGS}{$sname}{TIME} = $tim;
		#Log 1, "OUTPUT $hash->{NAME}: $sname wiederhergestellt auf $sval";
		if ($sname eq "state") {
			#RPI_GPIO_Set($hash,$hash->{NAME},$sname,$sval);
			RPI_GPIO_Set($hash,$hash->{NAME},$sval);
			#Log 1, "OUTPUT $hash->{NAME}: STATE wiederhergestellt auf $sval";	
		} 
	 } elsif ( (AttrVal($hash->{NAME},"direction","") eq "input") && (AttrVal($hash->{NAME},"toggletostate","") eq "yes")) {
	    if ($sname eq "Toggle") {
			   $hash->{READINGS}{$sname}{VAL} = $sval;
		     $hash->{READINGS}{$sname}{TIME} = $tim;
		     #RPI_GPIO_Set($hash,$hash->{NAME},$sval);
		     readingsBeginUpdate($hash);
         readingsBulkUpdate($hash, 'state', $sval);
         readingsEndUpdate($hash, 1);
		     #Log 1, "INPUT $hash->{NAME}: $sname und STATE wiederhergestellt auf $sval";	
		   } elsif ($sname eq "Counter") {
		     $hash->{READINGS}{$sname}{VAL} = $sval;
		     $hash->{READINGS}{$sname}{TIME} = $tim;
		     #Log 1, "INPUT $hash->{NAME}: $sname wiederhergestellt auf $sval";	
		   }
	 }
  }
  return;
}

sub RPI_GPIO_Attr(@) {
 my (undef, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = '';
 
 if ($attr eq 'poll_interval') {
   if ( defined($val) ) {
     if ( looks_like_number($val) && $val > 0) {
       RemoveInternalTimer($hash);
       InternalTimer(1, 'RPI_GPIO_Poll', $hash, 0);
     } else {
       $msg = "$hash->{NAME}: Wrong poll intervall defined. poll_interval must be a number > 0";
     }    
   } else { #wird auch aufgerufen wenn $val leer ist, aber der attribut wert wird auf 1 gesetzt
     RemoveInternalTimer($hash);
   }
 }
 
 if ($attr eq 'direction') {
   if (!$val) { #$val nicht definiert: Einstellungen löschen
       $msg = "$hash->{NAME}: no direction value. Use input output";
   } elsif ($val eq "input") {
       #fileaccess($hash, "direction", "in");
       exuexpin($hash, "in");
       #Log 1, "$hash->{NAME}: direction: input"; 
   } elsif( ( AttrVal($hash->{NAME}, "interrupt", "none") ) ne ( "none" ) ) {
       $msg = "$hash->{NAME}: Delete attribute interrupt or set it to none for output direction"; 
   } elsif ($val eq "output") {
       #fileaccess($hash, "direction", "out");
       exuexpin($hash, "out");
       #Log 1, "$hash->{NAME}: direction: output";
   } else {
       $msg = "$hash->{NAME}: Wrong $attr value. Use input output";
   }
 }

 if ($attr eq 'interrupt') {
   if ( !$val || ($val eq "none") ) {
     fileaccess($hash, "edge", "none");
     inthandling($hash, "stop");
     #Log 1, "$hash->{NAME}: interrupt: none"; 
   } elsif (( AttrVal($hash->{NAME}, "direction", "output") ) eq ( "output" )) {
     $msg = "$hash->{NAME}: Wrong direction value defined for interrupt. Use input";
   } elsif ($val eq "falling") {
     fileaccess($hash, "edge", "falling");
     inthandling($hash, "start");
     #Log 1, "$hash->{NAME}: interrupt: falling"; 
   } elsif ($val eq "rising") {
     fileaccess($hash, "edge", "rising");
     inthandling($hash, "start");
     #Log 1, "$hash->{NAME}: interrupt: rising";  
   } elsif ($val eq "both") {
     fileaccess($hash, "edge", "both");
     inthandling($hash, "start");
     #Log 1, "$hash->{NAME}: interrupt: both";  
   } else {
     $msg = "$hash->{NAME}: Wrong $attr value. Use none, falling, rising or both";
   }  
 }
 #Tastfunktion: bei jedem Tastendruck wird State invertiert
 if ($attr eq 'toggletostate') {
   if ( !$val || ($val eq ("yes" || "no") ) ) {
     #Log 1, "$hash->{NAME}: toggletostate: passt"; 
   } else {
     $msg = "$hash->{NAME}: Wrong $attr value. Use yes or no";
   }
 }
#invertierte Logik 
 if ($attr eq 'active_low') {
   if ( !$val || ($val eq "no" ) ) {
     fileaccess($hash, "active_low", "0");
     #Log 1, "$hash->{NAME}: interrupt: none"; 
   } elsif ($val eq "yes") {
     fileaccess($hash, "active_low", "1");
   } else {
     $msg = "$hash->{NAME}: Wrong $attr value. Use yes or no";
   }
 }
#Entprellzeit
 if ($attr eq 'debounce_in_ms') {
   if ( $val && ( ($val > 250) || ($val < 0) ) ) {
     $msg = "$hash->{NAME}: debounce_in_ms value to big. Use 0 to 250";
   }
 }

 if ($attr eq 'pud_resistor') {
   my $pud;
   if ( !$val ) {
   } elsif ($val eq "off") {
     $pud = $gpioprg.' -g mode '.$hash->{RPI_pin}.' tri';
	 $pud = `$pud`;
   } elsif ($val eq "up") {
     $pud = $gpioprg.' -g mode '.$hash->{RPI_pin}.' up';
	 $pud = `$pud`;
   } elsif ($val eq "down") {
     $pud = $gpioprg.' -g mode '.$hash->{RPI_pin}.' down';
	 $pud = `$pud`;
   } else {
     $msg = "$hash->{NAME}: Wrong $attr value. Use off, up or down";
   }
  }   
 return ($msg) ? $msg : undef; 
 }

sub RPI_GPIO_Poll($) {		#for attr poll_intervall -> readout pin value
  my ($hash) = @_;
  my $name = $hash->{NAME};
  updatevalue($hash);
  my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
  if ($pollInterval > 0) {
    InternalTimer(gettimeofday() + ($pollInterval * 60), 'RPI_GPIO_Poll', $hash, 0);
    }
  return;
} 

sub RPI_GPIO_Undef($$) {
  my ($hash, $arg) = @_;
  if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
    RemoveInternalTimer($hash);
  }
  if ( ( AttrVal($hash->{NAME}, "interrupt", "none") ) ne ( "none" ) ) {
    delete $selectlist{$hash->{NAME}};
    close($hash->{filehandle});
  }
  #unexport Pin alte Version
  #my $uexp = IO::File->new("> /sys/class/gpio/unexport");
  #print $uexp "$hash->{RPI_pin}";
  #$uexp->close;
  #alternative unexport Pin:
  exuexpin($hash, "unexport");
  return undef;
}

sub RPI_GPIO_Except($) {	#called from main if an interrupt occured 
  my ($hash) = @_;
  #seek($hash->{filehandle},0,0);									          #an Anfang der Datei springen (ist nötig falls vorher schon etwas gelesen wurde)
  #chomp ( my $firstval = $hash->{filehandle}->getline );		#aktuelle Zeile auslesen und Endezeichen entfernen
  my $eval = fileaccess($hash, "edge");								      #Eintstellung Flankensteuerung auslesen
  my ($valst, $valalt, $valto, $valcnt) = undef;
  my $debounce_time = AttrVal($hash->{NAME}, "debounce_in_ms", "0"); #Wartezeit zum entprellen
  if( $debounce_time ne "0" ) {
    $debounce_time /= 1000;
    Log 1, "Wartezeit: $debounce_time ms"; 
    select(undef, undef, undef, $debounce_time);
  }

  seek($hash->{filehandle},0,0);								#an Anfang der Datei springen (ist nötig falls vorher schon etwas gelesen wurde)
  chomp ( my $val = $hash->{filehandle}->getline );			#aktuelle Zeile auslesen und Endezeichen entfernen  
  
  if ( ( $val == 1) && ( $eval ne ("falling") ) ) {
    $valst = "on";
    $valalt = "high";
  } elsif ( ( $val == 0 ) && ($eval ne "rising" ) ) {
    $valst = "off";
    $valalt = "low";
  }
  if ( ( ($eval eq "rising") && ( $val == 1 ) ) || ( ($eval eq "falling") && ( $val == 0 ) ) ) {	#nur bei Trigger auf steigende / fallende Flanke
#Togglefunktion
    if (!defined($hash->{READINGS}{Toggle}{VAL})) {			#Togglewert existiert nicht -> anlegen
        #Log 1, "Toggle war nicht def";
        $valto = "on";
    } elsif ( $hash->{READINGS}{Toggle}{VAL} eq "off" ) {		#Togglewert invertieren
       #my $twert = $hash->{READINGS}{Toggle}{VAL};
       #Log 1, "Toggle war auf $twert";
       $valto = "on";
    } else {
       #my $twert = $hash->{READINGS}{Toggle}{VAL};
       #Log 1, "Toggle war auf $twert";
       $valto = "off";
    }
    #Log 1, "Toggle  ist jetzt $valto";
    if (( AttrVal($hash->{NAME}, "toggletostate", "no") ) eq ( "yes" )) {	#wenn Attr "toggletostate" gesetzt auch die Variable für den STATE wert setzen
       $valst = $valto;
    }
#Zählfunktion
    if (!defined($hash->{READINGS}{Counter}{VAL})) {			#Zähler existiert nicht -> anlegen
        #Log 1, "Zähler war nicht def";
        $valcnt = "1";
    } else {
		$valcnt = $hash->{READINGS}{Counter}{VAL} + 1;
		#Log 1, "Zähler  ist jetzt $valcnt";
    }    
  } elsif ($eval eq "both") {
	if 	( $val == 1 ) {
		my $lngpressInterval = 1;
		InternalTimer(gettimeofday() + $lngpressInterval, 'longpress', $hash, 0);
	} else {
		RemoveInternalTimer('longpress');
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'Longpress', 'off');
		readingsEndUpdate($hash, 1);
	}
  }
  
  delete ($hash->{READINGS}{Toggle}) if ($eval ne ("rising" || "falling"));		#Reading Toggle löschen wenn kein Wert in Variable
  delete ($hash->{READINGS}{Longpress}) if ($eval ne "both");						#Reading Longpress löschen wenn edge nicht on both
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'Pinlevel', $valalt);
  readingsBulkUpdate($hash, 'state', $valst);
  readingsBulkUpdate($hash, 'Toggle', $valto) if ($valto);
  readingsBulkUpdate($hash, 'Counter', $valcnt) if ($valcnt);
  readingsEndUpdate($hash, 1);
  #Log 1, "RPIGPIO: Except ausgelöst: $hash->{NAME}, Wert: $val, edge: $eval,vt: $valto, $debounce_time s: $firstval";  
}

sub longpress($) {			#for reading longpress
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $val = fileaccess($hash, "value");
  if ($val == 1) {
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'Longpress', 'on');
	readingsEndUpdate($hash, 1);
  }
}

sub dblclick($) {

}

sub updatevalue($) {		#update value for Input devices
  my ($hash) = @_;
  my $val = fileaccess($hash, "value");
  if ( defined ($val) ) {
    my ($valst, $valalt) = undef;
    if ( $val == 1) {
      $valst = "on";
      $valalt = "high";
    } elsif ( $val == 0 ) {
      $valst = "off";
      $valalt = "low";
    }
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'Pinlevel', $valalt);
    readingsBulkUpdate($hash, 'state', $valst) if (( AttrVal($hash->{NAME}, "toggletostate", "no") ) eq ( "no" ));
    readingsEndUpdate($hash, 1);
  } else {
  Log 1, "$hash->{NAME}: readout of Pinvalue fail";   
  }
}

sub fileaccess($$;$) {		#Fileaccess for GPIO base directory
 #my ($hash, $fname, $value) = @_;
 my ($hash, @args) = @_;
 my $fname = $args[0];
 my $pinroot = qq($gpiodir/gpio$hash->{RPI_pin});
 my $file =qq($pinroot/$fname);
 if (int(@args) < 2){
   my $fh = IO::File->new("< $file");
   if (defined $fh) {
      chomp ( my $pinvalue = $fh->getline );
      $fh->close;
      return $pinvalue;
   } 
   else {
      Log 1, "Can't open file: $hash->{NAME}, $fname";
   }
 } else {
   my $value = $args[1];
   my $fh = IO::File->new("> $file");
   if (defined $fh) {
      print $fh "$value";
      $fh->close;
   }
   else {
      Log 1, "Can't open file: $hash->{NAME}, $fname";
   }
 }
}

sub exuexpin($$) {			#export and unexport Pin via GPIO utility
 my ($hash, $dir) = @_;
 my $sw;
 if ($dir eq "unexport") {
   $sw = $dir;
   $dir = "";
 } else {
   $sw = "export";
   $dir = " ".$dir;
 }
 #alternative export Pin
 if(-e $gpioprg) {
   if(-x $gpioprg) {
     if(-u $gpioprg) {
       my $exp = $gpioprg.' '.$sw.' '.$hash->{RPI_pin}.$dir;
       $exp = `$exp`;
       } else {
         Log 1, "file $gpioprg is not setuid"; 
       }
     } else {
       Log 1, "file $gpioprg is not executable"; 
     }
   } else {
     Log 1, "file $gpioprg doesnt exist"; 
   }
 #######################

}

sub inthandling($$) {		#start/stop Interrupthandling
 my ($hash, $arg) = @_;
 my $msg = '';
 if ( $arg eq "start") {
    #FH für value-datei
    my $pinroot = qq($gpiodir/gpio$hash->{RPI_pin});
    my $valfile = qq($pinroot/value);
    $hash->{filehandle} = IO::File->new("< $valfile"); 
    if (!defined $hash->{filehandle}) {
      $msg = "Can't open file: $hash->{NAME}, $valfile";
    } else {
      $selectlist{$hash->{NAME}} = $hash;
      $hash->{EXCEPT_FD} = fileno($hash->{filehandle});
      my $pinvalue = $hash->{filehandle}->getline;
      Log 5, "Datei: $valfile, FH: $hash->{filehandle}, EXCEPT_FD: $hash->{EXCEPT_FD}, akt. Wert: $pinvalue";
    }
  } else {
    delete $selectlist{$hash->{NAME}};
    close($hash->{filehandle});
  }
}

1;
=pod
=begin html

<a name="RPI_GPIO"></a>
<h3>RPI_GPIO</h3>
<ul>
  <a name="RPI_GPIO"></a>
  <p>
    Raspberry Pi offers direct access to several GPIO via header P1 (and P5 on V2). The Pinout is shown in table under define. 
    With this module you are able to access these GPIO's directly as output or input. For input you can use either polling or interrupt mode<br><br>
    <b>Warning: Never apply any external voltage to an output configured pin! GPIO's internal logic operate with 3,3V. Don't exceed this Voltage!</b><br><br>
    
    <b>preliminary:</b><br>
    GPIO Pins accessed by sysfs. The files are located in folder /system/class/gpio which can be only accessed by root.
    This module uses gpio utility from <a href="http://wiringpi.com/download-and-install/">WiringPi</a> library to export and change access rights of GPIO's<br>
    Install WiringPi:
    <pre>
  sudo apt-get update
  sudo apt-get upgrade
  sudo apt-get install git-core
  git clone git://git.drogon.net/wiringPi
  cd wiringPi
  ./build
  sudo adduser fhem gpio</pre>
    Thats all<br><br>
          
  <a name="RPI_GPIODefine"></a>
  <b>Define</b>
  <ul>
    <code>define <name> RPI_GPIO &lt;GPIO number&gt;</code><br><br>
    all usable <code>GPIO number</code> are in the following tables<br><br>
    
	<table border="0" cellspacing="0" cellpadding="0">    
      <td> 
        PCB Revision 1 P1 pin header
        <table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>			 <td>Pin</td><td></td><td>Pin</td>	<td>Function</td></tr>
		<tr><td>3,3V</td>    			 <td>1</td>  <td></td><td>2</td>  	<td>5V</td></tr>
		<tr><td><b>GPIO 0 (SDA0)</b></td><td>3</td>  <td></td><td>4</td>	<td></td></tr>
		<tr><td><b>GPIO 1 (SCL0)</b></td><td>5</td>  <td></td><td>6</td>	<td>GND</td></tr>
		<tr><td>GPIO 4 (GPCLK0)</td>	 <td>7</td>  <td></td><td>8</td>	<td>GPIO 14 (TxD)</td></tr>
		<tr><td></td>					 <td>9</td>  <td></td><td>10</td>	<td>GPIO 15 (RxD)</td></tr>
		<tr><td>GPIO 17</td>			 <td>11</td> <td></td><td>12</td>	<td>GPIO 18 (PCM_CLK)</td></tr>
		<tr><td><b>GPIO 21</b></td>	 	 <td>13</td> <td></td><td>14</td>	<td></td></tr>
		<tr><td>GPIO 22</td>			 <td>15</td> <td></td><td>16</td>	<td>GPIO 23</td></tr>
		<tr><td></td>					 <td>17</td> <td></td><td>18</td>	<td>GPIO 24</td></tr>
		<tr><td>GPIO 10 (MOSI)</td>	 	 <td>19</td> <td></td><td>20</td>	<td></td></tr>
		<tr><td>GPIO 9 (MISO)</td>		 <td>21</td> <td></td><td>22</td>	<td>GPIO 25</td></tr>
		<tr><td>GPIO 11 (SCLK)</td>	 	 <td>23</td> <td></td><td>24</td>	<td>GPIO 8 (CE0)</td></tr>
		<tr><td></td>					 <td>25</td> <td></td><td>26</td>	<td>GPIO 7 (CE1)</td></tr></table>
	  </td>
	  <td>
	    PCB Revision 2 P1 pin header
		<table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>			 <td>Pin</td><td></td><td>Pin</td>	<td>Function</td></tr>
		<tr><td>3,3V</td>    			 <td>1</td>  <td></td><td>2</td>  	<td>5V</td></tr>
		<tr><td><b>GPIO 2 (SDA1)</b></td><td>3</td>  <td></td><td>4</td>	<td></td></tr>
		<tr><td><b>GPIO 3 (SCL1)</b></td><td>5</td>  <td></td><td>6</td>	<td>GND</td></tr>
		<tr><td>GPIO 4 (GPCLK0)</td>	 <td>7</td>  <td></td><td>8</td>	<td>GPIO 14 (TxD)</td></tr>
		<tr><td></td>					 <td>9</td>  <td></td><td>10</td>	<td>GPIO 15 (RxD)</td></tr>
		<tr><td>GPIO 17</td>			 <td>11</td> <td></td><td>12</td>	<td>GPIO 18 (PCM_CLK)</td></tr>
		<tr><td><b>GPIO 27</b></td>	 	 <td>13</td> <td></td><td>14</td>	<td></td></tr>
		<tr><td>GPIO 22</td>			 <td>15</td> <td></td><td>16</td>	<td>GPIO 23</td></tr>
		<tr><td></td>					 <td>17</td> <td></td><td>18</td>	<td>GPIO 24</td></tr>
		<tr><td>GPIO 10 (MOSI)</td>	 	 <td>19</td> <td></td><td>20</td>	<td></td></tr>
		<tr><td>GPIO 9 (MISO)</td>		 <td>21</td> <td></td><td>22</td>	<td>GPIO 25</td></tr>
		<tr><td>GPIO 11 (SCLK)</td>	 	 <td>23</td> <td></td><td>24</td>	<td>GPIO 8 (CE0)</td></tr>
		<tr><td></td>					 <td>25</td> <td></td><td>26</td>	<td>GPIO 7 (CE1)</td></tr></table>	
	  </td>
	  <td>
	    PCB Revision 2 P5 pin header
		<table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>	   <td>Pin</td><td></td><td>Pin</td><td>Function</td></tr>
		<tr><td>5V</td>    		   <td>1</td>  <td></td><td>2</td>  <td>3,3V</td></tr>
		<tr><td>GPIO 28 (SDA0)</td><td>3</td>  <td></td><td>4</td>	<td>GPIO 29 (SCL0)</td></tr>
		<tr><td>GPIO 30</td>	   <td>5</td>  <td></td><td>6</td>	<td>GPOI 31</td></tr> 
		<tr><td>GND</td>	 	   <td>7</td>  <td></td><td>8</td>	<td>GND</td></tr></table>
	  </td>
	</table>
    
    Examples:
    <pre>
      define Pin12 RPI_GPIO 18
      attr Pin12
      attr Pin12 poll_interval 5
    </pre>
  </ul>

  <a name="RPI_GPIOSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul><li>for output configured GPIO
      <ul><code>
        off<br>
        on<br>
        toggle<br>		
        </code>
      </ul>
      The <a href="#setExtensions"> set extensions</a> are also supported.<br>
      </li>
      <li>for input configured GPIO
      <ul><code>
        readval		
      </code></ul>
      readval refreshes the reading Pinlevel and, if attr toggletostate not set, the state value
    </ul>   
    </li><br>
     Examples:
    <ul>
      <code>set Pin12 off</code><br>
      <code>set Pin11,Pin12 on</code><br>
    </ul><br>
  </ul>

  <a name="RPI_GPIOGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt;</code>
    <br><br>
    returns "high" or "low" regarding the actual status of the pin and writes this value to reading <b>Pinlevel</b>
  </ul><br>

  <a name="RPI_GPIOAttr"></a>
  <b>Attributes</b>
  <ul>
    <li>direction<br>
      Sets the GPIO direction to input or output.<br>
      Default: input, valid values: input, output<br><br>
    </li>
    <li>interrupt<br>
      <b>can only be used with GPIO configured as input</b><br>
      enables edge detection for GPIO pin<br>
      on each interrupt event readings Pinlevel and state will be updated<br>
      Default: none, valid values: none, falling, rising, both<br>
	  For "both" the reading Longpress will be added and set to on as long as kes hold down longer than 1s<br>
	  For "falling" and "rising" the reading Toggle will be added an will be toggled at every interrupt and the reading Counter that increments at every interrupt<br><br>
    </li>
    <li>poll_interval<br>
      Set the polling interval in minutes to query the GPIO's level<br>
      Default: -, valid values: decimal number<br><br>
    </li>
    <li>toggletostate<br>
      <b>works with interrupt set to falling or rising only</b><br>
      if yes, state will be toggled at each interrupt event<br>
      Default: no, valid values: yes, no<br><br>
    </li>
    <li>pud_resistor<br>
      Sets the internal pullup/pulldown resistor<br>
      Default: -, valid values: off, up, down<br><br>
    </li>
    <li>debounce_in_ms<br>
      readout of pin value x ms after an interrupt occured. Can be used for switch debouncing<br>
      Default: 0, valid values: decimal number<br><br>
    </li>
    <li>restoreOnStartup<br>
      Restore Readings and sets after reboot<br>
      Default: on, valid values: on, off<br><br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>


=end html

=begin html_DE

<a name="RPI_GPIO"></a>
<h3>RPI_GPIO</h3>
<ul>
  <a name="RPI_GPIO"></a>
  <p>
    Das Raspberry Pi erm&ouml;glicht direkten Zugriff zu einigen GPIO's &uuml;ber den Pfostenstecker P1 (und P5 bei V2). Die Steckerbelegung ist in den Tabellen unter Define zu finden.
    Dieses Modul erm&ouml;glicht es, die herausgef&uuml;hten GPIO's direkt als Ein- und Ausgang zu benutzen. Die Eing&auml;nge k&ouml;nnen zyklisch abgefragt werden oder auch sofort bei Pegelwechsel gesetzt werden.<br><br>
    <b>Wichtig: Niemals Spannung an einen GPIO anlegen, der als Ausgang eingestellt ist! Die interne Logik der GPIO's arbeitet mit 3,3V. Ein &uuml;berschreiten der 3,3V zerst&ouml;rt den GPIO und vielleicht auch den ganzen Prozessor!</b><br><br>
    
    <b>Vorbereitung:</b><br>
    Auf GPIO Pins wird im Modul &uuml;ber sysfs zugegriffen. Die Dateien befinden sich unter /system/class/gpio und k&ouml;nnen nur mit root erreicht werden.
    Dieses Modul nutzt das gpio Tool von der <a href="http://wiringpi.com/download-and-install/">WiringPi</a>. Bibliothek um GPIS zu exportieren und die korrekten Nutzerrechte zu setzen.
    Installation WiringPi:
    <pre>
  sudo apt-get update
  sudo apt-get upgrade
  sudo apt-get install git-core
  git clone git://git.drogon.net/wiringPi
  cd wiringPi
  ./build
  sudo adduser fhem gpio</pre>
    Das wars!<br><br>
      
  <a name="RPI_GPIODefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RPI_GPIO &lt;GPIO number&gt;</code><br><br>
    Alle verf&uuml;gbaren <code>GPIO number</code> sind in den folgenden Tabellen zu finden<br><br>
    
	<table border="0" cellspacing="0" cellpadding="0">    
      <td> 
        PCB Revision 1 P1 pin header
        <table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>			 <td>Pin</td><td></td><td>Pin</td>	<td>Function</td></tr>
		<tr><td>3,3V</td>    			 <td>1</td>  <td></td><td>2</td>  	<td>5V</td></tr>
		<tr><td><b>GPIO 0 (SDA0)</b></td><td>3</td>  <td></td><td>4</td>	<td></td></tr>
		<tr><td><b>GPIO 1 (SCL0)</b></td><td>5</td>  <td></td><td>6</td>	<td>GND</td></tr>
		<tr><td>GPIO 4 (GPCLK0)</td>	 <td>7</td>  <td></td><td>8</td>	<td>GPIO 14 (TxD)</td></tr>
		<tr><td></td>					 <td>9</td>  <td></td><td>10</td>	<td>GPIO 15 (RxD)</td></tr>
		<tr><td>GPIO 17</td>			 <td>11</td> <td></td><td>12</td>	<td>GPIO 18 (PCM_CLK)</td></tr>
		<tr><td><b>GPIO 21</b></td>	 	 <td>13</td> <td></td><td>14</td>	<td></td></tr>
		<tr><td>GPIO 22</td>			 <td>15</td> <td></td><td>16</td>	<td>GPIO 23</td></tr>
		<tr><td></td>					 <td>17</td> <td></td><td>18</td>	<td>GPIO 24</td></tr>
		<tr><td>GPIO 10 (MOSI)</td>	 	 <td>19</td> <td></td><td>20</td>	<td></td></tr>
		<tr><td>GPIO 9 (MISO)</td>		 <td>21</td> <td></td><td>22</td>	<td>GPIO 25</td></tr>
		<tr><td>GPIO 11 (SCLK)</td>	 	 <td>23</td> <td></td><td>24</td>	<td>GPIO 8 (CE0)</td></tr>
		<tr><td></td>					 <td>25</td> <td></td><td>26</td>	<td>GPIO 7 (CE1)</td></tr></table>
	  </td>
	  <td>
	    PCB Revision 2 P1 pin header
		<table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>			 <td>Pin</td><td></td><td>Pin</td>	<td>Function</td></tr>
		<tr><td>3,3V</td>    			 <td>1</td>  <td></td><td>2</td>  	<td>5V</td></tr>
		<tr><td><b>GPIO 2 (SDA1)</b></td><td>3</td>  <td></td><td>4</td>	<td></td></tr>
		<tr><td><b>GPIO 3 (SCL1)</b></td><td>5</td>  <td></td><td>6</td>	<td>GND</td></tr>
		<tr><td>GPIO 4 (GPCLK0)</td>	 <td>7</td>  <td></td><td>8</td>	<td>GPIO 14 (TxD)</td></tr>
		<tr><td></td>					 <td>9</td>  <td></td><td>10</td>	<td>GPIO 15 (RxD)</td></tr>
		<tr><td>GPIO 17</td>			 <td>11</td> <td></td><td>12</td>	<td>GPIO 18 (PCM_CLK)</td></tr>
		<tr><td><b>GPIO 27</b></td>	 	 <td>13</td> <td></td><td>14</td>	<td></td></tr>
		<tr><td>GPIO 22</td>			 <td>15</td> <td></td><td>16</td>	<td>GPIO 23</td></tr>
		<tr><td></td>					 <td>17</td> <td></td><td>18</td>	<td>GPIO 24</td></tr>
		<tr><td>GPIO 10 (MOSI)</td>	 	 <td>19</td> <td></td><td>20</td>	<td></td></tr>
		<tr><td>GPIO 9 (MISO)</td>		 <td>21</td> <td></td><td>22</td>	<td>GPIO 25</td></tr>
		<tr><td>GPIO 11 (SCLK)</td>	 	 <td>23</td> <td></td><td>24</td>	<td>GPIO 8 (CE0)</td></tr>
		<tr><td></td>					 <td>25</td> <td></td><td>26</td>	<td>GPIO 7 (CE1)</td></tr></table>	
	  </td>
	  <td>
	    PCB Revision 2 P5 pin header
		<table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>	   <td>Pin</td><td></td><td>Pin</td><td>Function</td></tr>
		<tr><td>5V</td>    		   <td>1</td>  <td></td><td>2</td>  <td>3,3V</td></tr>
		<tr><td>GPIO 28 (SDA0)</td><td>3</td>  <td></td><td>4</td>	<td>GPIO 29 (SCL0)</td></tr>
		<tr><td>GPIO 30</td>	   <td>5</td>  <td></td><td>6</td>	<td>GPOI 31</td></tr> 
		<tr><td>GND</td>	 	   <td>7</td>  <td></td><td>8</td>	<td>GND</td></tr></table>
	  </td>
	</table>
    
    Beispiele:
    <pre>
      define Pin12 RPI_GPIO 18
      attr Pin12
      attr Pin12 poll_interval 5
    </pre>
  </ul>

  <a name="RPI_GPIOSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    <code>value</code> ist dabei einer der folgenden Werte:<br>
    <ul><li>F&uuml;r GPIO der als output konfiguriert ist
      <ul><code>
        off<br>
        on<br>
        toggle<br>		
        </code>
      </ul>
      Die <a href="#setExtensions"> set extensions</a> werden auch unterst&uuml;tzt.<br>
      </li>
      <li>F&uuml;r GPIO der als input konfiguriert ist
      <ul><code>
        readval		
      </code></ul>
      readval aktualisiert das reading Pinlevel und, wenn attr toggletostate nicht gesetzt ist, auch state
    </ul>   
    </li><br>
     Beispiele:
    <ul>
      <code>set Pin12 off</code><br>
      <code>set Pin11,Pin12 on</code><br>
    </ul><br>
  </ul>

  <a name="RPI_GPIOGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt;</code>
    <br><br>
    Gibt "high" oder "low" entsprechend dem aktuellen Pinstatus zur&uuml;ck und schreibt den Wert auch in das reading <b>Pinlevel</b>
  </ul><br>

  <a name="RPI_GPIOAttr"></a>
  <b>Attributes</b>
  <ul>
    <li>direction<br>
      Setzt den GPIO auf Ein- oder Ausgang.<br>
      Standard: input, g&uuml;ltige Werte: input, output<br><br>
    </li>
    <li>interrupt<br>
      <b>kann nur gew&auml;hlt werden, wenn der GPIO als Eingang konfiguriert ist</b><br>
      Aktiviert Flankenerkennung f&uuml;r den GPIO<br>
      bei jedem interrupt Ereignis werden die readings Pinlevel und state aktualisiert<br>
      Standard: none, g&uuml;ltige Werte: none, falling, rising, both<br><br>
	  Bei "both" wird ein reading Longpress angelegt, welches auf on gesetzt wird solange der Pin länger als 1s gedr&uuml;ckt wird<br>
	  Bei "falling" und "rising" wird ein reading Toggle angelegt, das bei jedem Interruptereignis toggelt und das Reading Counter, das bei jedem Ereignis um 1 hochzählt<br><br>

    </li>
    <li>poll_interval<br>
      Fragt den Zustand des GPIO regelm&auml;&szlig;ig ensprechend des eingestellten Wertes in Minuten ab<br>
      Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li>toggletostate<br>
      <b>Funktioniert nur bei auf falling oder rising gesetztem Attribut interrupt</b><br>
      Wenn auf "yes" gestellt wird bei jedem Triggerereignis das <b>state</b> reading invertiert<br>
      Standard: no, g&uuml;ltige Werte: yes, no<br><br>
    </li>
    <li>pud_resistor<br>
      Interner Pullup/down Widerstand<br>
      Standard: -, g&uuml;ltige Werte: off, up, down<br><br>
    </li>
    <li>debounce_in_ms<br>
      Wartezeit in ms bis nach ausgel&ouml;stem Interrupt der entsprechende Pin abgefragt wird. Kann zum entprellen von mechanischen Schaltern verwendet werden<br>
      Standard: 0, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li>restoreOnStartup<br>
      Wiederherstellen der Portzust&äuml;nde nach Neustart<br>
      Standard: on, g&uuml;ltige Werte: on, off<br><br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE

=cut 
