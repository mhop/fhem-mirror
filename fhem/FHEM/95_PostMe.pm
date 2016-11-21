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
use vars qw(%intAt);		    # FHEM at definitions
use vars qw($FW_RET);           # Returned data (html)
use vars qw($FW_RETTYPE);       # image/png or the like
use vars qw($FW_wname);         # Web instance

#########################
# Global variables
my $postmeversion  = "1.0";
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
  $hash->{AttrList}    = "postmeTTSDev postmeMsgFun postme[0-9]+MsgRec postmeMailFun postme[0-9]+MailRec postmeStd postmeIcon postmeStyle:test,jQuery,HTML,SVG postmeClick:0,1 ".$readingFnAttributes;		
    	 
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
  my ($cmd, $name, $attrName, $attrVal) = @_;
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
   my @std  = split(',',AttrVal("$devname","postmeStd",undef));
   
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
#           name = name of PostMe
#
#########################################################################################

sub PostMe_Check($$) {
   my ($hash,$name) = @_;
   my $devname = $hash->{NAME};
   my ($loop,$res); 
   
   #-- current number of PostMes
   my $cnop = ReadingsVal($devname,"postmeCnt",0);

   for( $loop=1;$loop<=$cnop;$loop++){
     $res = ReadingsVal($devname, sprintf("postme%02dName",$loop), undef);
     last 
       if($res eq $name);
   }
   #-- no PostMe with this name
   if( $res ne $name ){
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
#           name = name of PostMe
#
#########################################################################################

sub PostMe_Create($$) {
   my ($hash,$name) = @_;
   my $devname = $hash->{NAME}; 
   
   if( PostMe_Check($hash,$name) ){
     my $mga = "Error, a PostMe named $name does already exist";
     Log 1,"[PostMe_Create] $mga";
     return "$mga";
   }
   
   #-- current number of PostMes
   my $cnop = ReadingsVal($devname,"postmeCnt",0);
   $cnop++;
   
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash, sprintf("postme%02dName",$cnop),$name);
   readingsBulkUpdate($hash, sprintf("postme%02dCont",$cnop),"");
   readingsBulkUpdate($hash, "postmeCnt",$cnop);
   readingsEndUpdate($hash,1); 
 
   Log3 $devname,3,"[PostMe] Added a new PostMe named $name";
   return undef;
}

#########################################################################################
#
# PostMe_Delete - Delete an existing PostMe
# 
# Parameter hash = hash of device addressed
#           name = name of PostMe
#
#########################################################################################

sub PostMe_Delete($$) {
   my ($hash,$name) = @_;
   my $devname = $hash->{NAME}; 
   my $loop;
   
   if( index(AttrVal("$devname","postmeStd",""),$name) != -1){
     my $mga = "Error, the PostMe named $name is a standard PostMe and cannot be deleted";
     Log 1,"[PostMe_Delete] $mga";
     return "$mga";
   }
   
   my $pmn=PostMe_Check($hash,$name);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $name does not exist";
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

   Log3 $devname,3,"[PostMe] Deleted PostMe named $name";
   return undef;
 }

#########################################################################################
#
# PostMe_Rename - Renames an existing PostMe
# 
# Parameter hash = hash of device addressed
#           name = name of PostMe
#           newname = newname of PostMe
#
#########################################################################################

sub PostMe_Rename($$$) {
   my ($hash,$name,$newname) = @_;
   my $devname = $hash->{NAME}; 
   my $loop;
   
   if( index(AttrVal("$devname","postmeStd",""),$name) != -1){
     my $mga = "Error, the PostMe named $name is a standard PostMe and cannot be renamed";
     Log 1,"[PostMe_Rename] $mga";
     return "$mga";
   }
   
   my $pmn=PostMe_Check($hash,$name);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $name does not exist";
     Log 1,"[PostMe_Rename] $mga";
     return "$mga";
   }

   my $pnn=PostMe_Check($hash,$newname);
   
   if( !$pnn ){ 
     if( ReadingsVal($devname, sprintf("postme%02dName",$pnn),"") ne ""){
       my $mga = "Error, a PostMe named $newname does already exist and is not empty";
       Log 1,"[PostMe_Rename] $mga";
       return "$mga";
     }  
   
     #-- current number of PostMes
     my $cnop = ReadingsVal($devname,"postmeCnt",0);
   
     readingsBeginUpdate($hash);
     #-- re-ordering
     for( $loop=$pnn;$loop<$cnop;$loop++){
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
   }
   ReadingsSingleUpdate($hash,sprintf("postme%02dName",$pmn),$newname,1);
   
   Log3 $devname,3,"[PostMe] Renamed PostMe named $name into $newname";
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
   my ($hash,$name,@args) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$name);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $name does not exist";
     Log 1,"[PostMe_Add] $mga";
     return "$mga";
   }
   my $raw = join(' ',@args);
   #-- remove meta data
   my $item = $raw;
   $item =~ s/\[.*\]//g;
   $item =~ s/\]//g;
   $item =~ s/\[//g;
   #-- check old content
   my $old  = ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"");
   my $ind  = index($old,$item);
   if( $ind >= 0 ){
     my $mga = "Error, item $item is already present in PostMe $name";
     Log 1,"[PostMe_Add] $mga";
     return "$mga"; 
   }
   $old    .= ","
     if($old ne "");
   #-- TODO: META DATA MISSING
   readingsSingleUpdate($hash, sprintf("postme%02dCont",$pmn),$old.$item,1);

   Log3 $devname,3,"[Postme] Added item $item to PostMe named $name";
   return undef;
 }

