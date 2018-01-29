########################################################################################
#
# PostMe.pm
#
# FHEM module to set up a system of sticky notes, similar to Post-Its
#
# Prof. Dr. Peter A. Henning
#
# $Id$
#
# Not named Post-It, which is a trademark of 3M
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

package main;

use strict;
use warnings;
use vars qw(%defs);		        # FHEM device/button definitions
use vars qw($FW_RET);           # Returned data (html)
use vars qw($FW_RETTYPE);       # image/png or the like
use vars qw($FW_wname);         # Web instance

use Time::Local;

#########################
# Global variables
my $postmeversion  = "2.07";
my $FW_encoding    = "UTF-8";

#########################################################################################
#
# PostMe_Initialize 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub PostMe_Initialize ($) {
  my ($hash) = @_;
  
  my $devname = $hash->{NAME}; 
		
  $hash->{DefFn}       = "PostMe_Define";
  $hash->{SetFn}   	   = "PostMe_Set";  
  $hash->{GetFn}       = "PostMe_Get";
  $hash->{UndefFn}     = "PostMe_Undef";  
  $hash->{InitFn}      = "PostMe_Init";  
  $hash->{AttrFn}      = "PostMe_Attr";
  $hash->{AttrList}    = "postmeTTSFun postmeTTSDev postmeMsgFun postme[0-9]+MsgRec postmeMailFun postme[0-9]+MailRec ".
                         "postmeStd postmeIcon postmeStyle:test,jQuery,HTML,SVG postmeClick:0,1 listseparator ".$readingFnAttributes;		
  
  $hash->{FW_detailFn}  = "PostMe_detailFn";
    	 
  $data{FWEXT}{"/PostMe_widget"}{FUNC} = "PostMe_widget";
  $data{FWEXT}{"/PostMe_widget"}{FORKABLE} = 1; 
	
  return undef;
}

#########################################################################################
#
# PostMe_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub PostMe_Define ($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $now = time();
  my $devname = $hash->{NAME}; 
 
  $modules{PostMe}{defptr}{$a[0]} = $hash;

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","Initialized");
  readingsEndUpdate($hash,1); 
  InternalTimer(gettimeofday()+2, "PostMe_Init", $hash,0);

  return undef;
}

#########################################################################################
#
# PostMe_Undef - Implements Undef function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub PostMe_Undef ($$) {
  my ($hash,$arg) = @_;
  
  RemoveInternalTimer($hash);
  
  return undef;
}

#########################################################################################
#
# PostMe_Attr - Implements Attr function
# 
# Parameter hash = hash of device addressed, ???
#
#########################################################################################

sub PostMe_Attr($$$) {
  my ($cmd, $listname, $attrName, $attrVal) = @_;
  return;  
}

#########################################################################################
#
# PostMe_Init - Check, if default PostMes have been defined
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub PostMe_Init($) {
   my ($hash) = @_;
   my $devname = $hash->{NAME};
   my $now = time();
   my $err = 0; 
   
   #-- current number of PostMes
   my $cnop = ReadingsVal($devname,"postmeCnt",0);
   my @std  = split(',',AttrVal("$devname","postmeStd",""));
   
   for( my $i=0;$i<int(@std);$i++ ){
     my $pmn = PostMe_Check($hash,$std[$i]);
     if( !$pmn || ($pmn-1)!=$i ){
       $err = 1;
       Log 1,"[PostMe_Init] PostMe ".$std[$i]." not properly defined";
     }
   }
   
   #-- no write operation if everything is ok
   return undef
     if( $err==0 );

   #-- must be improved: Enforce first PostMes to be the standard ones
   for( my $i=0;$i<int(@std);$i++ ){
     PostMe_Create($hash,$std[$i]);
   }
   readingsSingleUpdate($hash,"state","OK",1);
}
 
#########################################################################################
#
# PostMe_Check - Check, if a PostMe exists with this name and return its number
# 
# Parameter hash = ash of device addressed
#           listname = name of PostMe
#
#########################################################################################

sub PostMe_Check($$) {
   my ($hash,$listname) = @_;
   my $devname = $hash->{NAME};
   my ($loop,$res); 
   
   #-- current number of PostMes
   my $cnop = ReadingsVal($devname,"postmeCnt",0);

   for( $loop=1;$loop<=$cnop;$loop++){
     $res = ReadingsVal($devname, sprintf("postme%02dName",$loop), undef);
     last 
       if($res eq $listname);
   }
   #-- no PostMe with this name
   if( $res ne $listname ){
     return undef;
   }else{
     return $loop;
   }
 }
   
#########################################################################################
#
# PostMe_Create - Create a new PostMe
# 
# Parameter hash = hash of device addressed
#           listname = name of PostMe
#
#########################################################################################

sub PostMe_Create($$) {
   my ($hash,$listname) = @_;
   my $devname = $hash->{NAME}; 
   
   if( PostMe_Check($hash,$listname) ){
     my $mga = "Error, a PostMe named $listname does already exist";
     Log 1,"[PostMe_Create] $mga";
     return "$mga";
   }
   
   #-- current number of PostMes
   my $cnop = ReadingsVal($devname,"postmeCnt",0);
   $cnop++;
   
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash, sprintf("postme%02dName",$cnop),$listname);
   readingsBulkUpdate($hash, sprintf("postme%02dCont",$cnop),"");
   readingsBulkUpdate($hash, "postmeCnt",$cnop);
   readingsEndUpdate($hash,1); 
 
   Log3 $devname,3,"[PostMe] Added a new PostMe named $listname";
   return undef;
}

#########################################################################################
#
# PostMe_Delete - Delete an existing PostMe
# 
# Parameter hash = hash of device addressed
#           listname = name of PostMe
#
#########################################################################################

sub PostMe_Delete($$) {
   my ($hash,$listname) = @_;
   my $devname = $hash->{NAME}; 
   my $loop;
   
   if( index(AttrVal("$devname","postmeStd",""),$listname) != -1){
     my $mga = "Error, the PostMe named $listname is a standard PostMe and cannot be deleted";
     Log 1,"[PostMe_Delete] $mga";
     return "$mga";
   }
   
   my $pmn=PostMe_Check($hash,$listname);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $listname does not exist";
     Log 1,"[PostMe_Delete] $mga";
     return "$mga";
   }
    
   #-- current number of PostMes
   my $cnop = ReadingsVal($devname,"postmeCnt",0);
   
   readingsBeginUpdate($hash);
   #-- re-ordering
   for( $loop=$pmn;$loop<$cnop;$loop++){
     readingsBulkUpdate($hash, sprintf("postme%02dName",$loop),
       ReadingsVal($devname, sprintf("postme%02dName",$loop+1),""));
     readingsBulkUpdate($hash, sprintf("postme%02dCont",$loop),
       ReadingsVal($devname, sprintf("postme%02dCont",$loop+1),""));
   }
   $cnop--;
   readingsBulkUpdate($hash, "postmeCnt",$cnop);
   readingsEndUpdate($hash,1); 
      
   fhem("deletereading $devname ".sprintf("postme%02dName",$cnop+1));
   fhem("deletereading $devname ".sprintf("postme%02dCont",$cnop+1));

   Log3 $devname,3,"[PostMe] Deleted PostMe named $listname";
   return undef;
 }

#########################################################################################
#
# PostMe_Rename - Renames an existing PostMe
# 
# Parameter hash = hash of device addressed
#           listname = name of PostMe
#           newname = newname of PostMe
#
#########################################################################################

