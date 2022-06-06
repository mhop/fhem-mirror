########################################################################################
#
# Vaillant_routines.pl ===> Insert into 99_myUtils.pm 
#
# Collection of various routines for Vaillant heating systems
#
# KEEP THE NAME AND COPYRIGHT 
#
# Prof. Dr. Peter A. Henning
#
# $Id: 99_myUtils.pm 2014-12 - pahenning $
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
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
########################################################################################

###############################################################################
#
#  Vaillant_HWC_mode_postproc
#
#  postprocessing of 
#  "get HWC OperatingMode\n\000get HWC Param1"
#  "read HWC Status2\n\000read SOL Status2"
#
###############################################################################

sub Vaillant_HWC_mode_postproc($$){

  my ($name,$str)=@_;
  my  $hash   = $defs{"$name"};
  my (@values,$day,$night,$off,$min,$max,$mode,$zval);

  if( $str =~ /.*;.*/){
     # target;mode target;0;0;0;131;22;0;min;max;0
     @values = split(/[; \n]/,$str);
     $day    = sprintf("%4.1f",$values[0]);
     $mode   = $values[1];
     $night  = sprintf("%4.1f",$values[6]);
     $off    = sprintf("%4.1f",$values[7]);
     $min    = sprintf("%4.1f",$values[9]);
     $max    = sprintf("%4.1f",$values[10]);
  } else {   
     @values = split(' ',$str);
     $day    = sprintf("%4.1f",$values[0]);
     $night  = sprintf("%4.1f",$values[4]);
     $off    = sprintf("%4.1f",$values[5]);
     $min    = sprintf("%4.1f",$values[6]);
     $max    = sprintf("%4.1f",$values[7]);
     if( $values[1]==0 ){
       $mode="disabled"
     }elsif( $values[1]==1 ){
       $mode="on"
     }elsif( $values[1]==2 ){
       $mode="off"
     }elsif( $values[1]==3 ){
       $mode="auto"
     }elsif( $values[1]==4 ){
       $mode="eco"
     }elsif( $values[1]==5 ){
       $mode="low"
     } 
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "postproc", $str);
  readingsBulkUpdate($hash, "mode", $mode);
  readingsBulkUpdate($hash, "Storage.day", $day);
  readingsBulkUpdate($hash, "Storage.min", $min);
  readingsBulkUpdate($hash, "Storage.max", $max);
  readingsEndUpdate($hash,1);
  $mode;
  }

###############################################################################
#
#  Vaillant_HWC_state_postproc
#
#  postprocessing of 
#  "get HWC Status2\n\000get SOL Status2"
#  "read HWC Status2\n\000read SOL Status2"
#
###############################################################################

sub Vaillant_HWC_state_postproc($$){

  my ($name,$str)=@_;
  my  $hash   = $defs{"$name"};
  my (@values,$rval,$tval,$bval,$pval,$xval,$zval,$sp2,$sp3);

  if( $str =~ /.*;.*/){
     # status;ladung;SP1;target SP1;SP2;SP3 
     @values = split(/[; \n]/,$str);
     $rval = sprintf("%5.2f",$values[2]);
     $tval = sprintf("%4.1f",$values[3]);
     $bval = ($values[0] == 80) ? "ON (WW)" : "OFF";
     $pval = ($values[1] == 1) ? "ON" : "OFF";
     $xval = sprintf("%5.2f %5.2f %5.2f %d %d", $values[2],0.0,$values[3],$values[0],$values[1]);
     $zval = sprintf("SP1.T %5.2f °C, %s", $values[2],$pval);
     $sp2  = sprintf("%5.2f",$values[5]);
     $sp3  = sprintf("%5.2f",$values[6]);

  }else{
     # SP1 target status ladung SP1 SP2 SP3 
     @values = split(' ',$str);
     $rval = sprintf("%5.2f",$values[0]);
     $tval = sprintf("%4.1f",$values[1]);
     $bval = ($values[2] == 80) ? "ON (WW)" : "OFF";
     $pval = ($values[3] == 1) ? "ON" : "OFF";
     $xval = sprintf("%5.2f %5.2f %5.2f %d %d", $values[0],0.0,$values[1],$values[2],$values[3]);
     $zval = sprintf("SP1.T %5.2f °C, %s", $values[0],$pval);
     $sp2  = sprintf("%5.2f",$values[5]);
     $sp3  = sprintf("%5.2f",$values[6]);

  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "postproc", $str);
  readingsBulkUpdate($hash, "Storage.SP1.T", $rval);
  readingsBulkUpdate($hash, "Storage.SP2.T", $sp2);
  readingsBulkUpdate($hash, "Storage.SP3.T", $sp3);
  readingsBulkUpdate($hash, "Storage.target", $tval);
  readingsBulkUpdate($hash, "Burner", $bval);
  readingsBulkUpdate($hash, "Pump", $pval);
  readingsBulkUpdate($hash, "reading", $xval);
  readingsEndUpdate($hash,1);
  $zval; 
}
  

