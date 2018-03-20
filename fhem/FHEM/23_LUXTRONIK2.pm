###############################################################
# $Id$Date: $
#
#  23_LUXTRONIK2.pm 
#
#  (c) 2012-2017 Torsten Poitzsch
#  (c) 2012-2013 Jan-Hinrich Fessel (oskar at fessel . org)
#
#  Copyright notice
#
#  The module reads and writes parameters of the heat pump controller 
#  Luxtronik 2.0 used in Alpha Innotec and Siemens Novelan (WPR NET) heat pumps.
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

##############################################
package main;

my $missingModul = "";

use strict;
use warnings;
use Blocking;
use IO::Socket; 
use Time::HiRes qw/ time /;
eval "use Net::Telnet;1" or $missingModul .= "Net::Telnet ";

sub LUXTRONIK2_doStatisticThermalPower ($$$$$$$$$);
sub LUXTRONIK2_doStatisticMinMax ($$$);
sub LUXTRONIK2_doStatisticMinMaxSingle ($$$$);
sub LUXTRONIK2_storeReadings ($$$$$$);
sub LUXTRONIK2_doStatisticDelta ($$$$$) ;
sub LUXTRONIK2_doStatisticDeltaSingle ($$$$$$$);
sub LUXTRONIK2_readData ($);


#List of firmware versions that are known to be compatible with this modul
my $testedFirmware = "#V1.51#V1.54C#V1.60#V1.61#V1.64#V1.69#V1.70#V1.73#V1.77#V1.80#V1.81#";
my $compatibleFirmware = "#V1.51#V1.54C#V1.60#V1.61#V1.64#V1.69#V1.70#V1.73#V1.77#V1.80#V1.81#";

sub ##########################################
LUXTRONIK2_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/LUXTRONIK2_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $instName, $loglevel, "LUXTRONIK2 $instName: $sub.$xline " . $text;
}


sub ########################################
LUXTRONIK2_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "LUXTRONIK2_Define";
  $hash->{UndefFn}  = "LUXTRONIK2_Undefine";
  $hash->{GetFn}    = "LUXTRONIK2_Get";
  $hash->{SetFn}    = "LUXTRONIK2_Set";
  $hash->{AttrFn}   = "LUXTRONIK2_Attr";
  $hash->{AttrList} = "disable:0,1 ".
                 "allowSetParameter:0,1 ".
                 "autoSynchClock:slider,10,5,300 ".
                 "boilerVolumn ".
                 "compressor2ElectricalPowerWatt ".
                 "doStatistics:0,1,2 ".
                 "heatPumpElectricalPowerFactor ".
                 "heatPumpElectricalPowerWatt ".
                 "heatRodElectricalPowerWatt ".
                 "ignoreFirmwareCheck:0,1 ".
                 "statusHTML ".
                 "userHeatpumpParameters ".
                 "userHeatpumpValues ".
                $readingFnAttributes;
}

sub ########################################
LUXTRONIK2_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> LUXTRONIK2 <ip-address> [poll-interval]" 
         if(@a <3 || @a >4);

  my $name = $a[0];
  my $host = $a[2];

  my $interval = 5*60;
  $interval = $a[3] if(int(@a) == 4);
  $interval = 10 if( $interval < 10 );

  $hash->{NAME} = $name;

  $hash->{STATE} = "Initializing";
  $hash->{HOST} = $host;
  if ( $host =~ /(.*):(.*)/ ) {
      $hash->{HOST} = $1;
      $hash->{PORT} = $2;
      $hash->{fhem}{portDefined} = 1;
  }
  else {
      $hash->{HOST} = $host;
      $hash->{PORT} = 8888;
      $hash->{fhem}{portDefined} = 0;
  }
  $hash->{INTERVAL} = $interval;
  $hash->{NOTIFYDEV} = "global";

  RemoveInternalTimer($hash);
  #Get first data after 10 seconds
  InternalTimer(gettimeofday() + 10, "LUXTRONIK2_GetUpdate", $hash, 0);

  #Reset temporary values
  $hash->{fhem}{durationFetchReadingsMin} = 0;
  $hash->{fhem}{durationFetchReadingsMax} = 0;
  $hash->{fhem}{alertFirmware} = 0;
  $hash->{fhem}{statBoilerHeatUpStep} = 0;
  $hash->{fhem}{statBoilerCoolDownStep} = 0;
  $hash->{fhem}{defrost}{mode}="none";
  $hash->{fhem}{hotWaterLastRun} = time();
  $hash->{fhem}{heatingPumpLastStop} = time();
  $hash->{fhem}{heatingPumpLastRun} = time();
 
  $hash->{fhem}{modulVersion} = '$Date$';
       
  return undef;
}

sub ########################################
LUXTRONIK2_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
}

sub ########################################
LUXTRONIK2_Attr(@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
     # $cmd can be "del" or "set"
   # $name is device name
   # aName and aVal are Attribute name and value
   if ($cmd eq "set") {
      if ($aName eq "1allowSetParameter") {
         eval { qr/$aVal/ };
         if ($@) {
            LUXTRONIK2_Log $name, 3, "Invalid allowSetParameter in attr $name $aName $aVal: $@";
            return "Invalid allowSetParameter $aVal";
         }
      }
   }
   
   return undef;
}

sub ########################################
LUXTRONIK2_Set($$@)
{
  my ($hash, $name, $cmd, $val) = @_;
  my $resultStr = "";
  
   if($cmd eq 'statusRequest') {
      $hash->{LOCAL} = 1;
      Log3 $name, 3, "set $name $cmd";
      LUXTRONIK2_GetUpdate($hash);
      $hash->{LOCAL} = 0;
      return undef;
   }
   elsif ($cmd eq 'resetStatistics') {
      Log3 $name, 3, "set $name $cmd $val";
      if ( $val eq "statBoilerGradientCoolDownMin" 
            && exists($hash->{READINGS}{statBoilerGradientCoolDownMin})) {
         delete $hash->{READINGS}{statBoilerGradientCoolDownMin};
         $resultStr .= " statBoilerGradientCoolDownMin";
      }
      elsif ($val =~ /all|statAmbientTemp\.\.\.|statElectricity\.\.\.|statHours\.\.\.|statHeatQ\.\.\./) {
         my $regExp;
         if ($val eq "all") { $regExp = "stat"; } 
         else { $regExp = substr $val, 0, -3; } 
         foreach (sort keys %{ $hash->{READINGS} }) {
            if ($_ =~ /^\.?$regExp/ && $_ ne "state") {
               delete $hash->{READINGS}{$_};
               $resultStr .= " " . $_;
            }
         }
      }
      if ( $resultStr eq "" ) {
         $resultStr = "$name: No statistics to reset";
      } else {
         $resultStr = "$name: Statistic value(s) deleted:" . $resultStr;
         WriteStatefile();
      }
      # LUXTRONIK2_Log $hash, 3, $resultStr;
      return $resultStr;
   }
   
   elsif($cmd eq 'INTERVAL' && int(@_)==4 ) {
      Log3 $name, 3, "set $name $cmd $val";
      $val = 10 if( $val < 10 );
      $hash->{INTERVAL}=$val;
      return "Polling interval set to $val seconds.";
   }
   
   elsif($cmd eq 'activeTariff' && int(@_)==4 ) {
      $val = 0 if( $val < 1 || $val > 9 );
      readingsSingleUpdate($hash,"activeTariff",$val, 1);
      $hash->{LOCAL} = 1;
      LUXTRONIK2_GetUpdate($hash);
      $hash->{LOCAL} = 0;
      Log3 $name, 3, "set $name $cmd $val";
      return undef;
   }

  #Check Firmware and Set-Parameter-lock 
  if ( $cmd =~ /^(synchronizeClockHeatPump|hotWaterTemperatureTarget|opModeHotWater)$/i ) 
   {
    my $firmware = ReadingsVal($name,"firmware","");
    my $firmwareCheck = LUXTRONIK2_checkFirmware($firmware);
     # stop in case of incompatible firmware
    if ($firmwareCheck eq "fwNotCompatible") {
      LUXTRONIK2_Log $name, 3, " Error: Host firmware '$firmware' not compatible for parameter setting.";
       return "Firmware '$firmware' not compatible for parameter setting. ";
     # stop in case of untested firmware and firmware check enabled
    } elsif (AttrVal($name, "ignoreFirmwareCheck", 0)!= 1 &&
            $firmwareCheck eq "fwNotTested") {
      LUXTRONIK2_Log $name, 3, " Error: Host firmware '$firmware' not tested for parameter setting. To test set attribute 'ignoreFirmwareCheck' to 1";
       return "Firmware '$firmware' not compatible for parameter setting. To test set attribute 'ignoreFirmwareCheck' to 1.";
     # stop in case setting of parameters is not enabled
    } elsif ( AttrVal($name, "allowSetParameter", 0) != 1) {
      LUXTRONIK2_Log $name, 3, " Error: Setting of parameters not allowed. Please set attribut 'allowSetParameter' to 1";
       return "Setting of parameters not allowed. To unlock, please set attribut 'allowSetParameter' to 1.";
     }
   }
  
   if ($cmd eq 'synchronizeClockHeatPump') {
      $hash->{LOCAL} = 1;
      $resultStr = LUXTRONIK2_synchronizeClock($hash);
      $hash->{LOCAL} = 0;
      LUXTRONIK2_Log $name, 3, $resultStr;
      return $resultStr;
      
   } 
   elsif ($cmd eq 'boostHotWater' && int(@_)<=4) {
      Log3 $name, 3, "set $name $cmd" unless $val;
      Log3 $name, 3, "set $name $cmd $val"  if $val;
      return LUXTRONIK2_boostHotWater_Start( $hash, $val );
   } 
   elsif(int(@_)==4 &&
         ($cmd eq 'hotWaterTemperatureTarget'
            || $cmd eq 'opModeHotWater'
            || $cmd eq 'returnTemperatureHyst'
            || $cmd eq 'returnTemperatureSetBack'
            || $cmd eq 'heatingCurveEndPoint'
            || $cmd eq 'heatingCurveOffset'
            || $cmd eq 'heatSourceDefrostAirEnd'
            || $cmd eq 'heatSourceDefrostAirThreshold')) {

      Log3 $name, 3, "set $name $cmd $val";
      $hash->{LOCAL} = 1;
      $resultStr = LUXTRONIK2_SetParameter ($hash, $cmd, $val);
      $hash->{LOCAL} = 0;
      return $resultStr;
   }
   elsif( int(@_)==4 && $cmd eq 'hotWaterCircPumpDeaerate' ) { # Einstellung->Entlüftung
      Log3 $name, 3, "set $name $cmd $val";
      return "$name Error: Wrong parameter given for opModeHotWater, use Automatik,Party,Off"
         if $val !~ /on|off/;
      $hash->{LOCAL} = 1;
      $resultStr = LUXTRONIK2_SetParameter ($hash, $cmd, $val);
      if ($val eq "on" ) {    $resultStr .= LUXTRONIK2_SetParameter ($hash, "runDeaerate", 1);    } 
      else {   $resultStr .= LUXTRONIK2_SetParameter ($hash, "runDeaerate", 0);   } # only send if no Deaerate checkbox is selected at all.
      $hash->{LOCAL} = 0;
      return $resultStr;
   }

  my $list = "statusRequest:noArg"
          ." activeTariff:0,1,2,3,4,5,6,7,8,9"
          ." boostHotWater"
          ." heatingCurveEndPoint"
          ." heatingCurveOffset"
          ." heatSourceDefrostAirEnd"
          ." heatSourceDefrostAirThreshold"
          ." hotWaterCircPumpDeaerate:on,off"
          ." hotWaterTemperatureTarget "
          ." resetStatistics:all,statBoilerGradientCoolDownMin,statAmbientTemp...,statElectricity...,statHours...,statHeatQ..."
          ." returnTemperatureHyst "
          ." returnTemperatureSetBack "
          ." opModeHotWater:Auto,Party,Off"
          ." synchronizeClockHeatPump:noArg"
          ." INTERVAL ";
          
  return "Unknown argument $cmd, choose one of $list";
}

