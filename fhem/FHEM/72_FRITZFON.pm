###############################################################
# $Id: $
#
#  72_FRITZFON.pm
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#
#  This module handles the Fritz!Phone MT-F 
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################
#
# define <name> FRITZFON
#
##############################################################################

package main;

use strict;
use warnings;
use Blocking;


sub FRITZFON_Log($$$);
sub FRITZFON_Init($);
sub FRITZFON_Init_Reading($$$@);
sub FRITZFON_Ring($$);
sub FRITZFON_Exec($$);
  
my %fonModel = ( 
        '0x01' => "MT-D"
      , '0x03' => "MT-F"
      , '0x04' => "C3"
      , '0x05' => "C4"
      , '0x08' => "M2"
   );

my %ringTone = ( 
     0 => "HandsetDefault"
   , 1 => "HandsetInternalTon"
   , 2 => "HandsetExternalTon"
   , 3 => "Standard"
   , 4 => "Eighties"
   , 5 => "Alarm"
   , 6 => "Ring"
   , 7 => "RingRing"
   , 8 => "News"
   , 9 => "CustomerRingTon"
   , 10 => "Bamboo"
   , 11 => "Andante"
   , 12 => "ChaCha"
   , 13 => "Budapest"
   , 14 => "Asia"
   , 15 => "Kullabaloo"
   , 16 => "silent"
   , 17 => "Comedy"
   , 18 => "Funky",
   , 19 => "Fatboy"
   , 20 => "Calypso"
   , 21 => "Pingpong"
   , 22 => "Melodica"
   , 23 => "Minimal"
   , 24 => "Signal"
   , 25 => "Blok1"
   , 26 => "Musicbox"
   , 27 => "Blok2"
   , 28 => "2Jazz"
   , 33 => "InternetRadio"
   , 34 => "MusicList"
   );

my %ringToneNumber;
while (my ($key, $value) = each %ringTone) {
   $ringToneNumber{lc $value}=$key;
}

   
my @radio=();
 
sub ##########################################
FRITZFON_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZFON_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "FRITZFON $instName: $sub.$xline " . $text;
}

sub ##########################################
FRITZFON_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FRITZFON_Define";
  $hash->{UndefFn}  = "FRITZFON_Undefine";

  $hash->{SetFn}    = "FRITZFON_Set";
  $hash->{GetFn}    = "FRITZFON_Get";
  $hash->{AttrFn}   = "FRITZFON_Attr";
  $hash->{AttrList} = "disable:0,1 "
                ."ringWithIntern:0,1,2 "
                .$readingFnAttributes;

} # end FRITZFON_Initialize


sub ##########################################
FRITZFON_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   return "Usage: define <name> FRITZFON" if(@args <2 || @args >2);  

   my $name = $args[0];

   $hash->{NAME} = $name;

   $hash->{STATE}       = "Initializing";
   $hash->{Message}     = "FHEM";
   $hash->{fhem}{modulVersion} = '$Date: $';

   RemoveInternalTimer($hash);
 # Get first data after 2 seconds
   InternalTimer(gettimeofday() + 2, "FRITZFON_Init", $hash, 0);
 
   return undef;
} #end FRITZFON_Define


sub ##########################################
FRITZFON_Undefine($$)
{
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash);

  return undef;
} # end FRITZFON_Undefine


sub ##########################################
FRITZFON_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
      # $cmd can be "del" or "set"
      # $name is device name
      # aName and aVal are Attribute name and value
   my $hash = $defs{$name};

   if ($cmd eq "set")
   {
   }

   return undef;
} # FRITZFON_Attr ende