sub PostMe_Rename($$$) {
   my ($hash,$listname,$newname) = @_;
   my $devname = $hash->{NAME}; 
   my $loop;
   
   if( index(AttrVal("$devname","postmeStd",""),$listname) != -1){
     my $mga = "Error, the PostMe named $listname is a standard PostMe and cannot be renamed";
     Log 1,"[PostMe_Rename] $mga";
     return "$mga";
   }
   
   my $pmn=PostMe_Check($hash,$listname);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $listname does not exist";
     Log 1,"[PostMe_Rename] $mga";
     return "$mga";
   }

   my $pnn=PostMe_Check($hash,$newname);
   
   if( $pnn ){ 
       my $mga = "Error, a PostMe named $newname does already exist and is not empty";
       Log 1,"[PostMe_Rename] $mga";
       return "$mga";
   }  
   
   readingsSingleUpdate($hash,sprintf("postme%02dName",$pmn),$newname,1);
   
   Log3 $devname,3,"[PostMe] Renamed PostMe named $listname into $newname";
   return undef;
}

#########################################################################################
#
# PostMe_Add - Add something to a PostMe
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub PostMe_Add($$@) {
   my ($hash,$listname,@args) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$listname);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $listname does not exist";
     Log 1,"[PostMe_Add] $mga";
     return "$mga";
   }
   my $raw = join(' ',@args);
   
   #-- remove meta data
   my $item = $raw;
   $item =~ s/\[.*\]//g;
   $item =~ s/\]//g;
   $item =~ s/\[//g;
   
   #-- safety catch: No action when item empty
   if( $item eq "" ){
     my $mga = "Error, empty item given";
     Log 1,"[PostMe_Add] $mga";
     return "$mga";
   }
   
   #-- check old content
   my $old  = ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"");
   my $ind  = index($old,$item);
   if( $ind >= 0 ){
     my $mga = "Error, item $item is already present in PostMe $listname";
     Log 1,"[PostMe_Add] $mga";
     return "$mga"; 
   }
   $old    .= AttrVal($devname,"listseparator",',')
     if($old ne "");
   #-- TODO: META DATA MISSING
   readingsSingleUpdate($hash, sprintf("postme%02dCont",$pmn),$old.$item,1);

   Log3 $devname,3,"[Postme] Added item $item to PostMe named $listname";
   return undef;
 }
 
#########################################################################################
#
# PostMe_Remove - Remove something from a PostMe
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub PostMe_Remove($$@) {
   my ($hash,$listname,@args) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$listname);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $listname does not exist";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   my $raw = join(' ',@args);
   my $listsep = AttrVal($devname,"listseparator",',');
   
   #-- remove meta data
   my $item = $raw;
   $item =~ s/\[.*\]//g;
   
   #-- safety catch: No action when item empty
   if( $item eq "" ){
     my $mga = "Error, empty item given";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   
   #-- get old content
   my $new  = "";
   my $old  = ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"");
   my @lines= split($listsep,$old);
      
   #-- item may be of type item\d\d
   if( $item =~ /item(\d+)/ ){
     $item = $lines[$1];
   }
   
   #-- check old content
   my $ind  = index($old,$item);
   if( $ind < 0 ){
     my $mga = "Error, item $item is not present in PostMe $listname";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   
   #-- item may be a short version of the real entry
   for( my $loop=0;$loop<int(@lines);$loop++){
     $ind  = index($lines[$loop],$item);
     #-- cleanup reminders
     if( $ind >= 0 ){
       my $line = $lines[$loop];
       my $itex = $line;
       my $meta = $line;
       $itex    =~ s/\s*\[.*//;
       #-- only if attributes present
       if( $line =~ /.*\[.*\].*/){
         $meta =~ s/.*\[//;
         $meta =~ s/\]//;
         my @lines2 = split('" ',$meta);
         for( my $loop2=0;$loop2<int(@lines2);$loop2++){
           my $attr = $lines2[$loop2];
           $attr   =~ /(.*)="(.*)/;
           $attr   = $1;
           my $val = $2;
           PostMe_cleanSpecial($hash,$listname,$itex,$attr);
         }
       } 
     #-- different item
     }else{
       $new  .= $lines[$loop].$listsep;
     }  
   }
   $new =~ s/$listsep$listsep/$listsep/;
   $new =~ s/^$listsep//;
   $new =~ s/$listsep$//;
   
   readingsSingleUpdate($hash, sprintf("postme%02dCont",$pmn),$new,1);

   Log3 $devname,3,"[Postme] Removed item $item from PostMe named $listname";
   return undef;
 }

#########################################################################################
#
# PostMe_Clear - clear a PostMe
# 
# Parameter hash = hash of device addressed
#           name = name of PostMe
#
#########################################################################################

sub PostMe_Clear($$) {
   my ($hash,$listname) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$listname);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $listname does not exist";
     Log 1,"[PostMe_Clear] $mga";
     return "$mga";
   }
   PostMe_Special($hash,$listname,1);
   readingsSingleUpdate($hash, sprintf("postme%02dCont",$pmn),"",1 );
   
   Log3 $devname,3,"[PostMe_Clear] Cleared PostMe named $listname";
   return undef;
 }

#########################################################################################
#
# PostMe_Modify - Annotate an item from a PostMe with meta data
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub PostMe_Modify($$@) {
   my ($hash,$listname,@args) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$listname);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $listname does not exist";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   my $listsep = AttrVal($devname,"listseparator",',');
   #-- difficult to separate item from new meta data. For now, first term is the item,
   #   second term is the attribute and remaining terms are the value
   my $item = $args[0];
   my $attr = $args[1];
   splice(@args,0,2);
   my $val  = join(' ',@args);
   
   #-- safety catch: No action when item empty
   if( $item eq "" ){
     my $mga = "Error, empty item given";
     Log 1,"[PostMe_Modify] $mga";
     return "$mga";
   }
   
   #-- check old content
   my $old  = ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"");
   my $ind  = index($old,$item);
   if( $ind < 0 ){
     my $mga = "Error, item $item is not present in PostMe $listname";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   #-- item 
   my @lines = split($listsep,$old);
   my $new   = "";
   for( my $loop=0;$loop<int(@lines);$loop++){
     $old  = $lines[$loop];
     $ind  = index($old,$item);
     #-- different item
     if( $ind < 0 ){
       $new  .= $old.$listsep;
     #-- correct item
     }elsif( $ind == 0 ){
       #-- item may be a short version of the real entry, or may consist of several words
       my $fullitem = $old;
       $fullitem    =~ s/\s*\[.*//;
       $item        = $fullitem
         if( $fullitem ne $item );
       $new .= $item.' [';
       #-- no attributes present so far
       if( ($old !~ /.*\[.*\].*/) && ($val) ){ 
         #PostMe_cleanSpecial($hash,$listname,$item,$attr);
         PostMe_procSpecial($hash,$listname,$item,$attr,$val);
         $new .= $attr.'="'.$val.'"';
       #-- attributes present already
       }else{
         $old =~ s/.*\[//;
         $old =~ s/\]//;
         #-- particular attribute not yet present
         if( index($old,$attr) < 0){
           if( $val ){
             #PostMe_cleanSpecial($hash,$listname,$item,$attr);
             PostMe_procSpecial($hash,$listname,$item,$attr,$val);
             $new .= $old.' '.$attr.'="'.$val.'"'
           } 
         #-- particular attribute already present        
         }else{
           my @lines2 = split('" ',$old);
           for( my $loop2=0;$loop2<int(@lines2);$loop2++){
             my $ind2 = index($lines2[$loop2],$attr);
             #-- different attribute
             if( $ind2 < 0){
               $new .= $lines2[$loop2].'" ';
             #-- correct attribute
             }else{
               #-- overwrite, if val ist given
               if( $val ){
                 PostMe_cleanSpecial($hash,$listname,$item,$attr);
                 PostMe_procSpecial($hash,$listname,$item,$attr,$val);
                 $new .= $attr.'="'.$val.'" ';
               #-- remove, if no val is given
               }
             }
           } 
         }  
       }  
       $new .= ']'.$listsep; 
     } 
   }
   #-- correction of sloppy formatting above
   $new =~ s/\s\[\]//g;
   $new =~ s/\s\]/\]/g;
   $new =~ s/\[\s/\[/g;
   $new =~ s/""/"/g;
   $new =~ s/$listsep$//g;
   
   readingsSingleUpdate($hash, sprintf("postme%02dCont",$pmn),$new,1);

   Log3 $devname,3,"[Postme] Modified item $item in PostMe named $listname";
   return undef;
}
 
########################################################################################
#
# PostMe_Special - process all special annotations of a PostMe
# 
# Parameter hash     = hash of device addressed
#           listanem = name of the PostMe
#           clean    = 0 normal processing, = 1 clean all reminders
#
#########################################################################################

sub PostMe_Special($$$) {
   my ($hash,$listname,$clean) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$listname);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $listname does not exist";
     Log 1,"[PostMe_Special] $mga";
     return "$mga";
   }
   my $listsep = AttrVal($devname,"listseparator",',');
   
   #-- check content
   my $cont  = ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"");
   
   #-- item 
   my @lines = split($listsep,$cont);
   for( my $loop=0;$loop<int(@lines);$loop++){
     my $line = $lines[$loop];
     my $item = $line;
     my $meta = $line;
     $item    =~ s/\s*\[.*//;
     #-- only if attributes present
     if( $line =~ /.*\[.*\].*/){
       $meta =~ s/.*\[//;
       $meta =~ s/\]//;
       my @lines2 = split('" ',$meta);
       for( my $loop2=0;$loop2<int(@lines2);$loop2++){
         my $attr = $lines2[$loop2];
         $attr   =~ /(.*)="(.*)/;
         $attr   = $1;
         my $val = $2;
         PostMe_cleanSpecial($hash,$listname,$item,$attr);
         PostMe_procSpecial($hash,$listname,$item,$attr,$val)
           if( $clean==0 ); 
       }
     }
   }      
 }
 