sub ########################################
LUXTRONIK2_Get($$@)
{
  my ($hash, $name, $cmd, @val ) = @_;
  my $resultStr = "";
  my @nameOfValue = qw( ? ? ? ? ? ? ? ? ? ? Temperatur_TVL Temperatur_TRL Sollwert_TRL_HZ Temperatur_TRL_ext Temperatur_THG Temperatur_TA Mitteltemperatur Temperatur_TBW Einst_BWS_akt Temperatur_TWE Temperatur_TWA Temperatur_TFB1 Sollwert_TVL_MK1 Temperatur_RFV Temperatur_TFB2 Sollwert_TVL_MK2 Temperatur_TSK Temperatur_TSS Temperatur_TEE ASDin BWTin EVUin HDin MOTin NDin PEXin SWTin AVout BUPout HUPout MA1out MZ1out VENout VBOout VD1out VD2out ZIPout ZUPout ZW1out ZW2SSTout ZW3SSTout FP2out SLPout SUPout MZ2out MA2out Zaehler_BetrZeitVD1 Zaehler_BetrZeitImpVD1 Zaehler_BetrZeitVD2 Zaehler_BetrZeitImpVD2 Zaehler_BetrZeitZWE1 Zaehler_BetrZeitZWE2 Zaehler_BetrZeitZWE3 Zaehler_BetrZeitWP Zaehler_BetrZeitHz Zaehler_BetrZeitBW Zaehler_BetrZeitKue Time_WPein_akt Time_ZWE1_akt Time_ZWE2_akt Timer_EinschVerz Time_SSPAUS_akt Time_SSPEIN_akt Time_VDStd_akt Time_HRM_akt Time_HRW_akt Time_LGS_akt Time_SBW_akt Code_WP_akt BIV_Stufe_akt WP_BZ_akt SoftStand1 SoftStand2 SoftStand3 SoftStand4 SoftStand5 SoftStand6 SoftStand7 SoftStand8 SoftStand9 SoftStand10 AdresseIP_akt SubNetMask_akt Add_Broadcast Add_StdGateway ERROR_Time0 ERROR_Time1 ERROR_Time2 ERROR_Time3 ERROR_Time4 ERROR_Nr0 ERROR_Nr1 ERROR_Nr2 ERROR_Nr3 ERROR_Nr4 AnzahlFehlerInSpeicher Switchoff_file_Nr0 Switchoff_file_Nr1 Switchoff_file_Nr2 Switchoff_file_Nr3 Switchoff_file_Nr4 Switchoff_file_Time0 Switchoff_file_Time1 Switchoff_file_Time2 Switchoff_file_Time3 Switchoff_file_Time4 Comfort_exists HauptMenuStatus_Zeile1 HauptMenuStatus_Zeile2 HauptMenuStatus_Zeile3 HauptMenuStatus_Zeit HauptMenuAHP_Stufe HauptMenuAHP_Temp HauptMenuAHP_Zeit SH_BWW SH_HZ SH_MK1 SH_MK2 Einst_Kurzprogramm StatusSlave_1 StatusSlave_2 StatusSlave_3 StatusSlave_4 StatusSlave_5 AktuelleTimeStamp SH_MK3 Sollwert_TVL_MK3 Temperatur_TFB3 MZ3out MA3out FP3out Time_AbtIn Temperatur_RFV2 Temperatur_RFV3 SH_SW Zaehler_BetrZeitSW FreigabKuehl AnalogIn SonderZeichen SH_ZIP WebsrvProgrammWerteBeobachten WMZ_Heizung WMZ_Brauchwasser WMZ_Schwimmbad WMZ_Seit WMZ_Durchfluss AnalogOut1 AnalogOut2 Time_Heissgas Temp_Lueftung_Zuluft Temp_Lueftung_Abluft Zaehler_BetrZeitSolar AnalogOut3 AnalogOut4 Out_VZU Out_VAB Out_VSK Out_FRH AnalogIn2 AnalogIn3 SAXin SPLin Compact_exists Durchfluss_WQ LIN_exists LIN_ANSAUG_VERDAMPFER LIN_ANSAUG_VERDICHTER LIN_VDH LIN_UH LIN_UH_Soll LIN_HD LIN_ND LIN_VDH_out HZIO_PWM HZIO_VEN HZIO_EVU2 HZIO_STB SEC_Qh_Soll SEC_Qh_Ist SEC_TVL_Soll SEC_Software SEC_BZ SEC_VWV SEC_VD SEC_VerdEVI SEC_AnsEVI SEC_UEH_EVI SEC_UEH_EVI_S SEC_KondTemp SEC_FlussigEx SEC_UK_EEV SEC_EVI_Druck SEC_U_Inv Temperatur_THG_2 Temperatur_TWE_2 LIN_ANSAUG_VERDAMPFER_2 LIN_ANSAUG_VERDICHTER_2 LIN_VDH_2 LIN_UH_2 LIN_UH_Soll_2 LIN_HD_2 LIN_ND_2 HDin_2 AVout_2 VBOout_2 VD1out_2 LIN_VDH_out_2 Switchoff2_Nr0 Switchoff2_Nr1 Switchoff2_Nr2 Switchoff2_Nr3 Switchoff2_Nr4 Switchoff2_Time0 Switchoff2_Time1 Switchoff2_Time2 Switchoff2_Time3 Switchoff2_Time4 RBE_RT_Ist RBE_RT_Soll Temp_BW_oben Code_WP_akt_2 Freq_VD LIN_Temp_ND LIN_Temp_HD Abtauwunsch Abtauwunsch_2 Freq_Soll Freq_Min Freq_Max VBO_Soll VBO_Ist HZUP_PWM HZUP_Soll HZUP_Ist Temperatur_VLMax Temperatur_VLMax_2 SEC_EVi SEC_EEV Time_ZWE3_akt );
  my @nameOfParameter = qw(Transfert_LuxNet Einst_WK_akt Einst_BWS_akt Ba_Hz_akt Ba_Bw_akt Ba_Al_akt SU_FrkdHz SU_FrkdBw SU_FrkdAl Einst_HReg_akt Einst_HzHwMAt_akt Einst_HzHwHKE_akt Einst_HzHKRANH_akt Einst_HzHKRABS_akt Einst_HzMK1E_akt Einst_HzMK1ANH_akt Einst_HzMK1ABS_akt Einst_HzFtRl_akt Einst_HzFtMK1Vl_akt Einst_SUBW_akt Einst_BwTDI_akt_MO Einst_BwTDI_akt_DI Einst_BwTDI_akt_MI Einst_BwTDI_akt_DO Einst_BwTDI_akt_FR Einst_BwTDI_akt_SA Einst_BwTDI_akt_SO Einst_BwTDI_akt_AL Einst_AnlKonf_akt Einst_Sprache_akt Switchoff_Zahler Switchoff_index Einst_EvuTyp_akt Einst_RFVEinb_akt Einst_AbtZykMax_akt Einst_HREinb_akt Einst_ZWE1Art_akt Einst_ZWE1Fkt_akt Einst_ZWE2Art_akt Einst_ZWE2Fkt_akt Einst_BWBer_akt Einst_En_Inst Einst_MK1Typ_akt Einst_ABTLuft_akt Einst_TLAbt_akt Einst_LAbtTime_akt Einst_ASDTyp_akt Einst_LGST_akt Einst_BwWpTime_akt Einst_Popt_akt Einst_Kurzprog_akt Timer_Kurzprog_akt Einst_ManAbt_akt Einst_Ahz_akt Einst_TVL_Ahz_1 Einst_TVL_Ahz_2 Einst_TVL_Ahz_3 Einst_TVL_Ahz_4 Einst_TVL_Ahz_5 Einst_TVL_Ahz_6 Einst_TVL_Ahz_7 Einst_TVL_Ahz_8 Einst_TVL_Ahz_9 Einst_TVL_Ahz_10 Einst_TVL_Std_1 Einst_TVL_Std_2 Einst_TVL_Std_3 Einst_TVL_Std_4 Einst_TVL_Std_5 Einst_TVL_Std_6 Einst_TVL_Std_7 Einst_TVL_Std_8 Einst_TVL_Std_9 Einst_TVL_Std_10 Einst_BWS_Hyst_akt Temp_TBW_BwHD_saved Einst_ABT1_akt Einst_LABTpaus_akt AHZ_state_akt Sollwert_TRL_HZ_AHZ AHP_valrecords Timer_AHZ_akt Einst_BWTINP_akt Einst_ZUPTYP_akt Sollwert_TLG_max Einst_BWZIP_akt Einst_ERRmZWE_akt Einst_TRBegr_akt Einst_HRHyst_akt Einst_TRErhmax_akt Einst_ZWEFreig_akt Einst_TAmax_akt Einst_TAmin_akt Einst_TWQmin_akt Einst_THGmax_akt Einst_FRGT2VD_akt Einst_TV2VDBW_akt Einst_SuAll_akt Einst_TAbtEnd_akt Einst_NrKlingel_akt Einst_BWStyp_akt Einst_ABT2_akt Einst_UeVd_akt Einst_RTyp_akt Einst_AhpM_akt Soll_BWS_akt Timer_Password Einst_Zugangscode Einst_BA_Kuehl_akt Sollwert_Kuehl1_akt Einst_KuehlFreig_akt Einst_TAbsMin_akt TWQmin_saved CWP_saved Einst_Anode_akt Timer_pexoff_akt Einst_AnlPrio_Hzakt Einst_AnlPrio_Bwakt Einst_AnlPrio_Swakt Ba_Sw_akt Einst_RTypMK1_akt Einst_RTypMK2_akt Einst_TDC_Ein_akt Einst_TDC_Aus_akt Einst_TDC_Max_akt Einst_HysHzExEn_akt Einst_HysBwExEn_akt Einst_ZWE3Art_akt Einst_ZWE3Fkt_akt Einst_HzSup_akt Einst_MK2Typ_akt Einst_KuTyp_akt Sollwert_KuCft1_akt Sollwert_KuCft2_akt Sollwert_AtDif1_akt Sollwert_AtDif2_akt SU_FrkdSwb Einst_SwbBer_akt Einst_TV2VDSWB_akt Einst_MinSwan_Time_akt Einst_SuMk2_akt Einst_HzMK2E_akt Einst_HzMK2ANH_akt Einst_HzMK2ABS_akt Einst_HzMK2Hgr_akt Einst_HzFtMK2Vl_akt Temp_THG_BwHD_saved Temp_TA_BwHD_saved Einst_BwHup_akt Einst_TVLmax_akt Einst_MK1LzFaktor_akt Einst_MK2LzFaktor_akt Einst_MK1PerFaktor_akt Einst_MK2PerFaktor_akt Entl_Zyklus_akt Einst_Entl_time_akt Entl_Pause Entl_timer Einst_Entl_akt Ahz_HLeist_confirmed FirstInit_akt Einst_SuAll_akt2 Einst_SuAllWo_zeit_0_0 Einst_SuAllWo_zeit_0_1 Einst_SuAllWo_zeit_1_0 Einst_SuAllWo_zeit_1_1 Einst_SuAllWo_zeit_2_0 Einst_SuAllWo_zeit_2_1 Einst_SuAll25_zeit_0_0 Einst_SuAll25_zeit_0_1 Einst_SuAll25_zeit_1_0 Einst_SuAll25_zeit_1_1 Einst_SuAll25_zeit_2_0 Einst_SuAll25_zeit_2_1 Einst_SuAll25_zeit_0_2 Einst_SuAll25_zeit_0_3 Einst_SuAll25_zeit_1_2 Einst_SuAll25_zeit_1_3 Einst_SuAll25_zeit_2_2 Einst_SuAll25_zeit_2_3 Einst_SuAllTg_zeit_0_0 Einst_SuAllTg_zeit_0_1 Einst_SuAllTg_zeit_1_0 Einst_SuAllTg_zeit_1_1 Einst_SuAllTg_zeit_2_0 Einst_SuAllTg_zeit_2_1 Einst_SuAllTg_zeit_0_2 Einst_SuAllTg_zeit_0_3 Einst_SuAllTg_zeit_1_2 Einst_SuAllTg_zeit_1_3 Einst_SuAllTg_zeit_2_2 Einst_SuAllTg_zeit_2_3 Einst_SuAllTg_zeit_0_4 Einst_SuAllTg_zeit_0_5 Einst_SuAllTg_zeit_1_4 Einst_SuAllTg_zeit_1_5 Einst_SuAllTg_zeit_2_4 Einst_SuAllTg_zeit_2_5 Einst_SuAllTg_zeit_0_6 Einst_SuAllTg_zeit_0_7 Einst_SuAllTg_zeit_1_6 Einst_SuAllTg_zeit_1_7 Einst_SuAllTg_zeit_2_6 Einst_SuAllTg_zeit_2_7 Einst_SuAllTg_zeit_0_8 Einst_SuAllTg_zeit_0_9 Einst_SuAllTg_zeit_1_8 Einst_SuAllTg_zeit_1_9 Einst_SuAllTg_zeit_2_8 Einst_SuAllTg_zeit_2_9 Einst_SuAllTg_zeit_0_10 Einst_SuAllTg_zeit_0_11 Einst_SuAllTg_zeit_1_10 Einst_SuAllTg_zeit_1_11 Einst_SuAllTg_zeit_2_10 Einst_SuAllTg_zeit_2_11 Einst_SuAllTg_zeit_0_12 Einst_SuAllTg_zeit_0_13 Einst_SuAllTg_zeit_1_12 Einst_SuAllTg_zeit_1_13 Einst_SuAllTg_zeit_2_12 Einst_SuAllTg_zeit_2_13 Einst_SuHkr_akt Einst_SuHkrW0_zeit_0_0 Einst_SuHkrW0_zeit_0_1 Einst_SuHkrW0_zeit_1_0 Einst_SuHkrW0_zeit_1_1 Einst_SuHkrW0_zeit_2_0 Einst_SuHkrW0_zeit_2_1 Einst_SuHkr25_zeit_0_0 Einst_SuHkr25_zeit_0_1 Einst_SuHkr25_zeit_1_0 Einst_SuHkr25_zeit_1_1 Einst_SuHkr25_zeit_2_0 Einst_SuHkr25_zeit_2_1 Einst_SuHkr25_zeit_0_2 Einst_SuHkr25_zeit_0_3 Einst_SuHkr25_zeit_1_2 Einst_SuHkr25_zeit_1_3 Einst_SuHkr25_zeit_2_2 Einst_SuHkr25_zeit_2_3 Einst_SuHkrTG_zeit_0_0 Einst_SuHkrTG_zeit_0_1 Einst_SuHkrTG_zeit_1_0 Einst_SuHkrTG_zeit_1_1 Einst_SuHkrTG_zeit_2_0 Einst_SuHkrTG_zeit_2_1 Einst_SuHkrTG_zeit_0_2 Einst_SuHkrTG_zeit_0_3 Einst_SuHkrTG_zeit_1_2 Einst_SuHkrTG_zeit_1_3 Einst_SuHkrTG_zeit_2_2 Einst_SuHkrTG_zeit_2_3 Einst_SuHkrTG_zeit_0_4 Einst_SuHkrTG_zeit_0_5 Einst_SuHkrTG_zeit_1_4 Einst_SuHkrTG_zeit_1_5 Einst_SuHkrTG_zeit_2_4 Einst_SuHkrTG_zeit_2_5 Einst_SuHkrTG_zeit_0_6 Einst_SuHkrTG_zeit_0_7 Einst_SuHkrTG_zeit_1_6 Einst_SuHkrTG_zeit_1_7 Einst_SuHkrTG_zeit_2_6 Einst_SuHkrTG_zeit_2_7 Einst_SuHkrTG_zeit_0_8 Einst_SuHkrTG_zeit_0_9 Einst_SuHkrTG_zeit_1_8 Einst_SuHkrTG_zeit_1_9 Einst_SuHkrTG_zeit_2_8 Einst_SuHkrTG_zeit_2_9 Einst_SuHkrTG_zeit_0_10 Einst_SuHkrTG_zeit_0_11 Einst_SuHkrTG_zeit_1_10 Einst_SuHkrTG_zeit_1_11 Einst_SuHkrTG_zeit_2_10 Einst_SuHkrTG_zeit_2_11 Einst_SuHkrTG_zeit_0_12 Einst_SuHkrTG_zeit_0_13 Einst_SuHkrTG_zeit_1_12 Einst_SuHkrTG_zeit_1_13 Einst_SuHkrTG_zeit_2_12 Einst_SuHkrTG_zeit_2_13 Einst_SuMk1_akt Einst_SuMk1W0_zeit_0_0 Einst_SuMk1W0_zeit_0_1 Einst_SuMk1W0_zeit_1_0 Einst_SuMk1W0_zeit_1_1 Einst_SuMk1W0_zeit_2_0 Einst_SuMk1W0_zeit_2_1 Einst_SuMk125_zeit_0_0 Einst_SuMk125_zeit_0_1 Einst_SuMk125_zeit_1_0 Einst_SuMk125_zeit_1_1 Einst_SuMk125_zeit_2_0 Einst_SuMk125_zeit_2_1 Einst_SuMk125_zeit_0_2 Einst_SuMk125_zeit_0_3 Einst_SuMk125_zeit_1_2 Einst_SuMk125_zeit_1_3 Einst_SuMk125_zeit_2_2 Einst_SuMk125_zeit_2_3 Einst_SuMk1TG_zeit_0_0 Einst_SuMk1TG_zeit_0_1 Einst_SuMk1TG_zeit_1_0 Einst_SuMk1TG_zeit_1_1 Einst_SuMk1TG_zeit_2_0 Einst_SuMk1TG_zeit_2_1 Einst_SuMk1TG_zeit_0_2 Einst_SuMk1TG_zeit_0_3 Einst_SuMk1TG_zeit_1_2 Einst_SuMk1TG_zeit_1_3 Einst_SuMk1TG_zeit_2_2 Einst_SuMk1TG_zeit_2_3 Einst_SuMk1TG_zeit_0_4 Einst_SuMk1TG_zeit_0_5 Einst_SuMk1TG_zeit_1_4 Einst_SuMk1TG_zeit_1_5 Einst_SuMk1TG_zeit_2_4 Einst_SuMk1TG_zeit_2_5 Einst_SuMk1TG_zeit_0_6 Einst_SuMk1TG_zeit_0_7 Einst_SuMk1TG_zeit_1_6 Einst_SuMk1TG_zeit_1_7 Einst_SuMk1TG_zeit_2_6 Einst_SuMk1TG_zeit_2_7 Einst_SuMk1TG_zeit_0_8 Einst_SuMk1TG_zeit_0_9 Einst_SuMk1TG_zeit_1_8 Einst_SuMk1TG_zeit_1_9 Einst_SuMk1TG_zeit_2_8 Einst_SuMk1TG_zeit_2_9 Einst_SuMk1TG_zeit_0_10 Einst_SuMk1TG_zeit_0_11 Einst_SuMk1TG_zeit_1_10 Einst_SuMk1TG_zeit_1_11 Einst_SuMk1TG_zeit_2_10 Einst_SuMk1TG_zeit_2_11 Einst_SuMk1TG_zeit_0_12 Einst_SuMk1TG_zeit_0_13 Einst_SuMk1TG_zeit_1_12 Einst_SuMk1TG_zeit_1_13 Einst_SuMk1TG_zeit_2_12 Einst_SuMk1TG_zeit_2_13 Einst_SuMk2_akt2 Einst_SuMk2Wo_zeit_0_0 Einst_SuMk2Wo_zeit_0_1 Einst_SuMk2Wo_zeit_1_0 Einst_SuMk2Wo_zeit_1_1 Einst_SuMk2Wo_zeit_2_0 Einst_SuMk2Wo_zeit_2_1 Einst_SuMk225_zeit_0_0 Einst_SuMk225_zeit_0_1 Einst_SuMk225_zeit_1_0 Einst_SuMk225_zeit_1_1 Einst_SuMk225_zeit_2_0 Einst_SuMk225_zeit_2_1 Einst_SuMk225_zeit_0_2 Einst_SuMk225_zeit_0_3 Einst_SuMk225_zeit_1_2 Einst_SuMk225_zeit_1_3 Einst_SuMk225_zeit_2_2 Einst_SuMk225_zeit_2_3 Einst_SuMk2Tg_zeit_0_0 Einst_SuMk2Tg_zeit_0_1 Einst_SuMk2Tg_zeit_1_0 Einst_SuMk2Tg_zeit_1_1 Einst_SuMk2Tg_zeit_2_0 Einst_SuMk2Tg_zeit_2_1 Einst_SuMk2Tg_zeit_0_2 Einst_SuMk2Tg_zeit_0_3 Einst_SuMk2Tg_zeit_1_2 Einst_SuMk2Tg_zeit_1_3 Einst_SuMk2Tg_zeit_2_2 Einst_SuMk2Tg_zeit_2_3 Einst_SuMk2Tg_zeit_0_4 Einst_SuMk2Tg_zeit_0_5 Einst_SuMk2Tg_zeit_1_4 Einst_SuMk2Tg_zeit_1_5 Einst_SuMk2Tg_zeit_2_4 Einst_SuMk2Tg_zeit_2_5 Einst_SuMk2Tg_zeit_0_6 Einst_SuMk2Tg_zeit_0_7 Einst_SuMk2Tg_zeit_1_6 Einst_SuMk2Tg_zeit_1_7 Einst_SuMk2Tg_zeit_2_6 Einst_SuMk2Tg_zeit_2_7 Einst_SuMk2Tg_zeit_0_8 Einst_SuMk2Tg_zeit_0_9 Einst_SuMk2Tg_zeit_1_8 Einst_SuMk2Tg_zeit_1_9 Einst_SuMk2Tg_zeit_2_8 Einst_SuMk2Tg_zeit_2_9 Einst_SuMk2Tg_zeit_0_10 Einst_SuMk2Tg_zeit_0_11 Einst_SuMk2Tg_zeit_1_10 Einst_SuMk2Tg_zeit_1_11 Einst_SuMk2Tg_zeit_2_10 Einst_SuMk2Tg_zeit_2_11 Einst_SuMk2Tg_zeit_0_12 Einst_SuMk2Tg_zeit_0_13 Einst_SuMk2Tg_zeit_1_12 Einst_SuMk2Tg_zeit_1_13 Einst_SuMk2Tg_zeit_2_12 Einst_SuMk2Tg_zeit_2_13 Einst_SUBW_akt2 Einst_SuBwWO_zeit_0_0 Einst_SuBwWO_zeit_0_1 Einst_SuBwWO_zeit_1_0 Einst_SuBwWO_zeit_1_1 Einst_SuBwWO_zeit_2_0 Einst_SuBwWO_zeit_2_1 Einst_SuBwWO_zeit_3_0 Einst_SuBwWO_zeit_3_1 Einst_SuBwWO_zeit_4_0 Einst_SuBwWO_zeit_4_1 Einst_SuBw25_zeit_0_0 Einst_SuBw25_zeit_0_1 Einst_SuBw25_zeit_1_0 Einst_SuBw25_zeit_1_1 Einst_SuBw25_zeit_2_0 Einst_SuBw25_zeit_2_1 Einst_SuBw25_zeit_3_0 Einst_SuBw25_zeit_3_1 Einst_SuBw25_zeit_4_0 Einst_SuBw25_zeit_4_1 Einst_SuBw25_zeit_0_2 Einst_SuBw25_zeit_0_3 Einst_SuBw25_zeit_1_2 Einst_SuBw25_zeit_1_3 Einst_SuBw25_zeit_2_2 Einst_SuBw25_zeit_2_3 Einst_SuBw25_zeit_3_2 Einst_SuBw25_zeit_3_3 Einst_SuBw25_zeit_4_2 Einst_SuBw25_zeit_4_3 Einst_SuBwTG_zeit_0_0 Einst_SuBwTG_zeit_0_1 Einst_SuBwTG_zeit_1_0 Einst_SuBwTG_zeit_1_1 Einst_SuBwTG_zeit_2_0 Einst_SuBwTG_zeit_2_1 Einst_SuBwTG_zeit_3_0 Einst_SuBwTG_zeit_3_1 Einst_SuBwTG_zeit_4_0 Einst_SuBwTG_zeit_4_1 Einst_SuBwTG_zeit_0_2 Einst_SuBwTG_zeit_0_3 Einst_SuBwTG_zeit_1_2 Einst_SuBwTG_zeit_1_3 Einst_SuBwTG_zeit_2_2 Einst_SuBwTG_zeit_2_3 Einst_SuBwTG_zeit_3_2 Einst_SuBwTG_zeit_3_3 Einst_SuBwTG_zeit_4_2 Einst_SuBwTG_zeit_4_3 Einst_SuBwTG_zeit_0_4 Einst_SuBwTG_zeit_0_5 Einst_SuBwTG_zeit_1_4 Einst_SuBwTG_zeit_1_5 Einst_SuBwTG_zeit_2_4 Einst_SuBwTG_zeit_2_5 Einst_SuBwTG_zeit_3_4 Einst_SuBwTG_zeit_3_5 Einst_SuBwTG_zeit_4_4 Einst_SuBwTG_zeit_4_5 Einst_SuBwTG_zeit_0_6 Einst_SuBwTG_zeit_0_7 Einst_SuBwTG_zeit_1_6 Einst_SuBwTG_zeit_1_7 Einst_SuBwTG_zeit_2_6 Einst_SuBwTG_zeit_2_7 Einst_SuBwTG_zeit_3_6 Einst_SuBwTG_zeit_3_7 Einst_SuBwTG_zeit_4_6 Einst_SuBwTG_zeit_4_7 Einst_SuBwTG_zeit_0_8 Einst_SuBwTG_zeit_0_9 Einst_SuBwTG_zeit_1_8 Einst_SuBwTG_zeit_1_9 Einst_SuBwTG_zeit_2_8 Einst_SuBwTG_zeit_2_9 Einst_SuBwTG_zeit_3_8 Einst_SuBwTG_zeit_3_9 Einst_SuBwTG_zeit_4_8 Einst_SuBwTG_zeit_4_9 Einst_SuBwTG_zeit_0_10 Einst_SuBwTG_zeit_0_11 Einst_SuBwTG_zeit_1_10 Einst_SuBwTG_zeit_1_11 Einst_SuBwTG_zeit_2_10 Einst_SuBwTG_zeit_2_11 Einst_SuBwTG_zeit_3_10 Einst_SuBwTG_zeit_3_11 Einst_SuBwTG_zeit_4_10 Einst_SuBwTG_zeit_4_11 Einst_SuBwTG_zeit_0_12 Einst_SuBwTG_zeit_0_13 Einst_SuBwTG_zeit_1_12 Einst_SuBwTG_zeit_1_13 Einst_SuBwTG_zeit_2_12 Einst_SuBwTG_zeit_2_13 Einst_SuBwTG_zeit_3_12 Einst_SuBwTG_zeit_3_13 Einst_SuBwTG_zeit_4_12 Einst_SuBwTG_zeit_4_13 Einst_SuZIP_akt Einst_SuZIPWo_zeit_0_0 Einst_SuZIPWo_zeit_0_1 Einst_SuZIPWo_zeit_1_0 Einst_SuZIPWo_zeit_1_1 Einst_SuZIPWo_zeit_2_0 Einst_SuZIPWo_zeit_2_1 Einst_SuZIPWo_zeit_3_0 Einst_SuZIPWo_zeit_3_1 Einst_SuZIPWo_zeit_4_0 Einst_SuZIPWo_zeit_4_1 Einst_SuZIP25_zeit_0_0 Einst_SuZIP25_zeit_0_1 Einst_SuZIP25_zeit_1_0 Einst_SuZIP25_zeit_1_1 Einst_SuZIP25_zeit_2_0 Einst_SuZIP25_zeit_2_1 Einst_SuZIP25_zeit_3_0 Einst_SuZIP25_zeit_3_1 Einst_SuZIP25_zeit_4_0 Einst_SuZIP25_zeit_4_1 Einst_SuZIP25_zeit_0_2 Einst_SuZIP25_zeit_0_3 Einst_SuZIP25_zeit_1_2 Einst_SuZIP25_zeit_1_3 Einst_SuZIP25_zeit_2_2 Einst_SuZIP25_zeit_2_3 Einst_SuZIP25_zeit_3_2 Einst_SuZIP25_zeit_3_3 Einst_SuZIP25_zeit_4_2 Einst_SuZIP25_zeit_4_3 Einst_SuZIPTg_zeit_0_0 Einst_SuZIPTg_zeit_0_1 Einst_SuZIPTg_zeit_1_0 Einst_SuZIPTg_zeit_1_1 Einst_SuZIPTg_zeit_2_0 Einst_SuZIPTg_zeit_2_1 Einst_SuZIPTg_zeit_3_0 Einst_SuZIPTg_zeit_3_1 Einst_SuZIPTg_zeit_4_0 Einst_SuZIPTg_zeit_4_1 Einst_SuZIPTg_zeit_0_2 Einst_SuZIPTg_zeit_0_3 Einst_SuZIPTg_zeit_1_2 Einst_SuZIPTg_zeit_1_3 Einst_SuZIPTg_zeit_2_2 Einst_SuZIPTg_zeit_2_3 Einst_SuZIPTg_zeit_3_2 Einst_SuZIPTg_zeit_3_3 Einst_SuZIPTg_zeit_4_2 Einst_SuZIPTg_zeit_4_3 Einst_SuZIPTg_zeit_0_4 Einst_SuZIPTg_zeit_0_5 Einst_SuZIPTg_zeit_1_4 Einst_SuZIPTg_zeit_1_5 Einst_SuZIPTg_zeit_2_4 Einst_SuZIPTg_zeit_2_5 Einst_SuZIPTg_zeit_3_4 Einst_SuZIPTg_zeit_3_5 Einst_SuZIPTg_zeit_4_4 Einst_SuZIPTg_zeit_4_5 Einst_SuZIPTg_zeit_0_6 Einst_SuZIPTg_zeit_0_7 Einst_SuZIPTg_zeit_1_6 Einst_SuZIPTg_zeit_1_7 Einst_SuZIPTg_zeit_2_6 Einst_SuZIPTg_zeit_2_7 Einst_SuZIPTg_zeit_3_6 Einst_SuZIPTg_zeit_3_7 Einst_SuZIPTg_zeit_4_6 Einst_SuZIPTg_zeit_4_7 Einst_SuZIPTg_zeit_0_8 Einst_SuZIPTg_zeit_0_9 Einst_SuZIPTg_zeit_1_8 Einst_SuZIPTg_zeit_1_9 Einst_SuZIPTg_zeit_2_8 Einst_SuZIPTg_zeit_2_9 Einst_SuZIPTg_zeit_3_8 Einst_SuZIPTg_zeit_3_9 Einst_SuZIPTg_zeit_4_8 Einst_SuZIPTg_zeit_4_9 Einst_SuZIPTg_zeit_0_10 Einst_SuZIPTg_zeit_0_11 Einst_SuZIPTg_zeit_1_10 Einst_SuZIPTg_zeit_1_11 Einst_SuZIPTg_zeit_2_10 Einst_SuZIPTg_zeit_2_11 Einst_SuZIPTg_zeit_3_10 Einst_SuZIPTg_zeit_3_11 Einst_SuZIPTg_zeit_4_10 Einst_SuZIPTg_zeit_4_11 Einst_SuZIPTg_zeit_0_12 Einst_SuZIPTg_zeit_0_13 Einst_SuZIPTg_zeit_1_12 Einst_SuZIPTg_zeit_1_13 Einst_SuZIPTg_zeit_2_12 Einst_SuZIPTg_zeit_2_13 Einst_SuZIPTg_zeit_3_12 Einst_SuZIPTg_zeit_3_13 Einst_SuZIPTg_zeit_4_12 Einst_SuZIPTg_zeit_4_13 Einst_SuSwb_akt Einst_SuSwbWo_zeit_0_0 Einst_SuSwbWo_zeit_0_1 Einst_SuSwbWo_zeit_1_0 Einst_SuSwbWo_zeit_1_1 Einst_SuSwbWo_zeit_2_0 Einst_SuSwbWo_zeit_2_1 Einst_SuSwb25_zeit_0_0 Einst_SuSwb25_zeit_0_1 Einst_SuSwb25_zeit_1_0 Einst_SuSwb25_zeit_1_1 Einst_SuSwb25_zeit_2_0 Einst_SuSwb25_zeit_2_1 Einst_SuSwb25_zeit_0_2 Einst_SuSwb25_zeit_0_3 Einst_SuSwb25_zeit_1_2 Einst_SuSwb25_zeit_1_3 Einst_SuSwb25_zeit_2_2 Einst_SuSwb25_zeit_2_3 Einst_SuSwbTg_zeit_0_0 Einst_SuSwbTg_zeit_0_1 Einst_SuSwbTg_zeit_1_0 Einst_SuSwbTg_zeit_1_1 Einst_SuSwbTg_zeit_2_0 Einst_SuSwbTg_zeit_2_1 Einst_SuSwbTg_zeit_0_2 Einst_SuSwbTg_zeit_0_3 Einst_SuSwbTg_zeit_1_2 Einst_SuSwbTg_zeit_1_3 Einst_SuSwbTg_zeit_2_2 Einst_SuSwbTg_zeit_2_3 Einst_SuSwbTg_zeit_0_4 Einst_SuSwbTg_zeit_0_5 Einst_SuSwbTg_zeit_1_4 Einst_SuSwbTg_zeit_1_5 Einst_SuSwbTg_zeit_2_4 Einst_SuSwbTg_zeit_2_5 Einst_SuSwbTg_zeit_0_6 Einst_SuSwbTg_zeit_0_7 Einst_SuSwbTg_zeit_1_6 Einst_SuSwbTg_zeit_1_7 Einst_SuSwbTg_zeit_2_6 Einst_SuSwbTg_zeit_2_7 Einst_SuSwbTg_zeit_0_8 Einst_SuSwbTg_zeit_0_9 Einst_SuSwbTg_zeit_1_8 Einst_SuSwbTg_zeit_1_9 Einst_SuSwbTg_zeit_2_8 Einst_SuSwbTg_zeit_2_9 Einst_SuSwbTg_zeit_0_10 Einst_SuSwbTg_zeit_0_11 Einst_SuSwbTg_zeit_1_10 Einst_SuSwbTg_zeit_1_11 Einst_SuSwbTg_zeit_2_10 Einst_SuSwbTg_zeit_2_11 Einst_SuSwbTg_zeit_0_12 Einst_SuSwbTg_zeit_0_13 Einst_SuSwbTg_zeit_1_12 Einst_SuSwbTg_zeit_1_13 Einst_SuSwbTg_zeit_2_12 Einst_SuSwbTg_zeit_2_13 Zaehler_BetrZeitWP Zaehler_BetrZeitVD1 Zaehler_BetrZeitVD2 Zaehler_BetrZeitZWE1 Zaehler_BetrZeitZWE2 Zaehler_BetrZeitZWE3 Zaehler_BetrZeitImpVD1 Zaehler_BetrZeitImpVD2 Zaehler_BetrZeitEZMVD1 Zaehler_BetrZeitEZMVD2 Einst_Entl_Typ_0 Einst_Entl_Typ_1 Einst_Entl_Typ_2 Einst_Entl_Typ_3 Einst_Entl_Typ_4 Einst_Entl_Typ_5 Einst_Entl_Typ_6 Einst_Entl_Typ_7 Einst_Entl_Typ_8 Einst_Entl_Typ_9 Einst_Entl_Typ_10 Einst_Entl_Typ_11 Einst_Entl_Typ_12 Einst_Vorl_max_MK1 Einst_Vorl_max_MK2 SU_FrkdMK1 SU_FrkdMK2 Ba_Hz_MK1_akt Ba_Hz_MK2_akt Einst_Zirk_Ein_akt Einst_Zirk_Aus_akt Einst_Heizgrenze Einst_Heizgrenze_Temp VariablenIBNgespeichert SchonIBNAssistant Heizgrenze_0 Heizgrenze_1 Heizgrenze_2 Heizgrenze_3 Heizgrenze_4 Heizgrenze_5 Heizgrenze_6 Heizgrenze_7 Heizgrenze_8 Heizgrenze_9 Heizgrenze_10 Heizgrenze_11 SchemenIBNgewahlt Switchoff_file_0_0 Switchoff_file_1_0 Switchoff_file_2_0 Switchoff_file_3_0 Switchoff_file_4_0 Switchoff_file_0_1 Switchoff_file_1_1 Switchoff_file_2_1 Switchoff_file_3_1 Switchoff_file_4_1 DauerDatenLoggerAktiv Laufvar_Heizgrenze Zaehler_BetrZeitHz Zaehler_BetrZeitBW Zaehler_BetrZeitKue SU_FstdHz SU_FstdBw SU_FstdSwb SU_FstdMK1 SU_FstdMK2 FerienAbsenkungHz FerienAbsenkungMK1 FerienAbsenkungMK2 FerienModusAktivHz FerienModusAktivBw FerienModusAktivSwb FerienModusAktivMk1 FerienModusAktivMk2 DisplayContrast_akt Ba_Hz_saved Ba_Bw_saved Ba_Sw_saved Ba_Hz_MK1_saved Ba_Hz_MK2_saved AdresseIP_akt SubNetMask_akt Add_Broadcast_akt Add_StdGateway_akt DHCPServerAktiv_akt WebserverPasswort_1_akt WebserverPasswort_2_akt WebserverPasswort_3_akt WebserverPasswort_4_akt WebserverPasswort_5_akt WebserverPasswort_6_akt WebServerWerteBekommen Einst_ParBetr_akt Einst_WpAnz_akt Einst_PhrTime_akt Einst_HysPar_akt IP_PB_Slave_0 IP_PB_Slave_1 IP_PB_Slave_2 IP_PB_Slave_3 IP_PB_Slave_4 IP_PB_Slave_5 Einst_BwHup_akt_backup Einst_SuMk3_akt Einst_HzMK3E_akt Einst_HzMK3ANH_akt Einst_HzMK3ABS_akt Einst_HzMK3Hgr_akt Einst_HzFtMK3Vl_akt Ba_Hz_MK3_akt Einst_MK3Typ_akt Einst_RTypMK3_akt Einst_MK3LzFaktor_akt Einst_MK3PerFaktor_akt FerienModusAktivMk3 SU_FrkdMK3 FerienAbsenkungMK3 SU_FstdMK3 Einst_SuMk3_akt2 Einst_SuMk3Wo_zeit_0_0 Einst_SuMk3Wo_zeit_0_1 Einst_SuMk3Wo_zeit_1_0 Einst_SuMk3Wo_zeit_1_1 Einst_SuMk3Wo_zeit_2_0 Einst_SuMk3Wo_zeit_2_1 Einst_SuMk325_zeit_0_0 Einst_SuMk325_zeit_0_1 Einst_SuMk325_zeit_1_0 Einst_SuMk325_zeit_1_1 Einst_SuMk325_zeit_2_0 Einst_SuMk325_zeit_2_1 Einst_SuMk325_zeit_0_2 Einst_SuMk325_zeit_0_3 Einst_SuMk325_zeit_1_2 Einst_SuMk325_zeit_1_3 Einst_SuMk325_zeit_2_2 Einst_SuMk325_zeit_2_3 Einst_SuMk3Tg_zeit_0_0 Einst_SuMk3Tg_zeit_0_1 Einst_SuMk3Tg_zeit_1_0 Einst_SuMk3Tg_zeit_1_1 Einst_SuMk3Tg_zeit_2_0 Einst_SuMk3Tg_zeit_2_1 Einst_SuMk3Tg_zeit_0_2 Einst_SuMk3Tg_zeit_0_3 Einst_SuMk3Tg_zeit_1_2 Einst_SuMk3Tg_zeit_1_3 Einst_SuMk3Tg_zeit_2_2 Einst_SuMk3Tg_zeit_2_3 Einst_SuMk3Tg_zeit_0_4 Einst_SuMk3Tg_zeit_0_5 Einst_SuMk3Tg_zeit_1_4 Einst_SuMk3Tg_zeit_1_5 Einst_SuMk3Tg_zeit_2_4 Einst_SuMk3Tg_zeit_2_5 Einst_SuMk3Tg_zeit_0_6 Einst_SuMk3Tg_zeit_0_7 Einst_SuMk3Tg_zeit_1_6 Einst_SuMk3Tg_zeit_1_7 Einst_SuMk3Tg_zeit_2_6 Einst_SuMk3Tg_zeit_2_7 Einst_SuMk3Tg_zeit_0_8 Einst_SuMk3Tg_zeit_0_9 Einst_SuMk3Tg_zeit_1_8 Einst_SuMk3Tg_zeit_1_9 Einst_SuMk3Tg_zeit_2_8 Einst_SuMk3Tg_zeit_2_9 Einst_SuMk3Tg_zeit_0_10 Einst_SuMk3Tg_zeit_0_11 Einst_SuMk3Tg_zeit_1_10 Einst_SuMk3Tg_zeit_1_11 Einst_SuMk3Tg_zeit_2_10 Einst_SuMk3Tg_zeit_2_11 Einst_SuMk3Tg_zeit_0_12 Einst_SuMk3Tg_zeit_0_13 Einst_SuMk3Tg_zeit_1_12 Einst_SuMk3Tg_zeit_1_13 Einst_SuMk3Tg_zeit_2_12 Einst_SuMk3Tg_zeit_2_13 Ba_Hz_MK3_saved Einst_Kuhl_Zeit_Ein_akt Einst_Kuhl_Zeit_Aus_akt Waermemenge_Seit Waermemenge_WQ Waermemenge_Hz Waermemenge_WQ_ges Einst_Entl_Typ_13 Einst_Entl_Typ_14 Einst_Entl_Typ_15 Zaehler_BetrZeitSW Einst_Fernwartung_akt AdresseIPServ_akt Einst_TA_EG_akt Einst_TVLmax_EG_akt Einst_Popt_Nachlauf_akt FernwartungVertrag_akt FernwartungAktuZeit Einst_Effizienzpumpe_Nominal_akt Einst_Effizienzpumpe_Minimal_akt Einst_Effizienzpumpe_akt Einst_Waermemenge_akt Einst_Wm_Versorgung_Korrektur_akt Einst_Wm_Auswertung_Korrektur_akt SoftwareUpdateJetztGemacht_akt WP_SerienNummer_DATUM WP_SerienNummer_HEX WP_SerienNummer_INDEX ProgWerteWebSrvBeobarten Waermemenge_BW Waermemenge_SW Waermemenge_Datum Einst_Solar_akt BSTD_Solar Einst_TDC_Koll_Max_akt Einst_Akt_Kuehlung_akt Einst_Vorlauf_VBO_akt Einst_KRHyst_akt Einst_Akt_Kuehl_Speicher_min_akt Einst_Akt_Kuehl_Freig_WQE_akt NDAB_WW_Anzahl NDS_WW_KD_Quitt Einst_AbtZykMin_akt Einst_VD2_Zeit_Min_akt Einst_Hysterese_HR_verkuerzt_akt Einst_BA_Lueftung_akt Einst_SuLuf_akt Einst_SuLufWo_zeit_0_0_0 Einst_SuLufWo_zeit_0_1_0 Einst_SuLufWo_zeit_0_2_0 Einst_SuLuf25_zeit_0_0_0 Einst_SuLuf25_zeit_0_1_0 Einst_SuLuf25_zeit_0_2_0 Einst_SuLuf25_zeit_0_0_2 Einst_SuLuf25_zeit_0_1_2 Einst_SuLuf25_zeit_0_2_2 Einst_SuLufTg_zeit_0_0_0 Einst_SuLufTg_zeit_0_1_0 Einst_SuLufTg_zeit_0_2_0 Einst_SuLufTg_zeit_0_0_2 Einst_SuLufTg_zeit_0_1_2 Einst_SuLufTg_zeit_0_2_2 Einst_SuLufTg_zeit_0_0_4 Einst_SuLufTg_zeit_0_1_4 Einst_SuLufTg_zeit_0_2_4 Einst_SuLufTg_zeit_0_0_6 Einst_SuLufTg_zeit_0_1_6 Einst_SuLufTg_zeit_0_2_6 Einst_SuLufTg_zeit_0_0_8 Einst_SuLufTg_zeit_0_1_8 Einst_SuLufTg_zeit_0_2_8 Einst_SuLufTg_zeit_0_0_10 Einst_SuLufTg_zeit_0_1_10 Einst_SuLufTg_zeit_0_2_10 Einst_SuLufTg_zeit_0_0_12 Einst_SuLufTg_zeit_0_1_12 Einst_SuLufTg_zeit_0_2_12 Einst_SuLufWo_zeit_1_0_0 Einst_SuLufWo_zeit_1_1_0 Einst_SuLufWo_zeit_1_2_0 Einst_SuLuf25_zeit_1_0_0 Einst_SuLuf25_zeit_1_1_0 Einst_SuLuf25_zeit_1_2_0 Einst_SuLuf25_zeit_1_0_2 Einst_SuLuf25_zeit_1_1_2 Einst_SuLuf25_zeit_1_2_2 Einst_SuLufTg_zeit_1_0_0 Einst_SuLufTg_zeit_1_1_0 Einst_SuLufTg_zeit_1_2_0 Einst_SuLufTg_zeit_1_0_2 Einst_SuLufTg_zeit_1_1_2 Einst_SuLufTg_zeit_1_2_2 Einst_SuLufTg_zeit_1_0_4 Einst_SuLufTg_zeit_1_1_4 Einst_SuLufTg_zeit_1_2_4 Einst_SuLufTg_zeit_1_0_6 Einst_SuLufTg_zeit_1_1_6 Einst_SuLufTg_zeit_1_2_6 Einst_SuLufTg_zeit_1_0_8 Einst_SuLufTg_zeit_1_1_8 Einst_SuLufTg_zeit_1_2_8 Einst_SuLufTg_zeit_1_0_10 Einst_SuLufTg_zeit_1_1_10 Einst_SuLufTg_zeit_1_2_10 Einst_SuLufTg_zeit_1_0_12 Einst_SuLufTg_zeit_1_1_12 Einst_SuLufTg_zeit_1_2_12 FerienModusAktivLueftung Einst_BA_Lueftung_saved SU_FrkdLueftung SU_FstdLueftung Einst_Luf_Feuchteschutz_akt Einst_Luf_Reduziert_akt Einst_Luf_Nennlueftung_akt Einst_Luf_Intensivlueftung_akt Timer_Fil_4Makt Timer_Fil_WoAkt Sollwert_KuCft3_akt Sollwert_AtDif3_akt Bitmaske_0 Einst_Lueftungsstufen SysEin_Meldung_TDI SysEin_Typ_WZW Einst_GLT_aktiviert Einst_BW_max Einst_Sollwert_TRL_Kuehlen Einst_Medium_Waermequelle Einst_Photovoltaik_akt Einst_Multispeicher_akt Einst_PKuehlTime_akt Einst_Minimale_Ruecklaufsolltemperatur RBE_Einflussfaktor_RT_akt RBE_Freigabe_Kuehlung_akt RBE_Waermeverteilsystem_akt RBE_Zeit_Heizstab_aktiv SEC_ND_Alarmgrenze SEC_HD_Alarmgrenze SEC_Abtauendtemperatur Einst_Min_RPM_BW Einst_Luf_Feuchteschutz_Faktor_akt Einst_Luf_Reduziert_Faktor_akt Einst_Luf_Nennlueftung_Faktor_akt Einst_Luf_Intensivlueftung_Faktor_akt Einst_Freigabe_Zeit_ZWE Einst_min_VL_Kuehl Einst_Warmwasser_Nachheizung Switchoff_file_LWD2_0_0 Switchoff_file_LWD2_1_0 Switchoff_file_LWD2_2_0 Switchoff_file_LWD2_3_0 Switchoff_file_LWD2_4_0 Switchoff_file_LWD2_0_1 Switchoff_file_LWD2_1_1 Switchoff_file_LWD2_2_1 Switchoff_file_LWD2_3_1 Switchoff_file_LWD2_4_1 Switchoff_index_LWD2 Einst_Effizienzpumpe_Nominal_2 Einst_Effizienzpumpe_Minimal_2 Einst_Wm_Versorgung_Korrektur_2 Einst_Wm_Auswertung_Korrektur_2 Einst_isTwin Einst_TAmin_2 Einst_TVLmax_2 Einst_TA_EG_2 Einst_TVLmax_EG_2 Waermemenge_Hz_2 Waermemenge_BW_2 Waermemenge_SW_2 Waermemenge_Seit_2 Einst_Entl_Typ_15_2 Einst_WW_Nachheizung_max Einst_Kuhl_Zeit_Ein_RT Einst_ZWE1_Pos Einst_ZWE2_Pos Einst_ZWE3_Pos Einst_Leistung_ZWE WP_SN2_DATUM WP_SN2_HEX WP_SN2_INDEX CWP_saved2 Einst_SmartGrid Einst_P155_HDS Einst_P155_PumpHeat_Max Einst_P155_PumpHeatCtrl Einst_P155_PumpDHWCtrl Einst_P155_PumpDHW_RPM Einst_P155_PumpPoolCtrl Einst_P155_PumpPool_RPM Einst_P155_PumpCool_RPM Einst_P155_PumpVBOCtrl Einst_P155_PumpVBO_RPM_C Einst_P155_PumpDHW_Max Einst_P155_PumpPool_Max Einst_P155_Sperrband_1 Einst_P155_Leistungsfreigabe Einst_P155_DHW_Freq Einst_SWHUP Einst_P155_SWB_Freq Einst_MK1_Regelung Einst_MK2_Regelung Einst_MK3_Regelung Einst_PV_WW_Sperrzeit Einst_Warmwasser_extra Einst_Vorl_akt_Kuehl WP_SN3_DATUM WP_SN3_HEX WP_SN3_INDEX Einst_Vorlauf_ZUP Einst_Abtauen_im_Warmwasser Waermemenge_ZWE Waermemenge_Reset Waermemenge_Reset_2 Einst_Brunnenpumpe_min Einst_Brunnenpumpe_max Einst_SmartHomeID Einst_SmartHK Einst_SmartMK1 Einst_SmartMK2 Einst_SmartMK3 Einst_SmartWW Einst_SmartDefrost Einst_Empty1071 Einst_MinVLMK1 Einst_MinVLMK2 Einst_MinVLMK3 Einst_MaxVLMK1 Einst_MaxVLMK2 Einst_MaxVLMK3 Einst_SmartPlusHz Einst_SmartMinusHz Einst_SmartPlusMK1 Einst_SmartMinusMK1 Einst_SmartPlusMK2 Einst_SmartMinusMK2 Einst_SmartPlusMK3 Einst_SmartMinusMK3
  );
   if($cmd eq 'heatingCurveParameter') {
      # Log3 $name, 3, "get $name $cmd";
      if (int @val !=4 ) {
         my $msg = "Wrong number of parameter (".int @val.")in get $name $cmd";
         Log3 $name, 3, $msg;
         return $msg;
      }
      else {
         return LUXTRONIK2_calcHeatingCurveParameter ( $hash, $val[0], $val[1], $val[2], $val[3]);
      }
   }
   elsif($cmd eq 'heatingCurveReturnTemperature') {
      # Log3 $name, 3, "get $name $cmd";
      if (int @val !=1) {
         my $msg = "Wrong number of parameter (".int @val.")in get $name $cmd";
         Log3 $name, 3, $msg;
         return $msg;
      }
      else {
         my $heatingCurveEndPoint = $hash->{READINGS}{heatingCurveEndPoint}{VAL};
         my $heatingCurveOffset = $hash->{READINGS}{heatingCurveOffset}{VAL};
         return LUXTRONIK2_getHeatingCurveReturnTemperature ( $hash, $val[0], $heatingCurveEndPoint, $heatingCurveOffset);
      }
   }
   elsif( $cmd eq 'rawData') {
		my ($state, $msg , $heatpump_values, $heatpump_parameters, $heatpump_visibility) = LUXTRONIK2_ReadData ($name);
		if ($state != 1) {
		  return $msg;
		}
		else {
		  my $index = 0;
      $resultStr = ("-" x 133) . "\n";
		  $resultStr .="Heatpump Values (".scalar(@$heatpump_values).")";
		  foreach (@$heatpump_values) {
        $resultStr .= "\n" . ("-" x 133)		if $index % 15 == 0;
        $resultStr .= "\n|"		if $index % 3 == 0;
        $resultStr .= sprintf ("%4s %-38s|", $index, $nameOfValue[$index] . " : " . $_);
        $index++;
		  }
		  $index = 0;
      $resultStr .= "\n\n" . ("_" x 133) . "\n\n";
		  $resultStr .="Heatpump Parameters (".scalar(@$heatpump_parameters).")";
		  foreach (@$heatpump_parameters) {
        $resultStr .= "\n" . ("-" x 133)		if $index % 15 == 0;
        $resultStr .= "\n|"		if $index % 3 == 0;
        $resultStr .= sprintf ("%4s %-38s|", $index, $nameOfParameter[$index] . " : " . $_);
        $index++;
		  }
		  return $resultStr;
		}
   }

   my $list = "heatingCurveParameter "
            . "heatingCurveReturnTemperature "
            . "rawData:noArg ";
   
          
  return "Unknown argument $cmd, choose one of $list";
}