sub ##########################################
FRITZFON_Set($$@) 
{
   my ($hash, $name, $cmd, @val) = @_;
   my $resultStr = "";
   
   if ( lc $cmd eq 'customerringtone')
   {
      if (int @val > 0) 
      {
         return FRITZFON_SetCustomerRingTone $hash, @val;
      }
      else
      {
         return "Missing parameters after command 'set $name $cmd'";
      }
   }
   elsif( lc $cmd eq 'reinit' ) 
   {
      FRITZFON_Init($hash);
      return undef;
   }
   elsif ( lc $cmd eq 'message')
   {
      if (int @val > 0) 
      {
         $hash->{Message} = substr (join(" ", @val),0,30) ;
         return undef;
      }
      else
      {
         return "Missing parameters after command 'set $name $cmd'";
      }
   }
   elsif ( lc $cmd eq 'ring')
   {
      if (int @val > 0) 
      {
         FRITZFON_Ring $hash, @val;
         return undef;
      }
      else
      {
         return "Missing parameters after command 'set $name $cmd'";
      }
   }
   elsif ( lc $cmd eq 'startradio')
   {
      if (int @val > 0) 
      {
         # FRITZFON_Ring $hash, @val; # join("|", @val);
         return undef;
      }
      else
      {
         return "Missing parameters after command 'set $name $cmd'";
      }
   }
   elsif ( lc $cmd eq 'convertringtone')
   {
      if (int @val > 0) 
      {
         return FRITZFON_ConvertRingTone $hash, @val;
      }
      else
      {
         return "Missing parameters after command 'set $name $cmd'";
      }
   }
   my $list = "reinit:noArg"
            . " customerRingTone"
            . " convertRingTone"
            . " message"
            . " ring"
            . " startRadio";
   return "Unknown argument $cmd, choose one of $list";

} # end FRITZFON_Set


sub ##########################################
FRITZFON_Get($@)
{
   my ($hash, $name, $cmd) = @_;
   my $returnStr;

   if (lc $cmd eq "ringtones") 
   {
      $returnStr  = "Ring tones to use with 'set <name> ring <intern> <duration> <ringTone>'\n";
      $returnStr .= "----------------------------------------------------------------------\n";
      $returnStr .= join "\n", sort values %ringTone;
      return $returnStr;
   }

   my $list = "ringTones:noArg";
   return "Unknown argument $cmd, choose one of $list";
} # end FRITZFON_Get