#########################################################################################
#
# PostMe_procSpecial - process special annotations
# Parameter hash = hash of device addressed
#           name = name of the PostMe
#           item = item content
#           attr = attribute name
#           val  = attribute value
#
#########################################################################################

sub PostMe_procSpecial($$$$$){
  my($hash,$listname,$item,$attr,$val) =@_;
  my $devname=$hash->{NAME};
  
  #-- get the number of this list
  my $pmn = PostMe_Check($hash,$listname);
  if( !$pmn ){
    my $mga = "Error, a PostMe named $listname does not exist";
    Log 1,"[PostMe_procSpecial] $mga";
    return "$mga";
  }
  
  if( $attr eq "at" ){
    my ($timeraw,$year,$mon,$day,$hour,$min,$sec,$delta,$deltah,$deltam,$repeat);
    my ($secn,$minn,$hourn,$dayn,$monn,$yearn) = localtime(time);
    
    my $str = "{";
    if( $val =~ /((\d\d\:\d\d)|(\d\d\:\d\d\:\d\d)|(\d\d\d\d-\d\d-\d\dT\d\d\:\d\d\:\d\d))(\-(\d\d:\d\d)(P(\d+))?)/ ){
      $timeraw = $1;
      $delta   = $6;
      $repeat  = ($8)?$8:1;
      $timeraw =~ /((\d\d\d\d)-(\d\d)-(\d\d)T)?(\d\d)\:(\d\d)\:?(\d\d)?/;
      #($year,$mon,$day,$hour,$min,$sec) = ($2,$3-1,$4,$5,$6,$7);
      $year =($2)?$2  : $yearn+1900;
      $mon  =($3)?$3-1: $monn;
      $mon  = ( ($mon>=0)&&($mon<=11) )? $mon:0;
      $day  =($4)?$4  : $dayn;
      $day  = ( ($day>=1)&&($day<=31) )? $day:0;
      $hour =($5)?$5  : $hourn;
      $hour = ( ($hour>=0)&&($hour<=23) )? $hour:0;
      $min  =($6)?$6  : $minn;
      $min  = ( ($min>=0)&&($min<=59) )? $min:0;
      $sec  =($7)?$7  : "00";
      $sec  = ( ($sec>=0)&&($sec<=59) )? $sec:0;
            
      $delta =~ /(\d\d):(\d\d)/;
      ($deltah,$deltam)=($1,$2);
      
      my $deltas = min(3600*$deltah+60*$deltam,86400);
      $repeat = ( ($repeat>=0)&&($repeat<=10) )? $repeat:0;
     
      my $ftime = timelocal($sec,$min,$hour,$day,$mon,$year);
      my $ftimel= localtime($ftime);
      #-- determine send strings
      my $mrcpt = AttrVal($devname,sprintf("postme%02dMailRec",$pmn),undef);
      my $mfun  = AttrVal($devname,"postmeMailFun",undef);
      if( $mrcpt && $mfun ){ 
         $str  .= "$mfun('$mrcpt','$listname','$item => $ftimel');;";
      }
      
      my $trcpt = AttrVal($devname,sprintf("postme%02dMsgRec",$pmn),undef);
      my $tfun  = AttrVal($devname,"postmeMsgFun",undef);
      if( $trcpt && $tfun ){ 
         $str  .= "$tfun('$trcpt','$listname','$item => $ftimel');;";
      }
      $str .="}";
                                                                                                                                     
      #-- define name for timer     
      my $safename = PostMe_safeItem($hash,$listname,$item,"at");
      fhem("define ".$safename."_00 at $ftime $str");
      fhem("attr ".$safename."_00 room hidden");
     
      if( $delta ){
        for(my $i=1;$i<=$repeat;$i++){
          my $stime = $ftime-$i*$deltas;
          my $sname = $safename.sprintf("_%02d",$i);
          fhem("define ".$sname." at $stime $str");
          fhem("attr   ".$sname." room hidden");
        }
      }
    }  
  }elsif( $attr eq "notify" ){
    return
      if( !$val);
    my $str = "{";
    #-- determine send strings
    my $mrcpt = AttrVal($devname,sprintf("postme%02dMailRec",$pmn),undef);
    my $mfun  = AttrVal($devname,"postmeMailFun",undef);
    if( $mrcpt && $mfun ){ 
       $str  .= "$mfun('$mrcpt','$listname','$item');;";
    }
      
    my $trcpt = AttrVal($devname,sprintf("postme%02dMsgRec",$pmn),undef);
    my $tfun  = AttrVal($devname,"postmeMsgFun",undef);
    if( $trcpt && $tfun ){ 
       $str  .= "$tfun('$trcpt','$listname','$item');;";
    }
    $str .="}";
                                                                                                                                     
    #-- define name for notify     
    my $safename = PostMe_safeItem($hash,$listname,$item,"notify");
    fhem("define ".$safename." notify $val $str");
    fhem("attr ".$safename." room hidden");
  
  } 
}

#########################################################################################
#
# PostMe_cleanSpecial - process special annotations by cleaning leftover procedures
# Parameter hash = hash of device addressed
#           name = name of the PostMe
#           item = item content
#           attr = attribute name
#
#########################################################################################

sub PostMe_cleanSpecial($$$$){
  my($hash,$listname,$item,$attr) =@_;
  my $devname=$hash->{NAME};
  
  if( $attr eq "at" ){
    #-- define name for timer     
    my $safename = PostMe_safeItem($hash,$listname,$item,"at");
    fhem("delete ".$safename.".*");
  }elsif( $attr eq "notify" ){
    #-- define name for notify     
    my $safename = PostMe_safeItem($hash,$listname,$item,"notify");
    fhem("delete ".$safename.".*");
  }  
} 
  