sub ########################################
LUXTRONIK2_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "LUXTRONIK2_GetUpdate", $hash, 1);
    return undef if( AttrVal($name, "disable", 0 ) == 1 );
  }

  $hash->{helper}{RUNNING_PID} = BlockingCall("LUXTRONIK2_DoUpdate", $name, "LUXTRONIK2_UpdateDone", 25, "LUXTRONIK2_UpdateAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
}

########################################
sub LUXTRONIK2_DoUpdate($)
{
  my ($name) = @_;
  my $hash = $defs{$name};
  my $host = $hash->{HOST};
  my $port = $hash->{PORT};
  
  my $count=0;
  my $result="";
  my $firstLoop;
  
  # Read raw data and handle error return
  my $readingStartTime = time();
  my ($state, $msg , $retValues, $retParameters, $retVisibility) = LUXTRONIK2_ReadData ($name);
  my $readingEndTime = time();
  
  return ("$name|$state|$msg")      if $state != 1 ;
  my @heatpump_values = @$retValues;
  my @heatpump_parameters = @$retParameters;
  my @heatpump_visibility = @$retVisibility;
  
#return certain readings for further processing
  # 0 - name
  my $return_str="$name";
  # 1 - no error = 1
  $return_str .= "|1";
  # 2 - opStateHeatPump1
  $return_str .= "|".$heatpump_values[117];
  # 3 - opStateHeatPump3
  $return_str .= "|".$heatpump_values[119];
  # 4 - Stufe - ID_WEB_HauptMenuAHP_Stufe
  $return_str .= "|".$heatpump_values[121];
  # 5 - Temperature Value - ID_WEB_HauptMenuAHP_Temp
  $return_str .= "|".$heatpump_values[122];
  # 6 - Compressor1 
  $return_str .= "|".$heatpump_values[44];
  # 7 - opModeHotWater
  $return_str .= "|".$heatpump_parameters[4];
  # 8 - hotWaterMonitoring
  $return_str .= "|".$heatpump_values[124];
  # 9 - hotWaterBoilerValve
  $return_str .= "|".$heatpump_values[38];
  # 10 - opModeHeating
  $return_str .= "|".$heatpump_parameters[3];
  # 11 - heatingLimit
  $return_str .= "|".$heatpump_parameters[699];
  # 12 - ambientTemperature
  $return_str .= "|".$heatpump_values[15];
  # 13 - averageAmbientTemperature
  $return_str .= "|".$heatpump_values[16];
  # 14 - hotWaterTemperature
  $return_str .= "|".$heatpump_values[17];
  # 15 - flowTemperature
  $return_str .= "|".$heatpump_values[10];
  # 16 - returnTemperature
  $return_str .= "|".$heatpump_values[11];
  # 17 - returnTemperatureTarget
  $return_str .= "|".$heatpump_values[12];
  # 18 - returnTemperatureExtern
  $return_str .= "|".($heatpump_visibility[24]==1 ? $heatpump_values[13] : "no");
  # 19 - flowRate 
  $return_str .= "|".($heatpump_parameters[870]!=0 ? $heatpump_values[155] : "no");
  # 20 - firmware
  my $fwvalue = "";
  for(my $fi=81; $fi<91; $fi++) {
      $fwvalue .= chr($heatpump_values[$fi]) if $heatpump_values[$fi];
  }
  $return_str .= "|".$fwvalue;
  # 21 - thresholdHeatingLimit
  $return_str .= "|".$heatpump_parameters[700];
  # 22 - rawDeviceTimeCalc
  $return_str .= "|".$heatpump_values[134];
  # 23 - heatSourceIN
  $return_str .= "|".$heatpump_values[19];
  # 24 - heatSourceOUT
  $return_str .= "|".$heatpump_values[20];
  # 25 - hotWaterTemperatureTarget
  $return_str .= "|".$heatpump_values[18];
  # 26 - hotGasTemperature
  $return_str .= "|".$heatpump_values[14];
  # 27 - heatingSystemCircPump
  $return_str .= "|".$heatpump_values[39];
  # 28 - hotWaterCircPumpExtern
  $return_str .= "|". ($heatpump_visibility[57]==1 ? $heatpump_values[46] : "no");
  # 29 - readingFhemStartTime
  $return_str .= "|".$readingStartTime;
  # 30 - readingFhemEndTime
  $return_str .= "|".$readingEndTime;
  # 31 - typeHeatpump
  $return_str .= "|".$heatpump_values[78];
  # 32 - counterHours2ndHeatSource1
  $return_str .= "|". ($heatpump_visibility[84]==1 ? $heatpump_values[60] : "no");
  # 33 - counterHoursHeatpump
  $return_str .= "|". ($heatpump_visibility[87]==1 ? $heatpump_values[63] : "no");
  # 34 - counterHoursHeating
  $return_str .= "|". ($heatpump_visibility[195]==1 ? $heatpump_values[64] : "no");
  # 35 - counterHoursHotWater
  $return_str .= "|". ($heatpump_visibility[196]==1 ? $heatpump_values[65] : "no");
  # 36 - counterHeatQHeating
  $return_str .= "|". ($heatpump_visibility[0]==1 ? $heatpump_values[151] : "no");
  # 37 - counterHeatQHotWater
  $return_str .= "|". ($heatpump_visibility[1]==1 ? $heatpump_values[152] : "no");
  # 38 - counterHours2ndHeatSource2
  $return_str .= "|". ($heatpump_visibility[85]==1 ? $heatpump_values[61] : "no");
  # 39 - counterHours2ndHeatSource3
  $return_str .= "|". ($heatpump_visibility[86]==1 ? $heatpump_values[62] : "no");
  # 40 - opStateHeatPump2 
  $return_str .= "|".$heatpump_values[118];
  # 41 - opStateHeatPump2Duration
  $return_str .= "|".$heatpump_values[120];
  # 42 - timeError0
  $return_str .= "|".$heatpump_values[95];
  # 43 - bivalentLevel
  $return_str .= "|".$heatpump_values[79];
  # 44 - Number of calculated values
  $return_str .= "|".scalar(@heatpump_values);
  # 45 - Number of set parameters
  $return_str .= "|".scalar(@heatpump_parameters);
  # 46 - opStateHeating
  $return_str .= "|".$heatpump_values[125];
  # 47 - deltaHeatingReduction
  $return_str .= "|".$heatpump_parameters[13];
  # 48 - thresholdTemperatureSetBack
  $return_str .= "|".$heatpump_parameters[111];
  # 49 - hotWaterTemperatureHysterese
  $return_str .= "|".$heatpump_parameters[74];
  # 50 - solarCollectorTemperature
  $return_str .= "|". ($heatpump_visibility[36]==1 ? $heatpump_values[26] : "no");
  # 51 - solarBufferTemperature
  $return_str .= "|". ($heatpump_visibility[37]==1 ? $heatpump_values[27] : "no");
  # 52 - counterHoursSolar
  $return_str .= "|". ($heatpump_visibility[248]==1 ? $heatpump_values[161] : "no");
  # 53 - Number of visibility attributes
  $return_str .= "|".scalar(@heatpump_visibility);
  # 54 - returnTemperatureSetBack
  $return_str .= "|".$heatpump_parameters[1];
  # 55 - mixer1FlowTemperature
  $return_str .= "|". ($heatpump_visibility[31]==1 ? $heatpump_values[21] : "no");
  # 56 - mixer1TargetTemperature
  $return_str .= "|". ($heatpump_visibility[32]==1 ? $heatpump_values[22] : "no");
  # 57 - mixer2FlowTemperature
  $return_str .= "|". ($heatpump_visibility[34]==1 ? $heatpump_values[24] : "no");
  # 58 - mixer2TargetTemperature
  $return_str .= "|". ($heatpump_visibility[35]==1 ? $heatpump_values[25] : "no");
  # 59 - mixer3FlowTemperature
  $return_str .= "|". ($heatpump_visibility[210]==1 ? $heatpump_values[137] : "no");
  # 60 - mixer3TargetTemperature
  $return_str .= "|". ($heatpump_visibility[211]==1 ? $heatpump_values[136] : "no");
  # 61 - hotWaterCircPumpDeaerate
  $return_str .= "|". ($heatpump_visibility[167]==1 ? $heatpump_parameters[684] : "no");
  # 62 - counterHeatQPool
  $return_str .= "|". ($heatpump_visibility[2]==1 ? $heatpump_values[153] : "no");
  # 63 - returnTemperatureTargetMin
   $heatpump_visibility[295]=1    unless defined($heatpump_visibility[295]);
   $return_str .= "|". ($heatpump_visibility[295]==1 ? $heatpump_parameters[979] : "no");
  # 64 - heatSourceMotor
   $return_str .= "|". ($heatpump_visibility[54]==1 ? $heatpump_values[43] : "no");
  # 65 - typeSerial
  $return_str .= "|";
  $return_str .= substr($heatpump_parameters[874],0,4)."/".substr($heatpump_parameters[874],4).= "-".sprintf("%03X",$heatpump_parameters[875])
        if $heatpump_parameters[874] || $heatpump_parameters[875] ;
  # 66 - heatSourceDefrostTimer
   $return_str .= "|". ($heatpump_visibility[219]==1 ? $heatpump_values[141] : "no");
  # 67 - defrostValve
   $return_str .= "|". ($heatpump_visibility[47]==1 ? $heatpump_values[37] : "no");
  # 68 - returnTempHyst
   $return_str .= "|". ($heatpump_visibility[93]==1 ? $heatpump_parameters[88] : "no");
  # 69 - Heating curve end point
   $return_str .= "|". ($heatpump_visibility[207]==1 ? $heatpump_parameters[11] : "no");
  # 70 - Heating curve parallel offset
   $return_str .= "|". ($heatpump_visibility[207]==1 ? $heatpump_parameters[12] : "no");
  # 71 - heatSourcedefrostAirThreshold
   $return_str .= "|". ($heatpump_visibility[97]==1 ? $heatpump_parameters[44] : "no");
  # 72 - heatSourcedefrostAirEnd
   $return_str .= "|". ($heatpump_visibility[105]==1 ? $heatpump_parameters[98] : "no");
  # 73 - analogOut4 - Voltage heating system circulation pump
   $return_str .= "|". ($heatpump_visibility[267]==1 ? $heatpump_values[163] : "no");
  # 74 - solarPump
   $return_str .= "|". ($heatpump_visibility[63]==1 ? $heatpump_values[52] : "no");
  # 75 - 2ndHeatSource1
    $return_str .= "|". ($heatpump_visibility[59]==1 ? $heatpump_values[48] : "no");
  # 76 userReadings (attributs: userHeatpumpParameters and userHeatpumpValues)
    $return_str .= "|";
    $firstLoop = 1;
    my @userReadings = split /,/, AttrVal( $name, "userHeatpumpParameters", "" );
    foreach (@userReadings) {
      $return_str .= ","     unless $firstLoop;
      $firstLoop = 0;
      my ($rIndex, $rName) = split / /, trim($_);
      $rName = "userParameter$rIndex"  if $rName eq "";
      $return_str .= $rName." ".$heatpump_parameters[$rIndex];
    }
    @userReadings = split /,/, AttrVal( $name, "userHeatpumpValues", "" );
    foreach (@userReadings) {
      $return_str .= ","     unless $firstLoop;
      $firstLoop = 0;
      my ($rIndex, $rName) = split / /, trim($_);
      $rName = "userValue$rIndex"  if $rName eq "";
      $return_str .= $rName." ".$heatpump_values[$rIndex];
    }
  # 77 - VentSupplyAirTemperature
  $return_str .= "|".($heatpump_visibility[264]==1 ? $heatpump_values[159] : "no");;
  # 78 - VentExhaustAirTemperature
  $return_str .= "|".($heatpump_visibility[265]==1 ? $heatpump_values[160] : "no");;
  # 79 - opModeVentilation
  $return_str .= "|".($heatpump_visibility[4]==1 ? $heatpump_parameters[894] : "no");;
  
   return $return_str;
}