# Starts the data capturing and sets the new timer
sub ##########################################
FRITZFON_Init($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   my $result;
   
   readingsBeginUpdate($hash);

  # Box Firmware
   FRITZFON_Init_Reading($hash
      , "box_fwVersion"
      , "ctlmgr_ctl r logic status/nspver"
      , "fwupdate");

  # Internetradioliste erzeugen
   my $i = 0;
   @radio = ();
   while ()
   {
      last unless $result = FRITZFON_Init_Reading($hash, 
         sprintf ("radio%02d",$i), 
         "ctlmgr_ctl r configd settings/WEBRADIO".$i."/Name");
      push @radio, $result;
      $i++;
   }

   foreach (1..6)
   {
     # Dect-Telefonname
      FRITZFON_Init_Reading($hash, 
         "dect".$_, 
         "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Name");
     # Dect-Interne Nummer
      FRITZFON_Init_Reading($hash, 
         "dect".$_."_intern", 
         "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Intern");
     # Dect-Internal Ring Tone
      # FRITZFON_Init_Reading($hash, 
         # "dect".$_."_intRingTone", 
         # "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/IntRingTone");
     # Handset manufacturer
      my $brand = FRITZFON_Init_Reading($hash, 
         "dect".$_."_manufacturer", 
         "ctlmgr_ctl r dect settings/Handset".($_-1)."/Manufacturer");   
     if ($brand eq "AVM")
     {
        # Ring Tone Name
         FRITZFON_Init_Reading($hash
            , "dect".$_."_intRingTone"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/IntRingTone"
            , "ringtone");
        # Radio Name
         FRITZFON_Init_Reading($hash
            , "dect".$_."_radio"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/RadioRingID"
            , "radio");
        # Background image
         FRITZFON_Init_Reading($hash
            , "dect".$_."_imagePath "
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/ImagePath ");
        # Customer Ring Tone
         FRITZFON_Init_Reading($hash
            , "dect".$_."_custRingTone"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/G722RingTone");
        # Customer Ring Tone Name
         FRITZFON_Init_Reading($hash
            , "dect".$_."_custRingToneName"
            , "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/G722RingToneName");
        # Firmware Version
         FRITZFON_Init_Reading($hash
            , "dect".$_."_fwVersion"
            , "ctlmgr_ctl r dect settings/Handset".($_-1)."/FWVersion");   
            
        # Phone Model
         FRITZFON_Init_Reading($hash 
            , "dect".$_."_model"
            , "ctlmgr_ctl r dect settings/Handset".($_-1)."/Model"
            , "model");   
      }
   }
   foreach (1..3)
   {
     # Analog-Telefonname
      if (FRITZFON_Init_Reading($hash, 
         "fon".$_, 
         "ctlmgr_ctl r telcfg settings/MSN/Port".($_-1)."/Name"))
      {
         readingsBulkUpdate($hash, "fon".$_."_intern", $_);
      }
   }
   # configd:settings/WEBRADIO/list(Name,URL)
   # telcfg:settings/Foncontrol/User"..g_ctlmgr.idx.."/RadioRingID
   readingsEndUpdate( $hash, 1 );
}

sub ##########################################
FRITZFON_Init_Reading($$$@)
{
   my ($hash, $rName, $cmd, $replace) = @_;
   $replace = "" 
      unless defined $replace;
   my $result = FRITZFON_Exec( $hash, $cmd);
   if ($result) {
      if ($replace eq "model")
      {
         $result = $fonModel{$result}
            if defined $fonModel{$result};
      }
      elsif ($replace eq "ringtone")
      {
         $result = $ringTone{$result};
      }
      elsif ($replace eq "radio")
      {
         $result = $radio[$result];
      }
      elsif ($replace eq "fwupdate")
      {
         my $update = FRITZFON_Exec( $hash, "ctlmgr_ctl r updatecheck status/update_available_hint");
         $result .= " (old)"
            if $update == 1;
      }
            
      readingsBulkUpdate($hash, $rName, $result)
         if $result;
   } elsif (defined $hash->{READINGS}{$rName} ) {
      delete $hash->{READINGS}{$rName};
   }
   return $result;
}

sub ##########################################
FRITZFON_Ring($@) 
{
   my ($hash, @val) = @_;
   my $name = $hash->{NAME};
   
   my $timeOut = 20;
   $timeOut = $val[1] + 15 
      if defined $val[1]; 

   if ( exists( $hash->{helper}{RUNNING_PID} ) )
   {
      FRITZFON_Log $hash, 1, "Double call. Killing old process ".$hash->{helper}{RUNNING_PID};
      BlockingKill( $hash->{helper}{RUNNING_PID} ); 
      delete($hash->{helper}{RUNNING_PID});
   }
 
   $hash->{helper}{RUNNING_PID} = BlockingCall("FRITZFON_Ring_Run", $name."|".join("|", @val), 
                                       "FRITZFON_Ring_Done", $timeOut,
                                       "FRITZFON_Ring_Aborted", $hash);
} # end FRITZFON_Ring

sub ##########################################
FRITZFON_Ring_Run($$) 
{
   my ($string) = @_;
   my ($name, $intNo, $duration, $ringTone) = split /\|/, $string;
   my $hash = $defs{$name};
   
   my $fonType;
   my $fonTypeNo;
   my $result;
   my $curIntRingTone;
   my $curCallerName;
   
   if (610<=$intNo && $intNo<=615)
   {
      $fonType = "DECT"; $fonTypeNo = $intNo - 609; 
   }
   
   return $name."|0|Error: Internal number '$intNo' not valid" 
      unless defined $fonType;

   $duration = 5 
      unless defined $duration;
   
   if (defined $ringTone)
   {
      my $temp = $ringTone;
      $ringTone = $ringToneNumber{lc $ringTone};
      return $name."|0|Error: Ring tone '$temp' not valid"
         unless defined $ringTone;
   }
      
   my $msg = $hash->{Message};
   $msg = "FHEM"
      unless defined $msg;
      
   my $ringWithIntern = AttrVal( $name, "ringWithIntern",  0 );
   
   # uses name of virtual port 0 (dial port 1) to show message on ringing phone
   if ($ringWithIntern =~ /^(1|2)$/ )
   {
      $curCallerName = FRITZFON_Exec( $hash, "ctlmgr_ctl r telcfg settings/MSN/Port".($ringWithIntern-1)."/Name");
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '$msg'");
   }
   
   if ($fonType eq "DECT" )
   {
      return $name."|0|Error: Internal number ".$intNo." does not exist"
         unless FRITZFON_Exec( $hash, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$fonTypeNo."/Intern");
      if (defined $ringTone)
      {
         $curIntRingTone = FRITZFON_Exec( $hash, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone");
         FRITZFON_Log $hash, 5, "Current internal ring tone of DECT ".$fonTypeNo." is ".$curIntRingTone;
         FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone ".$ringTone);
         FRITZFON_Log $hash, 5, "Set internal ring tone of DECT ".$fonTypeNo." to ".$ringTone;
      }
      sleep 0.5;
      FRITZFON_Log $hash, 5, "Ringing $intNo for $duration seconds";
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/DialPort 1");
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg command/Dial **".$intNo);
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/DialPort 50");
      sleep $duration;
      FRITZFON_Log $hash, 5, "Hangup ".$intNo;
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg command/Hangup **".$intNo);
      if (defined $ringTone)
      {
         FRITZFON_Log $hash, 5, "Set internal ring tone of DECT ".$fonTypeNo." back to ".$curIntRingTone;
         FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone ".$curIntRingTone);
      }
   }

   if ($ringWithIntern =~ /^(1|2)$/ )
   {
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '$curCallerName'");
   }

   return $name."|1|";
}

sub ##########################################
FRITZFON_Ring_Done($$) 
{
   my ($string) = @_;
   return unless defined $string;

   my ($name, $success, $result) = split("\\|", $string);
   my $hash = $defs{$name};
   
   delete($hash->{helper}{RUNNING_PID});

   if ($success != 1)
   {
      FRITZFON_Log $hash, 1, $result;
   }
}

sub ##########################################
FRITZFON_Ring_Aborted($$) 
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  FRITZFON_Log $hash, 1, "Timeout when ringing";
}

sub ############################################
FRITZFON_SetCustomerRingTone($@)
{  
   my ($hash, $intern, @file) = @_;
   my $returnStr;
   my $inFile = join " ", @file;
   my $uploadFile = '/tmp/fhem'.$intern.'.G722';
   
   $inFile =~ s/file:\/\///;
   if (lc (substr($inFile,-4)) eq ".mp3")
   {
      # mp3 files are converted
      $returnStr = FRITZFON_Exec ($hash,
         'picconv.sh "file://'.$inFile.'" "'.$uploadFile.'" ringtonemp3');
   }
   elsif (lc (substr($inFile,-5)) eq ".g722")
   {
      # G722 files are copied
      $returnStr = FRITZFON_Exec ($hash,
         "cp '$inFile' '$uploadFile'");
   }
   else
   {
      return "Error: only MP3 or G722 files can be uploaded to the phone";
   }
   # trigger the loading of the file to the phone, file will be deleted as soon as the upload finished
   $returnStr .= "\n".FRITZFON_Exec ($hash,
      '/usr/bin/pbd --set-ringtone-url --book="255" --id="'.$intern.'" --url="file:///'.$uploadFile.'" --name="FHEM"');
   return $returnStr;
}

sub ############################################
FRITZFON_ConvertRingTone ($@)
{  
   my ($hash, @val) = @_;
   my $inFile = join " ", @val;
   $inFile =~ s/file:\/\///;
   my $outFile = $inFile;
   $outFile = substr($inFile,0,-4)
      if (lc substr($inFile,-4) =~ /\.(mp3|wav)/);
   my $returnStr = FRITZFON_Exec ($hash,
      'picconv.sh "file://'.$inFile.'" "'.$outFile.'.g722" ringtonemp3');
   return $returnStr;
   
#'picconv.sh "'.$inFile.'" "'.$outFile.'.g722" ringtonemp3'
#picconv.sh "file://$dir/upload.mp3" "$dir/$filename" ringtonemp3   
#"ffmpegconv  -i '$inFile' -o '$outFile.g722' --limit 240");
#ffmpegconv -i "${in}" -o "${out}" --limit 240
#pbd --set-image-url --book=255 --id=612 --url=/var/InternerSpeicher/FRITZ/fonring/1416431162.g722 --type=1
#pbd --set-image-url --book=255 --id=612 --url=file://var/InternerSpeicher/fritzfontest.g722 --type=1
#ctlmgr_ctl r user settings/user0/bpjm_filter_enable
#CustomerRingTon 
#/usr/bin/pbd --set-ringtone-url --book="255" --id="612" --url="file:///var/InternerSpeicher/claydermann.g722" --name="Claydermann"
}


# Executed the command on the FritzBox Shell
sub ############################################
FRITZFON_Exec($$)
{
   my ($hash, $cmd) = @_;
   FRITZFON_Log $hash, 5, "Execute '".$cmd."'";
   my $result = qx($cmd);
   chomp ($result);
   FRITZFON_Log $hash, 5, "Result '".$result."'";
   
   return $result;
}

##################################### 

1;

=pod
=begin html

<a name="FRITZFON"></a>
<h3>FRITZFON</h3>
<div  style="width:800px"> 
<ul>
   The module implements the Fritz!Fon's (MT-F, MT-D, C3, C4) as a signaling device.
   <br>
   It has to run in an FHEM process <b>on</b> a Fritz!Box.
   <br/><br/>
   <a name="FRITZFONdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZFON</code>
      <br>
      Example:
      <br>
      <code>define Telefon FRITZFON</code>
      <br/><br/>
   </ul>
  
   <a name="FRITZFONset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; reinit</code>
         <br>
         Reads in some information of the connected phone devices.
      </li><br>
      <li><code>set &lt;name&gt; message &lt;text&gt;</code>
      <br>
      Stores the text to show it later as 'caller' on the ringing phone.
      This is done by changing the name of the calling internal number.
      Maximal 30 characters are allowed.
      </li><br>
      <li><code>set &lt;name&gt; ring &lt;internalNumber&gt; [duration] [ringTone]</code>
         <br>
         Rings the internal number for duration (seconds) and (if possible) with the given ring tone name.
      </li><br>
      <li><code>set &lt;name&gt; customerRingTone &lt;internalNumber&gt; &lt;fullFilePath&gt;</code>
         <br>
         Uploads the file fullFilePath on the given handset. Only mp3 or G722 format is allowed.
         <br>
         The file has to be placed on the file system of the fritzbox.
         <br>
         The upload takes about one minute before the tone is available.
      </li><br>
      <li><code>set &lt;name&gt; startradio &lt;internalNumber&gt; [name]</code>
         <br>
         not implemented yet. Start the internet radio on the given Fritz!Fon
         <br>
      </li><br>
   </ul>  

   <a name="FRITZFONget"></a>
   <b>Get</b>
   <ul>
      <li><code>get &lt;name&gt; ringTones</code>
         <br>
         Shows a list of ring tones that can be used.
      </li><br>
   </ul>  
  
   <a name="FRITZFONattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>ringWithIntern &lt;internalNumber&gt;</code>
      <br>
      To show a message during a ring the caller needs to be an internal phone number.
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br>

   <a name="FRITZFONreading"></a>
   <b>Readings</b>
   <ul><br>
      <li><b>dect</b><i>1</i><b>_intRingTone</b> - Internal ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intern</b> - Internal number of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_manufacturer</b> - Manufacturer of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_name</b> - Internal name of the DECT device <i>1</i></li>
   </ul>
   <br>
</ul>
</div>

=end html

=cut