#########################################################################################
#
# PostMe_safeItem - transform an item content into a FHEM name
# Parameter hash = hash of device addressed
#           name = name of the PostMe
#           item = item content
#           attr = attribute name
#
#########################################################################################

sub PostMe_safeItem($$$$){
  my($hash,$listname,$item,$attr) =@_;
  my $devname=$hash->{NAME};
  
  my $safeitem=join('_',split(' ',$item));
  $safeitem = substr($safeitem,0,4);
  $safeitem =~ tr/äöüÄÖÜß'/a_o_u_A_O_U_S__/;
  
  my $safelist=join('_',split(' ',$listname));
  $safelist = substr($safelist,0,4);
  $safelist =~ tr/äöüÄÖÜß'/a_o_u_A_O_U_S__/;
  
  my $safeattr = substr($attr,0,2);
  
  return $devname."rem_".$safelist."_".$safeitem."_".$safeattr;
}

#########################################################################################
#
# PostMe_LineIn - format a single PostMe line from input
# 
# Parameter hash = hash of device addressed
#           line = raw data in the form item [att1="val1" att2="val2"]
#
#########################################################################################

sub PostMe_LineIn($$) {
  my ($hash,$line) = @_;
  my $devname = $hash->{NAME}; 
   
  }

#########################################################################################
#
# PostMe_LineOut - format a single PostMe line for output
# 
# Parameter line   = raw data in the form item [att1="val1" att2="val2"] 
#                    (multiple items separated by comma)
#           format = 0 - item only
#
#########################################################################################

sub PostMe_LineOut($$$$) {
   my ($hash,$listname,$line,$format) = @_;
   my $devname = $hash->{NAME}; 
   my ($i,$line2,$item,$meat,$new,@lines,%meta);
   
   #Log 1,"LINEOUT format = $format, line=$line";
   
   #-- format == 0 - single item line
   if( $format < 10){
     $item = $line;
     $item =~ s/\s+\[.*//;
     $line =~ s/.*\[//;
     $line =~ s/\]//;
     my @list1 = split(/ /,$line);
     foreach my $item2(@list1) {
       my ($i,$j)= split(/=/, $item2);
       $meta{$i} = $j;
     }
     #Log 1,"line=$line, item=$item";
     return $item;
   
   #-- formats >= 10 for all items in a PostMe
   }elsif( $format >= 10){    
     my $listsep = AttrVal($devname,"listseparator",',');
     my @lines = split($listsep,$line);
     
     #-- format 13, return array
     return \@lines
       if( $format==14 ); 
     
     my $new   = "";
     my $item;
     my $meat;
     
     for( my $loop=0;$loop<int(@lines);$loop++){
       $line2  = $lines[$loop];
       $i = index($line2,'[');
       if( $i >=0 ){
         $item = substr($line2,0,$i);
         $meat = substr($line2,$i);
         $item =~ s/\s*$//;
         $meat =~ s/.*\[//;
         $meat =~ s/\]//;
         my @list1 = split('" ',$meat);
         foreach my $item2(@list1) {
           my ($i,$j)= split(/=/, $item2);
           $j =~ s/^"//;
           $meta{$i} = $j;
           #Log 1,"Setting META $i to VALUE $j";
         }
       }else{
         $item = $line2;
         $meat = "";
         $item =~ s/\s*$//;
       }
       #-- format 10: plain format, item only
       $new .= $item.','
         if( $format == 10);
         
       #-- format 11: meta data in brackets
       if( $format == 11){
         if( $meat ne "" ){
           $new .= $item.'('.$meat.'),';
         }else{
           $new .= $item.',';
         }
       }
         
       #-- format 13: Telegram format item w indexing
       $new .= '('.$item.sprintf(':%sitem%02d) ',$listname,$loop)
         if( $format == 13);
         
       #-- json format by hand
       if( $format == 15 ){
         $new .= '{"item": "'.$item.'"';
         if( $meat ne "" ){
           $new .= ',"meta": {';
           foreach my $k (keys %meta){
             $new .= '"'.$k.'": "'.$meta{$k}.'",';
           } 
           $new .= '}';
         }
         $new .= '},';
       }
     }
     $new =~ s/""/"/g;
     $new =~ s/,}/}/g;
     $new =~ s/,$//;
     return $new;
   }
 }

#########################################################################################
#
# PostMe_tgi - format a single PostMe as inline keyboard for telegram (items w. indexing)
# 
# Parameter devname  = device name
#           listname = list name
#
#########################################################################################

sub PostMe_tgi($$) {
  my ($devname,$listname) = @_;
  my $pmn;
  my $res = "";
  my $hash = $defs{$devname};
  if( !$hash ){
    my $mga = "Error, a PostMe device named $devname does not exist";
    Log 1,"[PostMe_tgi] $mga";
    return "$mga";
  }

  #Log 1,"[PostMe_Get] with name=$listname key=$key args=@args";
    
  $pmn = PostMe_Check($hash,$listname);
  if( !$pmn ){
    my $mga = "Error, a PostMe named $listname does not exist";
    Log 1,"[PostMe_tgi] $mga";
    return "$mga";
  }

  $res = PostMe_LineOut($hash,$listname,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),""),13);
  $res.= " ".$listname;
  return $res;
}


#########################################################################################
#
# PostMe_tgj - format a single PostMe as simple array
# 
# Parameter devname  = device name
#           listname = list name
#
###########################################################################k##############

sub PostMe_tgj($$) {
  my ($devname,$listname) = @_;
  my $pmn;
  my $hash = $defs{$devname};
  if( !$hash ){
    my $mga = "Error, a PostMe device named $devname does not exist";
    Log 1,"[PostMe_tgk] $mga";
    return "$mga";
  }

  #Log 1,"[PostMe_Get] with name=$listname key=$key args=@args";
    
  $pmn = PostMe_Check($hash,$listname);
  if( !$pmn ){
    my $mga = "Error, a PostMe named $listname does not exist";
    Log 1,"[PostMe_tgk] $mga";
    return "$mga";
  }
  my @ret=PostMe_LineOut($hash,$listname,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),""),14);
  return \@ret;
}

#########################################################################################
#
# PostMe_Set - Implements the Set function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub PostMe_Set($@) {
  my ( $hash, $devname, $key, @args ) = @_;

  #-- for the selector: which values are possible
  if ($key eq "?"){
    #--prevent any default set
    return undef;
    #-- obsolete
    my @cmds = ("create","delete","rename","add","modify","remove","clear");
    return "Unknown argument $key, choose one of " .join(" ",@cmds);
  }
  
  my $listname = shift @args; 
  
  if( $key eq "create"){
    PostMe_Create($hash,$listname);
  
  }elsif( $key eq "delete"){
    PostMe_Delete($hash,$listname);
      
  }elsif( $key eq "rename"){
    PostMe_Rename($hash,$listname,@args[0]);
  
  }elsif( $key eq "add"){
    PostMe_Add($hash,$listname,@args);

  }elsif( $key eq "modify"){
    PostMe_Modify($hash,$listname,@args);

  }elsif( $key eq "remove"){
    PostMe_Remove($hash,$listname,@args);
  
  }elsif( $key eq "clear"){
    PostMe_Clear($hash,$listname);
  }
}

