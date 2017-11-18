    ##############################################
    # $Id$
    # 
    # The purpose of this module is to support serval 
    # weather sensors like WS-0101  (Sender 868MHz ASK   Epmfänger RX868SH-DV elv)
    # Sidey79 & pejonp 2015  
    #
    # 22.09.2017: rainTotal --> rain_total
    # 23.09.2017: windDirAverage   SabineT https://forum.fhem.de/index.php/topic,75225.msg669950.html#msg669950
    # 
    #
    
    package main;
    
    use strict;
    use warnings;
    #use Math::Round qw/nearest/;
    
    # werden benötigt, aber im Programm noch extra abgetestet 
    #use Digest::CRC qw(crc);
    #use Math::Trig;
    
    sub SD_WS09_Initialize($)
    {
      my ($hash) = @_;
    
      $hash->{Match}     = "^P9#F[A-Fa-f0-9]+";    ## pos 7 ist aktuell immer 0xF
      $hash->{DefFn}     = "SD_WS09_Define";
      $hash->{UndefFn}   = "SD_WS09_Undef";
      $hash->{ParseFn}   = "SD_WS09_Parse";
      $hash->{AttrFn}	   = "SD_WS09_Attr";
      $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 "
                           ."model:CTW600,WH1080 ignore:0,1 "
                            ."windKorrektur:-3,-2,-1,0,1,2,3 "
                            ."Unit_of_Wind:m/s,km/h,ft/s,mph,bft,knot "
                            ."WindDirAverageTime "
                            ."WindDirAverageMinSpeed "
                            ."WindDirAverageDecay "
                            ."$readingFnAttributes ";
      $hash->{AutoCreate} =
            { "SD_WS09.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.* windKorrektur:.*:0 verbose:5" , FILTER => "%NAME", GPLOT => "WH1080wind4:windSpeed/windGust,",  autocreateThreshold => "2:180"} };
    
    
    }
    
    #############################
    sub SD_WS09_Define($$)
    {
      my ($hash, $def) = @_;
      my @a = split("[ \t][ \t]*", $def);
    
      return "wrong syntax: define <name> SD_WS09 <code> ".int(@a)
            if(int(@a) < 3 );
    
      $hash->{CODE} = $a[2];
      $hash->{lastMSG} =  "";
      $hash->{bitMSG} =  "";
    
      $modules{SD_WS09}{defptr}{$a[2]} = $hash;
      $hash->{STATE} = "Defined";
      
      my $model = $a[2];
      $model =~ s/_.*$//;
      $hash->{MODEL} = $model;
      
      my $name= $hash->{NAME};
      return undef;
    }
    
    #####################################
    sub SD_WS09_Undef($$)
    {
      my ($hash, $name) = @_;
      delete($modules{SD_WS09}{defptr}{$hash->{CODE}})
         if(defined($hash->{CODE}) &&
            defined($modules{SD_WS09}{defptr}{$hash->{CODE}}));
      return undef;
    }
    
    
    ###################################
    sub SD_WS09_Parse($$)
    {
      my ($iohash, $msg) = @_;
      my $name = $iohash->{NAME};
      my (undef ,$rawData) = split("#",$msg);
      my @winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");
      my %uowind_unit= ("m/s",'1',"km/h",'3.6',"ft/s",'3.28',"bft",'-1',"mph",'2.24',"knot",'1.94');
      my %uowind_index = ("m/s",'0',"km/h",'1',"ft/s",'2',"mph",'3',"knot",'4',"bft",'5');
      my $hlen = length($rawData);
      my $blen = $hlen * 4;
      my $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 
      my $bitData2;
      my $bitData20;
      my $rain = 0;
      my $deviceCode = 0;
      my $model = "undef";  # 0xFFA -> WS0101/WH1080 alles andere -> CTW600 
      my $modelid;
      my $windSpeed;
      my $windSpeed_kmh;
      my $windSpeed_fts;
      my $windSpeed_bft;
      my $windSpeed_mph;
      my $windSpeed_kn;
      my $windguest;
      my $windguest_kmh;
      my $windguest_fts;
      my $windguest_bft;
      my $windguest_mph;
      my $windguest_kn;
      my $sensdata;
      my $id;
      my $bat = 0;
      my $temp = 0;
      my $hum = 1;
      my $windDirection = 1 ;
      my $windDirectionText = "N";
      my $windDirectionDegree = 0;
      my $FOuvo ;   # UV data nybble ?
      my $FOlux ; # Lux High byte (full scale = 4,000,000?) # Lux Middle byte  # Lux Low byte, Unit = 0.1 Lux (binary)
      my $rr2 ;
      my $state;
      my $msg_vor = 'P9#';
      my $minL1 = 70;
      my $minL2 = 60;
      my $whid;
      my $wh;
      my $rawData_merk;
      my $wfaktor = 1;
      my @windstat;
      
      my $syncpos= index($bitData,"11111110");  #7x1 1x0 preamble
    	Log3 $iohash, 4, "$name: SD_WS09_Parse0 msg=$rawData Bin=$bitData syncp=$syncpos length:".length($bitData) ;

    	if ($syncpos ==-1 || length($bitData)-$syncpos < $minL2)
    	{
    			Log3 $iohash, 4, "$name: SD_WS09_Parse EXIT: msg=$rawData syncp=$syncpos length:".length($bitData) ;
    			return undef;
    	}
      
      my $crcwh1080 = AttrVal($iohash->{NAME},'WS09_CRCAUS',0);
      Log3 $iohash, 4, "$name: SD_WS09_Parse CRC_AUS:$crcwh1080 " ;
      $rawData_merk = $rawData;
     
       my $rc = eval
     {
      require Digest::CRC;
      Digest::CRC->import();
      1;
     };

    if($rc) # test ob  Digest::CRC geladen wurde
    {
      $rr2 = SD_WS09_CRCCHECK($rawData);
      if ($rr2 == 0 || (($rr2 == 49) && ($crcwh1080 == 2)) ) {
      # 1. OK
          $model = "WH1080";
          Log3 $iohash, 4, "$name: SD_WS09_SHIFT_0 OK rwa:$rawData" ;
      } else {
      # 1. nok
          $rawData = SD_WS09_SHIFT($rawData);
          Log3 $iohash, 4, "$name: SD_WS09_SHIFT_1 NOK  rwa:$rawData" ;
          $rr2 = SD_WS09_CRCCHECK($rawData);
          if ($rr2 == 0 || (($rr2 == 49) && ($crcwh1080 == 2)) ) {
          # 2.ok
              $msg = $msg_vor.$rawData;
              $model = "WH1080";
              Log3 $iohash, 4, "$name: SD_WS09_SHIFT_2 OK rwa:$rawData msg:$msg" ;
          } else {
              # 2. nok
              $rawData = SD_WS09_SHIFT($rawData);
              Log3 $iohash, 4, "$name: SD_WS09_SHIFT_3 NOK rwa:$rawData" ;
              $rr2 = SD_WS09_CRCCHECK($rawData);
              if ($rr2 == 0 || (($rr2 == 49) && ($crcwh1080 == 2)) ) {
                # 3. ok
                $msg = $msg_vor.$rawData;
                $model = "WH1080";
                Log3 $iohash, 4, "$name: SD_WS09_SHIFT_4 OK rwa:$rawData msg:$msg" ;
              }else{
               # 3. nok
                $rawData = $rawData_merk;
                $msg = $msg_vor.$rawData;
                Log3 $iohash, 4, "$name: SD_WS09_SHIFT_5 NOK rwa:$rawData msg:$msg" ;
             }
         }
      }
     }else {
      Log3 $iohash, 1, "$name: SD_WS09 CRC_not_load: Modul Digest::CRC fehlt: cpan install Digest::CRC or sudo apt-get install libdigest-crc-perl" ;
      return "";
   }  
    
     $hlen = length($rawData);
     $blen = $hlen * 4;
     $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 
     Log3 $iohash, 4, "$name: SD_WS09_CRC_test2 rwa:$rawData msg:$msg CRC:".SD_WS09_CRCCHECK($rawData) ;
                  
         if( $model eq "WH1080") {
            $sensdata = substr($bitData,8);
            $whid = substr($sensdata,0,4);
            
            if(  $whid == "1010" ){ # A  Wettermeldungen
               	  Log3 $iohash, 4, "$name: SD_WS09_Parse_1 msg=$sensdata length:".length($sensdata) ;
                  $model = "WH1080";
                  $id = SD_WS09_bin2dec(substr($sensdata,4,8));
                  $bat = (SD_WS09_bin2dec((substr($sensdata,64,4))) == 0) ? 'ok':'low' ; # decode battery = 0 --> ok
                  $temp = (SD_WS09_bin2dec(substr($sensdata,12,12)) - 400)/10;
        		      $hum = SD_WS09_bin2dec(substr($sensdata,24,8));
                  $windDirection = SD_WS09_bin2dec(substr($sensdata,68,4));  
                  $windDirectionText = $winddir_name[$windDirection];
                  $windDirectionDegree = $windDirection * 360 / 16;
                  $windSpeed =  round((SD_WS09_bin2dec(substr($sensdata,32,8))* 34)/100,01);
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_2 ".$model." id:$id, Windspeed bit: ".substr($sensdata,32,8)." Dec: " . $windSpeed ;
                  $windguest = round((SD_WS09_bin2dec(substr($sensdata,40,8)) * 34)/100,01);
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_3 ".$model." id:$id, Windguest bit: ".substr($sensdata,40,8)." Dec: " . $windguest ;
                  $rain =  SD_WS09_bin2dec(substr($sensdata,52,12)) * 0.3;
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_4 ".$model." id:$id, Rain bit: ".substr($sensdata,52,12)." Dec: " . $rain ;
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_5 ".$model." id:$id, bat:$bat, temp=$temp, hum=$hum, winddir=$windDirection:$windDirectionText wS=$windSpeed, wG=$windguest, rain=$rain";
            } elsif(  $whid == "1011" ){ # B  DCF-77 Zeitmeldungen vom Sensor
                  my $hrs1 = substr($sensdata,16,8);
                  my $hrs;
                  my $mins; 
                  my $sec; 
                  my $mday;
                  my $month;
                  my $year;
                  $id = SD_WS09_bin2dec(substr($sensdata,4,8));
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_6 Zeitmeldung0: HRS1=$hrs1 id:$id" ;
                  $hrs = sprintf "%02d" , SD_WS09_BCD2bin(substr($sensdata,18,6) ) ; # Stunde
                  $mins = sprintf "%02d" , SD_WS09_BCD2bin(substr($sensdata,24,8)); # Minute
                  $sec = sprintf "%02d" ,SD_WS09_BCD2bin(substr($sensdata,32,8)); # Sekunde
                  #day month year
                  $year = SD_WS09_BCD2bin(substr($sensdata,40,8)); # Jahr
                  $month = sprintf "%02d" ,SD_WS09_BCD2bin(substr($sensdata,51,5)); # Monat
                  $mday = sprintf "%02d" ,SD_WS09_BCD2bin(substr($sensdata,56,8)); # Tag
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_7 Zeitmeldung1: id:$id, msg=$rawData length:".length($bitData) ;
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_8 Zeitmeldung2: id:$id, HH:mm:ss - ".$hrs.":".$mins.":".$sec ;
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_9 Zeitmeldung3: id:$id, dd.mm.yy - ".$mday.".".$month.".".$year ;
                  return $name;
            } elsif(  $whid == "0111" ){   # 7  UV/Solar Meldungen vom Sensor
                  # Fine Offset (Solar Data) message BYTE offsets (within receive buffer)
                  # Examples= FF 75 B0 55 00 97 8E 0E *CRC*OK*
                  # =FF 75 B0 55 00 8F BE 92 *CRC*OK*
                  # symbol FOrunio = 0 ; Fine Offset Runin byte = FF
                  # symbol FOsaddo = 1 ; Solar Pod address word
                  # symbol FOuvo = 3 ; UV data nybble ?
                  # symbol FOluxHo = 4 ; Lux High byte (full scale = 4,000,000?)
                  # symbol FOluxMo = 5 ; Lux Middle byte
                  # symbol FOluxLo = 6 ; Lux Low byte, Unit = 0.1 Lux (binary)
                  # symbol FOcksumo= 7 ; CRC checksum (CRC-8 shifting left)
                  $id = SD_WS09_bin2dec(substr($sensdata,4,8));
                  $FOuvo = SD_WS09_bin2dec(substr($sensdata,12,4));
                  $FOlux = SD_WS09_bin2dec(substr($sensdata,24,24))/10;
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_10 UV-Solar1: id:$id, UV:".$FOuvo." Lux:".$FOlux ;
            } else {
                Log3 $iohash, 4, "$name: SD_WS09_Parse_Ex Exit: msg=$rawData length:".length($sensdata) ;
                Log3 $iohash, 4, "$name: SD_WS09_WH10 Exit:  Model=$model " ;
    	          return undef;
            }
         }else{
            # es wird eine CTW600 angenommen 
            $syncpos= index($bitData,"11111110");  #7x1 1x0 preamble
            $wh = substr($bitData,0,8);
            if ( $wh == "11111110" && length($bitData) > $minL1 )
            {
    	            Log3 $iohash, 4, "$name: SD_WS09_Parse_11 CTW600 EXIT: msg=$bitData wh:$wh length:".length($bitData) ; 
                  $sensdata = substr($bitData,$syncpos+8);
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_12 CTW WH=$wh msg=$sensdata syncp=$syncpos length:".length($sensdata) ;
                  $model = "CTW600";
                  $whid = "0000";
                  my $nn1 = substr($sensdata,10,2);  # Keine Bedeutung
                  my $nn2 = substr($sensdata,62,4);  # Keine Bedeutung
                  $modelid = substr($sensdata,0,4);
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_13 Id: ".$modelid." NN1:$nn1 NN2:$nn2" ;
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_14 Id: ".$modelid." Bin-Sync=$sensdata syncp=$syncpos length:".length($sensdata) ;
                  $bat = SD_WS09_bin2dec((substr($sensdata,0,3))) ;
                  $id = SD_WS09_bin2dec(substr($sensdata,4,6));
                  $temp = (SD_WS09_bin2dec(substr($sensdata,12,10)) - 400)/10;
    	            $hum = SD_WS09_bin2dec(substr($sensdata,22,8));
                  $windDirection = SD_WS09_bin2dec(substr($sensdata,66,4));  
                  $windDirectionText = $winddir_name[$windDirection];
                  $windDirectionDegree = $windDirection * 360 / 16;
                  $windSpeed =  round(SD_WS09_bin2dec(substr($sensdata,30,16))/240,01);
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_15 ".$model." Windspeed bit: ".substr($sensdata,32,8)." Dec: " . $windSpeed ;
                  $windguest = round((SD_WS09_bin2dec(substr($sensdata,40,8)) * 34)/100,01);
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_16 ".$model." Windguest bit: ".substr($sensdata,40,8)." Dec: " . $windguest ;
                  $rain =  round(SD_WS09_bin2dec(substr($sensdata,46,16)) * 0.3,01);
                  Log3 $iohash, 4, "$name: SD_WS09_Parse_17 ".$model." Rain bit: ".substr($sensdata,46,16)." Dec: " . $rain ;           
            }else{
                	Log3 $iohash, 4, "$name: SD_WS09_Parse_18 CTW600 EXIT: msg=$bitData length:".length($bitData) ;
                  return undef;
            }
          }
        
       		
      Log3 $iohash, 4, "$name: SD_WS09_Parse_19 ".$model." id:$id :$sensdata ";
    
      if($hum > 100 || $hum < 0) {
            	Log3 $iohash, 4, "$name: SD_WS09_Parse HUM: hum=$hum msg=$rawData " ;
    			   return undef;
         } 
      if($temp > 60 || $temp < -40) {
            	Log3 $iohash, 4, "$name: SD_WS09_Parse TEMP: Temp=$temp msg=$rawData " ;
    			   return undef;
         } 
          
      my $longids = AttrVal($iohash->{NAME},'longids',0);
     	if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))
    	{
    	 $deviceCode=$model."_".$id;
     		Log3 $iohash,4, "$name: SD_WS09_Parse using longid: $longids model: $model";
    	} else {
    		$deviceCode = $model;
    	}
       
        my $def = $modules{SD_WS09}{defptr}{$iohash->{NAME} . "." . $deviceCode};
        $def = $modules{SD_WS09}{defptr}{$deviceCode} if(!$def);
    
        if(!$def) {
    		Log3 $iohash, 1, 'SD_WS09_Parse UNDEFINED sensor ' . $model . ' detected, code ' . $deviceCode;
    		return "UNDEFINED $deviceCode SD_WS09 $deviceCode";
        }
        
      my $hash = $def;
    	$name = $hash->{NAME};	    	
      Log3 $name, 4, "SD_WS09_Parse_20: $name ($rawData)";  
    
    	if (!defined(AttrVal($name,"event-min-interval",undef)))
    	{
    		my $minsecs = AttrVal($iohash->{NAME},'minsecs',0);
    		if($hash->{lastReceive} && (time() - $hash->{lastReceive} < $minsecs)) {
    			Log3 $hash, 4, "SD_WS09_Parse_End $deviceCode Dropped due to short time. minsecs=$minsecs";
    		  	return undef;
    		}
    	}
    
       my $windkorr = AttrVal($name,'windKorrektur',0);
        if ($windkorr != 0 )      
        {
          my $oldwinddir = $windDirection; 
          $windDirection = $windDirection + $windkorr; 
          $windDirectionText = $winddir_name[$windDirection];
          Log3 $hash, 4, "SD_WS09_Parse_WK ".$model." Faktor:$windkorr wD:$oldwinddir  Korrektur wD:$windDirection:$windDirectionText" ;
        }
         
       # "Unit_of_Wind:m/s,km/h,ft/s,bft,knot "
       # my %uowind_unit= ("m/s",'1',"km/h",'3.6',"ft/s",'3.28',"bft",'-1',"mph",'2.24',"knot",'1.94');
       # B  =  Wurzel aus ( 9  +  6 * V )  -  3
       # V = 17 Meter pro Sekunde ergibt:  B =  Wurzel aus( 9 + 6 * 17 )  -  3 
       # Das ergibt : 7,53   Beaufort
       
        $windstat[0]= " Ws:$windSpeed  Wg:$windguest m/s";
        Log3 $hash, 4, "SD_WS09_Wind $windstat[0] : Faktor:$wfaktor" ;
       
        $wfaktor = $uowind_unit{"km/h"};
        $windguest_kmh = round ($windguest * $wfaktor,01);
        $windSpeed_kmh = round ($windSpeed * $wfaktor,01);
        $windstat[1]= " Ws:$windSpeed_kmh  Wg:$windguest_kmh km/h";
        Log3 $hash, 4, "SD_WS09_Wind $windstat[1] : Faktor:$wfaktor" ;
        
        $wfaktor = $uowind_unit{"ft/s"};
        $windguest_fts = round ($windguest * $wfaktor,01);
        $windSpeed_fts = round ($windSpeed * $wfaktor,01);
        $windstat[2]= " Ws:$windSpeed_fts  Wg:$windguest_fts ft/s";
        Log3 $hash, 4, "SD_WS09_Wind $windstat[2] : Faktor:$wfaktor" ;
        
        $wfaktor = $uowind_unit{"mph"};
        $windguest_mph = round ($windguest * $wfaktor,01);
        $windSpeed_mph = round ($windSpeed * $wfaktor,01);
        $windstat[3]= " Ws:$windSpeed_mph  Wg:$windguest_mph mph";
        Log3 $hash, 4, "SD_WS09_Wind $windstat[3] : Faktor:$wfaktor" ;
        
        $wfaktor = $uowind_unit{"knot"};
        $windguest_kn = round ($windguest * $wfaktor,01);
        $windSpeed_kn = round ($windSpeed * $wfaktor,01);
        $windstat[4]= " Ws:$windSpeed_kn  Wg:$windguest_kn kn" ;
        Log3 $hash, 4, "SD_WS09_Wind $windstat[4] : Faktor:$wfaktor" ;
        
        $windguest_bft = round(sqrt( 9 + (6 * $windguest)) - 3,0) ;
        $windSpeed_bft = round(sqrt( 9 + (6 * $windSpeed)) - 3,0) ;
        $windstat[5]= " Ws:$windSpeed_bft  Wg:$windguest_bft bft";
        Log3 $hash, 4, "SD_WS09_Wind $windstat[5] " ;
        
        # Resets des rain counters abfangen:
        # wenn der aktuelle Wert < letzter Wert ist, dann fand ein reset statt   
        # die Differenz "letzer Wert - aktueller Wert" wird dann als offset für zukünftige Ausgaben zu rain addiert
        # offset wird auch im Reading ".rain_offset" gespeichert
         my $last_rain = ReadingsVal($name, "rain", 0);
         my $rain_offset = ReadingsVal($name, ".rainOffset", 0);
         $rain_offset += $last_rain if($rain < $last_rain);
         my $rain_total = $rain + $rain_offset; 
         Log3 $hash, 4, "SD_WS09_Parse_rain_offset ".$model." rain:$rain raintotal:$rain_total rainoffset:$rain_offset " ;
           
         #  windDirectionAverage berechnen  
         my $average = SD_WS09_WindDirAverage($hash, $windSpeed, $windDirectionDegree);
      
         $hash->{lastReceive} = time();
    	   $def->{lastMSG} = $rawData;
         readingsBeginUpdate($hash);
      
        if($whid ne "0111") 
         {
          #my $uowind = AttrVal($hash->{NAME},'Unit_of_Wind',0) ; 
          my $uowind = AttrVal($name,'Unit_of_Wind',0) ;
          my $windex = $uowind_index{$uowind};
          if (!defined $windex) {
            $windex = 0;
          }
          
          $state = "T: $temp ". ($hum>0 ? " H: $hum ":" "). $windstat[$windex]." Wd: $windDirectionText "." R: $rain";
          readingsBulkUpdate($hash, "id", $id) if ($id ne "");
          readingsBulkUpdate($hash, "state", $state);
          readingsBulkUpdate($hash, "temperature", $temp)  if ($temp ne"");
          readingsBulkUpdate($hash, "humidity", $hum)  if ($hum ne "" && $hum != 0 );
          readingsBulkUpdate($hash, "battery", $bat)   if ($bat ne "");
          #zusätzlich Daten für Wetterstation
          readingsBulkUpdate($hash, "rain", $rain );
          readingsBulkUpdate($hash, ".rainOffset", $rain_offset );	# Zwischenspeicher für den offset
          readingsBulkUpdate($hash, "rain_total", $rain_total );	# monoton steigender Wert von rain
          readingsBulkUpdate($hash, "windGust", $windguest );
          readingsBulkUpdate($hash, "windSpeed", $windSpeed );
          readingsBulkUpdate($hash, "windGust_kmh", $windguest_kmh );
          readingsBulkUpdate($hash, "windSpeed_kmh", $windSpeed_kmh );
          readingsBulkUpdate($hash, "windGust_fts", $windguest_fts );
          readingsBulkUpdate($hash, "windSpeed_fts", $windSpeed_fts );
          readingsBulkUpdate($hash, "windGust_mph", $windguest_mph );
          readingsBulkUpdate($hash, "windSpeed_mph", $windSpeed_mph );
          readingsBulkUpdate($hash, "windGust_kn", $windguest_kn );
          readingsBulkUpdate($hash, "windSpeed_kn", $windSpeed_kn );
          readingsBulkUpdate($hash, "windDirectionAverage", $average );
          readingsBulkUpdate($hash, "windDirection", $windDirection );
          readingsBulkUpdate($hash, "windDirectionDegree", $windDirectionDegree);     
          readingsBulkUpdate($hash, "windDirectionText", $windDirectionText );
        }
         if(($whid eq "0111") &&  ($model eq "WH1080"))
         { 
          $state = "UV: $FOuvo Lux: $FOlux ";
          readingsBulkUpdate($hash, "id", $id) if ($id ne "");
          readingsBulkUpdate($hash, "state", $state);
          #zusätzliche Daten UV + Lux
          readingsBulkUpdate($hash, "UV", $FOuvo );
          readingsBulkUpdate($hash, "Lux", $FOlux );
        }
        readingsEndUpdate($hash, 1); # Notify is done by Dispatch
    
    	return $name;
    }
    
    sub SD_WS09_Attr(@)
    {
      my @a = @_;
      # Make possible to use the same code for different logical devices when they
      # are received through different physical devices.
      return  if($a[0] ne "set" || $a[2] ne "IODev");
      my $hash = $defs{$a[1]};
      my $iohash = $defs{$a[3]};
      my $cde = $hash->{CODE};
      delete($modules{SD_WS09}{defptr}{$cde});
      $modules{SD_WS09}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
      return undef;
    }

    sub SD_WS09_WindDirAverage($$$){
    ###############################################################################
    #  übernommen von SabineT https://forum.fhem.de/index.php/topic,75225.msg669950.html#msg669950
    #  WindDirAverage
    #       z.B.: myWindDirAverage('WH1080','windSpeed','windDirectionDegree',900,0.75,0.5)
    #       avtime ist optional, default ist 600 s    Zeitspanne, die berücksichtig werden soll
    #       decay ist optional, default ist 1         Parameter, um ältere Werte geringer zu gewichten
    #       minspeed ist optional, default ist 0 m/s
    #
    #  Als Ergebnis wird die Windrichtung zurück geliefert, die aus dem aktuellen und
    #  vergangenen Werten über eine Art exponentiellen Mittelwert berechnet werden.
    #  Dabei wird zusätzlich die jeweilige Windgeschwindigkeit mit berücksichtigt (höhere Geschwindigkeit
    #  bedeutet höhere Gewichtung).
    #
    #  decay: 1 -> alle Werte werden gleich gewichtet
    #         0 -> nur der aktuelle Wert wird verwendet.
    #         in der Praxis wird man Werte so um 0.75 nehmen
    #
    #  minspeed: da bei sehr geringer Windgeschwindigkeit die Windrichtung üblicherweise nicht
    #         eindeutig ist, kann mit minspeed ein Schwellwert angegeben werden
    #         Ist die (gewichtetete) mittlere Geschwindigkeit < minspeed wird undef zurück geliefert
    #
    ###############################################################################

     my ($hash, $ws, $wd) = @_;
     my $name = $hash->{NAME};
     Log3 $hash, 4, "SD_WS09_WindDirAverage --- OK ----" ;
     my $rc = eval
     {
      require Math::Trig;
      Math::Trig->import();
      1;
     };

     if($rc) # test ob  Math::Trig geladen wurde
     {
         Log3 $hash, 4, "SD_WS09_WindDirAverage Math::Trig:OK" ;
     }else
     {
         Log3 $hash, 1, "SD_WS09_WindDirAverage Math::Trig:fehlt : cpan install Math::Trig" ;
         return "";
     }
       
       my $avtime = AttrVal($name,'WindDirAverageTime',0);
       my $decay = AttrVal($name,'WindDirAverageDecay',0);
       my $minspeed = AttrVal($name,'WindDirAverageMinSpeed',0);
       
       # default Werte für die optionalen Parameter, falls nicht beim Aufruf mit angegeben
       $avtime = 600 if (!(defined $avtime) || $avtime == 0 );
       $decay = 1 if (!(defined $decay));
       $decay = 1 if ($decay > 1); # darf nicht >1 sein
       $decay = 0 if ($decay < 0); # darf nicht <0 sein
       $minspeed = 0 if (!(defined $minspeed));
       
       $wd = deg2rad($wd);
       my $ctime = time;
       my $time = FmtDateTime($ctime);
       my @new = ($ws,$wd,$time);

       Log3 $hash, 4,"SD_WS09_WindDirAverage_01 $name :Speed=".$ws." DirR=".round($wd,2)." Time=".$time;
       Log3 $hash, 4,"SD_WS09_WindDirAverage_02 $name :avtime=".$avtime." decay=".$decay." minspeed=".$minspeed;

       my $num;
       my $arr;
      
      #-- initialize if requested
      if( ($avtime eq "-1") ){
        $hash->{helper}{history}=undef;
      }
      
      #-- test for existence
      if(!$hash->{helper}{history}){
       Log3 $hash, 4,"SD_WS09_WindDirAverage_03 $name :ARRAY CREATED";
       push(@{$hash->{helper}{history}},\@new);
       $num = 1;
       $arr=\@{$hash->{helper}{history}};
      } else {
       $num = int(@{$hash->{helper}{history}});
       $arr=\@{$hash->{helper}{history}};
       my $stime = time_str2num($arr->[0][2]);       # Zeitpunkt des ältesten Eintrags
       my $ltime = time_str2num($arr->[$num-1][2]);  # Zeitpunkt des letzten Eintrags
       Log3 $hash,4,"SD_WS09_WindDirAverage_04 $name :Speed=".$ws." Dir=".round($wd,2)." Time=".$time." minspeed=".$minspeed." ctime=".$ctime." ltime=".$ltime." stime=".$stime." num=".$num;

       if((($ctime - $ltime) > 10) || ($num == 0)) {
        if(($num < 25) && (($ctime-$stime) < $avtime)){
         Log3 $hash,4,"SD_WS09_WindDirAverage_05 $name :Speed=".$ws." Dir=".round($wd,2)." Time=".$time." minspeed=".$minspeed." num=".$num;
         push(@{$hash->{helper}{history}},\@new);
        } else {
          shift(@{$hash->{helper}{history}});
          push(@{$hash->{helper}{history}},\@new);
          Log3 $hash,4,"SD_WS09_WindDirAverage_06 $name :Speed=".$ws." Dir=".round($wd,2)." Time=".$time." minspeed=".$minspeed." num=".$num;
         }
       } else {
          return undef;
       }
     }
  #-- output and average
  my ($anz, $sanz) = 0;
  $num = int(@{$hash->{helper}{history}});
  my ($sumSin, $sumCos, $sumSpeed, $age, $maxage, $weight) = 0;
  for(my $i=0; $i<$num; $i++){
    ($ws, $wd, $time) = @{ $arr->[$i] };
    $age = $ctime - time_str2num($time);
    if (($time eq "") || ($age > $avtime)) {
      #-- zu alte Einträge entfernen
      Log3 $hash,4,"SD_WS09_WindDirAverage_07 $name i=".$i." Speed=".round($ws,2)." Dir=".round($wd,2)." Time=".substr($time,11)." ctime=".$ctime." akt.=".time_str2num($time);
      shift(@{$hash->{helper}{history}});
      $i--;
      $num--;
    } else {
      #-- Werte aufsummieren, Windrichtung gewichtet über Geschwindigkeit und decay/"alter"
      $weight = $decay ** ($age / $avtime);
      #-- für die Mittelwertsbildung der Geschwindigkeit wird nur ein 10tel von avtime genommen
      if ($age < ($avtime / 10)) {
        $sumSpeed += $ws * $weight if ($age < ($avtime / 10));
        $sanz++;
      }
      $sumSin += sin($wd) * $ws * $weight;
      $sumCos += cos($wd) * $ws * $weight;
      $anz++;
      Log3 $hash,4,"SD_WS09_WindDirAverage_08 $name i=".$i." Speed=".round($ws,2)." Dir=".round($wd,2)." Time=".substr($time,11)." vec=".round($sumSin,2)."/".round($sumCos,2)." age=".$age." ".round($weight,2);
    }
  }
  my $average = int((rad2deg(atan2($sumSin, $sumCos)) + 360) % 360);
  Log3 $hash,4,"SD_WS09_WindDirAverage_09 $name Mittelwert über $anz Werte ist $average, avspeed=".round($sumSpeed/$num,1) if ($num > 0);
  #-- undef zurückliefern, wenn die durchschnittliche Geschwindigkeit zu gering oder gar keine Werte verfügbar
  return undef if (($anz == 0) || ($sanz == 0));
  return undef if (($sumSpeed / $sanz) < $minspeed);
  Log3 $hash,4,"SD_WS09_WindDirAverage_END $name Mittelwert=$average";
  return $average;
}
    
    sub SD_WS09_bin2dec($)
    {
      my $h = shift;
      my $int = unpack("N", pack("B32",substr("0" x 32 . $h, -32))); 
      return sprintf("%d", $int); 
    }
    
    sub SD_WS09_binflip($)
    {
      my $h = shift;
      my $hlen = length($h);
      my $i = 0;
      my $flip = "";
      
      for ($i=$hlen-1; $i >= 0; $i--) {
        $flip = $flip.substr($h,$i,1);
      }
      return $flip;
    }
    
    sub SD_WS09_BCD2bin($) {
      my $binary = shift;
      my $int = unpack("N", pack("B32", substr("0" x 32 . $binary, -32)));
      my $BCD = sprintf("%x", $int );
      return $BCD;
    }
    
    sub SD_WS09_SHIFT($){
         my $rawData = shift;
         my $hlen = length($rawData);
         my $blen = $hlen * 4;
         my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
    	   my $bitData2 = '1'.unpack("B$blen", pack("H$hlen", $rawData));
         my $bitData20 = substr($bitData2,0,length($bitData2)-1);
          $blen = length($bitData20);
          $hlen = $blen / 4;
          $rawData = uc(unpack("H$hlen", pack("B$blen", $bitData20)));
          $bitData = $bitData20;
          Log3 "SD_WS09_SHIFT", 4, "SD_WS09_SHIFT_0  raw: $rawData length:".length($bitData) ;
          Log3 "SD_WS09_SHIFT", 4, "SD_WS09_SHIFT_1  bitdata: $bitData" ;
        return $rawData;  
    }
    
    sub SD_WS09_CRCCHECK($) {
       my $rawData = shift;
       my $datacheck1 = pack( 'H*', substr($rawData,2,length($rawData)-2) );
       my $crcmein1 = Digest::CRC->new(width => 8, poly => 0x31);
       my $rr3 = $crcmein1->add($datacheck1)->hexdigest;
       $rr3 = sprintf("%d", hex($rr3));
       Log3 "SD_WS09_CRCCHECK", 4, "SD_WS09_CRCCHECK :  raw:$rawData CRC=$rr3 " ;
       return $rr3 ;
    }
    
    1;
    
    