sub ########################################
LUXTRONIK2_UpdateDone($)
{
  my ($string) = @_;
  return unless(defined($string));

  my $value = "";
  my $state = "";

  my @a = split("\\|",$string);
  my $hash = $defs{$a[0]};
  my $name = $a[0];
  
  delete($hash->{helper}{RUNNING_PID});

  return if($hash->{helper}{DISABLED});

  my $cop = 0;

  LUXTRONIK2_Log $hash, 4, $string;

  #Define Status Messages
  my %wpOpStat1 = ( 0 => "Wärmepumpe läuft",
            1 => "Wärmepumpe steht",
            2 => "Wärmepumpe kommt",
            4 => "Fehler",
            5 => "Abtauen",
            6 => "Warte auf LIN-Verbindung",
            7 => "Verdichter heizt auf",
            8 => "Pumpenvorlauf" );
            
  my %wpOpStat2 = ( 0 => "Heizbetrieb",
            1 => "Keine Anforderung",
            2 => "Netz Einschaltverzögerung",
            3 => "Schaltspielzeit",
            4 => "EVU Sperrzeit",
            5 => "Brauchwasser",
            6 => "Stufe",
            7 => "Abtauen",
            8 => "Pumpenvorlauf",
            9 => "Thermische Desinfektion",
            10 => "Kühlbetrieb",
            12 => "Schwimmbad/Photovoltaik",
            13 => "Heizen_Ext_En",
            14 => "Brauchw_Ext_En",
            16 => "Durchflussüberwachung",
            17 => "Elektrische Zusatzheizung" );
            
  my %wpMode = ( 0 => "Automatik",
             1 => "Zusatzheizung",
             2 => "Party",
             3 => "Ferien",
             4 => "Aus" );
   my %heatingState = ( 0 => "Abgesenkt",
                1 => "Normal",
                3 => "Aus");
  my %wpType = ( 0 => "ERC", 1 => "SW1", 
             2 => "SW2", 3 => "WW1", 
             4 => "WW2", 5 => "L1I", 
             6 => "L2I", 7 => "L1A", 
             8 => "L2A", 9 => "KSW",
            10 => "KLW", 11 => "SWC", 
            12 => "LWC", 13 => "L2G",
            14 => "WZS", 15 => "L1I407",
            16 => "L2I407", 17 => "L1A407",
            18 => "L2A407", 19 => "L2G407",
            
            20 => "LWC407", 21 => "L1AREV", 22 => "L2AREV", 23 => "WWC1",
            24 => "WWC2",   25 => "L2G404", 26 => "WZW",    27 => "L1S",
            28 => "L1H",    29 => "L2H",    30 => "WZWD",   31 => "ERC",
            
            40 => "WWB_20",   41 => "LD5", 42 => "LD7", 43 => "SW 37_45",
            44 => "SW 58_69", 45 => "SW 29_56", 46 => "LD5 (230V)", 
            47 => "LD7 (230 V)", 48 => "LD9",   49 => "LD5 REV",
            
            50 => "LD7 REV", 51 => "LD5 REV 230V",
            52 => "LD7 REV 230V", 53 => "LD9 REV 230V",
            54 => "SW 291", 55 => "LW SEC",  56 => "HMD 2",   57 => "MSW 4",
            58 => "MSW 6",   59 => "MSW 8",  60 => "MSW 10",  61 => "MSW 12",
            62 => "MSW 14",  63 => "MSW 17", 64 => "MSW 19",  65 => "MSW 23",
            66 => "MSW 26",  67 => "MSW 30", 68 => "MSW 4S",  69 => "MSW 6S",
            
            70 => "MSW 8S",  71 => "MSW 10S",72 => "MSW 13S", 73 => "MSW 16S",
            74 => "MSW2-6S", 75 => "MSW4-16",76 => "LD2AG",   77 => "LWD90V",
            78 => "MSW3-12", 79 => "MSW3-12S");

   my %ventMode = ( 0 => "Automatik",
                    1 => "Party",
                    2 => "Feuchteschutz",
                    3 => "Aus");
             
  my $counterRetry = $hash->{fhem}{counterRetry};
  $counterRetry++;    

  my $doStatistic = AttrVal($name,"doStatistics",0);

# Error
  if ($a[1]==0 ) {
     readingsSingleUpdate($hash,"state","Error: ".$a[2],1);
    $counterRetry = 0;
    if ( $hash->{fhem}{portDefined} == 0 ) {
      if ($hash->{PORT} == 8888 ) {
         $hash->{PORT} = 8889;
         LUXTRONIK2_Log $name, 3, "Error when using port 8888. Changed port to 8889";
      }
      elsif ($hash->{PORT} == 8889 ) {
         $hash->{PORT} = 8888;
         LUXTRONIK2_Log $name, 3, "Error when using port 8889. Changed port to 8888";
      }
    }
  }
# Busy, restart update
  elsif ($a[1]==2 )  {
     if ($counterRetry <=3) {
      InternalTimer(gettimeofday() + 5, "LUXTRONIK2_GetUpdate", $hash, 0);
     }
    else {
       readingsSingleUpdate($hash,"state","Error: Reading skipped after $counterRetry tries",1);
      LUXTRONIK2_Log $hash, 2, "Device readout skipped after $counterRetry tries with parameter change on target";
    }
  }
# Update readings
  elsif ($a[1]==1 )  {
    $counterRetry = 0;  

   readingsBeginUpdate($hash);

    # Temporary storage of values because needed several times
   my $ambientTemperature = LUXTRONIK2_CalcTemp($a[12]);
   my $averageAmbientTemperature = LUXTRONIK2_CalcTemp($a[13]);
   my $hotWaterTemperature = LUXTRONIK2_CalcTemp($a[14]);
   my $hotWaterTemperatureTarget = LUXTRONIK2_CalcTemp($a[25]);
   my $hotWaterTemperatureThreshold = LUXTRONIK2_CalcTemp($a[25] - $a[49]);
   my $heatSourceIN = LUXTRONIK2_CalcTemp($a[23]);
   my $heatSourceOUT = LUXTRONIK2_CalcTemp($a[24]);
   my $thresholdHeatingLimit = LUXTRONIK2_CalcTemp($a[21]);
   my $thresholdTemperatureSetBack = LUXTRONIK2_CalcTemp($a[48]);
   my $flowTemperature = LUXTRONIK2_CalcTemp($a[15]);
   my $returnTemperature = LUXTRONIK2_CalcTemp($a[16]);
   my $returnTemperatureTarget = LUXTRONIK2_CalcTemp($a[17]);
   my $returnTempHyst = LUXTRONIK2_CalcTemp($a[68]);
   my $returnTemperatureTargetMin = ($a[63] eq "no"?15:LUXTRONIK2_CalcTemp($a[63]) );
   my $compressor1 = $a[6]; #Ausgang Verdichter 1
   my $heatSourceMotor = $a[64]; #Ausgang Ventilator_BOSUP
   my $defrostValve = $a[67]; #AVout
   my $hotWaterBoilerValve = $a[9]; #BUP
   my $heatingSystemCircPump = $a[27]; #HUP
   my $opStateHeatPump3 = $a[3];
   my $analogOut4 = $a[73]; #Voltage heating system circulation pump
   my $flowRate = $a[19]; # flow rate
   # skips inconsistent flow rates (known problem of the used flow measurement devices)
   if ($flowRate !~ /no/ && $heatingSystemCircPump) {
      $flowRate = "inconsistent" if $flowRate == 0;
   } 
   
   my $heatPumpPower = 0;
   my $heatRodPower = AttrVal($name, "heatRodElectricalPowerWatt", 0);

   #WM[kW] = delta_Temp [K] * Durchfluss [l/h] / ( 3.600 [kJ/kWh] / ( 4,179 [kJ/(kg*K)] (H2O Wärmekapazität bei 30 & 40°C) * 0,994 [kg/l] (H2O Dichte bei 35°C) )  
   my $thermalPower = 0;
   # 0=Heizen, 5=Brauchwasser, 7=Abtauen, 16=Durchflussüberwachung 
   if ($opStateHeatPump3 =~ /^(0|5|16)$/) { 
      if ($flowRate !~ /no|inconsistent/) { $thermalPower = abs($flowTemperature - $returnTemperature) * $flowRate / 866.65; } #Nur bei Wärmezählern
      $heatPumpPower = AttrVal($name, "heatPumpElectricalPowerWatt", -1);
      $heatPumpPower *= (1 + ($flowTemperature-35) * AttrVal($name, "heatPumpElectricalPowerFactor", 0));
   }
   if ($flowRate !~ /no|inconsistent/) { readingsBulkUpdate( $hash, "thermalPower", sprintf "%.1f", $thermalPower); } #Nur bei Wärmezählern
   if ($heatPumpPower >-1 ) {    readingsBulkUpdate( $hash, "heatPumpElectricalPowerEstimated", sprintf "%.0f", $heatPumpPower); }
   if ($heatPumpPower > 0 && $flowRate !~ /no|inconsistent/) { #Nur bei Wärmezählern
     $cop = $thermalPower * 1000 / $heatPumpPower;
     readingsBulkUpdate( $hash, "COP", sprintf "%.2f", $cop);
   }

   
   # if attribute doStatistic = 1 do all the statistic calculations
   # if attribute doStatistic = 2 do only those statistic calculations not included in FHEM Module statistics
   if ( $doStatistic == 1) { 
    # LUXTRONIK2_doStatisticMinMax $hash, $readingName, $value
     LUXTRONIK2_doStatisticMinMax ( $hash, "statAmbientTemp", $ambientTemperature);
   }
   if ( $doStatistic >= 1) { 
      #LUXTRONIK2_doStatisticBoilerHeatUp $hash, $currOpHours, $currHQ, $currTemp, $opState, $target
      $value = LUXTRONIK2_doStatisticBoilerHeatUp ($hash, $a[35], $a[37]/10, $hotWaterTemperature, $opStateHeatPump3,$hotWaterTemperatureTarget);
      if ($value ne "") {
         readingsBulkUpdate($hash,"statBoilerGradientHeatUp",$value); 
         LUXTRONIK2_Log $name, 3, "statBoilerGradientHeatUp set to $value";
      }

      #LUXTRONIK2_doStatisticBoilerCoolDown $hash, $time, $currTemp, $opState, $target, $threshold
      $value = LUXTRONIK2_doStatisticBoilerCoolDown ($hash, $a[22], $hotWaterTemperature, $opStateHeatPump3, $hotWaterTemperatureTarget, $hotWaterTemperatureThreshold);
      if ($value ne "") {
         readingsBulkUpdate($hash,"statBoilerGradientCoolDown",$value); 
         LUXTRONIK2_Log $name, 3, "statBoilerGradientCoolDown set to $value";
         my @new = split / /, $value;
         if ( exists( $hash->{READINGS}{statBoilerGradientCoolDownMin} ) ) {
            my @old = split / /, $hash->{READINGS}{statBoilerGradientCoolDownMin}{VAL};
            if ($new[5]>6 && $new[1]>$old[1] && $new[1] < 0) {
               readingsBulkUpdate($hash,"statBoilerGradientCoolDownMin",$value,1); 
               LUXTRONIK2_Log $name, 3, "statBoilerGradientCoolDownMin set to '$value'";
            }
         } elsif ($new[5]>6 && $new[1] < 0) {
            readingsBulkUpdate($hash,"statBoilerGradientCoolDownMin",$value,1); 
            LUXTRONIK2_Log $name, 3, "statBoilerGradientCoolDownMin set to '$value'";
         }
      }

      # LUXTRONIK2_doStatisticThermalPower: $hash, $MonitoredOpState, $currOpState, $currHeatQuantity, $currOpHours,  $currAmbTemp, $currHeatSourceIn, $TargetTemp, $electricalPower
      $value = LUXTRONIK2_doStatisticThermalPower ($hash, 5, $opStateHeatPump3, $a[37]/10, $a[35], $ambientTemperature, $heatSourceIN,$hotWaterTemperatureTarget, $heatPumpPower);
      if ($value ne "") { readingsBulkUpdate($hash,"statThermalPowerBoiler",$value); }
      $value = LUXTRONIK2_doStatisticThermalPower ($hash, 0, $opStateHeatPump3, $a[36]/10, $a[34], $ambientTemperature, $heatSourceIN, $returnTemperatureTarget, $heatPumpPower);
      if ($value ne "") { readingsBulkUpdate($hash,"statThermalPowerHeating",$value); }
   }
  #Operating status of heat pump
     my $opStateHeatPump1 = $wpOpStat1{$a[2]}; ##############
      $opStateHeatPump1 = "unbekannt (".$a[2].")" unless $opStateHeatPump1;
     readingsBulkUpdate($hash,"opStateHeatPump1",$opStateHeatPump1);
     
     my $opStateHeatPump2 = "unknown ($a[40])"; ##############
     my $prefix = "";
     if ($a[40] == 0 || $a[40] == 2) { $prefix = "seit ";}
     elsif ($a[40] == 1) { $prefix = "in ";}
     if ($a[40] == 2) { #Sonderbehandlung bei WP-Fehlern
       $opStateHeatPump2 = $prefix . strftime "%d.%m.%Y %H:%M:%S", localtime($a[42]);
     } 
     else {
       $opStateHeatPump2 = $prefix . LUXTRONIK2_FormatDuration($a[41]);
     }
     readingsBulkUpdate($hash,"opStateHeatPump2",$opStateHeatPump2);
     
     my $opStateHeatPump3Txt = $wpOpStat2{$opStateHeatPump3}; ##############
     # refine text of third state
     if ($opStateHeatPump3==6) { 
        $opStateHeatPump3Txt = "Stufe ".$a[4]." ".LUXTRONIK2_CalcTemp($a[5])." C "; 
     }
      elsif ($opStateHeatPump3==7) { 
         if ( $defrostValve==1 ) {$opStateHeatPump3Txt = "Abtauen (Kreisumkehr)";}
         elsif ( $compressor1==0 && $heatSourceMotor==1 ) {$opStateHeatPump3Txt = "Luftabtauen";}
         else {$opStateHeatPump3Txt = "Abtauen";}
      }
      $opStateHeatPump3Txt = "unbekannt (".$opStateHeatPump3.")" unless $opStateHeatPump3Txt;
     readingsBulkUpdate($hash,"opStateHeatPump3",$opStateHeatPump3Txt);
   
   # Hot water operating mode 
     $value = $wpMode{$a[7]};
     $value = "unbekannt (".$a[7].")" unless $value;
     readingsBulkUpdate($hash,"opModeHotWater",$value);
   # opStateHotWater
     if ($a[8]==0) {$value="Sperrzeit";}
      elsif ($a[8]==1 && $hotWaterBoilerValve==1) {$value="Aufheizen";}
      elsif ($a[8]==1 && $hotWaterBoilerValve==0) {$value="Temp. OK";}
     elsif ($a[8]==3) {$value="Aus";}
      else {$value = "unbekannt (".$a[8]."/".$hotWaterBoilerValve.")";}
     readingsBulkUpdate($hash,"opStateHotWater",$value);

    # Heating operating mode
     $value = $wpMode{$a[10]};
     $value = "unbekannt (".$a[10].")" unless $value;
     readingsBulkUpdate($hash,"opModeHeating",$value);
   # Heating operating state
     # Consider also heating limit
     if ($a[10] == 0 && $a[11] == 1
        && $averageAmbientTemperature >= $thresholdHeatingLimit 
        && ($returnTemperatureTarget eq $returnTemperatureTargetMin || $returnTemperatureTarget == 20 && $ambientTemperature<10)
        ) {
        if ($ambientTemperature>=10 ) {
          $value = "Heizgrenze (Soll ".$returnTemperatureTargetMin."°C)";
        } 
        else {
          $value = "Frostschutz (Soll 20°C)";
        }
     }
     else {
       $value = $heatingState{$a[46]};
      $value = "unbekannt (".$a[46].")" unless $value;
     # Consider heating reduction limit
      if ($a[46] == 0) {
        if ($thresholdTemperatureSetBack <= $ambientTemperature) { 
          $value .= " ".LUXTRONIK2_CalcTemp($a[47])."°C"; #° &deg; &#176; &#x00B0; 
        }
        else {
          $value = "Normal da < ".$thresholdTemperatureSetBack."°C"; 
        }
      }
    }
    readingsBulkUpdate($hash,"opStateHeating",$value);

   # Ventilation operating mode
     if ( $a[79] !~ /no/ ) {
       $value = $ventMode{$a[79]};
       $value = "unbekannt (".$a[79].")" unless $value;
       readingsBulkUpdate($hash,"opModeVentilation",$value);
     } 
     
   # Defrost times
      if ($compressor1 != $heatSourceMotor) {
         if ($hash->{fhem}{defrost}{mode} eq "none") {
            $hash->{fhem}{defrost}{startTime} = time();
            $hash->{fhem}{defrost}{mode} = "air"         if $heatSourceMotor;
            $hash->{fhem}{defrost}{mode} = "reverse"     unless $heatSourceMotor;
            $hash->{fhem}{defrost}{ambStart} = $ambientTemperature;
            $hash->{fhem}{defrost}{hsInStart} = $heatSourceIN;
            $hash->{fhem}{defrost}{hsOutStart} = $heatSourceOUT;
         }
         $hash->{fhem}{defrost}{amb} = $ambientTemperature;
         $hash->{fhem}{defrost}{hsIn} = $heatSourceIN;
         $hash->{fhem}{defrost}{hsOut} = $heatSourceOUT;
      } 
   # Defrost-Readings creation
      elsif ( $hash->{fhem}{defrost}{mode} ne "none" ) {
         my $value = "Mode: " . $hash->{fhem}{defrost}{mode} . " Time: ";
         $value .=  strftime ( "%M:%S", localtime( time() - $hash->{fhem}{defrost}{startTime} ) ); 
         $value .= " Amb: ".$hash->{fhem}{defrost}{ambStart} . " - ". $hash->{fhem}{defrost}{amb};
         $value .= " hsIN: ".$hash->{fhem}{defrost}{hsInStart} . " - ". $hash->{fhem}{defrost}{hsIn};
         #$value .= " hsOUT: ".$hash->{fhem}{defrost}{hsOutStart} . " - ". $heatSourceOUT;
         readingsBulkUpdate( $hash, "heatSourceDefrostLast", $value);

         my $rName = "heatSourceDefrostCounter";
         $rName .= "Air"   if $hash->{fhem}{defrost}{mode} eq "air";
         $rName .= "Reverse"   if $hash->{fhem}{defrost}{mode} eq "reverse";
         my $rValue = ReadingsVal ( $name, $rName, 0 ) + 1;
         readingsBulkUpdate ( $hash, $rName, 0 )      if $rValue == 1; #for statistics module
         readingsBulkUpdate ( $hash, $rName, $rValue );

         $hash->{fhem}{defrost}{mode} = "none";

         #  16 => "Durchflussüberwachung"
         if ($opStateHeatPump3 == 16) { 
            readingsBulkUpdate( $hash, "heatSourceDefrostLastTimeout", "Amb: ".$hash->{fhem}{defrost}{amb}." hsIN: ".$hash->{fhem}{defrost}{hsIn}." hsOUT: ".$hash->{fhem}{defrost}{hsOut});
         }
      }
      
   # Determine last real heatings system return temperature, circulation needs to run at least 3 min or has been stopped less than 2 min ago
     $hash->{fhem}{hotWaterLastRun} = time()     if $hotWaterBoilerValve;
     $hash->{fhem}{heatingPumpLastStop} = time()     if !$heatingSystemCircPump;
     $hash->{fhem}{heatingPumpLastRun} = time()     if $heatingSystemCircPump;
     readingsBulkUpdate( $hash, "returnTemperatureHeating", $returnTemperature)
         if ( $heatingSystemCircPump && !$hotWaterBoilerValve 
              && time() - $hash->{fhem}{hotWaterLastRun} >= 180 
              && time() - $hash->{fhem}{heatingPumpLastStop} >= 120);
#           || ( !$heatingSystemCircPump && !$hotWaterBoilerValve 
#              && time() - $hash->{fhem}{hotWaterLastRun} >= 180 
#              && time() - $hash->{fhem}{heatingPumpLastRun} < $hash->{INTERVAL}+10);
      
   # Device and reading times, delays and durations
     $value = strftime "%Y-%m-%d %H:%M:%S", localtime($a[22]);
     readingsBulkUpdate($hash, "deviceTimeCalc", $value);
     my $delayDeviceTimeCalc=sprintf("%.0f",$a[29]-$a[22]);
     readingsBulkUpdate($hash, "delayDeviceTimeCalc", $delayDeviceTimeCalc);
     my $durationFetchReadings = sprintf("%.3f",$a[30]-$a[29]);
     readingsBulkUpdate($hash, "durationFetchReadings", $durationFetchReadings);
     #Remember min and max reading durations, will be reset when initializing the device
     if ($hash->{fhem}{durationFetchReadingsMin} == 0 || $hash->{fhem}{durationFetchReadingsMin} > $durationFetchReadings) {
      $hash->{fhem}{durationFetchReadingsMin} = $durationFetchReadings;
     } 
     if ($hash->{fhem}{durationFetchReadingsMax} < $durationFetchReadings) {
      $hash->{fhem}{durationFetchReadingsMax} = $durationFetchReadings;
     }
   
   # Temperatures and flow rate
     readingsBulkUpdate( $hash, "ambientTemperature", $ambientTemperature);
     readingsBulkUpdate( $hash, "averageAmbientTemperature", $averageAmbientTemperature);
     readingsBulkUpdate( $hash, "heatingLimit",$a[11]?"on":"off");
     readingsBulkUpdate( $hash, "thresholdHeatingLimit", $thresholdHeatingLimit);
     readingsBulkUpdate( $hash, "thresholdTemperatureSetBack", $thresholdTemperatureSetBack); 
     if ($a[69] !~ /no/) {readingsBulkUpdate( $hash, "heatingCurveEndPoint",LUXTRONIK2_CalcTemp($a[69]));}
     if ($a[70] !~ /no/) {readingsBulkUpdate( $hash, "heatingCurveOffset",LUXTRONIK2_CalcTemp($a[70]));}
     readingsBulkUpdate( $hash, "hotWaterTemperature", $hotWaterTemperature);
     readingsBulkUpdate( $hash, "hotWaterTemperatureTarget",$hotWaterTemperatureTarget);
     readingsBulkUpdate( $hash, "flowTemperature", $flowTemperature);
     readingsBulkUpdate( $hash, "returnTemperature", $returnTemperature);
     readingsBulkUpdate( $hash, "returnTemperatureTarget", $returnTemperatureTarget);
     readingsBulkUpdate( $hash, "returnTemperatureHyst", $returnTempHyst);
     readingsBulkUpdate( $hash, "returnTemperatureSetBack",LUXTRONIK2_CalcTemp($a[54]));
     if ($a[18] !~ /no/) {readingsBulkUpdate( $hash, "returnTemperatureExtern",LUXTRONIK2_CalcTemp($a[18]));}
     if ($analogOut4 !~ /no/) {readingsBulkUpdate( $hash, "heatingSystemCircPumpVoltage", $analogOut4/100);}
     if ($flowRate !~ /no|inconsistent/ ) { readingsBulkUpdate( $hash, "flowRate",$flowRate); }
     readingsBulkUpdate( $hash, "heatSourceIN", $heatSourceIN );
     readingsBulkUpdate( $hash, "heatSourceOUT", $heatSourceOUT );
     readingsBulkUpdate( $hash, "heatSourceMotor", $heatSourceMotor?"on":"off");
     if ($a[71] !~ /no/) {readingsBulkUpdate( $hash, "heatSourceDefrostAirThreshold",LUXTRONIK2_CalcTemp($a[71]));}
     if ($a[72] !~ /no/) {readingsBulkUpdate( $hash, "heatSourceDefrostAirEnd",LUXTRONIK2_CalcTemp($a[72]));}
     if ($a[66] !~ /no/) {readingsBulkUpdate( $hash, "heatSourceDefrostTimer",$a[66]);}
     readingsBulkUpdate( $hash, "compressor1",$compressor1?"on":"off");
     readingsBulkUpdate( $hash, "hotGasTemperature",LUXTRONIK2_CalcTemp($a[26]));
     if ($a[55] !~ /no/) {readingsBulkUpdate( $hash, "mixer1FlowTemperature",LUXTRONIK2_CalcTemp($a[55]));}
     if ($a[56] !~ /no/) {readingsBulkUpdate( $hash, "mixer1TargetTemperature",LUXTRONIK2_CalcTemp($a[56]));}
     if ($a[57] !~ /no/) {readingsBulkUpdate( $hash, "mixer2FlowTemperature",LUXTRONIK2_CalcTemp($a[57]));}
     if ($a[58] !~ /no/) {readingsBulkUpdate( $hash, "mixer2TargetTemperature",LUXTRONIK2_CalcTemp($a[58]));}
     if ($a[59] !~ /no/) {readingsBulkUpdate( $hash, "mixer3FlowTemperature",LUXTRONIK2_CalcTemp($a[59]));}
     if ($a[60] !~ /no/) {readingsBulkUpdate( $hash, "mixer3TargetTemperature",LUXTRONIK2_CalcTemp($a[60]));}
     if ($a[77] !~ /no/) {readingsBulkUpdate( $hash, "ventSupplyAirTemperature",LUXTRONIK2_CalcTemp($a[77]));}
     if ($a[78] !~ /no/) {readingsBulkUpdate( $hash, "ventExhaustAirTemperature",LUXTRONIK2_CalcTemp($a[78]));}

    # Operating hours (seconds->hours) and heat quantities   
     # LUXTRONIK2_storeReadings: $hash, $readingName, $value, $factor, $doStatistic, $electricalPower
     LUXTRONIK2_storeReadings $hash, "counterHours2ndHeatSource1", $a[32], 3600, $doStatistic, $heatRodPower;
     LUXTRONIK2_storeReadings $hash, "counterHours2ndHeatSource2", $a[38], 3600, $doStatistic, $heatRodPower;
     LUXTRONIK2_storeReadings $hash, "counterHours2ndHeatSource3", $a[39], 3600, $doStatistic, $heatRodPower;
     LUXTRONIK2_storeReadings $hash, "counterHoursHeatPump", $a[33], 3600, $doStatistic, $heatPumpPower;
     LUXTRONIK2_storeReadings $hash, "counterHoursHeating", $a[34], 3600, $doStatistic, $heatPumpPower;
     LUXTRONIK2_storeReadings $hash, "counterHoursHotWater", $a[35], 3600, $doStatistic, $heatPumpPower;
     my $heatQTotal = 0 ; 
     if ($a[36] !~ /no/) {
         LUXTRONIK2_storeReadings $hash, "counterHeatQHeating", $a[36], 10, ($flowRate !~ /no/ ? $doStatistic : 0), -1; 
         $heatQTotal += $a[36];
      }
     if ($a[37] !~ /no/) { 
         LUXTRONIK2_storeReadings $hash, "counterHeatQHotWater", $a[37], 10, ($flowRate !~ /no/ ? $doStatistic : 0), -1; 
         $heatQTotal += $a[37];
     }
     if ($a[62] !~ /no/) { 
         LUXTRONIK2_storeReadings $hash, "counterHeatQPool", $a[62], 10, ($flowRate !~ /no/ ? $doStatistic : 0), -1; 
         $heatQTotal += $a[62];
     }
     LUXTRONIK2_storeReadings $hash, "counterHeatQTotal", $heatQTotal, 10, ($flowRate !~ /no/ ? $doStatistic : 0), -1;
      
     
   # Input / Output status
     readingsBulkUpdate($hash,"heatingSystemCircPump",$heatingSystemCircPump?"on":"off");
     readingsBulkUpdate($hash,"hotWaterCircPumpExtern",$a[28]?"on":"off");
     readingsBulkUpdate($hash,"hotWaterSwitchingValve",$hotWaterBoilerValve?"on":"off");
     if ($a[74] !~ /no/) { readingsBulkUpdate($hash,"solarPump",$a[74]?"on":"off"); }
     if ($a[75] !~ /no/) { readingsBulkUpdate($hash,"2ndHeatSource1",$a[75]?"on":"off"); }
     
   # Deaerate Function
     readingsBulkUpdate( $hash, "hotWaterCircPumpDeaerate",$a[61]?"on":"off")    unless $a[61] eq "no";

   # bivalentLevel
     readingsBulkUpdate($hash,"bivalentLevel",$a[43]);
     
   # Firmware
     my $firmware = $a[20];
     readingsBulkUpdate($hash,"firmware",$firmware);
     my $firmwareCheck = LUXTRONIK2_checkFirmware($firmware);
     # if unknown firmware, ask at each startup to inform community
     if ($hash->{fhem}{alertFirmware} != 1 && $firmwareCheck eq "fwNotTested") {
      $hash->{fhem}{alertFirmware} = 1;
      LUXTRONIK2_Log $hash, 2, "Alert: Host uses untested Firmware '$a[20]'. Please inform FHEM community about compatibility.";
     }
     
   # Type of Heatpump  
     $value = $wpType{$a[31]};
     $value = "unbekannt (".$a[31].")" unless $value;
     readingsBulkUpdate($hash,"typeHeatpump",$value);
     $hash->{MODEL} = $value;
     readingsBulkUpdate($hash,"typeSerial",$a[65])       if $a[65] ne "";

   # Solar
     if ($a[50] !~ /no/) {readingsBulkUpdate($hash, "solarCollectorTemperature", LUXTRONIK2_CalcTemp($a[50]));}
     if ($a[51] !~ /no/) {readingsBulkUpdate($hash, "solarBufferTemperature", LUXTRONIK2_CalcTemp($a[51]));}
     if ($a[52] !~ /no/) {readingsBulkUpdate($hash, "counterHoursSolar", sprintf("%.1f", $a[52]/3600));}
     
   # HTML for floorplan
     if(AttrVal($name, "statusHTML", "none") ne "none") {
        $value = ""; #"<div class=fp_" . $a[0] . "_title>" . $a[0] . "</div> \n";
        $value .= "$opStateHeatPump1<br>\n";
        $value .= "$opStateHeatPump2<br>\n";
        $value .= "$opStateHeatPump3Txt<br>\n";
        $value .= "Brauchwasser: ".$hotWaterTemperature."°C";
        readingsBulkUpdate($hash,"floorplanHTML",$value);
     }
    # State update
      $value = "$opStateHeatPump1 $opStateHeatPump2 - $opStateHeatPump3Txt";
      if ($thermalPower != 0) { 
         $value .= sprintf (" (%.1f kW", $thermalPower);
         if ($heatPumpPower>0) {$value .= sprintf (", COP: %.2f", $cop);}
         $value .= ")"; }
      readingsBulkUpdate($hash, "state", $value);
     
    # Special readings
      # $compressor1 = $a[6]; #Ausgang Verdichter 1
      # $heatSourceMotor = $a[64]; #Ausgang Ventilator_BOSUP
      # $defrostValve = $a[67]; #AVout
      # $hotWaterBoilerValve = $a[9]; #BUP
      # $heatingSystemCircPump = $a[27]; #HUP
      # 0=Heizen, 1=keine Anforderung, 3=Schaltspielzeit, 5=Brauchwasser, 7=Abtauen, 16=Durchflussüberwachung
      my $lastHeatingCycle = ReadingsVal($name, "heatingCycle", "");
      if ( $opStateHeatPump3 == 0 ) {
         readingsBulkUpdate($hash, "heatingCycle", "running");
      }
      elsif ( $opStateHeatPump3 > 1 && $lastHeatingCycle eq "running") {
         readingsBulkUpdate($hash, "heatingCycle", "paused");
      }
      elsif ( $opStateHeatPump3 == 1 && $lastHeatingCycle eq "running") {
         readingsBulkUpdate($hash, "heatingCycle", "finished");
      }
      elsif ( $opStateHeatPump3 =~ /1|3/ && $lastHeatingCycle ne "finished" && $returnTemperature-$returnTemperatureTarget >= $returnTempHyst ) {
         readingsBulkUpdate($hash, "heatingCycle", "finished");
      }
      elsif ( $opStateHeatPump3 == 1 && $lastHeatingCycle eq "paused") { 
         readingsBulkUpdate($hash, "heatingCycle", "discontinued"); 
      }
         
      # 76 userHeatpumpParameters
      if (defined $a[76]) {
        my @userReadings = split /,/, $a[76];
        foreach (@userReadings) {
          my( $rName, $rValue) = split / /, $_;
          readingsBulkUpdate($hash, $rName, $rValue);
        }
      }
          
     readingsEndUpdate($hash,1);
     
     $hash->{helper}{fetched_calc_values} = $a[44];
     $hash->{helper}{fetched_parameters} = $a[45];
     $hash->{helper}{fetched_visib_attr} = $a[53];
     
   ############################ 
   #Auto Synchronize Device Clock
     my $autoSynchClock = AttrVal($name, "autoSynchClock", 0);
     $autoSynchClock = 10 unless ($autoSynchClock >= 10 || $autoSynchClock == 0);
     $autoSynchClock = 600 unless $autoSynchClock <= 600;
     if ($autoSynchClock != 0 and abs($delayDeviceTimeCalc) > $autoSynchClock ) {
      LUXTRONIK2_Log $name, 3, "autoSynchClock triggered (delayDeviceTimeCalc ".abs($delayDeviceTimeCalc)." > $autoSynchClock).";
      # Firmware not tested and Firmware Check not ignored
       if ($firmwareCheck eq "fwNotTested" && AttrVal($name, "ignoreFirmwareCheck", 0)!= 1) {
         LUXTRONIK2_Log $name, 1, "Host firmware '$firmware' not tested for clock synchronization. To test set 'ignoreFirmwareCheck' to 1.";
          $attr{$name}{autoSynchClock} = 0;
         LUXTRONIK2_Log $name, 3, "Attribute 'autoSynchClock' set to 0.";
      #Firmware not compatible
       } elsif ($firmwareCheck eq "fwNotCompatible") {
         LUXTRONIK2_Log $name, 1, "Host firmware '$firmware' not compatible for host clock synchronization.";
          $attr{$name}{autoSynchClock} = 0;
         LUXTRONIK2_Log $name, 3, "Attribute 'autoSynchClock' set to 0.";
      #Firmware OK -> Synchronize Clock
       } else {
         $value = LUXTRONIK2_synchronizeClock($hash, 600);
         LUXTRONIK2_Log $hash, 3, $value;
       }
     }
   #End of Auto Synchronize Device Clock
     ############################ 
   }
   else {
      LUXTRONIK2_Log $hash, 5, "Status = $a[1]";
   }
    $hash->{fhem}{counterRetry} = $counterRetry;
}