###############################################################################
#
#  Vaillant_HWC_broadcast_postproc
#
#  postprocessing of 
#  "get cyc broad StatusHWC\n"
#  "read broad StatusHWC
#
###############################################################################

sub Vaillant_HWC_broadcast_postproc($$){

  my ($name,$str)=@_;
  my  $hash   = $defs{"$name"};
  my (@values,$rval,$tval,$bval,$pval,$xval,$zval);

  if( ($str eq "")||($str eq "no data stored") ){
    $rval = "err";
    $tval = "err";
    $bval = "err";
    $pval = "err";
    $xval = "err";
    $zval = "err";
  } elsif( $str =~ /.*;.*/){
    # status;ladung;SP1;target 
    @values = split(';',$str);
    $rval = sprintf("%5.2f",$values[2]);
    $tval = sprintf("%4.1f",$values[3]);
    $bval = ($values[0] == 80) ? "ON (WW)" : "OFF";
    $pval = ($values[1] == 1) ? "ON" : "OFF";
    $xval = sprintf("%5.2f %5.2f %5.2f %d %d", $values[2],0.0,$values[3],$values[0],$values[1]);
    $zval = sprintf("SP1.T %5.2f °C, %s", $values[2],$pval);
  } else {
    @values=split(' ',$str);
    if( $values[1] < 15 ){
      $rval = "err";
      $tval = "err";
      $bval = "err";
      $pval = "err";
      $xval = "err";
      $zval = "err";
    }else {
      $rval = sprintf("%5.2f",$values[0]);
      $tval = sprintf("%4.1f",$values[1]);
      $bval = ($values[2] == 80) ? "ON (WW)" : "OFF";
      $pval = ($values[3] == 1) ? "ON" : "OFF";
      $xval = sprintf("%5.2f %5.2f %5.2f %d %d",$values[0],0.0,$values[1],$values[2],$values[3]);
      $zval = sprintf("SP1.T %5.2f °C, %s",$values[0],$pval);
    }
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "postproc", $str);
  readingsBulkUpdate($hash, "Storage.SP1.T", $rval);
  readingsBulkUpdate($hash, "Storage.target", $tval);
  readingsBulkUpdate($hash, "Burner", $bval);
  readingsBulkUpdate($hash, "Pump", $pval);
  readingsBulkUpdate($hash, "reading", $xval);
  readingsEndUpdate($hash,1);
  $zval; 
}

###############################################################################
#
#  Vaillant_HC_mode_postproc
#
#  postprocessing of 
#  "get HC OperatingMode\n\000get HC Param1\n\000get vrs620 NameHC"
#  "read HC OperatingMode\n\000read HC Param1\n\000read vrs620 NameHC"
#
###############################################################################

sub Vaillant_HC_mode_postproc($$$){

  my ($name,$str,$circuit)=@_;
  my  $hash   = $defs{"$name"};
  my (@values,$room,$night,$off,$add,$min,$max,$pre,$cname,$mode);
  
  $circuit=""
    if ( $circuit == 1);

  if( $str =~ /.*;.*/){
     # room;mode room;night;off;add;min;max;pre cname
     @values = split(/[; \n]/,$str);
     $room   = sprintf("%4.1f",$values[0]);
     $mode   = $values[1];
     $night  = sprintf("%4.1f",$values[3]);
     $off    = sprintf("%4.1f",$values[4]);
     $add    = sprintf("%4.1f",$values[5]);
     $min    = sprintf("%4.1f",$values[6]);
     $max    = sprintf("%4.1f",$values[7]);
     $pre    = sprintf("%4.1f",$values[8]);
     $cname   = sprintf("%s",$values[9]);
  } else {
     @values = split(' ',$str);
     $room   = sprintf("%4.1f",$values[0]);
     $night  = sprintf("%4.1f",$values[4]);
     $off    = sprintf("%4.1f",$values[5]);
     $add    = sprintf("%4.1f",$values[6]);
     $min    = sprintf("%4.1f",$values[7]);
     $max    = sprintf("%4.1f",$values[8]);
     $pre    = sprintf("%4.1f",$values[9]);
     $cname   = sprintf("%s",$values[10]);
     if( $values[1]==0 ){
       $mode="disabled"
     }elsif( $values[1]==1 ){
       $mode="on"
     }elsif( $values[1]==2 ){
       $mode="off"
     }elsif( $values[1]==3 ){
       $mode="auto"
     }elsif( $values[1]==4 ){
       $mode="eco"
     }elsif( $values[1]==5 ){
       $mode="low"
     } 
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "postproc", $str);
  readingsBulkUpdate($hash, "mode".$circuit, $mode);
  readingsBulkUpdate($hash, "mode".$circuit.".off", $off);
  readingsBulkUpdate($hash, "Room".$circuit.".T", $room);
  readingsBulkUpdate($hash, "Room".$circuit.".night", $night);
  readingsBulkUpdate($hash, "Room".$circuit.".add", $add);
  readingsBulkUpdate($hash, "VL".$circuit.".T.min", $min);
  readingsBulkUpdate($hash, "VL".$circuit.".T.max", $max);
  readingsBulkUpdate($hash, "name".$circuit, $cname);
  readingsEndUpdate($hash,1);
  $mode;
}