#########################################################################################
#
# PostMe_Get - Implements the Get function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub PostMe_Get($$$@) {
  my ($hash, $devname, $key, @args) = @_;
  my $pmn;
  my $res = "";
 
  my $hasMail = defined(AttrVal($devname,"postmeMailFun",undef)) ? 1 : 0;
  my $hasMsgr = defined(AttrVal($devname,"postmeMsgFun",undef)) ? 1 : 0;
  my $hasTTS  = defined(AttrVal($devname,"postmeTTSFun",undef)) ? 1 : 0;
  
  #-- for the selector: which values are possible
  if ($key eq "?"){
    #-- prevent any default get
    return undef;
    #-- obsolete
    #-- current number of PostMes
    my $cnop = ReadingsVal($devname,"postmeCnt",0);
    my $pml  = "";
    for( my $i=1;$i<=$cnop;$i++){
       $pml .= ","
          if( $i >1);
       $pml .= ReadingsVal($devname, sprintf("postme%02dName",$i),"");
    } 
    my @cmds = ("version:noArg","all:noArg","allspecial","list:".$pml,"special:".$pml);
    $res = "Unknown argument $key choose one of ".join(" ",@cmds);
    $res.= " mail:".$pml
      if($hasMail);
    $res.= " message:".$pml
      if($hasMsgr);
    $res.= " TTS:".$pml
      if($hasTTS);
    $res.= " JSON:".$pml;
      
    return $res;
  }
  
  my $listname = @args[0];
    
  if ($key eq "version") {
    return "PostMe.version => $postmeversion";
   
   #-- list one PostMe
  } elsif( ($key eq "list")||($key eq "special")||($key eq "JSON")||($key eq "mail")||($key eq "message")||($key eq "TTS") ){    
    $pmn = PostMe_Check($hash,$listname);
    if( !$pmn ){
      my $mga = "Error, a PostMe named $listname does not exist";
      Log 1,"[PostMe_Get] $mga";
      return "$mga";
    }
    ##-- list
    if( $key eq "list" ){
      $res = ReadingsVal($devname, sprintf("postme%02dName",$pmn),"");
      $res .= ": ";
      $res .= PostMe_LineOut($hash,$listname,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"")."\n",10);
      return $res;
    
    ##-- list
    }elsif( $key eq "special" ){
      PostMe_Special($hash,$listname,0);
     
    ##-- JSON
    }elsif( $key eq "JSON" ){
      $res = PostMe_LineOut($hash,$listname,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),""),15);
      return '{"'.$listname.'": ['.$res.']}';
    
    ##-- send by mail
    }elsif( $key eq "mail" ){
      my $rcpt = AttrVal($devname,sprintf("postme%02dMailRec",$pmn),undef);
      my $text = PostMe_LineOut($hash,$listname,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),undef),11);
      my $fun  = AttrVal($devname,"postmeMailFun",undef);
      
      if( $rcpt && $text && $fun ){ 
        my $ref = \&$fun;
        &$ref($rcpt,$listname,$text);
      }
      my $mga = "$listname sent by mail";
      readingsSingleUpdate($hash,"state",$mga,1 );
      Log3 $devname,3,"[PostMe] ".$mga;
      return undef;
    
    ##-- send by instant messenger
    }elsif( $key eq "message" ){
      my $rcpt = AttrVal($devname,sprintf("postme%02dMsgRec",$pmn),undef);
      my $text = PostMe_LineOut($hash,$listname,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),undef),11);
      $text =~ s/,/,\n/g;
      my $fun  = AttrVal($devname,"postmeMsgFun",undef);
      
      if( $rcpt && $text && $fun ){      
        my $ref = \&$fun;
        &$ref($rcpt,$listname,$text);
      }
      my $mga = "$listname sent by messenger";
      readingsSingleUpdate($hash,"state",$mga,1 );
      Log3 $devname,3,"[PostMe] ".$mga;
      return undef;
      
    ##-- speak as TTS
    }elsif( $key eq "TTS" ){
      my $dev  = AttrVal($devname,"postmeTTSDev",undef);
      my $text = $listname.": ".PostMe_LineOut($hash,$listname,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),undef),10);
      my $fun  = AttrVal($devname,"postmeTTSFun",undef);
      
      if( $text && $fun ){
        my $ref = \&$fun;
        &$ref($dev,$text);
      }
      my $mga = "$listname spoken by TTS";
      readingsSingleUpdate($hash,"state",$mga,1 );
      Log3 $devname,3,"[PostMe] ".$mga;
      return undef;
    } 
    
  #-- list all PostMe
  } elsif ($key eq "all") {
    #-- current number of PostMes
    my $cnop = ReadingsVal($devname,"postmeCnt",0);
   
    for( my $loop=1;$loop<=$cnop;$loop++){
      $res .= ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
      $res .= ": ".PostMe_LineOut($hash,$listname,ReadingsVal($devname, sprintf("postme%02dCont",$loop),"")."\n",10);
      $res .= "\n";
    }
    return $res;
  #-- process all PostMe special annotations
  } elsif ($key eq "allspecial") {
    #-- current number of PostMes
    my $cnop = ReadingsVal($devname,"postmeCnt",0);
   
    for( my $loop=1;$loop<=$cnop;$loop++){
      $listname = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
      PostMe_Special($hash,$listname,0);
    }
    return $res;
  }
}

#########################################################################################
#
# PostMe_detailFn - Displays PostMes in detailed view of FHEM
# 
# Parameter = web argument list
#
#########################################################################################