sub ########################################
LUXTRONIK2_UpdateAborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  my $name = $hash->{NAME};
  my $host = $hash->{HOST};
  LUXTRONIK2_Log $hash, 1, "Timeout when connecting to host $host";
}

########################################
sub LUXTRONIK2_ReadData($)
{
  my ($name) = @_;
  my $hash = $defs{$name};
  my $host = $hash->{HOST};
  my $port = $hash->{PORT};
  my @heatpump_values;
  my @heatpump_parameters;
  my @heatpump_visibility;
  my $count=0;
  my $result="";
  my $readingStartTime = time();
  
  LUXTRONIK2_Log $name, 5, "Opening connection to $host:$port";
  my $socket = new IO::Socket::INET (  
                  PeerAddr => $host, 
                  PeerPort => $port,
                   #   Type = SOCK_STREAM, # probably needed on some systems
                   Proto => 'tcp'
      );
  if (!$socket) {
      LUXTRONIK2_Log $name, 1, "Could not open connection to host $host:$port";
      return (0, "Can't connect to $host:$port");
  }
  $socket->autoflush(1);
  
############################ 
#Fetch operational values (FOV)
############################ 
  LUXTRONIK2_Log $name, 5, "Ask host for operational values";
  $socket->send( pack( "N2", (3004,0) ) );

  LUXTRONIK2_Log $name, 5, "Start to receive operational values";
 #(FOV) read first 4 bytes of response -> should be request_echo = 3004
  $socket->recv( $result,4, MSG_WAITALL );
  $count = unpack("N", $result);
  if($count != 3004) {
      LUXTRONIK2_Log $name, 2, "Fetching operational values - wrong echo of request 3004: ".length($result)." -> ".$count;
       $socket->close();
      return (0, "3004 != $count");
  }
 
 #(FOV) read next 4 bytes of response -> should be status = 0
  $socket->recv($result,4, MSG_WAITALL );
  $count = unpack("N", $result);
  if($count > 0) {
      LUXTRONIK2_Log $name, 4, "Parameter on target changed, restart parameter reading after 5 seconds";
     $socket->close();
      return (2, "Status = $count - parameter on target changed, restart device reading after 5 seconds");
  }
  
 #(FOV) read next 4 bytes of response -> should be count_calc_values > 0
  $socket->recv($result,4, MSG_WAITALL );
  my $count_calc_values = unpack("N", $result);
  if($count_calc_values == 0) {
      LUXTRONIK2_Log $name, 2, "Fetching operational values - 0 values announced: ".length($result)." -> ".$count_calc_values;
     $socket->close();
      return (0, "0 values read");
  }
  
 #(FOV) read remaining response -> should be previous number of parameters
  $socket->recv( $result, $count_calc_values*4, MSG_WAITALL ); 
  if( length($result) != $count_calc_values*4 ) {
      LUXTRONIK2_Log $name, 1, "Operational values length check: ".length($result)." should have been ". $count_calc_values * 4;
      $socket->close();
      return (0, "Number of values read mismatch ( $!)\n");
  }
  
 #(FOV) unpack response in array
  @heatpump_values = unpack("N$count_calc_values", $result);
  if(scalar(@heatpump_values) != $count_calc_values) {
      LUXTRONIK2_Log $name, 2, "Unpacking problem by operation values: ".scalar(@heatpump_values)." instead of ".$count_calc_values;
      $socket->close();
      return (0, "Unpacking problem of operational values");
  }

  LUXTRONIK2_Log $name, 5, "$count_calc_values operational values received";
 
############################ 
#Fetch set parameters (FSP)
############################ 
  LUXTRONIK2_Log $name, 5, "Ask host for set parameters";
  $socket->send( pack( "N2", (3003,0) ) );

  LUXTRONIK2_Log $name, 5, "Start to receive set parameters";
 #(FSP) read first 4 bytes of response -> should be request_echo=3003
  $socket->recv($result,4, MSG_WAITALL );
  $count = unpack("N", $result);
  if($count != 3003) {
      LUXTRONIK2_Log $name, 2, "Wrong echo of request 3003: ".length($result)." -> ".$count;
      $socket->close();
      return (0, "3003 != 3003");
  }
  
 #(FSP) read next 4 bytes of response -> should be number_of_parameters > 0
  $socket->recv($result,4, MSG_WAITALL );
  my $count_set_parameter = unpack("N", $result);
  if($count_set_parameter == 0) {
      LUXTRONIK2_Log $name, 2, "0 parameter read: ".length($result)." -> ".$count_set_parameter;
     $socket->close();
      return (0, "0 parameter read");
  }
  
 #(FSP) read remaining response -> should be previous number of parameters
   $socket->recv( $result, $count_set_parameter*4, MSG_WAITALL ); 

  if( length($result) != $count_set_parameter*4 ) {
     LUXTRONIK2_Log $name, 1, "Parameter length check: ".length($result)." should have been ". ($count_set_parameter * 4);
     $socket->close();
      return (0, "Number of parameters read mismatch ( $!)\n");
  }

  @heatpump_parameters = unpack("N$count_set_parameter", $result);
  if(scalar(@heatpump_parameters) != $count_set_parameter) {
      LUXTRONIK2_Log $name, 2, "Unpacking problem by set parameter: ".scalar(@heatpump_parameters)." instead of ".$count_set_parameter;
     $socket->close();
      return (0, "Unpacking problem of set parameters");
  }

  LUXTRONIK2_Log $name, 5, "$count_set_parameter set values received";

############################ 
#Fetch Visibility Attributes (FVA)
############################ 
  LUXTRONIK2_Log $name, 5, "Ask host for visibility attributes";
  $socket->send( pack( "N2", (3005,0) ) );

  LUXTRONIK2_Log $name, 5, "Start to receive visibility attributes";
 #(FVA) read first 4 bytes of response -> should be request_echo=3005
  $socket->recv($result,4, MSG_WAITALL );
  $count = unpack("N", $result);
  if($count != 3005) {
      LUXTRONIK2_Log $name, 2, "Wrong echo of request 3005: ".length($result)." -> ".$count;
      $socket->close();
      return (0, "3005 != $count");
  }
  
 #(FVA) read next 4 bytes of response -> should be number_of_Visibility_Attributes > 0
  $socket->recv($result,4, MSG_WAITALL );
  my $countVisibAttr = unpack("N", $result);
  if($countVisibAttr == 0) {
      LUXTRONIK2_Log $name, 2, "0 visibility attributes announced: ".length($result)." -> ".$countVisibAttr;
      $socket->close();
      return (0, "0 visibility attributes announced");
  }
  
 #(FVA) read remaining response bytewise -> should be previous number of parameters
  $socket->recv( $result, $countVisibAttr, MSG_WAITALL ); 
   if( length( $result ) != $countVisibAttr ) {
      LUXTRONIK2_Log $name, 1, "Visibility attributes length check: ".length($result)." should have been ". $countVisibAttr;
      $socket->close();
      return (0, "Number of Visibility attributes read mismatch ( $!)\n");
   }

  @heatpump_visibility = unpack("C$countVisibAttr", $result);
  if(scalar(@heatpump_visibility) != $countVisibAttr) {
      LUXTRONIK2_Log $name, 2, "Unpacking problem by visibility attributes: ".scalar(@heatpump_visibility)." instead of ".$countVisibAttr;
      $socket->close();
      return (0, "Unpacking problem of visibility attributes");
  }

  LUXTRONIK2_Log $name, 5, "$countVisibAttr visibility attributs received";

####################################  

  LUXTRONIK2_Log $name, 5, "Closing connection to host $host";
  $socket->close();

  my $readingEndTime = time();

#return all readings for further processing
  return ( 1, "OK", \@heatpump_values, \@heatpump_parameters, \@heatpump_visibility);
 
}