###############################################################################
#
#  Vaillant_HC_mode_postproc
#
#  postprocessing of 
#  "read HC Status1\n\000read HC Status2a\n\000read broad StatusHC"
# 
#
###############################################################################

sub Vaillant_HC_state_postproc($$){

  my ($name,$str)=@_;
  my  $hash   = $defs{"$name"};
  my (@values,$vval,$rval,$bval,$pval, $qval,$xval,$zval);

  if( ($str eq "")||($str eq "no data stored") ){
     $vval = "err";
     $rval = "err";
     $bval = "err";
     $pval = "err";
     $qval = "err";
     $xval = "err";
     $zval = "err";
  }elsif( $str =~ /.*;.*/){
     # 
     @values = split(/[; \n]/,$str);
     $vval = sprintf("%4.1f",$values[10]);
     $rval = sprintf("%4.1f",$values[11]);
     if( $values[14] == 0 ){
        $pval = "OFF";
        $qval = "0 0";
     }elsif( $values[14] == 1 ){
        $pval = "ON (HK)";
        $qval = "80 0";
     }elsif( $values[14] == 2 ){
        $pval = "ON (WW)";
        $qval = "0 80";
     }else{
        $pval = "unknown";
        $qval = "err";
     }

  }else{
     # 
     @values = split(' ',$str);
     $vval  = sprintf("%4.1f",$values[5]);
     $rval  = sprintf("%4.1f",$values[6]);
     if( $values[2] == 0 ){
        $pval = "OFF";
        $qval = "0 0";
     }elsif( $values[2] == 1 ){
        $pval = "ON (HK)";
        $qval = "80 0";
     }elsif( $values[2] == 2 ){
        $pval = "ON (WW)";
        $qval = "0 80";
     }else{
        $pval = "unknown";
        $qval = "err";
     }
  }
  
  $bval = HzBedarf();
  $xval = sprintf("%5.2f %5.2f %s %5.2f",$vval,$rval,$qval,$bval);
  $zval = sprintf("VL.T %5.2f °C, RL.T %5.2f °C, %s",$vval,$rval,$pval);
  
  if( ($vval < 5) ){
     $vval = "err";
     $rval = "err";
     $bval = "err";
     $pval = "err";
     $qval = "err";
     $xval = "";
     $zval = "err";
  }
    
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "postproc", $str);
  readingsBulkUpdate($hash, "VL.T", $vval);
  readingsBulkUpdate($hash, "RL.T", $rval);
  readingsBulkUpdate($hash, "pump", $pval); 
  readingsBulkUpdate($hash, "pump.P", $qval);
  readingsBulkUpdate($hash, "consumption", $bval);
  readingsBulkUpdate($hash, "reading", $xval) 
    if( $xval ne "" );
  readingsEndUpdate($hash,1);
  $zval
}
  
###############################################################################
#
#  Vaillant_SOL_mode_postproc
#
#  postprocessing of 
#  "get HC OperatingMode\n\000get HC Param1\n\000get vrs620 NameHC"
#  "read HC OperatingMode\n\000read HC Param1\n\000read vrs620 NameHC"
#
###############################################################################

sub Vaillant_SOL_state_postproc($$){

  my ($name,$str)=@_;
  my  $hash   = $defs{"$name"};
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "postproc", $str);
  readingsEndUpdate($hash,1);
}  
  
  
###############################################################################
#
#  Vaillant_Timer
#
###############################################################################

sub Vaillant_Timer($)
{
  my @values=split(/[; ]/,$_);
  #-- suppress leading zero ?
  for(my $i=0;$i<6;$i++){ 
    $values[$i]=~s/^0//;
  }
  my $sval=sprintf("%s-%s",$values[0],$values[1]);
  $sval  .=sprintf(", %s-%s",$values[2],$values[3])
    if($values[2] ne $values[3]);
  $sval  .=sprintf(", %s-%s",$values[4],$values[5])
    if($values[4] ne $values[5]);
  return $sval;
}