=pod
=item summary    Supports weather sensors (WH1080/3080/CTW-600) protocol 9 from SIGNALduino
=item summary_DE Unterstuetzt Wettersensoren (WH1080/3080/CTW-600) mit Protokol 9 vom SIGNALduino
=begin html

<a name="SD_WS09"></a>
<h3>Wether Sensors protocol #9</h3>
<ul>
  The SD_WS09 module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  Requires Perl-Modul Digest::CRC. <br>
   <br> 
  cpan install Digest::CRC    or   sudo apt-get install libdigest-crc-perl <br>
   <br>
  <br>
  <b>Known models:</b>
  <ul>
    <li>WS-0101              --> Model: WH1080</li>
    <li>TFA 30.3189 / WH1080 --> Model: WH1080</li>
    <li>1073 (WS1080)        --> Model: WH1080</li>
     <li>WH3080               --> Model: WH1080</li>
    <li>CTW600               --> Model: CTW600 (??) </li> 
  </ul>
  <br>
  New received device are add in fhem with autocreate.
  <br><br>

  <a name="SD_WS09_Define"></a>
  <b>Define</b> 
  <ul>The received devices created automatically.<br>
  The ID of the defice is the model or, if the longid attribute is specified, it is a combination of model and some random generated bits at powering the sensor.<br>
  If you want to use more sensors, you can use the longid option to differentiate them.
  </ul>
  <br>
  <a name="SD_WS09 Events"></a>
  <b>Generated readings:</b>
  <br>Some devices may not support all readings, so they will not be presented<br>
  <ul>
   <li>State (T: H: Ws: Wg: Wd: R: )  temperature, humidity, windSpeed, windGuest, windDirection, Rain</li>
     <li>Temperature (&deg;C)</li>
     <li>Humidity: (The humidity (1-100 if available)</li>
     <li>Battery: (low or ok)</li>
     <li>ID: (The ID-Number (number if)</li>
     <li>windSpeed/windGuest (Unit_of_Wind)) and windDirection (N-O-S-W)</li>
     <li>Rain (mm)</li>
     <li>windDirectionAverage<br>
     As a result, the wind direction is returned, which are calculated from the current and past values
     via a kind of exponential mean value. 
     The respective wind speed is additionally taken into account (higher speed means higher weighting)</li>
     <b>WH3080:</b>
     <li>UV Index</li>
     <li>Lux</li>
    
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li>Model: WH1080,CTW600
    </li>
    <li>windKorrektur: -3,-2,-1,0,1,2,3   
    </li>
    <li>Unit_of_Wind<br>
    Unit of windSpeed and windGuest. State-Format: Value + Unit.
       <br>m/s,km/h,ft/s,mph,bft,knot 
    </li><br>
    
    <li>WindDirAverageTime<br>
    default is 600s, time span to be considered for the calculation
    </li><br>
    
    <li>WindDirAverageMinSpeed<br>
    since the wind direction is usually not clear at very low wind speeds,
    minspeed can be used to specify a threshold value. 
    <br>The (weighted) mean velocity < minspeed is returned undef
    </li><br>
    
    <li>WindDirAverageDecay<br>
       1 -> all values ​​are weighted equally  <br>
       0 -> only the current value is used.   <br>
       in practice, you will take values ​​around 0.75 
    </li><br>
    
    <li>WS09_CRCAUS (set in Signalduino-Modul 00_SIGNALduino.pm)
       <br>0: CRC-Check WH1080 CRC-Summe = 0  on, default   
       <br>2: CRC-Summe = 49 (x031) WH1080, set OK
    </li>
   </ul> <br>
  <a name="SD_WS09_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS09_Parse"></a>
  <b>Parse</b> <ul>N/A</ul><br>

</ul>

=end html
=begin html_DE

<a name="SD_WS09"></a>
<h3>SD_WS09</h3>
<ul>
  Das SD_WS09 Module verarbeitet von einem IO Gerät (CUL, CUN, SIGNALDuino, etc.) empfangene Nachrichten von Temperatur-Sensoren.<br>
  <br>
  Perl-Modul Digest::CRC erforderlich. <br>
   <br>
    cpan install Digest::CRC oder auch             <br>
    sudo apt-get install libdigest-crc-perl         <br>
   <br>
  <br>
  <b>Unterstütze Modelle:</b>
  <ul>
    <li>WS-0101              --> Model: WH1080</li>
    <li>TFA 30.3189 / WH1080 --> Model: WH1080</li>
    <li>1073 (WS1080)        --> Model: WH1080</li>
    <li>WH3080               --> Model: WH1080</li>
    <li>CTW600               --> Model: CTW600</li>    
  </ul>
  <br>
  Neu empfangene Sensoren werden in FHEM per autocreate angelegt.
  <br><br>

  <a name="SD_WS09_Define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
  Die ID der angelegten Sensoren wird nach jedem Batteriewechsel ge&aumlndert, welche der Sensor beim Einschalten zuf&aumlllig vergibt.<br>
  CRC Checksumme wird zur Zeit noch nicht überpr&uumlft, deshalb werden Sensoren bei denen die Luftfeuchte < 0 oder > 100 ist, nicht angelegt.<br>
  </ul>
  <br>
  <a name="SD_WS09 Events"></a>
  <b>Generierte Readings:</b>
  <ul>
     <li>State (T: H: Ws: Wg: Wd: R: )  temperature, humidity, windSpeed, windGuest, Einheit, windDirection, Rain</li>
     <li>Temperature (&deg;C)</li>
     <li>Humidity: (The humidity (1-100 if available)</li>
     <li>Battery: (low or ok)</li>
     <li>ID: (The ID-Number (number if)</li>
     <li>windSpeed/windgust (Einheit siehe Unit_of_Wind)  and windDirection (N-O-S-W)</li>
     <li>Rain (mm)</li>
     <li>windDirectionAverage
      Als Ergebnis wird die Windrichtung zurück geliefert, die aus dem aktuellen und
    vergangenen Werten über eine Art exponentiellen Mittelwert berechnet werden.
    Dabei wird zusätzlich die jeweilige Windgeschwindigkeit mit berücksichtigt (höhere Geschwindigkeit
    bedeutet höhere Gewichtung).</li>
     <b>WH3080:</b>
     <li>UV Index</li>
     <li>Lux</li>
     
  </ul>
  <br>
  <b>Attribute</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li>Model<br>
        WH1080, CTW600
    </li><br>
    <li>windKorrektur<br>
    Korrigiert die Nord-Ausrichtung des Windrichtungsmessers, wenn dieser nicht richtig nach Norden ausgerichtet ist. 
      -3,-2,-1,0,1,2,3    
    </li><br>
    <li>Unit_of_Wind<br>
    Hiermit wird der Einheit eingestellt und im State die entsprechenden Werte + Einheit angezeigt.
       <br>m/s,km/h,ft/s,mph,bft,knot 
    </li><br>
    
    <li>WindDirAverageTime<br>
     default ist 600s, Zeitspanne die für die Berechung berücksichtig werden soll
    </li><br>
    
    <li>WindDirAverageMinSpeed<br>
    da bei sehr geringer Windgeschwindigkeit die Windrichtung üblicherweise nicht
    eindeutig ist, kann mit minspeed ein Schwellwert angegeben werden
    Ist die (gewichtetete) mittlere Geschwindigkeit < minspeed wird undef zurück geliefert
    </li><br>
    
    <li>WindDirAverageDecay<br>
    1 -> alle Werte werden gleich gewichtet <br>
    0 -> nur der aktuelle Wert wird verwendet.<br>
    in der Praxis wird man Werte so um 0.75 nehmen
    </li><br>
   
    <li>WS09_CRCAUS<br>
    Wird im Signalduino-Modul (00_SIGNALduino.pm) gesetzt 
       <br>0: CRC-Prüfung bei WH1080 CRC-Summe = 0  
       <br>2: CRC-Summe = 49 (x031) bei WH1080 wird als OK verarbeitet
    </li><br>
    
   </ul>

  <a name="SD_WS09_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS09_Parse"></a>
  <b>Parse</b> <ul>N/A</ul><br>

</ul>

=end html_DE
=cut