sub ########################################
LUXTRONIK2_CalcTemp($)
{
  my ($temp) = @_;
  #change unsigned into signed
  if ($temp > 2147483648) {$temp = $temp-4294967296;}
  $temp /= 10;
  return sprintf ("%.1f", $temp);
}

########################################
sub LUXTRONIK2_FormatDuration($)
{
  my ($value) = @_;
  my $returnstr;
  $returnstr = sprintf "%01dd ", int($value/86400)
      if $value >= 86400;
  $value %= 86400;
  $returnstr .= sprintf "%02d:", int($value/3600);
  $value %= 3600;
  $returnstr .= sprintf "%02d:", int($value/60);
  $value %= 60;
  $returnstr .= sprintf "%02d", $value;
  
  return $returnstr;
}

########################################
sub LUXTRONIK2_SetParameter ($$$)
{
  my ($hash, $parameterName, $realValue) = @_;
  my $setParameter = 0;
  my $setValue = 0;
  my $result;
  my $buffer;
  my $host = $hash->{HOST};
  my $name = $hash->{NAME};
  
   my %opMode = ( "Auto" => 0,
                 "Party" => 2,
                   "Off" => 4);
   
  if(AttrVal($name, "allowSetParameter", 0) != 1) {
   return $name." Error: Setting of parameters not allowed. Please set attribut 'allowSetParameter' to 1";
  }
  
  if ($parameterName eq "hotWaterTemperatureTarget") {
     #parameter number
    $setParameter = 2;
    #limit temperature range
    $realValue = 30 if( $realValue < 30 );
    $realValue = 65 if( $realValue > 65 );
    #Allow only integer temperatures with decimal .1
    $setValue = int($realValue * 10);
    $realValue = $setValue / 10;
  }
  
  elsif ($parameterName eq "heatingCurveEndPoint") {
     #parameter number
    $setParameter = 11;
    #limit temperature range
    $realValue = 20 if( $realValue < 20.0 );
    $realValue = 70 if( $realValue > 70.0 );
    #Allow only integer temperatures
    $setValue = int($realValue * 10);
    $realValue = $setValue / 10;
  }
  
  elsif ($parameterName eq "heatingCurveOffset") {
     #parameter number
    $setParameter = 12;
    #limit temperature range
    $realValue = 5 if( $realValue < 5.0 );
    $realValue = 35 if( $realValue > 35.0 );
    #Allow only integer temperatures
    $setValue = int($realValue * 10);
    $realValue = $setValue / 10;
  }
  
  elsif ($parameterName eq "heatSourceDefrostAirEnd") {
     #parameter number
    $setParameter = 98;
    #limit temperature range
    $realValue = 1 if( $realValue < 1.0 );
    $realValue = 24 if( $realValue > 24.0 );
    #Allow only integer temperatures
    $setValue = int($realValue * 10);
    $realValue = $setValue / 10;
  }

  elsif ($parameterName eq "heatSourceDefrostAirThreshold") {
     #parameter number
    $setParameter = 44;
    #limit temperature range
    $realValue = 1.5 if( $realValue < 1.5 );
    $realValue = 20 if( $realValue > 20.0 );
    #Allow only integer temperatures
    $setValue = int($realValue * 10);
    $realValue = $setValue / 10;
  }

  elsif ($parameterName eq "opModeHotWater") {
    if (! exists($opMode{$realValue})) {
      return "$name Error: Wrong parameter given for opModeHotWater, use Automatik,Party,Off"
     }
     $setParameter = 4;
     $setValue = $opMode{$realValue};
  }
  
  elsif ($parameterName eq "returnTemperatureHyst") {
     #parameter number
    $setParameter = 88;
    #limit temperature range
    $realValue = 0.5 if( $realValue < 0.5 );
    $realValue = 3.0 if( $realValue > 3.0 );
    #Allow only temperatures with decimal .1
    $setValue = int($realValue * 10);
    $realValue = $setValue / 10;
  }

  elsif ($parameterName eq "returnTemperatureSetBack") {
     #parameter number
    $setParameter = 1;
    #limit temperature range
    $realValue = -5 if( $realValue < -5 );
    $realValue = 5 if( $realValue > 5 );
    #Allow only temperatures with decimal .1
    $setValue = int($realValue * 10);
    $realValue = $setValue / 10;
  }

   elsif ($parameterName eq "hotWaterCircPumpDeaerate") { #isVisible(167) 
     $setParameter = 684;
     $setValue = $realValue eq "on" ? 1 : 0;
   }
   elsif ($parameterName eq "runDeaerate") {
     $setParameter = 158;
     $setValue = $realValue;
   }

   else {
    return "$name LUXTRONIK2_SetParameter-Error: unknown parameter $parameterName";
  }

############################ 
# Send new parameter to host
############################ 
  if ($setParameter != 0) {
     LUXTRONIK2_Log $name, 5, "Opening connection to host ".$host;
     my $socket = new IO::Socket::INET (  PeerAddr => $host, 
                     PeerPort => 8888,
                     Proto => 'tcp'
       );
      # Socket error
      if (!$socket) {
        LUXTRONIK2_Log $name, 1, "Could not open connection to host ".$host;
        return "$name Error: Could not open connection to host ".$host;
     }
      $socket->autoflush(1);
     
     LUXTRONIK2_Log $name, 5, "Set parameter $parameterName ($setParameter) = $realValue ($setValue)";
     $socket->send( pack( "N3", (3002, $setParameter, $setValue) ) );
     
     LUXTRONIK2_Log $name, 5, "Receive confirmation";
    #read first 4 bytes of response -> should be request_echo = 3002
     $socket->recv($buffer,4, MSG_WAITALL );
     $result = unpack("N", $buffer);
     if($result != 3002) {
        LUXTRONIK2_Log $name, 2, "Set parameter $parameterName - wrong echo of request: $result instead of 3002";
        $socket->close();
        return "$name Error: Host did not confirm parameter setting";
     }
    
    #Read next 4 bytes of response -> should be setParameter
     $socket->recv($buffer,4, MSG_WAITALL );
     $result = unpack("N", $buffer);
     if($result !=$setParameter) {
        LUXTRONIK2_Log $name, 2, "Set parameter $parameterName - missing confirmation: $result instead of $setParameter";
        $socket->close();
        return "$name Error: Host did not confirm parameter setting";
     }
     LUXTRONIK2_Log $name, 5, "Parameter setting confirmed";
     
     $socket->close();
     
     readingsSingleUpdate($hash,$parameterName,$realValue,0)   unless $parameterName eq "runDeaerate";
     
     return undef;
   }
  
}

########################################
sub LUXTRONIK2_synchronizeClock (@)
{
  my ($hash,$maxDelta) = @_;
  my $host = $hash->{HOST};
  my $name = $hash->{NAME};
  my $delay = 0;
  my $returnStr = "";

  $maxDelta = 60 unless defined $maxDelta;
  $maxDelta = 60 unless $maxDelta >= 0;
  $maxDelta = 600 unless $maxDelta <= 600;
         
   LUXTRONIK2_Log $name, 5, "Open telnet connection to $host";
   my $telnet = new Net::Telnet ( host=>$host, port => 23, timeout=>10, errmode=>'return');
   if (!$telnet) {
      my $msg = "Could not open telnet connection to $host: $!";
      LUXTRONIK2_Log $name, 1, $msg;
      return "$name synchronizeDeviceClock-Error: ".$msg;
   }
  
    LUXTRONIK2_Log $name, 5, "Log into $host";
      if (!$telnet->login('root', '')) {
        LUXTRONIK2_Log $name, 1, $telnet->errmsg;
        return "$name synchronizeDeviceClock-Error: ".$telnet->errmsg;
      }
      
   LUXTRONIK2_Log $name, 5, "Read current time of host";
      my @output = $telnet->cmd('date +%s');
     $delay = sprintf("%.1f",time() - $output[0]);
   LUXTRONIK2_Log $name, 5, "Current time is ".localtime($output[0])." Delay is $delay seconds.";

     if (abs($delay)>$maxDelta && $maxDelta!=0) {
      $returnStr = "Do not dare to synchronize. Device clock of host $host differs by $delay seconds (max. is $maxDelta).";
     } elsif ($delay == 0) {
       $returnStr = "Internal clock of host $host has no delay. -> not synchronized";
    } else {
      my $newTime = strftime "%m%d%H%M%Y.%S", localtime();
     LUXTRONIK2_Log $name, 5, "Run command 'date ".$newTime."'";
      @output=$telnet->cmd('date '.$newTime);
      $returnStr = "Internal clock of host $host corrected by $delay seconds. -> ".$output[0];
      readingsSingleUpdate($hash,"deviceTimeLastSync",TimeNow,1);
     }
   
   LUXTRONIK2_Log $name, 5, "Close telnet connection.";
   $telnet->close;
   
   return $returnStr;
}

########################################
sub LUXTRONIK2_boostHotWater_Start ($$)
{ my ($hash, $temperature) = @_;

   my $name = $hash->{NAME};

   return "boostHotWater not implemented yet";
   
   return "$temperature is not a number."  if defined $temperature && $temperature !~ /^\d*\.?\d*$/;

   my $currTarget = $hash->{READINGS}{hotWaterTemperatureTarget}{VAL};
   return "Could not determine current hotWaterTemperatureTarget."   unless defined $currTarget;
   readingsSingleUpdate($hash,"bhwLastTarget",$currTarget, 0)    unless $hash->{READINGS}{bhwLastTarget}{VAL};
   
   my $currMode = $hash->{READINGS}{opModeHotWater}{VAL};
   return "Could not determine current opModeHotWater."   unless defined $currMode;
   readingsSingleUpdate($hash,"bhwLastMode",$currMode, 0)     unless $hash->{READINGS}{bhwLastMode}{VAL};

   my $currState = $hash->{READINGS}{opStateHotWater}{VAL};
   return "Could not determine current opStateHotWater."   unless defined $currState;
   
   $hash->{boostHotWater} = 1;

   if ( defined $temperature ) {
      LUXTRONIK2_Log $name, 4, "set 'hotWaterTemperatureTarget' temporarly to ".$temperature;
      LUXTRONIK2_SetParameter($hash, "hotWaterTemperatureTarget", $temperature);
   }

   
   if ( $currState !~ /Aufheizen|Temp. OK/) {
      LUXTRONIK2_Log $name, 4, "set 'opModeHotWater' temporarly to 'Party'";
      LUXTRONIK2_SetParameter($hash, "opModeHotWater", "Party");
   }
   
}

######################################## 
sub LUXTRONIK2_calcHeatingCurveParameter ($$$$$)
{ my ($hash, $aussen_1, $rtSoll_1, $aussen_2, $rtSoll_2) = @_;

   if ($aussen_1 > $aussen_2) {
      my $temp= $aussen_1;  
      $aussen_1=$aussen_2; 
      $aussen_2=$temp;
      $temp= $rtSoll_1;  
      $rtSoll_1=$rtSoll_2; 
      $rtSoll_2=$temp;
   }

   my $endPoint_Ist = $hash->{READINGS}{heatingCurveEndPoint}{VAL};
   my $endPoint = $endPoint_Ist;
   my $offset_Ist = $hash->{READINGS}{heatingCurveOffset}{VAL};
   my $offset = $offset_Ist;
   my $rtIst_1 = LUXTRONIK2_getHeatingCurveReturnTemperature ( $hash, $aussen_1, $endPoint, $offset);
   my $rtIst_2 = LUXTRONIK2_getHeatingCurveReturnTemperature ( $hash, $aussen_2, $endPoint, $offset);
   my $delta_1; my $delta_2;  
   my $msg;  my $i;

   #get Heizung heatingCurveParameter 0 27 10 25

   for ( $i=0; $i<1000; $i++ ) {
      $delta_1 = LUXTRONIK2_getHeatingCurveReturnTemperature ( $hash, $aussen_1, $endPoint, $offset) - $rtSoll_1;
      $delta_1 = int(10.0 * $delta_1 + 0.5) / 10.0;
      $delta_2 = LUXTRONIK2_getHeatingCurveReturnTemperature ( $hash, $aussen_2, $endPoint, $offset) - $rtSoll_2;
      $delta_2 = int(10.0 * $delta_2 + 0.5) / 10.0;

      $msg = "Calculate loop $i: hcEndPoint=$endPoint, hcOffset=$offset, delta($aussen_1)=$delta_1, delta($aussen_2)=$delta_2)\n";
      LUXTRONIK2_Log $hash, 4, $msg;
      last     if $delta_1 == 0 && $delta_2 == 0;
     
      if ($delta_2 > 0) {
         $offset -= 0.1;
      }
      elsif ($delta_2 < 0) {
         $offset += 0.1;
      }
      elsif ($delta_1 > 0) {
         $endPoint -= 0.1;
      }
      elsif ($delta_1 < 0) {
         $endPoint += 0.1;
      }
      $endPoint = int(10.0 * $endPoint + 0.5) / 10.0;
      $offset = int(10.0 * $offset + 0.5) / 10.0;
   }
   LUXTRONIK2_Log $hash, 3, "Heating-Curve-Parameter calculated in $i loops.";
   $msg = "New Values: heatingCurveEndPoint=$endPoint heatingCurveOffset=$offset\n";
   $msg .= "Old Values: heatingCurveEndPoint=$endPoint_Ist heatingCurveOffset=$offset_Ist\n\n";
   $msg .= "New Heating-Curve: returnTemp($aussen_1)=".($delta_1+$rtSoll_1)." and returnTemp($aussen_2)=".($delta_2+$rtSoll_2)."\n";
   $msg .= "Old Heating-Curve: returnTemp($aussen_1)=".($rtIst_1)." and returnTemp($aussen_2)=".($rtIst_2)."\n";
   $msg .= "calculated in $i loops\n";
   return $msg;
}