#########################################################################################
#
# PostMe_Modify - Modify something from a PostMe
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub PostMe_Modify($$@) {
   my ($hash,$name,@args) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$name);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $name does not exist";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   #-- difficult to separate item from new meta data. For now, first term is the item,
   #   second term is the attribute and remaining terms are the value
   my $item = @args[0];
   my $attr = @args[1];
   splice(@args,0,2);
   my $val  = join(' ',@args);
   
   #-- check old content
   my $old  = ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"");
   my $ind  = index($old,$item);
   if( $ind < 0 ){
     my $mga = "Error, item $item is not present in PostMe $name";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   #-- item 
   my @lines = split(',',$old);
   my $new   = "";
   for( my $loop=0;$loop<int(@lines);$loop++){
     $old  = $lines[$loop];
     $ind  = index($old,$item);
     #-- different item
     if( $ind < 0 ){
       $new  .= $old.',';
     #-- correct item
     }elsif( $ind == 0 ){
       #-- item may be a short version of the real entry, or may consist of several words
       my $fullitem = $old;
       $fullitem    =~ s/\s*\[.*//;
       $item        = $fullitem
         if( $fullitem ne $item );
       $new .= $item.' [';
       #-- no attributes present so far
       if( $old !~ /.*\[.*\].*/ ){
         $new .= $attr.'="'.$val.'"';
       #-- attributes present already
       }else{
         $old =~ s/.*\[//;
         $old =~ s/\]//;
         #-- particular attribute not yet present
         if( index($old,$attr) < 0){
           if( $val ){
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
                 $new .= $attr.'="'.$val.'" ';
               #-- remove, if no val is given
               }
             }
           }  
         }  
       }  
       $new .= '],'; 
     } 
   }
   #-- correction of sloppy formatting above
   $new =~ s/\s\[\]//g;
   $new =~ s/\s\]/\]/g;
   $new =~ s/\[\s/\[/g;
   $new =~ s/""/"/g;
   $new =~ s/,$//g;
   
   readingsSingleUpdate($hash, sprintf("postme%02dCont",$pmn),$new,1);

   Log3 $devname,3,"[Postme] Modified item $item in PostMe named $name";
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
   my ($hash,$name,@args) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$name);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $name does not exist";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   my $raw = join(' ',@args);
   #-- remove meta data
   my $item = $raw;
   $item =~ s/\[.*\]//g;
   #-- check old content
   my $old  = ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"");
   my $ind  = index($old,$item);
   if( $ind < 0 ){
     my $mga = "Error, item $item is not present in PostMe $name";
     Log 1,"[PostMe_Remove] $mga";
     return "$mga";
   }
   #-- item may be a short version of the real entry
   my @lines= split(',',$old);
   my $new  = "";
   for( my $loop=0;$loop<int(@lines);$loop++){
     $ind  = index($lines[$loop],$item);
     if( $ind < 0 ){
       $new  .= $lines[$loop].',';
     }  
   }
   $new =~ s/,,/,/;
   $new =~ s/^,//;
   $new =~ s/,$//;
   
   readingsSingleUpdate($hash, sprintf("postme%02dCont",$pmn),$new,1);

   Log3 $devname,3,"[Postme] Removed item $item from PostMe named $name";
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
   my ($hash,$name) = @_;
   my $devname = $hash->{NAME}; 
   
   my $pmn=PostMe_Check($hash,$name);
   
   if( !$pmn ){
     my $mga = "Error, a PostMe named $name does not exist";
     Log 1,"[PostMe_Clear] $mga";
     return "$mga";
   }
   
   readingsSingleUpdate($hash, sprintf("postme%02dCont",$pmn),"",1 );
   
   Log3 $devname,3,"[PostMe] Cleared PostMe named $name";
   return undef;
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
# Parameter hash   = hash of device addressed
#           line   = raw data in the form item [att1="val1" att2="val2"]
#           format = 0 - item only
#
#########################################################################################