sub PostMe_detailFn(){
  my ($FW_wname, $devname, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $hash = $defs{$devname};

  $hash->{mayBeVisible} = 1;
  
  my $pmname=$hash->{NAME};
  my $pmfirst = ReadingsVal($devname, "postme01Name","");
  my $pmlist="";
  my $pmoption="";
  
  #-- current number of PostMes
  my $cnop = ReadingsVal($devname,"postmeCnt",0);
   
  for( my $loop=1;$loop<=$cnop;$loop++){
      my $n = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
      $pmlist .= $n;
      $pmlist .= ","
        if( $loop != $cnop);
      if( $loop == 1){
        $pmoption .= '<option selected="selected" value="'.$n.'">'.$n.'</option>';
      }else{
        $pmoption .= '<option value="'.$n.'">'.$n.'</option>';
      }
    }
    
  my $icon = AttrVal($devname, "icon", "");
  $icon = FW_makeImage($icon,$icon,"icon") . "&nbsp;" if($icon);

  my $html = '<div  id="ddtable" class="makeTable wide"><table class="block wide"><tr class="odd">'.
             '<td width="300px"><div>'.$icon.'</div></td>'.
             '<td informId="'.$pmname.'"><div id="'.$pmname.'"  title="Initialized" class="col2">'.ReadingsVal($devname,"state","").'</div></td>'.
             '</tr></table></div>';
   
  $html .= '<script type="text/javascript">function oc(){var p1=document.getElementById("val1_set'.$pmname.'").value;var p2=document.getElementById("val2_set'.$pmname.'").value;'.
           'var p3;if(document.getElementById("sel_set'.$pmname.'").selectedIndex == 3) p3=p2; else p3=p1+" "+p2;document.getElementById("val_set'.$pmname.'").value=p3;}'.
           'function dc1(i){if(i == 3)document.getElementById("val1_set'.$pmname.'").style.visibility = "hidden";'.
           'else document.getElementById("val1_set'.$pmname.'").style.visibility = "visible";'.
           'if(i > 4)document.getElementById("val2_set'.$pmname.'").style.visibility = "hidden"; else document.getElementById("val2_set'.$pmname.'").style.visibility = "visible";}'.
           'function dc2(i){if(i > 4)document.getElementById("val_get'.$pmname.'").style.visibility = "hidden";'.
           'else document.getElementById("val_get'.$pmname.'").style.visibility = "visible";};</script>';
           
  $html .= '<table><tr><td>'.
           '<form method="post" action="/fhem" autocomplete="off"><input id="pm.setter" type="hidden" name="fwcsrf" value="none"/>'.
           '<input type="hidden" name="detail" value="'.$pmname.'"/><input type="hidden" name="dev.set'.$pmname.'" value="'.$pmname.'"/>'.
           '<input type="submit" name="cmd.set'.$pmname.'" value="set" class="set"/><div class="set downText">&nbsp;'.$pmname.'&nbsp;</div>'.
           '<select  id="sel_set'.$pmname.'" informId="sel_set'.$pmname.'" name="arg.set'.$pmname.'" class="set" style="width:100px;" '.
           'onchange="dc1(this.selectedIndex)">'.
           '<option selected="selected" value="add">add</option><option value="modify">modify</option><option value="remove">remove</option><option value="create">create</option>'.
           '<option value="rename">rename</option><option value="clear">clear</option><option value="delete">delete</option>'.
           '</select>'.
           '<select id="val1_set'.$pmname.'" informId="val1_set'.$pmname.'" name="val1.set'.$pmname.'" class="set" onchange="oc()">'.$pmoption.'</select>'.
           '<input type="text" id="val2_set'.$pmname.'" informId="val2_set'.$pmname.'" name="val2.set'.$pmname.'" class="set" size="30" value="" onchange="oc()"/>'.
           '<input type="hidden" id="val_set'.$pmname.'" informId="val_set'.$pmname.'" name="val.set'.$pmname.'" class="set" size="30" value="'.$pmfirst.'"/></form></td></tr>';
  
  $html .= '<tr><td>'.
           '<form method="post" action="/fhem" autocomplete="off"><input id="pm.getter" type="hidden" name="fwcsrf" value="none"/>'.
           '<input type="hidden" name="detail" value="'.$pmname.'"/><input type="hidden" name="dev.get'.$pmname.'" value="'.$pmname.'"/>'.
           '<input type="submit" name="cmd.get'.$pmname.'" value="get" class="get"/><div class="get downText">&nbsp;'.$pmname.'&nbsp;</div>'.
           '<select id="sel_get'.$pmname.'" informId="sel_get'.$pmname.'" name="arg.get'.$pmname.'" class="get" style="width:100px;" '.
           'onchange="dc2(this.selectedIndex)">'.
           '<option selected="selected" value="list">list</option><option value="special">special</option><option value="mail">mail</option><option value="message">message</option><option value="TTS">TTS</option>'.
           '<option value="JSON">JSON</option><option value="all">all</option><option value="allspecial">allspecial</option><<option value="version">version</option>'.
           '</select>'.
           '<select type="hidden" id="val_get'.$pmname.'" informId="val_get'.$pmname.'" name="val.get'.$pmname.'" class="get">'.$pmoption.'</select>'.
           '</form></td></tr></table>';
           
   $html .= '<script type="text/javascript">var req = new XMLHttpRequest();req.open(\'GET\', document.location.href, false);req.send(null);'.
           'var csrfToken = req.getResponseHeader(\'X-FHEM-csrfToken\');if( csrfToken == null ){csrfToken = "null";}'.
           'document.getElementById("pm.setter").value=csrfToken;document.getElementById("pm.getter").value=csrfToken;</script>';

  return $html;

}

#########################################################################################
#
# PostMe_widget - Displays PostMes as widgets
# 
# Parameter = web argument list
#
#########################################################################################

sub PostMe_widget($) {
  my ($arg) = @_;
  my $type   = $FW_webArgs{type};
  $type = "show"
    if( !$type);
  my $devname  = $FW_webArgs{postit};
  my $listname = $FW_webArgs{name};
  my $pmn;
  my $res = "";

  #-- device name
  if( !$devname ){
    Log 1,"[PostMe_widget] Error, web argument postit=... is missing";
    return undef;
  }
  
  my $hash  = $defs{$devname};
  my $style = AttrVal($devname,"postmeStyle","jQuery");
  my $icon  = AttrVal($devname,"postmeIcon","images/default/pin_red_32.png");
  my $click = AttrVal($devname,"postmeClick","0");
  my $css   = '<link href="www/pgm2/'.AttrVal($FW_wname, "stylesheetPrefix", "").'style.css" rel="stylesheet"/>';  
  
  ##################################################-- type=pins => list with pins
  if( $type eq "pins"){
    #-- current number of Postmes
    my $cnop = ReadingsVal($devname,"postmeCnt",0);
   
    #-- jQuery rendering
    if( $style eq "jQuery" ){   
      $FW_RETTYPE = "text/html";
      $FW_RET="";
      $res .= $css;
      #-- we need our own jQuery object
      $res .= '<script  type="text/javascript" src="/fhem/pgm2/jquery.min.js"></script>';
      $res .= '<script  type="text/javascript" src="/fhem/pgm2/jquery-ui.min.js"></script>';
      
      #-- this is for the selector
      $res .= '<div id="postme" class="postmeclass">';    
      for( my $loop=1;$loop<=$cnop;$loop++){
        my $name2 = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
        my $sel   = sprintf("sel%02d",$loop);
        $res .= '<div id="'.$sel.'"><img src="'.$icon.'"/>'.$name2.'</div><br/>';
      };
      $res .= '</div>';
      
      #-- this is the scripting for the dialog box
      $res .= '<script type="text/javascript">';
      $res .=         'var $jParent = window.parent.jQuery;';
      $res .=         '$jParent( ".roomBlock1" ).prepend( "<div id=\'postmedia\' style=\'width:200px\'></div>" );';
      $res .=         'var dlg1 = $jParent("#postmedia");';
      $res .=         'dlg1 = dlg1.dialog({width:300,autoOpen:false';
      $res .=                             ',open:function(event, ui){$(".ui-dialog-titlebar-close").hide();}';
      #-- button only when needed
      $res .=                             ',buttons:[{text: "OK",click:function(){dlg1.dialog("close");}}]'
        if ($click == 1);
      $res .=                             '});';
      
      #-- this is the scripting for the connection selector-dialog
      for( my $loop=1;$loop<=$cnop;$loop++){
        my $name2 = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
        my $sel  = sprintf("sel%02d",$loop);
        if( $click == 0){
          $res .=         '$("#'.$sel.'").mouseover(function(){dlg1.load("/fhem/PostMe_widget?postit='.$devname.'&name='.$name2.'",';
          $res .=                                          'function(){dlg1.dialog("open")})});';
          $res .=         '$("#'.$sel.'").mouseout(function(){dlg1.dialog("close")});';
        }else{
          $res .=         '$("#'.$sel.'").click(function(){dlg1.load("/fhem/PostMe_widget?postit='.$devname.'&name='.$name2.'",';
          $res .=                                          'function(){dlg1.dialog("open")})});';
        }
      }
      $res .= '</script>';
      FW_pO $res;
    
    #-- HTML rendering
    }elsif( $style eq "HTML"){
      $FW_RETTYPE = "text/html; charset=$FW_encoding";
      $FW_RET="";
      $res .= $css;
      $res .= '<div class="postmeclass">';
      for( my $loop=1;$loop<=$cnop;$loop++){
        my $name2 = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
        if( $click == 0){
          $res .= '<div onmouseover="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name2.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');" ';
          $res .= 'onmouseout="postit.close()"><img src="'.$icon.'"/>'.$name2.'</div><br/>';
        }else{
          $res .= '<div onclick="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name2.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');">';
          $res .= '<img src="'.$icon.'"/>'.$name2.'</div><br/>';
        }
      }
      FW_pO $res.'</div>';
    
    #-- SVG rendering
    }else{
      $FW_RETTYPE = "image/svg+xml";
      $FW_RET="";
      FW_pO '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100px" height="100px">';
      for( my $loop=1;$loop<=$cnop;$loop++){
        my $name2 = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
        $res.=  sprintf('<text x="10" y="%02d" fill="blue" style="font-family:Helvetica;font-size:12px;font-weight:bold" ',10+15*$loop);
        $res.=  'onmouseover="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name2.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');" ';
        $res.=  'onmouseout="postit.close()">'.$name2.'</text>';
        $res.= <g>
      }
      FW_pO $res.'</svg>';
    }
    return ($FW_RETTYPE, $FW_RET);
  }
  
  #-- PostMe name
  if( !$listname ){
    Log 1,"[PostMe_widget] Error, web argument name=... is missing";
    return undef;
  }

  $pmn = PostMe_Check($hash,$listname);
  if( !$pmn ){
    Log 1,"[PostMe_widget] Error, a PostMe named $listname does not exist";
    return undef;
  }
  
  ##################################################-- type=pin => single pin
  if( $type eq "pin"){
  #-- jQuery rendering
    if( $style eq "jQuery"){
    
      my $sel  = sprintf("sel%02d",$pmn);
      
      $FW_RETTYPE = "text/html";
      $FW_RET="";
      $res .= $css;
      #-- we need our own jQuery object
      $res .= '<script  type="text/javascript" src="/fhem/pgm2/jquery.min.js"></script>';
      $res .= '<script  type="text/javascript" src="/fhem/pgm2/jquery-ui.min.js"></script>';
      
      #-- this is for the selector
      $res .= '<div id="postme" class="postmeclass">';    
      $res .= '<div id="'.$sel.'"><img src="'.$icon.'"/>'.$listname.'</div><br/>';
      $res .= '</div>';
      
      #-- this is the scripting for the dialog box
      $res .= '<script type="text/javascript">';
      $res .=         'var $jParent = window.parent.jQuery;';
      $res .=         '$jParent( ".roomBlock1" ).prepend( "<div id=\'postmedia\' style=\'width:200px\'></div>" );';
      $res .=         'var dlg1 = $jParent("#postmedia");';
      $res .=         'dlg1 = dlg1.dialog({width:300,autoOpen:false';
      $res .=                             ',open:function(event, ui){$(".ui-dialog-titlebar-close").hide();}';
      #-- button only when needed
      $res .=                             ',buttons:[{text: "OK",click:function(){dlg1.dialog("close");}}]'
        if ($click == 1);
      $res .=                             '});';
      
      #-- this is the scripting for the connection selector-dialog
      if( $click == 0){
        $res .=         '$("#'.$sel.'").mouseover(function(){dlg1.load("/fhem/PostMe_widget?postit='.$devname.'&name='.$listname.'",';
        $res .=                                          'function(){dlg1.dialog("open")})});';
        $res .=         '$("#'.$sel.'").mouseout(function(){dlg1.dialog("close")});';
      }else{
        $res .=         '$("#'.$sel.'").click(function(){dlg1.load("/fhem/PostMe_widget?postit='.$devname.'&name='.$listname.'",';
        $res .=                                          'function(){dlg1.dialog("open")})});';
      }
      $res .= '</script>';
      FW_pO $res;
      
    #-- HTML rendering
    }elsif( $style eq "HTML"){
      $FW_RETTYPE = "text/html";
      $FW_RET="";
      $res .= $css;
      $res .= '<div class="postmeclass">';
      if( $click == 0){
        $res.=  '<div onmouseover="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$listname.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');" ';
        $res.=  'onmouseout="postit.close()">';
      }else{
        $res.=  '<div     onclick="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$listname.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');">';
      }
      FW_pO $res.'<img src="'.$icon.'"/>'.$listname.'</div>';
     
    #-- SVG rendering
    }else{
      $FW_RETTYPE = "image/svg+xml";
      $FW_RET="";
      FW_pO '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100px" height="100px">';
      $res.=  '<text x="10" y="10" fill="blue" style="font-family:Helvetica;font-size:12px;font-weight:bold" ';
      $res.=  'onmouseover="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$listname.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');" ';
      $res.=  'onmouseout="postit.close()">'.$listname.'</text>';
      FW_pO $res.'</svg>';
    }
    return ($FW_RETTYPE, $FW_RET);
  }
  
  ################################################## default (type missing) => content of a single postme
  
  my @lines=split(AttrVal($devname,"listseparator",','),ReadingsVal($devname, sprintf("postme%02dCont",$pmn),""));
  if( !(int(@lines)>0) ){
    #Log 1,"[PostMe_widget] Asking to display empty PostMe $listname";
    return undef;
  }

    #-- HTML rendering
    if( $style ne "SVG"){
      $FW_RETTYPE = "text/html; charset=$FW_encoding";
      $FW_RET="";
      $res .= $css;
      $res .= '<div class="postmeclass2" style="width:200px">';
      $res .= '<b>'.$listname.'</b><br/>';
      for (my $i=0;$i<int(@lines);$i++){
        #--special for meta data
        my $line=PostMe_LineOut($hash,$listname,$lines[$i],0);
        $res.=  $line.'<br/>';
      }
      FW_pO $res.'</div>';
    
    #--- SVG rendering
    }else{
      $FW_RETTYPE = "image/svg+xml";
      $FW_RET="";
      FW_pO '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100px" height="100px">';

      $res =  '<text x="10" y="10" fill="blue" style="font-family:Helvetica;font-size:12px;font-weight:bold">';
      $res.=  $listname.'</text>';   
      for (my $i=0;$i<int(@lines);$i++){
        $res.=  sprintf('<text x="10" y="%02d" fill="blue" style="font-family:Helvetica;font-size:10px">',25+$i*12);
        $res.=  PostMe_LineOut($hash,$listname,$lines[$i],0);
        $res.=  '</text>';
      }
      FW_pO $res.'</svg>';

    }
    return ($FW_RETTYPE, $FW_RET);
}