######################################## 
sub LUXTRONIK2_getHeatingCurveReturnTemperature ($$$$)
{ my ($hash, $aussen, $endPoint, $offset) = @_;
    LUXTRONIK2_Log $hash, 5, "Calculate return-temperature at $aussen with heating curve ($endPoint, $offset)";
    my $result = $offset + ($endPoint - 20.0) * ($offset - $aussen) / (20.0 - ($aussen - $offset) / 2);
    $result = int(10.0 * $result + 0.5) / 10.0;
    return $result;
}


######################################## 
sub LUXTRONIK2_checkFirmware ($) 
{
  my ($myFirmware) = @_;

  #Firmware not tested
   if (index($testedFirmware,"#".$myFirmware."#") == -1) { 
      return "fwNotTested";
  #Firmware tested but not compatible
   } elsif (index($compatibleFirmware,"#".$myFirmware."#") == -1) { 
      return "fwNotCompatible";
  #Firmware compatible
    } else {
       return "fwCompatible";
   }
}

# Calculate heat-up gradients of boiler based on hotWaterTemperature and counterHeatQHeating
sub ######################################## 
LUXTRONIK2_doStatisticThermalPower ($$$$$$$$$)
{
   my ($hash, $MonitoredOpState, $currOpState, $currHeatQuantity, $currOpHours,  $currAmbTemp, $currHeatSourceIn, $targetTemp, $electricalPower) = @_;
   my @last = split / /, $hash->{fhem}{"statThermalPowerOpState_".$MonitoredOpState} || "1";
   my $returnStr = "";
   my $value1;
   my $value2;
   my $value3;
   my $save = 0;

   if ( $last[0] != $MonitoredOpState && $currOpState == $MonitoredOpState ) {
   # Save start values at the beginning of the monitored operation (5=Hot Water, 0=Heating)
      $save = 1;
      $last[0] = $currOpState;
      $last[1] = $currHeatQuantity;
      $last[2] = $currOpHours;
      $last[3] = $currAmbTemp;
      $last[4] = $currHeatSourceIn;
      $last[5] = 1;
      $last[6] = $targetTemp;
      $last[7] = $electricalPower;
   
   } elsif ($last[0] == $MonitoredOpState && ($currOpState == $MonitoredOpState || $currOpState == 16) ) { #16=Durchflussüberwachung
   # Store intermediate values as long as the correct opMode runs
      $save = 1;
      $last[3] += $currAmbTemp;
      $last[4] += $currHeatSourceIn;
      $last[5]++;
      $last[7] += $electricalPower;

   } elsif ($last[0] == $MonitoredOpState && $currOpState != $MonitoredOpState && $currOpState != 16 ) { #16=Durchflussüberwachung
   # Do statistics at the end of the monitored operation if it run at least 9.5 minutes
      $save = 1;
      $last[0] = $currOpState;
      $value2 = ($currOpHours - $last[2])/60;
      if ($value2 >= 6) {
         $returnStr = sprintf "aT: %.1f iT: %.1f tT: %.1f", $last[3]/$last[5], $last[4]/$last[5], $targetTemp;
         $value1 = $currHeatQuantity -  $last[1];
         $value3 = $value1 * 60 / $value2;
         $returnStr .= sprintf " thP: %.1f DQ: %.1f t: %.0f", $value3, $value1, $value2;
         if ($last[7]>0) {
            $value1 = $value3 *1000 / $last[7] * $last[5];;
            $returnStr .= sprintf " COP: %.2f", $value1;
         }
         if ($last[6] > $targetTemp) { $returnStr .= " tTStart: " . $last[6]; }
      }
   }

   if ($save == 1) { $hash->{fhem}{"statThermalPowerOpState_".$MonitoredOpState} = join( " ", @last);}

   return $returnStr;
}

# Calculate heat-up gradients of boiler based on hotWaterTemperature and counterHeatQHeating
sub ######################################## 
LUXTRONIK2_doStatisticBoilerHeatUp ($$$$$$) 
{
   my ($hash, $currOpHours, $currHQ, $currTemp, $opState, $target) = @_;
   my $name = $hash->{NAME};
   my $step = $hash->{fhem}{statBoilerHeatUpStep};
   my $minTemp = $hash->{fhem}{statBoilerHeatUpMin};
   my $maxTemp = $hash->{fhem}{statBoilerHeatUpMax};
   my $lastHQ = $hash->{fhem}{statBoilerHeatUpHQ};
   my $lastOpHours = $hash->{fhem}{statBoilerHeatUpOpHours}; 
   my $value1 = 0;
   my $value2 = 0;
   my $value3 = 0;
   my $returnStr = "";

  # step 0 = Initialize - if hot water preparation is off
   if ($step == 0) { 
     if ($opState != 5) { # wait till hot water preparation stopped
        LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 0->1: Initializing Measurment";
        $step = 1;
        $lastOpHours = $currOpHours;
        $lastHQ = $currHQ;
        $minTemp = $currTemp;
     }
     
  # step 1 = wait till hot water preparation starts -> monitor Tmin, take previous HQ and previous operating hours
   } elsif ($step == 1) { 
     if ($currTemp < $minTemp) { # monitor minimum temperature
       LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 1: Monitor minimum temperature ($minTemp -> $currTemp)";
       $minTemp = $currTemp;
     }
     if ($opState != 5) { # wait -> update operating hours and HQ to be used as start value in calculations
        $lastOpHours = $currOpHours; 
        $lastHQ = $currHQ;
     } else { # go to step 2 - if hot water preparation running
         LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 1->2: Hot water preparation started ".($currOpHours-$lastOpHours)." s ago";
        $step = 2; 
        $maxTemp = $currTemp;
     }

  # step 2 = wait till hot water preparation done and target reached
   } elsif ($step == 2) { 
     if ($currTemp < $minTemp) { # monitor minimal temperature
       LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 2: Boiler temperature still decreasing ($minTemp -> $currTemp)";
       $minTemp = $currTemp;
     }
     if ($currTemp > $maxTemp) { # monitor maximal temperature
       LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 2: Boiler temperature increasing ($maxTemp -> $currTemp)";
       $maxTemp = $currTemp;
     }
     
     if ($opState != 5) { # wait till hot water preparation stopped
        if ($currTemp >= $target) {
          LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 2->3: Hot water preparation stopped";
           $step = 3; 
        } else {
           LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 2->1: Measurement cancelled (hot water preparation stopped but target not reached, $currTemp < $target)";
           $step = 1; 
           $lastOpHours = $currOpHours; 
           $lastHQ = $currHQ;
           $minTemp = $currTemp;
        }
     }
     
  # step 3 = wait with calculation till temperature maximum reached once
   } elsif ($step == 3) { 
     # cancel measurement - if hot water preparation has restarted
      if ($opState == 5) { 
         LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 3->0: Measurement cancelled (hot water preparation restarted before maximum reached)";
        $step = 0; 
    # monitor maximal temperature
       } elsif ($currTemp > $maxTemp) { 
        LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 3: Temperature still increasing ($maxTemp -> $currTemp)";
        $maxTemp = $currTemp;
    # else calculate temperature gradient 
      } else {
        LUXTRONIK2_Log $name, 4, "Statistic Boiler Heat-Up step 3->1: Boiler heat-up measurement finished";
        $value1 =  ( int(10 * $maxTemp) - int(10 * $minTemp) ) / 10; # delta hot water temperature
        $value2 = ( $currOpHours - $lastOpHours ) / 60; # delta time (minutes)
        $value3 = $currHQ - $lastHQ; # delta heat quantity, average thermal power
 
        $returnStr = sprintf "DT/min: %.2f DT: %.2f Dmin: %.0f DQ: %.1f thP: %.1f", $value1/$value2, $value1, $value2, $value3, $value3*60/$value2;
        
        #real (mixed) Temperature-Difference
        my $boilerVolumn = AttrVal($name, "boilerVolumn", 0);
        if ($boilerVolumn >0 ) {
           # (delta T) [K] = Wärmemenge [kWh] / #Volumen [l] * ( 3.600 [kJ/kWh] / ( 4,179 [kJ/(kg*K)] (H2O Wärmekapazität bei 40°C) * 0,992 [kg/l] (H2O Dichte bei 40°C) ) [K/(kWh*l)] )  
           $value2 = 868.4 * $value3 / $boilerVolumn ;  
           $returnStr .= sprintf " realDT: %.0f", $value2;
        }
        
        $step = 1; 
        $lastOpHours = $currOpHours; 
        $lastHQ = $currHQ;
        $minTemp = $currTemp;

      }
   }
   $hash->{fhem}{statBoilerHeatUpStep} = $step;
   $hash->{fhem}{statBoilerHeatUpMin} = $minTemp;
   $hash->{fhem}{statBoilerHeatUpMax} = $maxTemp;
   $hash->{fhem}{statBoilerHeatUpHQ} = $lastHQ;
   $hash->{fhem}{statBoilerHeatUpOpHours} = $lastOpHours; 
   
    return $returnStr;
     
}
     
# Calculate heat loss gradients of boiler based on hotWaterTemperature and counterHeatQHeating
sub ######################################## 
LUXTRONIK2_doStatisticBoilerCoolDown ($$$$$$) 
{
   my ($hash, $time, $currTemp, $opState, $target, $threshold) = @_;
   my $name = $hash->{NAME};
   my $step = $hash->{fhem}{statBoilerCoolDownStep};
   my $maxTemp = $hash->{fhem}{statBoilerCoolDownMax};
   my $startTime = $hash->{fhem}{statBoilerCoolDownStartTime}; 
   my $lastTime = $hash->{fhem}{statBoilerCoolDownLastTime}; 
   my $lastTemp = $hash->{fhem}{statBoilerCoolDownLastTemp}; 
   my $value1 = 0;
   my $value2 = 0;
   my $value3 = 0;
   my $returnStr = "";

  # step 0 = Initialize - if hot water preparation is off and target reached, 
   if ($step == 0) { 
     if ($opState == 5 || $currTemp < $target) { # -> stay step 0
        # LUXTRONIK2_Log $name, 4, "Statistic Boiler Cool-Down step 0: Wait till hot water preparation stops and target is reached ($currTemp < $target)";
     } else {
        LUXTRONIK2_Log $name, 4, "Statistic Boiler Cool-Down step 0->1: Initializing, target reached ($currTemp >= $target)";
        $step = 1; 
        $startTime = $time; 
        $maxTemp = $currTemp;
     }
  # step 1 = wait till threshold is reached -> do calculation, monitor maximal temperature
   } elsif ($step == 1) { 
      if ($currTemp > $maxTemp) { # monitor maximal temperature
         LUXTRONIK2_Log $name, 4, "Statistic Boiler Cool-Down step 1: Temperature still increasing ($currTemp > $maxTemp)";
         $maxTemp = $currTemp;
         $startTime = $time; 
      }
      if ($opState == 5 || $currTemp <= $threshold) {
         if ($opState == 5) {
            LUXTRONIK2_Log $name, 4, "Statistic Boiler Cool-Down step 1->0: Heat-up started, measurement finished";
            $value1 =  $lastTemp - $maxTemp; # delta hot water temperature
            $value2 = ( $lastTime - $startTime ) / 3600; # delta time (hours)
         } elsif ($currTemp <= $threshold) {
            LUXTRONIK2_Log $name, 4, "Statistic Boiler Cool-Down step 1->0: Measurement finished, threshold reached ($currTemp <= $threshold)";
            $value1 =  $currTemp - $maxTemp; # delta hot water temperature
            $value2 = ( $time - $startTime ) / 3600; # delta time (hours)
         }
         $returnStr = sprintf "DT/h: %.2f DT: %.1f Dh: %.2f", $value1/$value2, $value1, $value2;
         $step = 0;
      } 
   }   

   $hash->{fhem}{statBoilerCoolDownStep} = $step;
   $hash->{fhem}{statBoilerCoolDownMax} = $maxTemp;
   $hash->{fhem}{statBoilerCoolDownStartTime} = $startTime; 
   $hash->{fhem}{statBoilerCoolDownLastTime} = $time; 
   $hash->{fhem}{statBoilerCoolDownLastTemp} = $currTemp; 

   return $returnStr;
}   

# Calculates single MaxMin Values and informs about end of day and month
######################################## 
sub LUXTRONIK2_doStatisticMinMax ($$$) 
{
   my ($hash, $readingName, $value) = @_;
   my $dummy;
   my $saveLast;
   my $statReadingName;

   my $lastReading;
   my $lastSums;
   my @newReading;
   
   my $yearLast;
   my $monthLast;
   my $dayLast;
   my $dayNow;
   my $monthNow;
   my $yearNow;
   
  # Determine date of last and current reading
   if (exists($hash->{READINGS}{$readingName."Day"}{TIME})) {
      ($yearLast, $monthLast, $dayLast) = $hash->{READINGS}{$readingName."Day"}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;
   } else {
      ($dummy, $dummy, $dummy, $dayLast, $monthLast, $yearLast) = localtime;
      $yearLast += 1900;
      $monthLast ++;
   }
   ($dummy, $dummy, $dummy, $dayNow, $monthNow, $yearNow) = localtime;
   $yearNow += 1900;
   $monthNow ++;

  # Daily Statistic
   $saveLast = ($dayNow != $dayLast);
   $statReadingName = $readingName."Day";
   LUXTRONIK2_doStatisticMinMaxSingle $hash, $statReadingName, $value, $saveLast;
   
  # Monthly Statistic
   $saveLast = ($monthNow != $monthLast);
   $statReadingName = $readingName."Month";
   LUXTRONIK2_doStatisticMinMaxSingle $hash, $statReadingName, $value, $saveLast;
    
  # Yearly Statistic
   $saveLast = ($yearNow != $yearLast);
   $statReadingName = $readingName."Year";
   LUXTRONIK2_doStatisticMinMaxSingle $hash, $statReadingName, $value, $saveLast;

   return ;

}

# Calculates single MaxMin Values and informs about end of day and month
sub ######################################## 
LUXTRONIK2_doStatisticMinMaxSingle ($$$$) 
{
   my ($hash, $readingName, $value, $saveLast) = @_;
   my $result;
   
   my $lastReading = $hash->{READINGS}{$readingName}{VAL} || "";
   
 # Initializing
   if ( $lastReading eq "" ) { 
      my $since = strftime "%Y-%m-%d_%H:%M:%S", localtime(); 
      $result = "Count: 1 Sum: $value ShowDate: 1";
      readingsBulkUpdate($hash, ".".$readingName, $result);
      $result = "Min: $value Avg: $value Max: $value (since: $since )";
      readingsBulkUpdate($hash, $readingName, $result);

 # Calculations
   } else { 
      my @a = split / /, $hash->{READINGS}{"." . $readingName}{VAL}; # Internal values
      my @b = split / /, $lastReading;
    # Do calculations
      $a[1]++; # Count
      $a[3] += $value; # Sum
      if ($value < $b[1]) { $b[1]=$value; } # Min
      if ($a[1]>0) {$b[3] = sprintf "%.1f" , $a[3] / $a[1] ;} # Avg
      if ($value > $b[5]) { $b[5]=$value; } # Max

      # in case of period change, save "last" values and reset counters
      if ($saveLast) {
         $result = "Min: $b[1] Avg: $b[3] Max: $b[5]";
         if ($a[5] == 1) { $result .= " (since: $b[7] )"; }
         readingsBulkUpdate($hash, $readingName . "Last", $lastReading);
         $a[1] = 1;   $a[3] = $value;   $a[5] = 0;
         $b[1] = $value;   $b[3] = $value;   $b[5] = $value;
      }
    # Store internal calculation values
      $result = "Count: $a[1] Sum: $a[3] ShowDate: $a[5]";  
      readingsBulkUpdate($hash, ".".$readingName, $result);
    # Store visible Reading
      if ($a[5] == 1) {
         $result = "Min: $b[1] Avg: $b[3] Max: $b[5] (since: $b[7] )";  
      } else {
         $result = "Min: $b[1] Avg: $b[3] Max: $b[5]";  
      }
      readingsBulkUpdate($hash, $readingName, $result);
   }
   return;
}

########################################
sub LUXTRONIK2_storeReadings($$$$$$)
{
   my ($hash, $readingName, $value, $factor, $doStatistic, $electricalPower) = @_;
   
   if ($value eq "no" || $value == 0 ) { return; }

   readingsBulkUpdate($hash, $readingName, sprintf("%.1f", $value / $factor));
   
   $readingName =~ s/counter//;
 
   # LUXTRONIK2_doStatisticDelta: $hash, $readingName, $value, $factor, $electricalPower
   if ( $doStatistic == 1) { LUXTRONIK2_doStatisticDelta $hash, "stat".$readingName, $value, $factor, $electricalPower; }
}

# Calculates deltas for day, month and year
######################################## 
sub LUXTRONIK2_doStatisticDelta ($$$$$) 
{
   my ($hash, $readingName, $value, $factor, $electricalPower) = @_;
   my $name = $hash->{NAME};
   my $dummy;
   my $result;
   
   my $deltaValue;
   my $previousTariff; 
   my $showDate;
   
 # Determine if time period switched (day, month, year)
 # Get deltaValue and Tariff of previous call
   my $periodSwitch = 0;
   my $yearLast; my $monthLast; my $dayLast; my $dayNow; my $monthNow; my $yearNow;
   if (exists($hash->{READINGS}{"." . $readingName . "Before"})) {
      ($yearLast, $monthLast, $dayLast) = ($hash->{READINGS}{"." . $readingName . "Before"}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/);
      $yearLast -= 1900;
      $monthLast --;
      ($dummy, $deltaValue, $dummy, $previousTariff, $dummy, $showDate) = split / /,  $hash->{READINGS}{"." . $readingName . "Before"}{VAL} || "";
      $deltaValue = $value - $deltaValue;
   } else {
      ($dummy, $dummy, $dummy, $dayLast, $monthLast, $yearLast) = localtime;
      $deltaValue = 0;
      $previousTariff = 0; 
      $showDate = 6;
   }
   ($dummy, $dummy, $dummy, $dayNow, $monthNow, $yearNow) = localtime;
   if ($yearNow != $yearLast) { $periodSwitch = 3; }
   elsif ($monthNow != $monthLast) { $periodSwitch = 2; }
   elsif ($dayNow != $dayLast) { $periodSwitch = 1; }

   # Determine if "since" value has to be shown in current and last reading
   if ($periodSwitch == 3) {
      if ($showDate == 1) { $showDate = 0; } # Do not show the "since:" value for year changes anymore
      if ($showDate >= 2) { $showDate = 1; } # Shows the "since:" value for the first year change
   }
   if ($periodSwitch >= 2){
      if ($showDate == 3) { $showDate = 2; } # Do not show the "since:" value for month changes anymore
      if ($showDate >= 4) { $showDate = 3; } # Shows the "since:" value for the first month change
   }
   if ($periodSwitch >= 1){
      if ($showDate == 5) { $showDate = 4; } # Do not show the "since:" value for day changes anymore
      if ($showDate >= 6) { $showDate = 5; } # Shows the "since:" value for the first day change
   }

   # LUXTRONIK2_doStatisticDeltaSingle; $hash, $readingName, $deltaValue, $periodSwitch, $showDate, $firstCall
   LUXTRONIK2_doStatisticDeltaSingle ($hash, $readingName, $deltaValue, $factor, $periodSwitch, $showDate, 0);

   my $activeTariff = ReadingsVal($name,"activeTariff",0);

   if ( $electricalPower >=0 ) {
      my $readingNamePower = $readingName;
         $readingNamePower =~ s/Hours/Electricity/ ;
      if ($activeTariff > 0) {
         foreach (1,2,3,4,5,6,7,8,9) {
            if ( $previousTariff == $_ ) {
               LUXTRONIK2_doStatisticDeltaSingle ($hash, $readingNamePower."Tariff".$_, $deltaValue * $electricalPower, $factor, $periodSwitch, $showDate, 1);
            } elsif ($activeTariff == $_ || ($periodSwitch > 0 && exists($hash->{READINGS}{$readingNamePower . "Tariff".$_}))) {
               LUXTRONIK2_doStatisticDeltaSingle ($hash, $readingNamePower."Tariff".$_, 0, $factor, $periodSwitch, $showDate, 1);
            }
         }
      } else {
         LUXTRONIK2_doStatisticDeltaSingle ($hash, $readingNamePower, $deltaValue * $electricalPower, $factor, $periodSwitch, $showDate, 1);
      }
   }
 # Hidden storage of current values for next call(before values)
   $result = "Value: $value Tariff: $activeTariff ShowDate: $showDate";  
   readingsBulkUpdate($hash, ".".$readingName."Before", $result);
   
   return ;
}