sub PostMe_LineOut($$$) {
   my ($hash,$line,$format) = @_;
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
     my @lines = split(',',$line);
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
           Log 1,"Setting META $i to VALUE $j";
         }
       }else{
         $item = $line2;
         $meat = "";
         $item =~ s/\s*$//;
       }
       #-- plain format, item only
       $new .= $item.','
         if( $format == 10);
         
       #-- meta data in brackets
       if( $format == 11){
         if( $meat ne "" ){
           $new .= $item.'('.$meat.'),';
         }else{
           $new .= $item.',';
         }
       }
         
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
# PostMe_Set - Implements the Set function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub PostMe_Set($@) {
  my ( $hash, $name, $key, @args ) = @_;

  #-- for the selector: which values are possible
  if ($key eq "?"){
    my @cmds = ("create","delete","rename","add","modify","remove","clear");
    return "Unknown argument $key, choose one of " .join(" ",@cmds);
  }
  
  my $value = shift @args; 
  #Log 1,"[PostMe_Set] called with key ".$key." and value ".$value;
  
  if( $key eq "create"){
    PostMe_Create($hash,$value);
  
  }elsif( $key eq "delete"){
    PostMe_Delete($hash,$value);
      
  }elsif( $key eq "rename"){
    PostMe_Remove($hash,$value,@args);
  
  }elsif( $key eq "add"){
    PostMe_Add($hash,$value,@args);

  }elsif( $key eq "modify"){
    PostMe_Modify($hash,$value,@args);

  }elsif( $key eq "remove"){
    PostMe_Remove($hash,$value,@args);
  
  }elsif( $key eq "clear"){
    PostMe_Clear($hash,$value);
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
  my ($hash, $name, $key, @args) = @_;
  my $pmn;
  my $res = "";
  my $devname = $hash->{NAME};
   
  #Log 1,"[PostMe_Get] with name=$name key=$key args=@args";
 
  my $hasMail = defined(AttrVal($devname,"postmeMailFun",undef)) ? 1 : 0;
  my $hasMsgr = defined(AttrVal($devname,"postmeMsgFun",undef)) ? 1 : 0;
  my $hasTTS  = defined(AttrVal($devname,"postmeTTSDev",undef)) ? 1 : 0;
  
  #-- for the selector: which values are possible
  if ($key eq "?"){
    #-- current number of PostMes
    my $cnop = ReadingsVal($devname,"postmeCnt",0);
    my $pml  = "";
    for( my $i=1;$i<=$cnop;$i++){
       $pml .= ","
          if( $i >1);
       $pml .= ReadingsVal($devname, sprintf("postme%02dName",$i),"");
    } 
    my @cmds = ("version:noArg","all:noArg","list:".$pml);
    $res = "Unknown argument $key choose one of ".join(" ",@cmds);
    $res.= " mail:".$pml
      if($hasMail);
    $res.= " message:".$pml
      if($hasMsgr);
    $res.= " ttsSay:".$pml
      if($hasTTS);
    $res.= " z_JSON:".$pml;
      
    return $res;
  }
  
  Log 1,"[PostMe_Get] with key=$key";
    
  if ($key eq "version") {
    return "PostMe.version => $postmeversion";
   
   #-- list one PostMe
  } elsif( ($key eq "list")||($key eq "z_JSON")||($key eq "mail")||($key eq "message")||($key eq "ttsSay") ){
   
    $pmn = PostMe_Check($hash,$args[0]);
    if( !$pmn ){
      my $mga = "Error, a PostMe named $name does not exist";
      Log 1,"[PostMe_Get] $mga";
      return "$mga";
    }
    ##-- list
    if( $key eq "list" ){
      $res = ReadingsVal($devname, sprintf("postme%02dName",$pmn),"");
      $res .= ": ";
      $res .= PostMe_LineOut($hash,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),"")."\n",10);
      return $res;
      
    ##-- JSON
    }elsif( $key eq "z_JSON" ){
      my $line = ReadingsVal($devname, sprintf("postme%02dName",$pmn),"");
      $res = PostMe_LineOut($hash,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),""),15);
      return '{"'.$line.'": ['.$res.']}';
    
    ##-- send by mail
    }elsif( $key eq "mail" ){
      my $rcpt = AttrVal($devname,sprintf("postme%02dMailRec",$pmn),undef);
      my $sbjt = ReadingsVal($devname, sprintf("postme%02dName",$pmn),undef);
      my $text = PostMe_LineOut($hash,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),undef),11);
      my $fun  = AttrVal($devname,"postmeMailFun",undef);
      
      if( $rcpt && $sbjt && $text && $fun ){ 
        my $ref = \&$fun;
        &$ref($rcpt,$sbjt,$text);
      }
      my $mga = "$sbjt sent by mail";
      readingsSingleUpdate($hash,"state",$mga,1 );
      Log3 $devname,3,"[PostMe] ".$mga;
      return undef;
    
    ##-- send by instant messenger
    }elsif( $key eq "message" ){
      my $rcpt = AttrVal($devname,sprintf("postme%02dMsgRec",$pmn),undef);
      my $sbjt = ReadingsVal($devname, sprintf("postme%02dName",$pmn),undef);
      my $text = PostMe_LineOut($hash,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),undef),11);
      my $fun  = AttrVal($devname,"postmeMsgFun",undef);
      
      if( $rcpt && $sbjt && $text && $fun ){      
        my $ref = \&$fun;
        &$ref($rcpt,$sbjt,$text);
      }
      my $mga = "$sbjt sent by messenger";
      readingsSingleUpdate($hash,"state",$mga,1 );
      Log3 $devname,3,"[PostMe] ".$mga;
      return undef;
      
    ##-- speak as TTS
    }elsif( $key eq "ttsSay" ){
      my $sbjt = ReadingsVal($devname, sprintf("postme%02dName",$pmn),undef);
      my $text = PostMe_LineOut($hash,ReadingsVal($devname, sprintf("postme%02dCont",$pmn),undef),10);
      $text =~ s/,/\<break time=\"1s\"\/\>/g;
      my $dev  = AttrVal($devname,"postmeTTSDev",undef);
      
      if( $sbjt && $text && $dev ){
        fhem('set '.$dev.' ttsSay '.$sbjt.' enthält <break time="1s"/> '.$text);
      }
      my $mga = "$sbjt spoken by TTS";
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
      $res .= ": ".PostMe_LineOut($hash,ReadingsVal($devname, sprintf("postme%02dCont",$loop),"")."\n",10);
    }
    return $res;
  } 
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
  my $devname= $FW_webArgs{postit};
  my $name   = $FW_webArgs{name};
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
        my $name = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
        my $sel  = sprintf("sel%02d",$loop);
        $res .= '<div id="'.$sel.'"><img src="'.$icon.'"/>'.$name.'</div><br/>';
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
        my $name = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
        my $sel  = sprintf("sel%02d",$loop);
        if( $click == 0){
          $res .=         '$("#'.$sel.'").mouseover(function(){dlg1.load("/fhem/PostMe_widget?postit='.$devname.'&name='.$name.'",';
          $res .=                                          'function(){dlg1.dialog("open")})});';
          $res .=         '$("#'.$sel.'").mouseout(function(){dlg1.dialog("close")});';
        }else{
          $res .=         '$("#'.$sel.'").click(function(){dlg1.load("/fhem/PostMe_widget?postit='.$devname.'&name='.$name.'",';
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
        my $name = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
        if( $click == 0){
          $res .= '<div onmouseover="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');" ';
          $res .= 'onmouseout="postit.close()"><img src="'.$icon.'"/>'.$name.'</div><br/>';
        }else{
          $res .= '<div onclick="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');">';
          $res .= '<img src="'.$icon.'"/>'.$name.'</div><br/>';
        }
      }
      FW_pO $res.'</div>';
    
    #-- SVG rendering
    }else{
      $FW_RETTYPE = "image/svg+xml";
      $FW_RET="";
      FW_pO '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100px" height="100px">';
      for( my $loop=1;$loop<=$cnop;$loop++){
        my $name = ReadingsVal($devname, sprintf("postme%02dName",$loop),"");
        $res.=  sprintf('<text x="10" y="%02d" fill="blue" style="font-family:Helvetica;font-size:12px;font-weight:bold" ',10+15*$loop);
        $res.=  'onmouseover="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');" ';
        $res.=  'onmouseout="postit.close()">'.$name.'</text>';
        $res.= <g>
      }
      FW_pO $res.'</svg>';
    }
    return ($FW_RETTYPE, $FW_RET);
  }
  
  #-- PostMe name
  if( !$name ){
    Log 1,"[PostMe_widget] Error, web argument name=... is missing";
    return undef;
  }

  $pmn = PostMe_Check($hash,$name);
  if( !$pmn ){
    Log 1,"[PostMe_widget] Error, a PostMe named $name does not exist";
    return undef;
  }
  
  ##################################################-- type=pin => single pin
  if( $type eq "pin"){
  #-- jQuery rendering
    if( $style eq "jQuery"){
    
      my $name = ReadingsVal($devname, sprintf("postme%02dName",$pmn),"");
      my $sel  = sprintf("sel%02d",$pmn);
      
      $FW_RETTYPE = "text/html";
      $FW_RET="";
      $res .= $css;
      #-- we need our own jQuery object
      $res .= '<script  type="text/javascript" src="/fhem/pgm2/jquery.min.js"></script>';
      $res .= '<script  type="text/javascript" src="/fhem/pgm2/jquery-ui.min.js"></script>';
      
      #-- this is for the selector
      $res .= '<div id="postme" class="postmeclass">';    
      $res .= '<div id="'.$sel.'"><img src="'.$icon.'"/>'.$name.'</div><br/>';
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
        $res .=         '$("#'.$sel.'").mouseover(function(){dlg1.load("/fhem/PostMe_widget?postit='.$devname.'&name='.$name.'",';
        $res .=                                          'function(){dlg1.dialog("open")})});';
        $res .=         '$("#'.$sel.'").mouseout(function(){dlg1.dialog("close")});';
      }else{
        $res .=         '$("#'.$sel.'").click(function(){dlg1.load("/fhem/PostMe_widget?postit='.$devname.'&name='.$name.'",';
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
      my $name = ReadingsVal($devname, sprintf("postme%02dName",$pmn),"");
      if( $click == 0){
        $res.=  '<div onmouseover="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');" ';
        $res.=  'onmouseout="postit.close()">';
      }else{
        $res.=  '<div     onclick="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');">';
      }
      FW_pO $res.'<img src="'.$icon.'"/>'.$name.'</div>';
     
    #-- SVG rendering
    }else{
      $FW_RETTYPE = "image/svg+xml";
      $FW_RET="";
      FW_pO '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100px" height="100px">';
      my $name = ReadingsVal($devname, sprintf("postme%02dName",$pmn),"");
      $res.=  '<text x="10" y="10" fill="blue" style="font-family:Helvetica;font-size:12px;font-weight:bold" ';
      $res.=  'onmouseover="postit=window.open(\'PostMe_widget?postit='.$devname.'&amp;name='.$name.'\',\'postit\',\'height=200,width=200,top=400,left=400,menubar=no,toolbar=no,titlebar=no\');" ';
      $res.=  'onmouseout="postit.close()">'.$name.'</text>';
      FW_pO $res.'</svg>';
    }
    return ($FW_RETTYPE, $FW_RET);
  }
  
  ################################################## default (type missing) => content of a single postme
  
  my @lines=split(',',ReadingsVal($devname, sprintf("postme%02dCont",$pmn),""));
  if( !(int(@lines)>0) ){
    Log 1,"[PostMe_widget] Asking to display empty PostMe $name";
    return undef;
  }

    #-- HTML rendering
    if( $style ne "SVG"){
      $FW_RETTYPE = "text/html; charset=$FW_encoding";
      $FW_RET="";
      $res .= $css;
      $res .= '<div class="postmeclass2" style="width:200px">';
      $res .= '<b>'.$name.'</b><br/>';
      for (my $i=0;$i<int(@lines);$i++){
        #--special for meta data
        my $line=PostMe_LineOut($hash,$lines[$i],0);
        $res.=  $line.'<br/>';
      }
      FW_pO $res.'</div>';
    
    #--- SVG rendering
    }else{
      $FW_RETTYPE = "image/svg+xml";
      $FW_RET="";
      FW_pO '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100px" height="100px">';

      $res =  '<text x="10" y="10" fill="blue" style="font-family:Helvetica;font-size:12px;font-weight:bold">';
      $res.=  $name.'</text>';   
      for (my $i=0;$i<int(@lines);$i++){
        $res.=  sprintf('<text x="10" y="%02d" fill="blue" style="font-family:Helvetica;font-size:10px">',25+$i*12);
        $res.=  PostMe_LineOut($hash,$lines[$i],0);
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
=begin html

   <a name="PostMe"></a>
        <h3>PostMe</h3>
        <p> FHEM module to set up a system of sticky notes, similar to Post-Its&trade;</p>

        <a name="PostMedefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;postit&gt; PostMe</code>
            <br />Defines the PostMe system, &lt;postit&gt; is an arbitrary name for the system. </p>
        <a name="PostMeusage"></a>
        <h4>Usage</h4>
        Special meta data for items may be included by using "[" and "]"; characters, e.g.
        <code>set &lt;postit&gt; add &lt;name&gt; &lt;item&gt; [&lt;attribute1&gt;="&lt;data1&gt;" ...</code>
        The attribute-value pairs may be added,modified and removed with the set modify command, see below. 
        The sticky notes may be integrated into any Web page by simply embedding the following tags
           <ul>
           <li> <code>&lt;embed src="/fhem/PostMe_widget?type=pins&amp;postit=&lt;postit&gt;"/&gt;</code> <br/>
           to produce an interactive list of all PostMe names with pins from system &lt;postit&gt;.</li>
           <li> <code>&lt;embed src="/fhem/PostMe_widget?type=pin&amp;postit=&lt;postit&gt;&amp;name=&lt;name&gt;"/&gt;</code> <br/>
           to produce an interactive entry for PostMe &lt;name&gt;from system &lt;postit&gt;</li>
           </ul>
           
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
            <li><code>set &lt;postit&gt; remove &lt;name&gt; &lt;item&gt;</code>
                <br />removes from the sticky note named &lt;name&gt; an item &lt;item&gt;</li>
            <li><code>set &lt;postit&gt; clear &lt;name&gt;</code>
                <br />clears the sticky note named &lt;name&gt; from all items </li>
          
        </ul>
        <a name="PostMeget"></a>
        <h4>Get</h4>
        <ul>
            <li><code>get &lt;postit&gt; version</code>
                <br />Display the version of the module</li>
            <li><code>get &lt;postit&gt; all</code>
                <br />Show all sticky notes and their content</li>
            <li><code>get &lt;postit&gt; list &lt;name&gt;</code>
                <br />Show the sticky note named &lt;name&gt; and its content</li>
            <li><code>get &lt;postit&gt; mail &lt;name&gt;</code>
                <br />Send the sticky note named &lt;name&gt; and its content via eMail to a predefined
                recipient (e.g. sticky note <postme01Name> is sent to <postme01MailRec>). </li>
            <li><code>get &lt;postit&gt; message &lt;name&gt;</code>
                <br />Send the sticky note named &lt;name&gt; and its content via instant messenger to a predefined
                recipient (e.g. sticky note <postme01Name> is sent to <postme01MsgRec>). The messenger 
                subroutine <postmeMsgFun> is called with three parameters for recipient, subject
                and text. </li>
            <li><code>get &lt;postit&gt; ttsSay &lt;name&gt;</code>
                <br />Speak the sticky note named &lt;name&gt; and its content on a predefined
                device <postmeTTSDev></li>
        </ul>
        <a name="PostMeattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><code>attr &lt;postit&gt; postmeStd &lt;name1,name2,...&gt;</code>
                <br />Comma separated list of standard sticky notes that will be created on device start.</li>
            <li><code>attr &lt;postit&gt; postmeClick 1|0 (default)</code>
                <br />If 0, embedded sticky notes will pop up on mouseover-events and vanish on mouseout-events (default).<br/>
                      If 1, embedded sticky notes will pop up on click events and vanish after closing the note</li>
            <li><code>attr &lt;postit&gt; postmeicon &lt;string&gt;</code>
                <br />Icon for display of a sticky note</li>
            <li><code>attr &lt;postit&gt; postmeStyle SVG|HTML|jQuery (default)</code>
                <br />If jQuery, embedded sticky notes will produce jQuery code (default) <br/>
                      If HTML, embedded sticky notes will produce HTML code <br/>
                      If SVG, embedded sticky notes will produce SVG code</li>
            <li><code>attr &lt;postit&gt; postmeMailFun &lt;string&gt;</code>
                <br />Function name for the eMail function.  This subroutine 
                is called with three parameters for recipient, subject
                and text.</li>
            <li><code>attr &lt;postit&gt; postmeMsgFun &lt;string&gt;</code>
                <br />Function name for the instant messenger function.  This subroutine 
                is called with three parameters for recipient, subject
                and text.</li>
            <li><code>attr &lt;postit&gt; postmeTTSDev &lt;string&gt;</code>
                <br />Device name for the TTS function.</li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
=end html
=begin html_DE

<a name="PostMe"></a>
<h3>PostMe</h3>

=end html_DE
=cut