1;

=pod
=item helper
=item summary to set up a system of sticky notes, similar to Post-Its&trade;
=item summary_DE zur Definition eines Systems von Klebezetteln ähnlich des Post-Its&trade;
=begin html

   <a name="PostMe"></a>
        <h3>PostMe</h3>
        <ul>
        <p> FHEM module to set up a system of sticky notes, similar to Post-Its&trade;</p>

        <a name="PostMedefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;postit&gt; PostMe</code>
            <br />Defines the PostMe system, &lt;postit&gt; is an arbitrary name for the system. </p>
        <a name="PostMeusage"></a>
        <h4>Usage</h4>
        See <a href="http://www.fhemwiki.de/wiki/Modul_PostMe">German Wiki page</a>
        <br/>
        An arbitrary number of lists may be added to the system with the <i>create</i> command.<br/>
        List items may consist of one or more words, and are added/removed by the <i>add</i> and 
        <i>remove</i>  command, but no separator characters are allowed in one item<br/> 
        Attention: A comma "," is the <i>default</i> separator for list items, see attributes below.</br/>
        <p/>
        Meta data for items (=annotations)may be included in the items by using "[" and "]"; characters, e.g.<br/>
        <code>set &lt;postit&gt; add &lt;name&gt; &lt;item&gt; [&lt;attribute1&gt;="&lt;data1&gt;" ...</code><br/>
        These attribute-value pairs may be added, modified and removed with the <i>modify</i> command. 
        <p/>
        <b>Special annotations</b> will be evaluated further, either on creation or manually by executing the commands<br/>
        <code>get &lt;postit&gt; special &lt;name&gt;</code> resp. <code>get &lt;postit&gt; allspecial</code>
        <ul>
          <li>The attribute <i>at="&lt;timespec/datespec&gt;"</i>, when given a timespec/datespec value, will result in a single or multiple
          reminding messages for this item. The syntax for this timespec/datespec value is<br/>
          <code>(&lt;HH:MM&gt;|&lt;HH:MM:SS&gt;|&lt;YYYY-MM-DD&gt;T&lt;HH:MM:SS&gt;)[-&lt;HH:MM&gt;[P&lt;number&gt;]]</code>
          <br/>
          The first part is the time/date specification when the item is <i>due</i>. 
          <br/>The second optional part beginning with a "-"-sign
          denotes how much time befor this date you want to be alerted. 
          <br/>The third optional part beginning with a "P" character 
          allows to specify a &lt;number&gt; of periodic reminders, the period given by the second part.<br/>
          Processing this attribute means, that several <i>at</i> devices will be set up in the room <i>hidden</i> 
          that are triggered when at the specified times.
          See documentation in Wiki for examples.
       </li>
          <li>The attribute <i>notify="&lt;eventspec&gt;"</i>, when given an eventspec value, will result in a single or multiple
          reminding messages for this item.<br/>
          Processing this attribute means, that a <i>notify</i> device will be set up in the room <i>hidden</i> 
          that is triggered when the event is detected.</li> 
        </ul>
        The sticky notes may be integrated into any Web page by simply embedding the following tags
           <ul>
           <li> <code>&lt;embed src="/fhem/PostMe_widget?type=pins&amp;postit=&lt;postit&gt;"/&gt;</code> <br/>
           to produce an interactive list of all PostMe names with pins from system &lt;postit&gt;.</li>
           <li> <code>&lt;embed src="/fhem/PostMe_widget?type=pin&amp;postit=&lt;postit&gt;&amp;name=&lt;name&gt;"/&gt;</code> <br/>
           to produce an interactive entry for PostMe &lt;name&gt;from system &lt;postit&gt;</li>
           </ul>
        <br/>   
        The module provides interface routines that may be called from your own Perl programs, see documentation in the Wiki.
        <br/>    
        <a name="PostMeset"></a>     
        <h4>Set</h4>
        <ul>
            <li><code>set &lt;postit&gt; create &lt;name&gt;</code>
                <br />creates a sticky note named &lt;name&gt;</li>
            <li><code>set &lt;postit&gt; rename &lt;name&gt; &lt;newname&gt;</code>
                <br />renames the sticky note named &lt;name&gt; as &lt;newname&gt;</li>
            <li><code>set &lt;postit&gt; delete &lt;name&gt;</code>
                <br />deletes the sticky note named &lt;name&gt;</li>
            <li><code>set &lt;postit&gt; add &lt;name&gt; &lt;item&gt;</code>
                <br />adds to the sticky note named &lt;name&gt; an item &lt;item&gt;</li>
            <li><code>set &lt;postit&gt; modify &lt;name&gt; &lt;item&gt; &lt;attribute&gt; &lt;data&gt;</code>
                <br />adds/modifies/removes and attribute-value-pair &lt;attribute&gt;="&lt;data&gt;" to the item &lt;item&gt; on the sticky note named &lt;name&gt;<br/>
                adding, if this attribute is not yet present; modification, if it is present - &lt;data&gt; will then be overwritten; removal, if no &lt;data&gt; is given</li>
            <li><code>set &lt;postit&gt; remove &lt;name&gt; &lt;item&gt;</code><br />
                <code>set &lt;postit&gt; remove &lt;name&gt; item&lt;number&gt;</code>
                <br />removes from the sticky note named &lt;name&gt; an item &lt;item&gt; or the one numbered &lt;number&gt; (starting at 0)</li>
            <li><code>set &lt;postit&gt; clear &lt;name&gt;</code>
                <br />clears the sticky note named &lt;name&gt; from all items </li>
          
        </ul>
        <a name="PostMeget"></a>
        <h4>Get</h4>
        <ul>
            <li><code>get &lt;postit&gt; list &lt;name&gt;</code>
                <br />Show the sticky note named &lt;name&gt; and its content</li>
            <li><code>get &lt;postit&gt; special &lt;name&gt;</code>
                <br />Process the special annotations (see above) of the sticky note named &lt;name&gt;</li>
            <li><code>get &lt;postit&gt; mail &lt;name&gt;</code>
                <br />Send the sticky note named &lt;name&gt; and its content via eMail to a predefined
                recipient (e.g. sticky note &lt;postme01Name&gt; is sent to &lt;postme01MailRec&gt;).<br/> The mailing
                subroutine <postmeMsgFun> is called with three parameters for recipient, subject
                and text.  </li>
            <li><code>get &lt;postit&gt; message &lt;name&gt;</code>
                <br />Send the sticky note named &lt;name&gt; and its content via instant messenger to a predefined
                recipient (e.g. sticky note &lt;postme01Name&gt; is sent to &lt;postme01MsgRec&gt;).<br/> The messenger 
                subroutine <postmeMsgFun> is called with three parameters for recipient, subject
                and text. </li>
            <li><code>get &lt;postit&gt; TTS &lt;name&gt;</code>
                <br />Speak the sticky note named &lt;name&gt; and its content. The TTS 
                subroutine <postmeTTSFun> is called with one parameter text. </li>   
            <li><code>get &lt;postit&gt; JSON &lt;name&gt;</code>
                <br />Return the sticky note named &lt;name&gt; in JSON format</li>       
            <li><code>get &lt;postit&gt; all</code>
                <br />Show all sticky notes and their content</li>
            <li><code>get &lt;postit&gt; allspecial</code>
                <br />Process the special annotations (see above) of all sticky notes</li>
            <li><code>get &lt;postit&gt; version</code>
                <br />Display the version of the module</li>
        </ul>
        <a name="PostMeattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><code>attr &lt;postit&gt; postmeStd &lt;name1,name2,...&gt;</code>
                <br />Comma separated list of standard sticky notes that will be created on device start.</li>
            <li><code>attr &lt;postit&gt; postmeClick 1|0 (default)</code>
                <br />If 0, embedded sticky notes will pop up on mouseover-events and vanish on mouseout-events (default).<br/>
                      If 1, embedded sticky notes will pop up on click events and vanish after closing the note</li>
            <li><code>attr &lt;postit&gt; postmeIcon &lt;string&gt;</code>
                <br />Icon for display of a sticky note</li>
            <li><code>attr &lt;postit&gt; postmeStyle SVG|HTML|jQuery (default)</code>
                <br />If jQuery, embedded sticky notes will produce jQuery code (default) <br/>
                      If HTML, embedded sticky notes will produce HTML code <br/>
                      If SVG, embedded sticky notes will produce SVG code</li>
             <li><code>attr &lt;postit&gt; listseparator &lt;character&gt;</code>
                <br />Character used to separate list items (default ',')</li>
            </ul>
            Note, that in the parameters sent to the following functions, ":" serves as separator between list name and items, 
            and "," serves as separator between items. They may be exchanged with simple regular expression operations.
            <ul>
            <li><code>attr &lt;postit&gt; postmeMailFun &lt;string&gt;</code>
                <br />Function name for the eMail function.  This subroutine 
                is called with three parameters for recipient, subject
                and text.</li>
            <li><code>attr &lt;postit&gt; postmeMailRec(01|02|...) &lt;string&gt;</code>
                recipient addresses for the above eMail function (per PostMe).</li>
            <li><code>attr &lt;postit&gt; postmeMsgFun &lt;string&gt;</code>
                <br />Function name for the instant messenger function.  This subroutine 
                is called with three parameters for recipient, subject
                and text.</li>
             <li><code>attr &lt;postit&gt; postmeMsgRec(01|02|...) &lt;string&gt;</code>
                recipient addresses for the above instant messenger function (per PostMe).</li>
            <li><code>attr &lt;postit&gt; postmeTTSFun &lt;string&gt;</code>
                <br />Function name for the text-to-speech function.  This subroutine 
                is called with two parameters, the device name and the composite text.
                </li>
             <li><code>attr &lt;postit&gt; postmeTTSDev(01|02|...) &lt;string&gt;</code>
                device name for the above TTS function.</li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        </ul>
=end html
=begin html_DE

<a name="PostMe"></a>
<h3>PostMe</h3>
<ul>
<a href="https://wiki.fhem.de/wiki/Modul_PostMe">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#PostMe">PostMe</a> 
</ul>
=end html_DE
=cut