sub ######################################## 
LUXTRONIK2_doStatisticDeltaSingle ($$$$$$$) 
{
   my ($hash, $readingName, $deltaValue, $factor, $periodSwitch, $showDate, $specMonth) = @_;
   my $dummy;
   my $result;   

 # get existing statistic reading
   my @curr;
   if (exists($hash->{READINGS}{".".$readingName}{VAL})) {
      @curr = split / /, $hash->{READINGS}{".".$readingName}{VAL} || "";
   } else {
      $curr[1] = 0; $curr[3] = 0;  $curr[5] = 0;
      if ($showDate>5) {$curr[7] = strftime "%Y-%m-%d_%H:%M:%S", localtime();} # start
      else {$curr[7] = strftime "%Y-%m-%d", localtime();} # start
   }
   
 # get statistic values of previous period
   my @last;
   if ($periodSwitch >= 1) {
      if (exists ($hash->{READINGS}{$readingName."Last"})) { 
         @last = split / /,  $hash->{READINGS}{$readingName."Last"}{VAL};
      } else {
         @last = split / /,  "Day: - Month: - Year: -";
      }
   }
   
 # Do statistic
   $curr[1] += $deltaValue;
   $curr[3] += $deltaValue;
   $curr[5] += $deltaValue;

 # If change of year, change yearly statistic
   if ($periodSwitch == 3){
      if ($specMonth) { $last[5] = sprintf("%.3f",$curr[5] / $factor/ 1000); }
      else {$last[5] = sprintf("%.0f",$curr[5] / $factor);}
      $curr[5] = 0;
      if ($showDate == 1) { $last[7] = $curr[7]; }
   }

 # If change of month, change monthly statistic 
   if ($periodSwitch >= 2){
      if ($specMonth) { $last[3] = sprintf("%.3f",$curr[3] / $factor/ 1000); }
      else {$last[3] = sprintf("%.0f",$curr[3] / $factor);}
      $curr[3] = 0;
      if ($showDate == 3) { $last[7] = $curr[7];}
   }

 # If change of day, change daily statistic
   if ($periodSwitch >= 1){
      $last[1] = sprintf("%.1f",$curr[1] / $factor);
      $curr[1] = 0;
      if ($showDate == 5) {
         $last[7] = $curr[7];
        # Next monthly and yearly values start at 00:00 and show only date (no time)
         $curr[3] = 0;
         $curr[5] = 0;
         $curr[7] = strftime "%Y-%m-%d", localtime(); # start
      }
   }

 # Store hidden statistic readings (delta values)
   $result = "Day: $curr[1] Month: $curr[3] Year: $curr[5]";
   if ( $showDate >=2 ) { $result .= " (since: $curr[7] )"; }
   readingsBulkUpdate($hash,".".$readingName,$result);
   
 # Store visible statistic readings (delta values)
   if ($specMonth) { $result = sprintf "Day: %.1f Month: %.3f Year: %.3f", $curr[1]/$factor, $curr[3]/$factor/1000, $curr[5]/$factor/1000; }
   else { $result = sprintf "Day: %.1f Month: %.0f Year: %.0f", $curr[1]/$factor, $curr[3]/$factor, $curr[5]/$factor; }
   if ( $showDate >=2 ) { $result .= " (since: $curr[7] )"; }
   readingsBulkUpdate($hash,$readingName,$result);
   
 # if changed, store previous visible statistic (delta) values
   if ($periodSwitch >= 1) {
      $result = "Day: $last[1] Month: $last[3] Year: $last[5]";
      if ( $showDate =~ /1|3|5/ ) { $result .= " (since: $last[7] )";}
      readingsBulkUpdate($hash,$readingName."Last",$result); 
   }
}


1;

=pod
=item device
=item summary Connects with a Luxtronik 2.0 controller for heat pumps.
=item summary_DE Verbindet mit einer Luxtronik 2.0 Heizungssteuerung für Wärmepumpen.

=begin html

<a name="LUXTRONIK2"></a>
<h3>LUXTRONIK2</h3>
<div>
<ul>
  Luxtronik 2.0 and 2.1 is a heating controller from <a href="http://www.alpha-innotec.de">Alpha InnoTec (AIT)</a> used in heat pumps of Alpha InnoTec, Buderus (Logamatic HMC20, HMC20 Z), CTA All-In-One (Aeroplus), Elco, Nibe (AP-AW10), Roth (ThermoAura&reg;, ThermoTerra), Novelan (WPR NET) and Wolf Heiztechnik (BWL/BWS).<br>
  It has a built-in ethernet (RJ45) port, so it can be directly integrated into a local area network (LAN).
  <br>
  <i>The module is reported to work with firmware: V1.51, V1.54C, V1.60, V1.64, V1.69, V1.70, V1.73, V1.77, V1.80, V1.81.</i>
  <br>
  More Info on the particular <a href="http://www.fhemwiki.de/wiki/Luxtronik_2.0">page of FHEM-Wiki</a> (in German).
  <br>
  &nbsp;
  <br>
  
  <a name="LUXTRONIK2define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LUXTRONIK2 &lt;IP-address[:Port]&gt; [poll-interval]</code><br>
    If the pool interval is omitted, it is set to 300 (seconds). Smallest possible value is 10.
    <br>
    Usually, the port needs not to be defined.
    <br>
    Example: <code>define Heizung LUXTRONIK2 192.168.0.12 600</code>
  </ul>
  <br>
  
  <a name="LUXTRONIK2set"></a>
  <b>Set</b>
   <ul>A firmware check assures before each set operation that a heat pump with untested firmware is not damaged accidently.
       <li><code>activeTariff &lt; 0 - 9 &gt;</code>
         <br>
         Allows the separate measurement of the consumption (doStatistics = 1 or 2) within different tariffs.<br>
         This value must be set at the correct point of time in accordance to the existing or planned tariff <b>by the FHEM command "at"</b>.<br>
         0 = without separate tariffs
       </li><br>
       <li><code>INTERVAL &lt;polling interval&gt;</code><br>
         Polling interval in seconds
       </li><br>
      <li><code>heatingCurveEndPoint &lt;Temperarature&gt;</code><br>
         Sets the heating curve parameter. Adjustable in 0.1 steps.
      </li><br>
      <li><code>heatingCurveOffset &lt;Temperarature&gt;</code><br>
         Sets the heating curve parameter. Adjustable in 0.1 steps.
      </li><br>
      <li><code>hotWaterTemperatureTarget &lt;temperature&gt;</code><br>
         Target temperature of domestic hot water boiler in &deg;C
         </li><br>
      <li><code>hotWaterCircPumpDeaerate &lt;on | off&gt;</code><br>
         Switches the external circulation pump for the hot water on or off. The circulation prevents a cool down of the hot water in the pipes but increases the heat consumption drastically.
         <br>
         NOTE! It uses the deaerate function of the controller. So, the pump alternates always 5 minutes on and 5 minutes off.
         </li><br>
       <li><code>opModeHotWater &lt;Mode&gt;</code><br>
         Operating Mode of domestic hot water boiler (Auto | Party | Off)
         </li><br>
     <li><code>resetStatistics &lt;statReadings&gt;</code>
         <br>
         Deletes the selected statistic values <i>all, statBoilerGradientCoolDownMin, statAmbientTemp..., statElectricity..., statHours..., statHeatQ...</i>
         </li><br>
     <li><code>returnTemperatureHyst &lt;Temperature&gt;</code>
         <br>
         Hysteresis of the returnTemperatureTarget of the heating controller. 0.5 K till 3 K. Adjustable in 0.1 steps.
         </li><br>
     <li><code>returnTemperatureSetBack &lt;Temperature&gt;</code>
         <br>
         Decreasing or increasing of the returnTemperatureTarget by -5 K till + 5 K. Adjustable in 0.1 steps.
         </li><br>
      <li><code>statusRequest</code><br>
         Update device information
         </li><br>
      <li><code>synchClockHeatPump</code><br>
         Synchronizes controller clock with FHEM time. <b>!! This change is lost in case of controller power off!!</b></li>
   </ul>
   <br>
   
   <a name="LUXTRONIK2get"></a>
   <b>Get</b>
  <ul>
      <li><code>heatingCurveParameter &lt;OutsideTemp1 SetTemp1 OutsideTemp2 SetTemp2&gt;</code>
      <br>
      Determines based on two points on the heating curve the respective heat curve parameter <i>heatingCurveEndPoint</i> and <i>heatingCurveOffset</i>.<br>
      These parameter can be set via the respective set commands.
      </li>
      <br>
      <li><code>rawData</code>
      <br>
      Shows a table with all parameter and operational values returned by the controller.<br>
      They can be assigned to device readings via the attributes <i>userHeatpumpParameters</i> und <i>userHeatpumpValues</i>.
      </li><br>
  </ul>
   <br>
  
   <a name="LUXTRONIK2attr"></a>
   <b>Attributes</b>
   <ul>
      <li><code>allowSetParameter &lt; 0 | 1 &gt;</code>
         <br>
         The <a href="#LUXTRONIK2set">parameters</a> of the heat pump controller can only be changed if this attribut is set to 1.
         </li><br>
      <li><code>autoSynchClock &lt;delay&gt;</code>
         <br>
         Corrects the clock of the heatpump automatically if a certain <i>delay</i> (10 s - 600 s) against the FHEM time is exeeded. Does a firmware check before.
         <br>
         <i>(A 'delayDeviceTimeCalc' &lt;= 2 s can be caused by the internal calculation interval of the heat pump controller.)</i>
         </li><br>
      <li><code>compressor2ElectricalPowerWatt</code><br>
         Electrical power of the 2nd compressor to calculated the COP and estimate electrical consumption (calculations not implemented yet)
         </li><br>
      <li><code>doStatistics &lt; 0 | 1 | 2 &gt;</code>
         <br>
         1 or 2: Calculates statistic values: <i>statBoilerGradientHeatUp, statBoilerGradientCoolDown, statBoilerGradientCoolDownMin (boiler heat loss)</i>
         <br>
         1: Builds daily, monthly and yearly statistics for certain readings (average/min/max or cumulated values).
         <br>
         Logging and visualisation of the statistic should be done with readings of type 'stat<i>ReadingName</i><b>Last</b>'.
         </li><br>
      <li><code>heatPumpElectricalPowerWatt</code><br>
         Electrical power of the heat pump by a flow temperature of 35&deg;C to calculated coefficency factor and estimate electrical consumption
         </li><br>
      <li><code>heatPumpElectricalPowerFactor</code><br>
         Change of electrical power consumption per 1 K flow temperature differenz to 35&deg;C (e.g. 2% per 1 K = 0,02) 
         </li><br>
      <li><code>heatRodElectricalPowerWatt</code><br>
         Electrical power of the heat rods (2nd heat source) to estimate electrical consumption
         </li><br>
      <li><code>ignoreFirmwareCheck &lt; 0 | 1 &gt;</code>
         <br>
         A firmware check assures before each set operation that a heatpump controller with untested firmware is not damaged accidently.
         <br>
         If this attribute is set to 1, the firmware check is ignored and new firmware can be tested for compatibility.
         </li><br>
      <li><code>statusHTML</code>
         <br>
         If set, a HTML-formatted reading named "floorplanHTML" is created. It can be used with the <a href="#FLOORPLAN">FLOORPLAN</a> module.
         <br>
         Currently, if the value of this attribute is not NULL, the corresponding reading consists of the current status of the heat pump and the temperature of the water.
         </li><br>
       <li><code>userHeatpumpParameters &lt;Index [Name][,Index2 [Name2],Index3 [Name3] ...]&gt;</code>
         <br>
         Allows to continuously read the value of certain controler parameters. The index number of the parameter can be determined with the get command <i>rawData</i><br> 
         In the attribute definition, a name can be written behind the index number separated by a space. The respective parameter value will either be shown with the prefix "userParameter..." or under the given name. <br>
         Multiple indexes are separated by a comma.<br>
         If the readings are not used anymore the can be deleted with the FHEM command <a href="#deletereading">deleteReading</a>.
         </li><br>
       <li><code>userHeatpumpValues &lt;Index Name[,Index2 Name2,Index3 Name3 ...]&gt;</code>
         <br> 
         Allows to read out specific operational values. Proceed as with <i>userHeatpumpParameters</i>.
         </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
</ul>
</div>

=end html

=begin html_DE

<a name="LUXTRONIK2"></a>
<h3>LUXTRONIK2</h3>
<div>
<ul>
  Die Luxtronik 2.0 and 2.1 ist eine Heizungssteuerung der Firma <a href="http://www.alpha-innotec.de">Alpha InnoTec AIT</a>, welche in Wärmepumpen von Alpha InnoTec, Buderus (Logamatic HMC20, HMC20 Z), CTA All-In-One (Aeroplus), Elco, Nibe (AP-AW10), Roth (ThermoAura&reg;, ThermoTerra), Novelan (WPR NET) und Wolf Heiztechnik (BWL/BWS) verbaut ist. Sie besitzt einen Ethernet (RJ45) Anschluss, so dass sie direkt in lokale Netzwerke (LAN) integriert werden kann.
  <br>
  <i>Das Modul wurde bisher mit folgender Steuerung-Firmware getestet: V1.51, V1.54C, V1.60, V1.64, V1.69, V1.70, V1.73, V1.77, V1.80, V1.81.</i>
  <br>
  Mehr Infos im entsprechenden <u><a href="http://www.fhemwiki.de/wiki/Luxtronik_2.0">Artikel der FHEM-Wiki</a></u>.
  <br>&nbsp;
  <br>
  <a name="LUXTRONIK2define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LUXTRONIK2 &lt;IP-Adresse[:Port]&gt; [Abfrageinterval]</code>
    <br>
    Wenn das Abfrage-Interval nicht angegeben ist, wird es auf 300 (Sekunden) gesetzt. Der kleinste mögliche Wert ist 10.
    <br>
    Die Angabe des Portes kann gewöhnlich entfallen.
    <br>
    Beispiel: <code>define Heizung LUXTRONIK2 192.168.0.12 600</code>
 
  </ul>
  <br>
  
  <a name="LUXTRONIK2set"></a>
  <b>Set</b><br>
  <ul>
     Durch einen Firmware-Test wird vor jeder Set-Operation sichergestellt, dass Wärmepumpen mit ungetesteter Firmware nicht unabsichtlich beschädigt werden.
     <br>&nbsp;
       <li><code>activeTariff &lt; 0 - 9 &gt;</code>
         <br>
         Erlaubt die gezielte, separate Erfassung der statistischen Verbrauchswerte (doStatistics = 1) für verschiedene Tarife (Doppelstromzähler)<br>
         Dieser Wert muss entsprechend des vorhandenen oder geplanten Tarifes zum jeweiligen Zeitpunkt z.B. durch den FHEM-Befehl "at" gesetzt werden.<br>
         0 = tariflos 
      </li><br>
      <li><code>heatingCurveEndPoint &lt;Temperatur&gt;</code><br>
         Einstellung des Heizkurven-Parameters. In 0.1er Schritten einstellbar.
      </li><br>
      <li><code>heatingCurveOffset &lt;Temperatur&gt;</code><br>
         Einstellung des Heizkurven-Parameters. In 0.1er Schritten einstellbar.
      </li><br>
      <li><code>hotWaterCircPumpDeaerate &lt;on | off&gt;</code><br>
         Schaltet die externe Warmwasser-Zirkulationspumpe an oder aus. Durch die Zirkulation wird das Abkühlen des Warmwassers in den Hausleitungen verhindert. Der Wärmeverbrauch steigt jedoch drastisch.
         <br>
         Achtung! Es wird die Entlüftungsfunktion der Steuerung genutzt. Dadurch taktet die Pumpe jeweils 5 Minuten ein und 5 Minuten aus.
         </li><br>
     <li><code>hotWaterTemperatureTarget &lt;Temperatur&gt;</code>
         <br>
         Soll-Temperatur des Heißwasserspeichers in °C
         </li><br>
      <li><code>opModeHotWater &lt;Betriebsmodus&gt;</code>
         <br>
         Betriebsmodus des Heißwasserspeichers ( Auto | Party | Off )
         </li><br>
     <li><code>resetStatistics &lt;statWerte&gt;</code>
         <br>
         Löscht die ausgewählten statistischen Werte: <i>all, statBoilerGradientCoolDownMin, statAmbientTemp..., statElectricity..., statHours..., statHeatQ...</i>
         </li><br>
     <li><code>returnTemperatureHyst &lt;Temperatur&gt;</code>
         <br>
         Sollwert-Hysterese der Heizungsregelung. 0.5 K bis 3 K. In 0.1er Schritten einstellbar.
         </li><br>
     <li><code>returnTemperatureSetBack &lt;Temperatur&gt;</code>
         <br>
         Absenkung oder Anhebung der Rücklauftemperatur von -5 K bis + 5K. In 0.1er Schritten einstellbar.
         </li><br>
     <li><code>INTERVAL &lt;Sekunden&gt;</code>
         <br>
         Abfrageintervall in Sekunden
         </li><br>
     <li><code>statusRequest</code>
         <br>
         Aktualisieren der Gerätewerte
         </li><br>
     <li><code>synchClockHeatPump</code>
         <br>
         Abgleich der Uhr der Steuerung mit der FHEM Zeit. <b>Diese Änderung geht verloren, sobald die Steuerung ausgeschaltet wird!!</b></li>
  </ul>
  <br>
  
  <a name="LUXTRONIK2get"></a>
  <b>Get</b>
  <ul>
      <li><code>heatingCurveParameter &lt;Aussentemp1 Solltemp1 Aussentemp2 Solltemp2&gt;</code>
      <br>
      Ermittelt rekursiv anhand zweier Punkte auf der Heizkurve die entsprechenden Heizkurven-Parameter <i>heatingCurveEndPoint</i> und <i>heatingCurveOffset</i>.<br>
      Diese können dann über die entsprechenden set-Befehl einstellt werden.
      </li>
      <br>
      <li><code>rawData</code>
      <br>
      Zeigt alle von der Steuerung auslesbaren Parameter und Betriebswerte an.<br>
      Diese können dann mit den Attributen <i>userHeatpumpParameters</i> und <i>userHeatpumpValues</i> einem Gerätewert zugeordnet werden.
      </li><br>
  </ul>
  <br>
  
  <a name="LUXTRONIK2attr"></a>
  <b>Attribute</b>
  <ul>
   <li><code>allowSetParameter &lt; 0 | 1 &gt;</code>
      <br>
      Die internen <a href="#LUXTRONIK2set">Parameter</a> der Wärmepumpensteuerung können
      nur geändert werden, wenn dieses Attribut auf 1 gesetzt ist.
      </li><br>
   <li><code>autoSynchClock &lt;Zeitunterschied&gt;</code>
      <br>
      Die Uhr der Wärmepumpe wird automatisch korrigiert, wenn ein gewisser <i>Zeitunterschied</i> (10 s - 600 s) 
      gegenüber der FHEM Zeit erreicht ist. Zuvor wird die Kompatibilität der Firmware überprüft.<br>
      <i>(Ein Gerätewert 'delayDeviceTimeCalc' &lt;= 2 s ist auf die internen Berechnungsintervale der
      Wärmepumpensteuerung zurückzuführen.)</i>
      </li><br>
    <li><code>compressor2ElectricalPowerWatt</code><br>
      Betriebsleistung des zweiten Kompressors zur Berechnung der Arbeitszahl (erzeugte Wärme pro elektrische Energieeinheit)
      und Abschätzung des elektrischen Verbrauches (Auswertungen noch nicht implementiert)
      </li><br>
    <li><code>doStatistics &lt; 0 | 1 | 2 &gt;</code>
      <br>
      Berechnet statistische Werte: <i>statBoilerGradientHeatUp, statBoilerGradientCoolDown,
      statBoilerGradientCoolDownMin (Wärmeverlust des Boilers)</i>
      <br>
      Bildet tägliche, monatliche und jährliche Statistiken bestimmter Gerätewerte.<br>
      Für grafische Auswertungen können die Werte der Form 'stat<i>ReadingName</i><b>Last</b>' genutzt werden.
      </li><br>
    <li><code>heatPumpElectricalPowerWatt &lt;E-Leistung in Watt&gt;</code><br>
      Elektrische Leistungsaufnahme der Wärmepumpe in Watt bei einer Vorlauftemperatur von 35 &deg;C zur Berechung der Arbeitszahl (erzeugte Wärme pro elektrische Energieeinheit)
      und Abschätzung des elektrischen Verbrauches
      </li><br>
    <li><code>heatPumpElectricalPowerFactor</code><br>
         änderung der elektrischen Leistungsaufnahme pro 1 K Vorlauftemperaturdifferenz zu 35 &deg;C
         <br>
         (z.B. 2% pro 1 K = 0,02)
         </li><br>
    <li><code>heatRodElectricalPowerWatt &lt;E-Leistung in Watt&gt;</code><br>
      Elektrische Leistungsaufnahme der Heizstäbe in Watt zur Abschätzung des elektrischen Verbrauches
      </li><br>
   <li><code>ignoreFirmwareCheck &lt; 0 | 1 &gt;</code>
      <br>
      Durch einen Firmware-Test wird vor jeder Set-Operation sichergestellt, dass Wärmepumpen
      mit ungetester Firmware nicht unabsichtlich beschädigt werden. Wenn dieses Attribute auf 1
      gesetzt ist, dann wird der Firmware-Test ignoriert und neue Firmware kann getestet werden.
      Dieses Attribut wird jedoch ignoriert, wenn die Steuerung-Firmware bereits als nicht kompatibel berichtet wurde.
      </li><br>
    <li><code>statusHTML</code>
      <br>
      Wenn gesetzt, dann wird ein HTML-formatierter Wert "floorplanHTML" erzeugt, 
      welcher vom Modul <a href="#FLOORPLAN">FLOORPLAN</a> genutzt werden kann.<br>
      Momentan wird nur geprüft, ob der Wert dieses Attributes ungleich NULL ist, 
      der entsprechende Gerätewerte besteht aus dem aktuellen Wärmepumpenstatus und der Warmwassertemperatur.
      </li><br>
    <li><code>userHeatpumpParameters &lt;Index [Name][,Index2 [Name2],Index3 [Name3] ...]&gt;</code>
      <br>
      Erlaubt das Auslesen der Werte benutzerspezifischer Parameter. Die Indizes der verfügbaren Parameterwerte können mit dem get-Befehl <i>rawData</i> ermittelt werden.<br> 
      In der Attributdefinition kann der Name hinter den Index getrennt durch ein Leerzeichen geschrieben werden. Der jeweilige Parameter-Wert wird entweder mit dem Präfix "userParameter..." oder unter dem angegebenen Namen angezeigt. <br>
      Mehrere Indizes werden durch Kommas getrennt.<br>
      Nicht mehr benötigte Gerätewerte können mit dem FHEM-Befehl <a href="#deletereading">deleteReading</a> gelöscht werden.
      </li><br>
    <li><code>userHeatpumpValues &lt;Index Name[,Index2 Name2,Index3 Name3 ...]&gt;</code>
      <br> 
      Erlaubt das Auslesen benutzerspezifische Betriebswerte. Vorgehen wie bei <i>userHeatpumpParameters</i>.
      </li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a>
    </li><br>
  </ul>
</ul>
</div>
=end html_DE
=cut

