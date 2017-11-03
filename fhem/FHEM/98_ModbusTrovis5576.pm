##################################################################
#
# $Id$
#
# Fhem Modul für die Abfrage/Steuerung von Heizungssteuerungen vom Typ Samson Trovis 5576.
# Verwendet Modbus.pm als Basismodul für die eigentliche Implementation des Protokolls.
#
# Siehe 98_ModbusAttr.pm für ausführlichere Infos zur Verwendung des Moduls 98_Modbus.pm 
#
##################################################################
#
#     This file is part of fhem.
# 
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
# 
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
# Changelog
# 03.11.2017
#	Ein neues Register hinzugefügt: "Fehlerstatusregister_CL1".
# 28.06.2017
#	Zwei neue Register hinzugefügt: "Wasser_Zirkulationspumpe" und das entsprechende Ebenen-Bit "Wasser_Zirkulationspumpe_EBN" dazu.
# 14.03.2016 
#	Initial Release
#
##############################################################################

package main;
use strict;
use warnings;
sub ModbusTrovis5576_Initialize($);

my %Trovis5576ParseInfo = (
	# Grundlegendes
	'h0' => {	reading => 'Modellnummer',
				name => 'Erzeugnisnummer, Gerätekennung',
				poll => 'once'
			},
	'h9' => {	reading => 'Aussen_Temp',
				name => 'AußentempAF1',
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				poll => 1
			},
	'h149' => {	reading => 'Fehlerstatusregister_CL1',
				name => 'FehlerstatusReg',
				map => '0:Aus, 1:An',
				poll => 1
			},
	
	# RK1
	'h102' => {	reading => 'RK1_Schalter',
				name => 'Schalteroben',
				map => '0:PA, 1:Auto, 2:Standby, 3:Hand, 4:Sonne, 5:Mond',
				poll => 1
			},
	'c1008' => {reading => 'RK1_Frostschutzbetrieb',
				name => 'FrostschutzRk1',
				map => '0:Aus, 1:An',
				poll => 1
			},
	'h105' => {	reading => 'RK1_Betriebsart',
				name => 'BetriebsArtRk1',
				map => '2:Standby, 4:Sonne, 5:Mond',
				poll => 1,
				set => 1
			},
	'c88' => {	reading => 'RK1_Betriebsart_EBN',
				name => 'Ebene Betriebsart Rk1 (HR40106)',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'h106' => {	reading => 'RK1_Stellsignal',
				name => 'Stellsignal Rk1 [0...100%] (CL90)',
				min => 0,
				max => 100,
				poll => 1,
				set => 1
			},
	'c89' => {	reading => 'RK1_Stellsignal_EBN',
				name => 'Ebene Stellsignal Rk1 (HR40107)',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'c56' => {	reading => 'RK1_Umwaelzpumpe',
				name => 'Umwälzpumpe UP1 (Netzseite, CL96)',
				map => '0:Aus, 1:An',
				poll => 1,
				set => 1
			},
	'c95' => {	reading => 'RK1_Umwaelzpumpe_EBN',
				name => 'Ebene Umwälzpumpe UP1 (Netzseite, CL57)',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'h12' => {	reading => 'RK1_Vorlauf_Temp',
				name => 'VorlauftempVF1',
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				poll => 1
			},
	'h16' => {	reading => 'RK1_Ruecklauf_Temp',
				name => 'RückltempRüF1',
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				poll => 1
			},
	
	# RK2
	'h103' => {	reading => 'RK2_Schalter',
				name => 'Schaltermitte',
				map => '0:PA, 1:Auto, 2:Standby, 3:Hand, 4:Sonne, 5:Mond',
				poll => 1
			},
	'c1208' => {reading => 'RK2_Frostschutzbetrieb',
				name => 'FrostschutzRk2',
				map => '0:Aus, 1:An',
				poll => 1
			},
	'h107' => {	reading => 'RK2_Betriebsart',
				name => 'BetriebsArtRk2',
				map => '2:Standby, 4:Sonne, 5:Mond',
				poll => 1,
				set => 1
			},
	'c90' => {	reading => 'RK2_Betriebsart_EBN',
				name => 'Ebene Betriebsart Rk2 (HR40108)',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'h108' => {	reading => 'RK2_Stellsignal',
				name => 'Stellsignal Rk2 [0...100%] (CL90)',
				min => 0,
				max => 100,
				poll => 1,
				set => 1
			},
	'c91' => {	reading => 'RK2_Stellsignal_EBN',
				name => 'Ebene Stellsignal Rk2 (HR40109)',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'c57' => {	reading => 'RK2_Umwaelzpumpe',
				name => 'Umwälzpumpe UP2 (Netzseite, CL97)',
				map => '0:Aus, 1:An',
				poll => 1,
				set => 1
			},
	'c96' => {	reading => 'RK2_Umwaelzpumpe_EBN',
				name => 'Ebene Umwälzpumpe UP2 (Netzseite, CL58)',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'h13' => {	reading => 'RK2_Vorlauf_Temp',
				name => 'VorlauftempVF2',
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				poll => 1
			},
	'h17' => {	reading => 'RK2_Ruecklauf_Temp',
				name => 'RückltempRüF2',
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				poll => 1
			},
	
	# Wasser
	'h104' => {	reading => 'Wasser_Schalter',
				name => 'Schalterunten',
				map => '0:PA, 1:Auto, 2:Standby, 3:Hand, 4:Sonne, 5:Mond',
				poll => 1
			},
	'c1805' => {reading => 'Wasser_Frostschutzbetrieb',
				name => 'FrostschutzTW',
				map => '0:Aus, 1:An',
				poll => 1
			},
	'h111' => {	reading => 'Wasser_Betriebsart',
				name => 'BetriebsArtTW',
				map => '2:Standby, 4:Sonne, 5:Mond',
				poll => 1,
				set => 1
			},
	'c94' => {	reading => 'Wasser_Betriebsart_EBN',
				name => 'EBNBetrArtTW',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'c59' => {	reading => 'Wasser_Speicherladepumpe',
				name => 'BinärausgBA4',
				map => '0:Aus, 1:An',
				poll => 1,
				set => 1
			},
	'c98' => {	reading => 'Wasser_Speicherladepumpe_EBN',
				name => 'EBNBinärBA4',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'c60' => {	reading => 'Wasser_Zirkulationspumpe',
				name => 'BinärausgBA5',
				map => '0:Aus, 1:An',
				poll => 1,
				set => 1
			},
	'c99' => {	reading => 'Wasser_Zirkulationspumpe_EBN',
				name => 'EBNBinärBA5',
				map => '0:GLT, 1:Autark',
				poll => 1,
				set => 1
			},
	'c1837' => {reading => 'Wasser_ThermischeDesinfektion',
				name => 'FB14ThermDes',
				map => '0:Aus, 1:An',
				poll => 1,
				set => 1
			},
	'h22' => {	reading => 'Wasser_Temp',
				name => 'SpeichertempSF1',
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				poll => 1
			},
	'h1799' => {reading => 'Wasser_Temp_Soll',
				name => 'Trinkwasser (Speicher) -Sollwert',
				hint => '20.0,25.0,30.0,35.0,40.0,45.0,50.0,55.0,60.0,65.0,70.0,75.0,80.0,85.0,90.0',
				min => 20,
				max => 90,
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				setexpr => '$val*10',
				poll => 1,
				set => 1
			},
	'h1806' => {reading => 'Wasser_Temp_Minimum',
				name => 'Trinkwasser (Speicher) - Minimalwert',
				hint => '20.0,25.0,30.0,35.0,40.0,45.0,50.0,55.0,60.0,65.0,70.0,75.0,80.0,85.0,90.0',
				min => 20,
				max => 90,
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				setexpr => '$val*10',
				poll => 1,
				set => 1
			},
	'h1829' => {reading => 'Wasser_Temp_Desinfektion',
				name => 'Desinfektionstemperatur',
				hint => '60.0,65.0,70.0,75.0,80.0,85.0,90.0',
				min => 60,
				max => 90,
				expr => '$val/10',
				format => '%.1f',
				unpack => 's>',
				setexpr => '$val*10',
				poll => 1,
				set => 1
			}
);

my %Trovis5576DeviceInfo = (
	'h' => {defShowGet => 1,
			combine => 5
		},
	'c' => {defShowGet => 1,
			combine => 5
		},
	'timing' => {sendDelay => 0.2,
				commDelay => 0.2
		}
);



#####################################
sub ModbusTrovis5576_Initialize($) {
	my ($hash) = @_;
	
	require "$attr{global}{modpath}/FHEM/98_Modbus.pm";
	$hash->{parseInfo}  = \%Trovis5576ParseInfo;  # defines registers, inputs, coils etc. for this Modbus Device
	$hash->{deviceInfo} = \%Trovis5576DeviceInfo; # defines properties of the device like defaults and supported function codes
	
	ModbusLD_Initialize($hash); # Generic function of the Modbus module does the rest
	
	$hash->{AttrList} .= ' '.$hash->{ObjAttrList}.' '.$hash->{DevAttrList}.' poll-.* polldelay-.*';
}

1;

=pod
=item summary    Module to work with Heatung Control System Samson Trovis 5576
=item summary_DE Modul für Heizungssteuerungen vom Typ Samson Trovis 5576.
=begin html

<a name="ModbusTrovis5576"></a>
<h3>ModbusTrovis5576</h3>
<ul>
    ModbusTrovis5576 uses the low level Modbus module to provide a way to communicate with the Samson Trovis 5576 Heating Management.
    It defines the modbus holding registers for the different values and reads them in a defined interval.
    <br /><br />

    <b>Prerequisites</b>
	<ul>
	<b>This module requires the basic <a href="#Modbus">Modbus</a> module which itsef requires Device::SerialPort or Win32::SerialPort module.</b>
    </ul><br />
    
    <b>Hardware Connection</b>
	<ul>
    The <a href="https://www.samson.de/pdf_de/e55760de.pdf">Manual</a> shows on page 124 a diagram of the correct pins for connecting to the serial port. The RS232-Port is <b>not</b> the one on the front side, but, as seen from the front, on the left side of the heating management. This port is covered with a small plastic-shield which can easily be removed.<br />
    Only the usual pins for serial communication (TD, RD and Ground) are needed.
    </ul><br />
    
    <b>Special meanings with Readings and the Heating Management System</b>
	<ul>
	If you change the value of "Betriebsart" ("Operating Mode") the rotary switch at the heating management doesn't change. To reflect this fact the display shows "GLT" (in German "Gebäudeleittechnik" - Building Control Center) and the corresponding so-called Ebenen-Bit ("_EBN" - Level-Bit) is set to "GLT".<br />
	If you want to switch back to autonomous mode you can set the appropriate Ebenen-Bit to "Autark".<br /><br />
	
	If you change the value of "Betriebsart" to standby it could be happen that it is automatically (re-)changed to "Mond" ("Moon"). This happens if the outside temperature is lower than 3°C and it's shown with the value of "Frostschutzbetrieb" ("Frost Protection Mode").<br /><br />
    <b>Suggestion:</b><br />
    It is hardly recommended to set the Attribute <code>event-on-change-reading</code> to <code>.*</code>. Otherwise the system will generate many senseless events.
    </ul><br />
    
    <a name="ModbusTrovis5576Define"></a>
    <b>Define</b>
    <ul>
    <code>define &lt;name&gt; ModbusTrovis5576 &lt;ID&gt; &lt;Interval&gt;</code><br /><br />
    The module connects to the Samson Trovis 5576 Heating Management with the Modbus Id &lt;ID&gt; through an already defined Modbus device and actively requests data from the system every &lt;Interval&gt; seconds.<br /><br />
    Example:<br>
    <code>define heizung ModbusTrovis5576 255 60</code>
    </ul><br />

    <a name="ModbusTrovis5576Set"></a>
    <b>Set-Commands</b>
	<ul>
    The following set options are available:
    <ul>
    	<li>Regelkreis 1 (Usually Wallmounted-Heatings):<ul>
	    	<li><b>RK1_Betriebsart</b>: Operating mode of Regelkreis 1. Possible values are Standby, Mond or Sonne.</li>
	    	<li><b>RK1_Betriebsart_EBN</b>: The Ebenen-Bit according to the Operating Mode. Possible values are GLT or Autark.</li>
	    	<li><b>RK1_Stellsignal</b>: The percent value of opening of the heat transportation valve.</li>
	    	<li><b>RK1_Stellsignal_EBN</b>: The Ebenen-Bit according to the heat transportation valve. Possible values are GLT or Autark.</li>
	    	<li><b>RK1_Umwaelzpumpe</b>: The on/off state of thr circulation pump. Possible values are An or Aus.</li>
	    	<li><b>RK1_Umwaelzpumpe_EBN</b>: The Ebenen-Bit according to the circulation pump. Possible values are GLT or Autark.</li>
    	</ul></li>
    	
    	<li>Regelkreis 2 (Usually Floor Heating System):<ul>
	    	<li><b>RK2_Betriebsart</b>: Operating mode of Regelkreis 2. Possible values are Standby, Mond or Sonne.</li>
	    	<li><b>RK2_Betriebsart_EBN</b>: The Ebenen-Bit according to the Operating Mode. Possible values are GLT or Autark.</li>
	    	<li><b>RK2_Stellsignal</b>: The percent value of opening of the heat transportation valve.</li>
	    	<li><b>RK2_Stellsignal_EBN</b>: The Ebenen-Bit according to the heat transportation valve. Possible values are GLT or Autark.</li>
	    	<li><b>RK2_Umwaelzpumpe</b>: The on/off state of the circulation pump. Possible values are An or Aus.</li>
	    	<li><b>RK2_Umwaelzpumpe_EBN</b>: The Ebenen-Bit according to the circulation pump. Possible values are GLT or Autark.</li>
    	</ul></li>
    	
    	<li>Drinkable Water Reservoir:<ul>
	    	<li><b>Wasser_Betriebsart</b>: Operating mode of the drinkable water system. Possible values are Standby, Mond or Sonne.</li>
	    	<li><b>Wasser_Betriebsart_EBN</b>: The Ebenen-Bit according to the Operating Mode. Possible values are GLT or Autark.</li>
	    	<li><b>Wasser_Speicherladepumpe</b>: The on/off state of the reservoir loading pump. Possible values are An or Aus.</li>
	    	<li><b>Wasser_Speicherladepumpe_EBN</b>: The Ebenen-Bit according to the Speicherladepumpe. Possible values are GLT or Autark.</li>
	    	<li><b>Wasser_Zirkulationspumpe</b>: The on/off state of the circular pump. Possible values are An or Aus.</li>
	    	<li><b>Wasser_Zirkulationspumpe_EBN</b>: The Ebenen-Bit according to the circular pump. Possible values are GLT or Autark.</li>
	    	<li><b>Wasser_ThermischeDesinfektion</b>: On/off state of the thermal disinfection. Possible values are An or Aus.</li>
	    	<li><b>Wasser_Temp_Soll</b>: The desired temperature for the drinkabke water reservoir.</li>
	    	<li><b>Wasser_Temp_Minimum</b>: The lowest temperature for the drinkable water reservoir.</li>
	    	<li><b>Wasser_Temp_Desinfektion</b>: The desired temperature of the thermal disinfection system.</li>
	    </ul></li>
    </ul><br />
    All other Readings (along with their Meanings) which can only be read:<br />
    <ul>
    	<li>Common Data:<ul>
	    	<li><b>Modellnummer</b>: Shows the modelnumber. Should be "5576".</li>
	    	<li><b>Aussen_Temp</b>: Shows the currently measured outside temperature in °C.</li>
	    	<li><b>Fehlerstatusregister_CL1</b>: Shows the current status register (CL1).</li>
	    </ul></li>
    	
    	<li>Regelkreis 1 (Usually Wallmounted-Heatings):<ul>
	    	<li><b>RK1_Schalter</b>: Represent the current value of the rotary switch. Possible values are PA, Auto, Standby, Hand, Sonne or Mond.</li>
	    	<li><b>RK1_Frostschutzbetrieb</b>: On/off state of the frost protection mode of Regelkreis 1.</li>
	    	<li><b>RK1_Vorlauf_Temp</b>: Shows the currently measured flow temperature in °C of Regelkreis 1.</li>
	    	<li><b>RK1_Ruecklauf_Temp</b>: Shows the currently measured return temperature in °C of Regelkreis 1.</li>
	    </ul></li>
    	
    	<li>Regelkreis 2 (Usually Floor Heating System):<ul>
	    	<li><b>RK2_Schalter</b>: Represent the current value of the rotary switch. Possible values are PA, Auto, Standby, Hand, Sonne or Mond.</li>
	    	<li><b>RK2_Frostschutzbetrieb</b>: On/off state of the frost protection mode of Regelkreis 2.</li>
	    	<li><b>RK2_Vorlauf_Temp</b>: Shows the currently measured flow temperature in °C of Regelkreis 2.</li>
	    	<li><b>RK2_Ruecklauf_Temp</b>: Shows the currently measured return temperature in °C of Regelkreis 2.</li>
	    </ul></li>
    	
    	<li>Drinkable Water Reservoir:<ul>
	    	<li><b>Wasser_Schalter</b>: Represent the current value of the rotary switch. Possible values are PA, Auto, Standby, Hand, Sonne or Mond.</li>
	    	<li><b>Wasser_Frostschutzbetrieb</b>: On/off state of the frost protection mode of the drinkable water heating system.</li>
	    	<li><b>Wasser_Temp</b>: Shows the currently measured return temperature in °C of the drinkablr water reservoir.</li>
	    </ul></li>
    </ul>
    </ul><br />
    
    <a name="ModbusTrovis5576Get"></a>
    <b>Get-Commands</b>
	<ul>
    All readings are also available as Get commands. Internally a Get command triggers the corresponding request to the device and then interprets the data and returns the correct field value. This is a good way for getting a new current value from the Heating Management System.
    </ul><br />
    
    <a name="ModbusTrovis5576attr"></a>
    <b>Attribute</b>
	<ul>
	Only centralized Attributes are in use. Especially:
	    <ul>
	    	<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	    </ul>
    </ul><br />
</ul>

=end html

=begin html_DE

<a name="ModbusTrovis5576"></a>
<h3>ModbusTrovis5576</h3>
<ul>
    ModbusTrovis5576 verwendet das Modul Modbus für die Kommunikation mit der Samson Trovis 5576 Heizungssteuerung.
    Hier wurden die wichtigsten (der über 2000 verfügbaren) Werte aus den Holding-Registern und Coils-Statuswerten definiert und werden im angegebenen Intervall abgefragt und aktualisiert.
    <br /><br />

    <b>Vorraussetzungen</b>
	<ul>
    Dieses Modul benötigt das Basismodul <a href="#Modbus">Modbus</a> für die Kommunikation, welches wiederum das Perl-Modul Device::SerialPort oder Win32::SerialPort benötigt.
    </ul><br />
    
    <b>Physikalische Verbindung zur Heizungssteuerung</b>
	<ul>
    Im <a href="https://www.samson.de/pdf_de/e55760de.pdf">Handbuch</a> auf Seite 124 steht die Pinbelegung der RS232-Schnittstelle. Diese befindet sich <b>nicht</b> vorne am Reglermodul, sondern, von vorne gesehen, an der linken Seite des Reglers. Diese Schnittstelle ist mit einem Schutzdeckel verschlossen, den man einfach abziehen kann.<br />
    Man benötigt nur die üblichen Pins für TD und RD, sowie Ground.
    </ul><br />
    
    <b>Besonderheiten der Readings und des Reglers</b>
	<ul>
    Man kann mit diesem Modul z.B. die Betriebsart der jeweiligen Regelkreise umschalten. Da der Drehschalter am Regler selbst natürlich immer noch auf der alten Stellung steht, wird diese "Umgehung" durch die Anzeige "GLT" (steht für "Gebäudeleittechnik", also für die zentrale Steuerungsübernahme) im Display deutlich gemacht. Gleichzeitig dazu wird das entsprechende Ebenen-Bit ("_EBN") auf "GLT" gesetzt.<br />
    Um jetzt wieder auf die hardwaremäßig gesetzte Einstellung zurückzuschalten, muss das entsprechende Ebenen-Bit auf "Autark" gesetzt werden. Das dazugehörende Reading wird im Anschluß auf den nun im Regler gültigen Wert gesetzt.<br /><br />
    
    Wenn man eine Betriebsart auf "Standby" umschaltet, kann es sein, dass die Heizungsanlage diese auf "Mond" (zurück-)umstellt. Das wird dann mit dem Bit für Frostschutzbetrieb angezeigt, und erfolgt, wenn die gemessene Aussentemperatur unter 3°C liegt.<br /><br />
    <b>Hinweis:</b><br />
    Es ist sehr empfehlenswert das Attribut <code>event-on-change-reading</code> auf <code>.*</code> zu setzen. Sonst werden sehr viele unnötige Events erzeugt.
    </ul><br />

    <a name="ModbusTrovis5576Define"></a>
    <b>Define</b>
	<ul>
    <code>define &lt;name&gt; ModbusTrovis5576 &lt;ID&gt; &lt;Interval&gt;</code><br /><br />
    Das Modul verbindet sich zur Samson Trovis 5576 Heizungssteuerung mit der angegebenen Modbus Id &lt;ID&gt; über ein bereits fertig definiertes Modbus-Device und fragt die gewünschten Werte im Abstand von &lt;Interval&gt; Sekunden ab.<br /><br />
    Beispiel:<br>
    <code>define heizung ModbusTrovis5576 255 60</code>
    </ul><br />

    <a name="ModbusTrovis5576Set"></a>
    <b>Set-Kommandos</b>
	<ul>
    Die folgenden Werte können gesetzt werden:
    <ul>
    	<li>Regelkreis 1 (Normalerweise Wandheizkörper):<ul>
	    	<li><b>RK1_Betriebsart</b>: Die Betriebsart des Regelkreis 1. Kann Standby, Mond oder Sonne sein, und entspricht der Einstellung am Regler selbst (siehe auch Reading RK1_Schalter).</li>
	    	<li><b>RK1_Betriebsart_EBN</b>: Das Ebenen-Bit zur Betriebsart. Kann GLT oder Autark sein, und gibt an, ob die Heizungssteuerung Autark läuft, oder übersteuert wurde.</li>
	    	<li><b>RK1_Stellsignal</b>: Der Öffnungsgrad in Prozent des Stellglieds zur Wärmeübertragung.</li>
	    	<li><b>RK1_Stellsignal_EBN</b>: Das Ebenen-Bit zum Stellsignal. Kann GLT oder Autark sein, und gibt an, ob die Heizungssteuerung Autark läuft, oder übersteuert wurde.</li>
	    	<li><b>RK1_Umwaelzpumpe</b>: Der Zustand der Umwälzpumpe, Kann An oder Aus sein.</li>
	    	<li><b>RK1_Umwaelzpumpe_EBN</b>: Das Ebenen-Bit zur Umwälzpumpe. Kann GLT oder Autark sein, und gibt an, ob die Heizungssteuerung Autark läuft, oder übersteuert wurde.</li>
    	</ul></li>
    	
    	<li>Regelkreis 2 (Normalerweise Fußbodenheizung):<ul>
	    	<li><b>RK2_Betriebsart</b>: Die Betriebsart des Regelkreis 2. Kann Standby, Mond oder Sonne sein, und entspricht der Einstellung am Regler selbst (siehe auch Reading RK2_Schalter).</li>
	    	<li><b>RK2_Betriebsart_EBN</b>: Das Ebenen-Bit zur Betriebsart. Kann GLT oder Autark sein, und gibt an, ob die Heizungssteuerung Autark läuft, oder übersteuert wurde.</li>
	    	<li><b>RK2_Stellsignal</b>: Der Öffnungsgrad in Prozent des Stellglieds zur Wärmeübertragung.</li>
	    	<li><b>RK2_Stellsignal_EBN</b>: Das Ebenen-Bit zum Stellsignal. Kann GLT oder Autark sein, und gibt an, ob die Heizungssteuerung Autark läuft, oder übersteuert wurde.</li>
	    	<li><b>RK2_Umwaelzpumpe</b>: Der Zustand der Umwälzpumpe, Kann An oder Aus sein.</li>
	    	<li><b>RK2_Umwaelzpumpe_EBN</b>: Das Ebenen-Bit zur Umwälzpumpe. Kann GLT oder Autark sein, und gibt an, ob die Heizungssteuerung Autark läuft, oder übersteuert wurde.</li>
    	</ul></li>
    	
    	<li>Trinkwasserspeicher:<ul>
	    	<li><b>Wasser_Betriebsart</b>: Die Betriebsart des Trinkwasserkreises. Kann Standby, Mond oder Sonne sein, und entspricht der Einstellung am Regler selbst (siehe auch Reading Wasser_Schalter).</li>
	    	<li><b>Wasser_Betriebsart_EBN</b>: Das Ebenen-Bit zur Betriebsart. Kann GLT oder Autark sein, und gibt an, ob die Heizungssteuerung Autark läuft, oder übersteuert wurde.</li>
	    	<li><b>Wasser_Speicherladepumpe</b>: Der Zustand der Speicherladepumpe. Kann An oder Aus sein.</li>
	    	<li><b>Wasser_Speicherladepumpe_EBN</b>: Das Ebenen-Bit zur Speicherladepumpe. Kann GLT oder Autark sein, und gibt an, ob die Pumpe Autark läuft, oder übersteuert wurde.</li>
	    	<li><b>Wasser_Zirkulationspumpe</b>: Der Zustand der Zirkulationspumpe. Kann An oder Aus sein.</li>
	    	<li><b>Wasser_Zirkulationspumpe_EBN</b>: Das Ebenen-Bit zur Zirkulationspumpe. Kann GLT oder Autark sein, und gibt an, ob die Pumpe Autark läuft, oder übersteuert wurde.</li>
	    	<li><b>Wasser_ThermischeDesinfektion</b>: Gibt an, ob gerade eine thermische Desinfektion läuft (=An) oder nicht (=Aus). </li>
	    	<li><b>Wasser_Temp_Soll</b>: Die Solltemperatur des Trinkwasserspeichers.</li>
	    	<li><b>Wasser_Temp_Minimum</b>: Die Minimaltemperatur des Trinkwasserspeichers.</li>
	    	<li><b>Wasser_Temp_Desinfektion</b>: Die Solltemperatur der thermischen Desinfektion.</li>
	    </ul></li>
    </ul><br />
    Hier der Vollständigkeit halber die Bedeutung der restlichen Readings (die nur gelesen werden können):<br />
    <ul>
    	<li>Grundsätzliches:<ul>
	    	<li><b>Modellnummer</b>: Gibt die gemeldete Modellnummer an. Sollte "5576" sein.</li>
	    	<li><b>Aussen_Temp</b>: Gibt die gemessene Aussentemperatur in °C an.</li>
	    	<li><b>Fehlerstatusregister_CL1</b>: Gibt den Zustand des aktuellen Status Register zurück.</li>
	    </ul></li>
    	
    	<li>Regelkreis 1 (Normalerweise Wandheizkörper):<ul>
	    	<li><b>RK1_Schalter</b>: Gibt die Schalterstellung am Regler an. Kann PA, Auto, Standby, Hand, Sonne oder Mond sein.</li>
	    	<li><b>RK1_Frostschutzbetrieb</b>: Gibt an, ob der Heizungsregelkreis 1 im Frostschutzbetrieb läuft.</li>
	    	<li><b>RK1_Vorlauf_Temp</b>: Gibt die Heizungsvorlauftemperatur in °C an.</li>
	    	<li><b>RK1_Ruecklauf_Temp</b>: Gibt die Heizungsrücklauftemperatur in °C an.</li>
	    </ul></li>
    	
    	<li>Regelkreis 2 (Normalerweise Fußbodenheizung):<ul>
	    	<li><b>RK2_Schalter</b>: Gibt die Schalterstellung am Regler an. Kann PA, Auto, Standby, Hand, Sonne oder Mond sein.</li>
	    	<li><b>RK2_Frostschutzbetrieb</b>: Gibt an, ob der Heizungsregelkreis 2 im Frostschutzbetrieb läuft.</li>
	    	<li><b>RK2_Vorlauf_Temp</b>: Gibt die Heizungsvorlauftemperatur in °C an.</li>
	    	<li><b>RK2_Ruecklauf_Temp</b>: Gibt die Heizungsrücklauftemperatur in °C an.</li>
	    </ul></li>
    	
    	<li>Trinkwasserspeicher:<ul>
	    	<li><b>Wasser_Schalter</b>: Gibt die Schalterstellung am Regler an. Kann PA, Auto, Standby, Hand, Sonne oder Mond sein.</li>
	    	<li><b>Wasser_Frostschutzbetrieb</b>: Gibt an, ob der Trinkwasserregelkreis im Frostschutzbetrieb läuft.</li>
	    	<li><b>Wasser_Temp</b>: Gibt die Trinkwasserspeichertemperatur in °C an.</li>
	    </ul></li>
    </ul>
    </ul><br />
    
    <a name="ModbusTrovis5576Get"></a>
    <b>Get-Kommandos</b>
	<ul>
    Alle Readings sind auch als get-Kommando verfügbar. Intern führt ein get einen Request an die Heizungssteuerung aus, und aktualisiert den entsprechenden Readings-Wert (und gibt ihn als Ergebnis des Aufrufs zurück). Damit kann man eine zusätzliche Aktualisierung des Wertes erzwingen.
    </ul><br />
    
    <a name="ModbusTrovis5576attr"></a>
    <b>Attribute</b>
	<ul>
	Nur zentral definierte Attribute werden untstützt. Im speziellen:
	    <ul>
	    	<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	    </ul>
    </ul><br />
</ul>

=end html_DE
=cut
