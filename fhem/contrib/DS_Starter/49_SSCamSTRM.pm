########################################################################################################################
# $Id: 49_SSCamSTRM.pm 22329 2020-07-02 17:16:52Z DS_Starter $
#########################################################################################################################
#       49_SSCamSTRM.pm
#
#       (c) 2018-2020 by Heiko Maaz
#       forked from 98_weblink.pm by Rudolf König
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module is used by module 49_SSCam to create Streaming devices.
#       It can't be used without any SSCam-Device.
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#########################################################################################################################

package FHEM::SSCamSTRM;                               ## no critic 'package';

use strict;
use warnings;
use GPUtils qw(GP_Import GP_Export);                   # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday);
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;      ## no critic 'eval'

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          AnalyzePerlCommand
          AttrVal
          CommandSet
          data
          defs
          devspec2array
          FmtDateTime
          InternalTimer
          IsDisabled
          Log3    
          modules          
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsVal
          RemoveInternalTimer
          readingFnAttributes
          sortTopicNum
          FW_cmd
          FW_directNotify                                                              
          FW_wname   
          FW_pH    
          FW_widgetFallbackFn          
          FHEM::SSCam::ptzPanel 
          FHEM::SSCam::streamDev
          FHEM::SSCam::composeGallery
          FHEM::SSCam::getClHash
        )
  );
  
  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/gx;
  #     for (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
        )
  );  
  
}

# Versions History intern
my %vNotesIntern = (
  "2.13.0" => "14.07.2020  integrate streamDev master ",
  "2.12.0" => "28.06.2020  upgrade SSCam functions due to SSCam switch to packages ",
  "2.11.0" => "24.06.2020  switch to packages, changes according to PBP ",
  "2.10.2" => "08.11.2019  undef \$link in FwFn / streamAsHtml to save memory ",
  "2.10.1" => "18.10.2019  set parentState initial in Define, Forum: https://forum.fhem.de/index.php/topic,45671.msg985136.html#msg985136 ",
  "2.10.0" => "21.09.2019  new attribute hideAudio ",
  "2.9.0"  => "19.09.2019  new attribute noLink ",
  "2.8.0"  => "09.09.2019  new attribute hideButtons ",
  "2.7.0"  => "15.07.2019  FTUI support, new attributes htmlattrFTUI, hideDisplayNameFTUI, ptzButtonSize, ptzButtonSizeFTUI ",
  "2.6.0"  => "21.06.2019  GetFn -> get <name> html ",
  "2.5.0"  => "27.03.2019  add Meta.pm support ",
  "2.4.0"  => "24.02.2019  support for \"genericStrmHtmlTag\" in streaming device MODEL generic ",
  "2.3.0"  => "04.02.2019  Rename / Copy added, Streaming device can now be renamed or copied ",
  "2.2.1"  => "19.12.2018  commandref revised ",
  "2.2.0"  => "13.12.2018  load sscam_hls.js, sscam_tooltip.js from pgm2 for HLS Streaming support and tooltips ",
  "2.1.0"  => "11.12.2018  switch \"popupStream\" from get to set ",
  "2.0.0"  => "09.12.2018  get command \"popupStream\" and attribute \"popupStreamFW\" ",
  "1.5.0"  => "02.12.2018  new attribute \"popupWindowSize\" ",
  "1.4.1"  => "31.10.2018  attribute \"autoLoop\" changed to \"autoRefresh\", new attribute \"autoRefreshFW\" ",
  "1.4.0"  => "29.10.2018  readingFnAttributes added ",
  "1.3.0"  => "28.10.2018  direct help for attributes, new attribute \"autoLoop\" ",
  "1.2.4"  => "27.10.2018  fix undefined subroutine &main::SSCam_ptzpanel (https://forum.fhem.de/index.php/topic,45671.msg850505.html#msg850505) ",
  "1.2.3"  => "03.07.2018  behavior changed if device is disabled ",
  "1.2.2"  => "26.06.2018  make changes for generic stream dev ",
  "1.2.1"  => "23.06.2018  no name add-on if MODEL is snapgallery ",
  "1.2.0"  => "20.06.2018  running stream as human readable entry for SSCamSTRM-Device ",
  "1.1.0"  => "16.06.2018  attr hideDisplayName regarding to Forum #88667 ",
  "1.0.1"  => "14.06.2018  commandref revised ",
  "1.0.0"  => "14.06.2018  switch to longpoll refresh ",
  "0.4.0"  => "13.06.2018  new attribute \"noDetaillink\" (deleted in V1.0.0) ",
  "0.3.0"  => "12.06.2018  new attribute \"forcePageRefresh\" ",
  "0.2.0"  => "11.06.2018  check in with SSCam 5.0.0 ",
  "0.1.0"  => "10.06.2018  initial Version "
);

my %fupgrade = (                                                           # Funktionsupgrade in SSCamSTRM devices definiert vor SSCam Version 9.4.0
    1 => { of => "SSCam_ptzpanel",       nf => "FHEM::SSCam::ptzPanel"       },
    2 => { of => "SSCam_composegallery", nf => "FHEM::SSCam::composeGallery" },  
    3 => { of => "SSCam_StreamDev",      nf => "FHEM::SSCam::streamDev"      },      
);

my %hvattr = (                                                             # Hash zur Validierung von Attributen
    adoptSubset         => { master => 1, nomaster => 0 },
    autoRefresh         => { master => 1, nomaster => 1 },
    autoRefreshFW       => { master => 1, nomaster => 1 },
    disable             => { master => 1, nomaster => 1 },
    forcePageRefresh    => { master => 1, nomaster => 1 },
    genericStrmHtmlTag  => { master => 0, nomaster => 1 },
    htmlattr            => { master => 0, nomaster => 1 },
    htmlattrFTUI        => { master => 0, nomaster => 1 },
    hideAudio           => { master => 0, nomaster => 1 },
    hideButtons         => { master => 0, nomaster => 1 },
    hideDisplayName     => { master => 1, nomaster => 1 }, 
    hideDisplayNameFTUI => { master => 1, nomaster => 1 },
    noLink              => { master => 1, nomaster => 1 },
    popupWindowSize     => { master => 0, nomaster => 1 },
    popupStreamFW       => { master => 0, nomaster => 1 },
    popupStreamTo       => { master => 0, nomaster => 1 },
    ptzButtonSize       => { master => 0, nomaster => 1 }, 
    ptzButtonSizeFTUI   => { master => 0, nomaster => 1 },     
);

my %sdevs = ();                                                             # Hash der vorhandenen Streaming Devices

my $todef = 5;                                                              # Default Popup Zeit für set <> popupStream

################################################################
sub Initialize {
  my $hash = shift;

  my $fwd = join(",",devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized")); 
  my $sd  = "--reset--,".allStreamDevs();    
  
  $hash->{DefFn}              = \&Define;
  $hash->{SetFn}              = \&Set;
  $hash->{GetFn}              = \&Get;
  $hash->{AttrList}           = "adoptSubset:sortable-strict,$sd ".
                                "autoRefresh:selectnumbers,120,0.2,1800,0,log10 ".
                                "autoRefreshFW:$fwd ".
                                "disable:1,0 ". 
                                "forcePageRefresh:1,0 ".
                                "genericStrmHtmlTag ".
                                "htmlattr ".
                                "htmlattrFTUI ".
                                "hideAudio:1,0 ".
                                "hideButtons:1,0 ".
                                "hideDisplayName:1,0 ".
                                "hideDisplayNameFTUI:1,0 ".
                                "noLink:1,0 ".
                                "popupWindowSize ".
                                "popupStreamFW:$fwd ".
                                "popupStreamTo:OK,1,2,3,4,5,6,7,8,9,10,15,20,25,30,40,50,60 ".
                                "ptzButtonSize:selectnumbers,50,5,100,0,lin ".
                                "ptzButtonSizeFTUI:selectnumbers,50,5,200,0,lin ".
                                $readingFnAttributes;
  $hash->{RenameFn}           = \&Rename;
  $hash->{CopyFn}             = \&Copy;
  $hash->{FW_summaryFn}       = \&FwFn;
  $hash->{FW_detailFn}        = \&FwFn;
  $hash->{AttrFn}             = \&Attr;
  $hash->{FW_hideDisplayName} = 1;                     # Forum 88667
  # $hash->{FW_addDetailToSummary} = 1;
  # $hash->{FW_atPageEnd} = 1;                         # wenn 1 -> kein Longpoll ohne informid in HTML-Tag

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval' # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)
 
return; 
}

################################################################
#                             Define
################################################################
sub Define {
  my ($hash, $def) = @_;
  my ($name, $type, $link) = split("[ \t]+", $def, 3);
  
  if(!$link) {
    return "Usage: define <name> SSCamSTRM <arg>";
  }

  $link = migrateFunc($hash,$link);
  
  explodeLinkData ($hash, $link, 1);
  
  $hash->{HELPER}{MODMETAABSENT}   = 1 if($modMetaAbsent);                         # Modul Meta.pm nicht vorhanden
  
  # Versionsinformationen setzen
  setVersionInfo($hash);
  
  my @r;
  push @r, "adoptSubset:--reset--" if(IsModelMaster($hash));                       # Init für FTUI Subset wenn benutzt (Attr adoptSubset)
  push @r, "parentState:initialized";                                              # Init für "parentState" Forum: https://forum.fhem.de/index.php/topic,45671.msg985136.html#msg985136
  push @r, "state:initialized";                                                    # Init für "state" 
  
  setReadings($hash, \@r, 1);
  
return;
}

################################################################
#  im DEF hinterlegte Funktionen vor SSCam V9.4.0 migrieren
################################################################
sub migrateFunc {   
  my $hash = shift;
  my $link = shift;
  
  for my $k (keys %fupgrade) {
      $hash->{DEF} =~ s/$fupgrade{$k}{of}/$fupgrade{$k}{nf}/gx;
      $link        =~ s/$fupgrade{$k}{of}/$fupgrade{$k}{nf}/gx;
  }
  
return $link;
}

###############################################################
#                  SSCamSTRM Copy & Rename
#  passt die Deviceparameter bei kopierten / umbenennen an
###############################################################
sub Rename {
    my $new_name = shift;
    my $old_name = shift;
    my $hash     = $defs{$new_name} // return;
    
    $hash->{DEF} =~ s/\'$old_name\'/\'$new_name\'/xg;
    explodeLinkData ($hash, $hash->{DEF}, 1);

return;
}

sub Copy {
    my $old_name = shift;
    my $new_name = shift;
    my $hash     = $defs{$new_name} // return;
    
    $hash->{DEF} =~ s/\'$old_name\'/\'$new_name\'/xg;
    explodeLinkData ($hash, $hash->{DEF}, 1);

return;
}

################################################################
sub Set {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];    
  
  return if(IsDisabled($name) || $hash->{MODEL} =~ /ptzcontrol|snapgallery/x);
  
  my $setlist;
  
  if(!IsModelMaster($hash)) {
      $setlist = "Unknown argument $opt, choose one of ".
                 "popupStream "
                 ;
  } else {
      my $as  = "--reset--,".allStreamDevs();
      my $sd  = AttrVal($name, "adoptSubset", $as);
      $sd     =~ s/\s+/#/gx;      
      
      my $rsd = $as;
      $rsd    =~ s/#/ /g;                                   ## no critic 'regular expression' # Regular expression without "/x" flag nicht anwenden !!!
      push my @ado, "adoptList:$rsd";
      setReadings($hash, \@ado, 0);
      
      $setlist = "Unknown argument $opt, choose one of ".
                 "adopt:$sd "
                 ;  
  }
  
  if ($opt eq "popupStream") {
      my $txt = FHEM::SSCam::getClHash($hash);
      return $txt if($txt);
      
      # OK-Dialogbox oder Autoclose
      my $temp    = AttrVal($name, "popupStreamTo", $todef);
      my $to      = $prop // $temp;
      unless ($to =~ /^\d+$/x || lc($to) eq "ok") { $to = $todef; }
      $to         = ($to =~ /\d+/x) ? (1000 * $to) : $to;
      
      my $pd       = AttrVal($name, "popupStreamFW", "TYPE=FHEMWEB");
      my $htmlCode = $hash->{HELPER}{STREAM};
      
      if ($hash->{HELPER}{STREAMACTIVE}) {
          my $out = "<html>";
          $out .= $htmlCode;
          $out .= "</html>";
          
          Log3($name, 4, "$name - Stream to display: $htmlCode");
          Log3($name, 4, "$name - Stream display to webdevice: $pd");
          
          if($to =~ /\d+/x) {
              map {FW_directNotify("#FHEMWEB:$_", "FW_errmsg('$out', $to)", "")} devspec2array("$pd");  ## no critic 'void context';
          } else {
              map {FW_directNotify("#FHEMWEB:$_", "FW_okDialog('$out')", "")} devspec2array("$pd");     ## no critic 'void context';
          } 
      }
  
  } elsif ($opt eq "adopt") {
      shift @a; shift @a;
      $prop = join "#", @a;
      
      if($prop eq "--reset--") {
         CommandSet(undef, "$name reset"); 
         return;
      }
      
      my $strmd = $sdevs{"$prop"} // "";
      my $valid = ($strmd && $defs{$strmd} && $defs{$strmd}{TYPE} eq "SSCamSTRM");
      
      return qq{The command "$opt" needs a valid SSCamSTRM device as argument instead of "$strmd"} if(!$valid);
      
      # Übernahme der Readings
      my @r;
      delReadings($hash);
      for my $key (keys %{$defs{$strmd}{READINGS}}) {
          my $val = ReadingsVal($strmd, $key, "");
          next if(!$val);
          push @r, "$key:$val";        
      }
      
      # Übernahme Link-Parameter
      my $link = "{$defs{$strmd}{LINKFN}('$defs{$strmd}{LINKPARENT}','$defs{$strmd}{LINKNAME}','$defs{$strmd}{LINKMODEL}')}";
      
      explodeLinkData ($hash, $link, 0);
      
      push @r, "clientLink:$link";
      push @r, "parentCam:$hash->{LINKPARENT}";
      
      if(@r) {
          setReadings($hash, \@r, 1);
      }
      
      my $camname                     = $hash->{LINKPARENT};
      $defs{$camname}{HELPER}{INFORM} = $hash->{FUUID};
      
      InternalTimer(gettimeofday()+1.5, "FHEM::SSCam::roomRefresh", "$camname,0,0,0", 0);
      
  } elsif ($opt eq "reset") {
      delReadings($hash);
      explodeLinkData ($hash, $hash->{DEF}, 1);
      
      my @r;
      push @r, "parentState:initialized";
      push @r, "state:initialized";
      push @r, "parentCam:initialized";
      
      setReadings($hash, \@r, 1);
      
      my $camname                     = $hash->{LINKPARENT};
      $defs{$camname}{HELPER}{INFORM} = $hash->{FUUID};
      
      InternalTimer(gettimeofday()+1.5, "FHEM::SSCam::roomRefresh", "$camname,0,0,0", 0);
      
  } else {
      return "$setlist";
  }
  
return;  
}

###############################################################
#                  SSCamSTRM Get
###############################################################
sub Get {
 my ($hash, @a) = @_;
 return "\"get X\" needs at least an argument" if ( @a < 2 );
 my $name = shift @a;
 my $cmd  = shift @a;
       
 if ($cmd eq "html") {
     return streamAsHtml($hash);
 } 
 
 if ($cmd eq "ftui") {
     return streamAsHtml($hash,"ftui");
 }
 
return;
}

################################################################
#                               Attr
# $cmd can be "del" or "set"
# $name is device name
# aName and aVal are Attribute name and value
################################################################
sub Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash  = $defs{$name};
    my $model = $hash->{MODEL};
    
    my ($do,$val);
    
    if(defined $hvattr{$aName}) {
        if ($model eq "master" && !$hvattr{$aName}{master}) {            
            return qq{The attribute "$aName" is only valid if MODEL is not "$model" !};
        }
        
        if ($model ne "master" && !$hvattr{$aName}{nomaster}) {            
            return qq{The attribute "$aName" is only valid if MODEL is "master" !};
        }
    }
    
    if($aName eq "genericStrmHtmlTag" && $hash->{MODEL} ne "generic") {
        return qq{This attribute is only valid if MODEL is "generic" !};
    }
    
    if($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        $val = ($do == 1 ? "disabled" : "initialized");
    
        readingsSingleUpdate($hash, "state", $val, 1);
    }
    
    if($aName eq "adoptSubset") {
        if($cmd eq "set") {
            readingsSingleUpdate($hash, "adoptSubset", $aVal, 1);
        } else {
            readingsSingleUpdate($hash, "adoptSubset", "--reset--", 1);
        }
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/popupStreamTo/x) {
            unless ($aVal =~ /^\d+$/x || $aVal eq "OK") { return qq{The Value for $aName is not valid. Use only figures 0-9 or "OK" !}; }
        }        
    }

return;
}

#############################################################################################
#                                 FHEMWEB Summary  
#############################################################################################
sub FwFn {
  my ($FW_wname, $name, $room, $pageHash) = @_;               # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  
  RemoveInternalTimer($hash);
  
  $hash->{HELPER}{FW} = $FW_wname;
  my $clink           = ReadingsVal($name, "clientLink", "");
  
  explodeLinkData ($hash, $clink, 0);
  
  # Beispielsyntax: "{$hash->{LINKFN}('$hash->{LINKPARENT}','$hash->{LINKNAME}','$hash->{LINKMODEL}')}";
  
  my $ftui   = 0;
  my $linkfn = $hash->{LINKFN};
  my %pars   = ( linkparent => $hash->{LINKPARENT},
			     linkname   => $hash->{LINKNAME},
                 linkmodel  => $hash->{LINKMODEL},
                 omodel     => $hash->{MODEL},
                 oname      => $hash->{NAME},
				 ftui       => $ftui
               );
  
  no strict "refs";                                      ## no critic 'NoStrict' 
  my $html = eval{ &{$linkfn}(\%pars) } or do { return qq{Error in Streaming function definition of <html><a href=\"/fhem?detail=$name\">$name</a></html>} };
  use strict "refs";  
  
  my $ret = "";
  
  if(IsModelMaster($hash) && $clink) {
      my $alias = AttrVal($name, "alias", $name);                                                         # Linktext als Aliasname oder Devicename setzen
      my $lang  = AttrVal("global", "language", "EN");
      my $txt   = "is Streaming master of";
      $txt      = "ist Streaming Master von " if($lang eq "DE");
      my $dlink = "<a href=\"/fhem?detail=$name\">$alias</a> $txt ";
      $dlink    = "$alias $txt " if(AttrVal($name, "noLink", 0));                                         # keine Links im Stream-Dev generieren
      $ret     .= "<span align=\"center\">$dlink </span>"   if(!AttrVal($name,"hideDisplayName",0));
  }
  
  if(IsDisabled($name)) {
      if(AttrVal($name,"hideDisplayName",0)) {
          $ret .= "Stream-device <a href=\"/fhem?detail=$name\">$name</a> is disabled";
      } else {
          $ret .= "<html>Stream-device is disabled</html>";
      } 
      
  } else {
      $ret .= $html;
      $ret .= sDevsWidget($name) if(IsModelMaster($hash)); 
  }
   
  my $al = AttrVal($name, "autoRefresh", 0);                                                             # Autorefresh nur des aufrufenden FHEMWEB-Devices
  if($al) {  
      InternalTimer(gettimeofday()+$al, "FHEM::SSCamSTRM::webRefresh", $hash, 0);
      Log3($name, 5, "$name - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  }
  
  undef $html;

return $ret;
}

#############################################################################################
#            Bestandteile des DEF (oder Link) auflösen 
#      $link = aufzulösender String
#      $def  = 1 -> es ist ein Shash->{DEF} Inhalt, 0 -> eine andere Quelle 
#############################################################################################
sub explodeLinkData {                    
  my $hash = shift;
  my $link = shift;
  my $def  = shift;
  
  return if(!$link);
  
  my ($fn,$arg) = split("[()]",$link);
  
  $arg =~ s/'//xg;
  $fn  =~ s/{//xg;
  
  if($def) {
      ($hash->{PARENT},$hash->{LINKNAME},$hash->{MODEL}) = split(",",$arg);
      $hash->{LINKMODEL}  = $hash->{MODEL};
      $hash->{LINKPARENT} = $hash->{PARENT};
  } else {
      ($hash->{LINKPARENT},$hash->{LINKNAME},$hash->{LINKMODEL}) = split(",",$arg);     
  }
  
  $hash->{LINKFN} = $fn;
  
return;
}

#############################################################################################
#                       Ist das MODEL "master" ?
#############################################################################################
sub IsModelMaster {                                                          
  my $hash = shift;

  my $mm = $hash->{MODEL} eq "master" ? 1 : 0;
  
return $mm;
}

#############################################################################################
#                                     Seitenrefresh 
#        festgelegt durch SSCamSTRM-Attribut "autoRefresh" und "autoRefreshFW"
#############################################################################################
sub webRefresh { 
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $rd = AttrVal($name, "autoRefreshFW", $hash->{HELPER}{FW});
  { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } $rd }   ## no critic 'void context';
  
  my $al = AttrVal($name, "autoRefresh", 0);
  if($al) {      
      InternalTimer(gettimeofday()+$al, "FHEM::SSCamSTRM::webRefresh", $hash, 0);
      Log3($name, 5, "$name - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  } else {
      RemoveInternalTimer($hash);
  }
  
return;
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub setVersionInfo {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
      # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                                     # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SSCamSTRM}{META}}
      if($modules{$type}{META}{x_version}) {                                                       # {x_version} ( nur gesetzt wenn $Id: 49_SSCamSTRM.pm 22329 2020-07-02 17:16:52Z DS_Starter $ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                          # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 49_SSCamSTRM.pm 22329 2020-07-02 17:16:52Z DS_Starter $ im Kopf komplett! vorhanden )
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                    ## no critic 'VERSION'                                         
      }
  } else {
      # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

################################################################
#    Grafik als HTML zurück liefern    (z.B. für Widget)
################################################################
sub streamAsHtml { 
  my $hash = shift;
  my $ftui = shift;
  my $name = $hash->{NAME};
  
  if($ftui && $ftui eq "ftui") {
      $ftui = 1;
  } else {
      $ftui = 0; 
  }
  
  my $clink = ReadingsVal($name, "clientLink", "");
  
  explodeLinkData ($hash, $clink, 0);
    
  my $linkfn = $hash->{LINKFN};
  my %pars   = ( linkparent => $hash->{LINKPARENT},
			     linkname   => $hash->{LINKNAME},
                 linkmodel  => $hash->{LINKMODEL},
                 omodel     => $hash->{MODEL},
                 oname      => $hash->{NAME},
				 ftui       => $ftui
               );
  
  no strict "refs";                                      ## no critic 'NoStrict' 
  my $html = eval{ &{$linkfn}(\%pars) } or do { return qq{Error in Streaming function definition of <html><a href=\"/fhem?detail=$name\">$name</a></html>} };
  use strict "refs"; 
  
  my $ret = "<html>";
  if(IsDisabled($name)) {  
      if(AttrVal($name,"hideDisplayName",0)) {
          $ret .= "Stream-device <a href=\"/fhem?detail=$name\">$name</a> is disabled";
      } else {
          $ret .= "Stream-device is disabled";
      }

  } else {
      $ret .= $html;     
  }
  
  $ret .= "</html>";
  
  undef $html;
  
return $ret;
}

################################################################
#                    delete Readings
#        $rd = angegebenes Reading löschen
################################################################
sub delReadings {
  my $hash = shift;
  my $rd   = shift;
  my $name = $hash->{NAME};
  
  my $bl   = "state|parentState|adoptSubset";                              # Blacklist
   
  if($rd) {                                                                # angegebenes Reading löschen wenn nicht im providerLevel enthalten
      readingsDelete($hash, $rd) if($rd !~ /$bl/x);
      return;
  } 

  for my $key (keys %{$hash->{READINGS}}) {
      readingsDelete($hash, $key) if($key !~ /$bl/x);
  }

return;
}

################################################################
#                    set Readings
#   $rref  = Referenz zum Array der zu setzenen Reading
#            (Aufbau: <Reading>:<Wert>)
#   $event = 1 wenn Event generiert werden soll
################################################################
sub setReadings {
  my $hash  = shift;
  my $rref  = shift;
  my $event = shift;
  
  my $name  = $hash->{NAME};
  
  readingsBeginUpdate($hash);
  
  for my $elem (@$rref) {
      my ($rn,$rval) = split ":", $elem, 2;
      readingsBulkUpdate($hash, $rn, $rval);      
  }

  readingsEndUpdate($hash, $event);

return;
}

################################################################
#  liefert String aller Streamingdevices außer MODEL = master
#  und füllt Hash %sdevs{Alias} = Devicename zu Auflösung
#
#  (es wird Alias (wenn gesetzt) oder Devicename verwendet,
#   Leerzeichen werden durch "#" ersetzt)
################################################################
sub allStreamDevs {

  my $sd = "";
  undef %sdevs;
  
  my @strmdevs = devspec2array("TYPE=SSCamSTRM:FILTER=MODEL!=master");            # Liste Streaming devices außer MODEL = master
  for my $da (@strmdevs) {
      next if(!$defs{$da});
      my $alias      = AttrVal($da, "alias", $da); 
      $alias         =~ s/\s+/#/gx;
      $sdevs{$alias} = "$da";        
  }
  
  for my $a (sort keys %sdevs) {
      $sd .= "," if($sd);
      $sd .= $a;
  }
  
  for my $d (@strmdevs) {                                                        # Devicenamen zusätzlich als Schlüssel speichern damit set <> adopt ohne Widget funktioniert
      next if(!$defs{$d});
      $sdevs{$d} = "$d";        
  }

return $sd;
}

################################################################
#   Streaming Devices Drop-Down Widget zur Auswahl 
#   in einem Master Streaming Device
################################################################
sub sDevsWidget {
  my $name = shift;
  
  my $Adopts;
  my $ret        = "";
  my $cmdAdopt   = "adopt";
  my $as         = "--reset--,".allStreamDevs();
  my $valAdopts  = AttrVal($name, "adoptSubset", $as);
  $valAdopts     =~ s/\s+/#/gx;
  
  for my $fn (sort keys %{$data{webCmdFn}}) {
      next if($data{webCmdFn}{$fn} ne "FW_widgetFallbackFn");
      no strict "refs";                                                                    ## no critic 'NoStrict'  
      $Adopts = &{$data{webCmdFn}{$fn}}($FW_wname,$name,"",$cmdAdopt,$valAdopts);
      use strict "refs";
      last if(defined($Adopts));
  }
  
  if($Adopts) {
      $Adopts =~ s,^<td[^>]*>(.*)</td>$,$1,x;
  } else {
      $Adopts = FW_pH "cmd.$name=set $name $cmdAdopt", $cmdAdopt, 0, "", 1, 1;
  }
       
  ## Tabellenerstellung
  $ret .= "<style>.defsize { font-size:16px; } </style>";
  $ret .= '<table class="rc_body defsize">';
  
  $ret .= "<tr>";
  $ret .= "<td>Streaming Device: </td><td>$Adopts</td>";  
  $ret .= "</tr>"; 

  $ret .= "</table>"; 

return $ret;
}

1;

=pod
=item summary    Definition of a streaming device by the SSCam module
=item summary_DE Erstellung eines Streaming-Device durch das SSCam-Modul
=begin html

<a name="SSCamSTRM"></a>
<h3>SSCamSTRM</h3>
<br>
  <ul>
  The module SSCamSTRM is a special device module synchronized to the SSCam module. It is used for definition of
  Streaming-Devices. <br>
  Dependend of the Streaming-Device state, different buttons are provided to start actions: <br><br>
  
    <ul>   
      <table>  
      <colgroup> <col width=25%> <col width=75%> </colgroup>
        <tr><td> Switch off      </td><td>- stops a running playback </td></tr>
        <tr><td> Refresh         </td><td>- refresh a view (no page reload) </td></tr>
        <tr><td> Restart         </td><td>- restart a running content (e.g. a HLS-Stream) </td></tr>
        <tr><td> MJPEG           </td><td>- starts a MJPEG Livestream </td></tr>
        <tr><td> HLS             </td><td>- starts HLS (HTTP Live Stream) </td></tr>
        <tr><td> Last Record     </td><td>- playback the last recording as iFrame </td></tr>
        <tr><td> Last Rec H.264  </td><td>- playback the last recording if available as H.264 </td></tr>
        <tr><td> Last Rec MJPEG  </td><td>- playback the last recording if available as MJPEG </td></tr>
        <tr><td> Last SNAP       </td><td>- show the last snapshot </td></tr>
        <tr><td> Start Recording </td><td>- starts an endless recording </td></tr>
        <tr><td> Stop Recording  </td><td>- stopps the recording </td></tr>
        <tr><td> Take Snapshot   </td><td>- take a snapshot </td></tr>
      </table>
     </ul>     
     <br>
   
  <b>Integration into FHEM TabletUI: </b> <br><br>
  There is a widget provided for integration of SSCam-Streaming devices into FTUI. For further information please be informed by the
  (german) FHEM Wiki article: <br>
   <a href="https://wiki.fhem.de/wiki/FTUI_Widget_f%C3%BCr_SSCam_Streaming_Devices_(SSCamSTRM)">FTUI Widget für SSCam Streaming Devices (SSCamSTRM)</a>.
  <br><br>
  </ul>

<ul>
  <a name="SSCamSTRMdefine"></a>
  <b>Define</b>
  <br><br>
  
  <ul>
    A SSCam Streaming-device is defined by the SSCam command: <br><br>
    
    <ul>
      set &lt;name&gt; createStreamDev  &lt;Device Typ&gt; <br><br>
    </ul>
    
    Please refer to SSCam <a href="#SSCamcreateStreamDev">"createStreamDev"</a> command.  
    <br><br>
  </ul>

  <a name="SSCamSTRMset"></a>
  <b>Set</b> 
  <ul>
  
  <ul>
  <li><b>popupStream</b>   &nbsp;&nbsp;&nbsp;&nbsp;(only valid if MODEL != master)<br>
  
  The current streaming content is depicted in a popup window. By setting attribute "popupWindowSize" the 
  size of display can be adjusted. The attribute "popupStreamTo" determines the type of the popup window.
  If "OK" is set, an OK-dialog window will be opened. A specified number in seconds closes the popup window after this 
  time automatically (default 5 seconds). <br>
  Optionally you can append "OK" or &lt;seconds&gt; directly to override the adjustment by attribute "popupStreamTo".
  </li>
  </ul>
  <br>
  
  <ul>
  <li><b>adopt &lt;Streaming device&gt; </b>   &nbsp;&nbsp;&nbsp;&nbsp;(only valid if MODEL = master)<br>
  
  A Streaming Device of type <b>master</b> adopts the content of another defined Streaming Device.
  </li>
  </ul>
  <br>
  
  </ul>
  <br>
  
  <a name="SSCamSTRMget"></a>
  <b>Get</b> 
  <ul>
    <br>
    <ul>
      <li><b> get &lt;name&gt; html </b> </li>  
      The stream object (camera live view, snapshots or replay) is fetched as HTML-code and depicted. 
    </ul>
    <br>
    
    <br>
  </ul>
  
  <a name="SSCamSTRMattr"></a>
  <b>Attributes</b>
  <br><br>
  
  <ul>
  <ul>
  
    <a name="adoptSubset"></a>
    <li><b>adoptSubset</b> &nbsp;&nbsp;&nbsp;&nbsp;(only valid for MODEL "master") <br>
      In a Streaming <b>master</b> Device a subset of all defined Streaming Devices is selected and used for 
      the <b>adopt</b> command is provided. <br>
      For control in the FTUI, the selection is also stored in the Reading of the same name.
    </li>
    <br>

    <a name="autoRefresh"></a>
    <li><b>autoRefresh</b><br>
      If set, active browser pages of the FHEMWEB-Device which has called the SSCamSTRM-Device, are new reloaded after  
      the specified time (seconds). Browser pages of a particular FHEMWEB-Device to be refreshed can be specified by 
      attribute "autoRefreshFW" instead.
      This may stabilize the video playback in some cases.
    </li>
    <br>
    
    <a name="autoRefreshFW"></a>
    <li><b>autoRefreshFW</b><br>
      If "autoRefresh" is activated, you can specify a particular FHEMWEB-Device whose active browser pages are refreshed 
      periodically.
    </li>
    <br>
    
    <a name="disable"></a>
    <li><b>disable</b><br>
      Deactivates the device.
    </li>
    <br>
    
    <a name="forcePageRefresh"></a>
    <li><b>forcePageRefresh</b><br>
      The attribute is evaluated by SSCam. <br>
      If set, a reload of all browser pages with active FHEMWEB connections will be enforced when particular camera operations 
      were finished. 
      This may stabilize the video playback in some cases.       
    </li>
    <br>
    
  <a name="genericStrmHtmlTag"></a>
  <li><b>genericStrmHtmlTag</b> &nbsp;&nbsp;&nbsp;&nbsp;(only valid for MODEL "generic") <br>
  This attribute contains HTML-Tags for video-specification in a Streaming-Device of type "generic". 
  <br><br> 
  
    <ul>
      <b>Examples:</b>
      <pre>
attr &lt;name&gt; genericStrmHtmlTag &lt;video $HTMLATTR controls autoplay&gt;
                                 &lt;source src='http://192.168.2.10:32000/$NAME.m3u8' type='application/x-mpegURL'&gt;
                               &lt;/video&gt; 
                               
attr &lt;name&gt; genericStrmHtmlTag &lt;img $HTMLATTR 
                                 src="http://192.168.2.10:32774"
                                 onClick="FW_okDialog('&lt;img src=http://192.168.2.10:32774 $PWS&gt')"
                               &gt  
      </pre>
      The variables $HTMLATTR, $NAME and $PWS are placeholders and absorb the attribute "htmlattr" (if set), the SSCam-Devicename 
      respectively the value of attribute "popupWindowSize" in streaming-device, which specify the windowsize of a popup window.
    </ul>
    <br><br>
    </li>
    
    <a name="hideAudio"></a>
    <li><b>hideAudio</b><br>
      Hide the control block for audio playback in the footer.    
    </li>
    <br>
    
    <a name="hideButtons"></a>
    <li><b>hideButtons</b><br>
      Hide the buttons in the footer. It has no impact for streaming devices of type "switched".    
    </li>
    <br>
    
    <a name="hideDisplayName"></a>
    <li><b>hideDisplayName</b><br>
      Hide the device/alias name (link to detail view).     
    </li>
    <br>
    
    <a name="hideDisplayNameFTUI"></a>
    <li><b>hideDisplayNameFTUI</b><br>
      Hide the device/alias name (link to detail view) in FHEM TabletUI.     
    </li>
    <br>
    
    <a name="htmlattr"></a>
    <li><b>htmlattr</b><br>
      Additional HTML tags to manipulate the streaming device. 
      <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; htmlattr width="580" height="460" <br>
      </ul>
    </li>
    <br>
    
    <a name="htmlattrFTUI"></a>
    <li><b>htmlattrFTUI</b><br>
      Additional HTML tags to manipulate the streaming device in TabletUI. 
      <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; htmlattr width="580" height="460" <br>
      </ul>
    </li>
    <br>
    
    <a name="noLink"></a>
    <li><b>noLink</b><br>
      The device name or alias doesn't contain a link to the detail device view. 
    </li>
    <br>
    
    <a name="popupStreamFW"></a>
    <li><b>popupStreamFW</b><br>
      You can specify a particular FHEMWEB device whose active browser pages should open a popup window by the 
      "set &lt;name&gt; popupStream" command (default: all active FHEMWEB devices).
    </li>
    <br>
    
    <a name="popupStreamTo"></a>
    <li><b>popupStreamTo [OK | &lt;seconds&gt;]</b><br>
      The attribute "popupStreamTo" determines the type of the popup window which is opend by set-function "popupStream".
      If "OK" is set, an OK-dialog window will be opened. A specified number in seconds closes the popup window after this 
      time automatically (default 5 seconds)..
      <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; popupStreamTo 10  <br>
      </ul>
      <br>
    </li>
    
    <a name="popupWindowSize"></a>
    <li><b>popupWindowSize</b><br>
      If the content of playback (Videostream or Snapshot gallery) is suitable, by clicking the content a popup window will 
      appear. 
      The size of display can be setup by this attribute. 
      It is also valid for the get-function "popupStream".
      <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; popupWindowSize width="600" height="425"  <br>
      </ul>
    </li>
    <br>
    
    <a name="ptzButtonSize"></a>
    <li><b>ptzButtonSize</b><br>
      Specifies the PTZ-panel button size (in %).
    </li>
    <br>
    
    <a name="ptzButtonSizeFTUI"></a>
    <li><b>ptzButtonSizeFTUI</b><br>
      Specifies the PTZ-panel button size used in a Tablet UI (in %).
    </li>
  
  </ul>
  </ul>
  
</ul>

=end html
=begin html_DE

<a name="SSCamSTRM"></a>
<h3>SSCamSTRM</h3>
<ul>
  <br>
  Das Modul SSCamSTRM ist ein mit SSCam abgestimmtes Gerätemodul zur Definition von Streaming-Devices. <br>
  Abhängig vom Zustand des Streaming-Devices werden zum Start von Aktionen unterschiedliche Drucktasten angeboten: <br><br>
    <ul>   
      <table>  
      <colgroup> <col width=25%> <col width=75%> </colgroup>
        <tr><td> Switch off      </td><td>- stoppt eine laufende Wiedergabe </td></tr>
        <tr><td> Refresh         </td><td>- auffrischen einer Ansicht (kein Browser Seiten-Reload) </td></tr>
        <tr><td> Restart         </td><td>- neu starten eines laufenden Contents (z.B. eines HLS-Streams) </td></tr>
        <tr><td> MJPEG           </td><td>- Startet MJPEG Livestream </td></tr>
        <tr><td> HLS             </td><td>- Startet HLS (HTTP Live Stream) </td></tr>
        <tr><td> Last Record     </td><td>- spielt die letzte Aufnahme als iFrame </td></tr>
        <tr><td> Last Rec H.264  </td><td>- spielt die letzte Aufnahme wenn als H.264 vorliegend </td></tr>
        <tr><td> Last Rec MJPEG  </td><td>- spielt die letzte Aufnahme wenn als MJPEG vorliegend </td></tr>
        <tr><td> Last SNAP       </td><td>- zeigt den letzten Snapshot </td></tr>
        <tr><td> Start Recording </td><td>- startet eine Endlosaufnahme </td></tr>
        <tr><td> Stop Recording  </td><td>- stoppt eine Aufnahme </td></tr>
        <tr><td> Take Snapshot   </td><td>- löst einen Schnappschuß aus </td></tr>
      </table>
     </ul>     
     <br>
   
    <b>Integration in FHEM TabletUI: </b> <br><br>
    Zur Integration von SSCam Streaming Devices (Typ SSCamSTRM) wird ein Widget bereitgestellt. 
    Für weitere Information dazu bitte den Artikel im Wiki durchlesen: <br>
    <a href="https://wiki.fhem.de/wiki/FTUI_Widget_f%C3%BCr_SSCam_Streaming_Devices_(SSCamSTRM)">FTUI Widget für SSCam Streaming Devices (SSCamSTRM)</a>.
    <br><br><br>
</ul>

<ul>
  <a name="SSCamSTRMdefine"></a>
  <b>Define</b>
  <br><br>
  
  <ul>
    Ein SSCam Streaming-Device wird durch den SSCam Befehl <br><br>
    
    <ul>
      set &lt;name&gt; createStreamDev  &lt;Device Typ&gt; <br><br>
    </ul>
    
    erstellt. Siehe auch die Beschreibung zum SSCam <a href="#SSCamcreateStreamDev">"createStreamDev"</a> Befehl.  
    <br><br>
  </ul>

  <a name="SSCamSTRMset"></a>
  <b>Set</b> 
  <ul>
  
  <ul>
  <li><b>popupStream [OK | &lt;Sekunden&gt;]</b>   &nbsp;&nbsp;&nbsp;&nbsp;(nur wenn MODEL != master)<br>
  
  Der aktuelle Streaminhalt wird in einem Popup-Fenster dargestellt. Mit dem Attribut "popupWindowSize" kann die 
  Darstellungsgröße eingestellt werden. Das Attribut "popupStreamTo" legt die Art des Popup-Fensters fest.
  Ist "OK" eingestellt, öffnet sich ein OK-Dialogfenster. Die angegebene Zahl in Sekunden schließt das Fenster nach dieser 
  Zeit automatisch (default 5 Sekunden). <br>
  Durch die optionalen Angabe von "OK" oder &lt;Sekunden&gt; kann die Einstellung des Attributes "popupStreamTo" übersteuert 
  werden.
  </li>
  </ul>
  <br>
  
  <ul>
  <li><b>adopt &lt;Streaming Device&gt; </b>   &nbsp;&nbsp;&nbsp;&nbsp;(nur wenn MODEL = master)<br>
  
  Ein Streaming Device vom Type <b>master</b> übernimmt (adoptiert) den Content eines anderen definierten Streaming Devices.
  </li>
  </ul>
  <br>
  
  </ul>
  <br>
  
  <a name="SSCamSTRMget"></a>
  <b>Get</b> 
  <ul>
    <br>
    <ul>
      <li><b> get &lt;name&gt; html </b> </li>  
      Das eingebundene Streamobjekt (Kamera Live View, Schnappschüsse oder Wiedergabe einer Aufnahme) wird als HTML-code 
      abgerufen und dargestellt. 
    </ul>
    <br>
    
    <br>
  </ul>

  <a name="SSCamSTRMattr"></a>
  <b>Attribute</b>
  <br><br>
  
  <ul>
  <ul>
  
    <a name="adoptSubset"></a>
    <li><b>adoptSubset</b> &nbsp;&nbsp;&nbsp;&nbsp;(nur für MODEL "master") <br>
      In einem Streaming <b>master</b> Device wird eine Teilmenge aller definierten Streaming Devices ausgewählt und für 
      das  <b>adopt</b> Kommando bereitgestellt. <br>
      Für die Steuerung im FTUI wird die Auswahl ebenfalls im gleichnamigen Reading gespeichert.
    </li>
    <br>
  
    <a name="autoRefresh"></a>
    <li><b>autoRefresh</b><br>
      Wenn gesetzt, werden aktive Browserseiten des FHEMWEB-Devices welches das SSCamSTRM-Device aufgerufen hat, nach der 
      eingestellten Zeit (Sekunden) neu geladen. Sollen statt dessen Browserseiten eines bestimmten FHEMWEB-Devices neu 
      geladen werden, kann dieses Device mit dem Attribut "autoRefreshFW" festgelegt werden.
      Dies kann in manchen Fällen die Wiedergabe innerhalb einer Anwendung stabilisieren.
    </li>
    <br>
    
    <a name="autoRefreshFW"></a>
    <li><b>autoRefreshFW</b><br>
      Ist "autoRefresh" aktiviert, kann mit diesem Attribut das FHEMWEB-Device bestimmt werden dessen aktive Browserseiten
      regelmäßig neu geladen werden sollen.
    </li>
    <br>
  
    <a name="disable"></a>
    <li><b>disable</b><br>
      Aktiviert/deaktiviert das Device.
    </li>
    <br>
    
    <a name="forcePageRefresh"></a>
    <li><b>forcePageRefresh</b><br>
      Das Attribut wird durch SSCam ausgewertet. <br>
      Wenn gesetzt, wird ein Reload aller Browserseiten mit aktiven FHEMWEB-Verbindungen nach dem Abschluß bestimmter 
      SSCam-Befehle erzwungen. 
      Dies kann in manchen Fällen die Wiedergabe innerhalb einer Anwendung stabilisieren.     
    </li>
    <br>
    
  <a name="genericStrmHtmlTag"></a>  
  <li><b>genericStrmHtmlTag</b> &nbsp;&nbsp;&nbsp;&nbsp;(nur für MODEL "generic")<br>
  Das Attribut enthält HTML-Tags zur Video-Spezifikation in einem Streaming-Device von Typ "generic". 
  <br><br> 
  
    <ul>
      <b>Beispiele:</b>
      <pre>
attr &lt;name&gt; genericStrmHtmlTag &lt;video $HTMLATTR controls autoplay&gt;
                                 &lt;source src='http://192.168.2.10:32000/$NAME.m3u8' type='application/x-mpegURL'&gt;
                               &lt;/video&gt;
                               
attr &lt;name&gt; genericStrmHtmlTag &lt;img $HTMLATTR 
                                 src="http://192.168.2.10:32774"
                                 onClick="FW_okDialog('&lt;img src=http://192.168.2.10:32774 $PWS &gt')"
                               &gt                              
      </pre>
      Die Variablen $HTMLATTR, $NAME und $PWS sind Platzhalter und übernehmen ein gesetztes Attribut "htmlattr", den SSCam-
      Devicenamen bzw. das Attribut "popupWindowSize" im Streaming-Device, welches die Größe eines Popup-Windows festlegt.    
    </ul>
    <br><br>
    </li> 
    
    <a name="hideAudio"></a>
    <li><b>hideAudio</b><br>
      Verbirgt die Steuerungsbereich für die Audiowiedergabe in der Fußzeile.    
    </li>
    <br>  

    <a name="hideButtons"></a>
    <li><b>hideButtons</b><br>
      Verbirgt die Drucktasten in der Fußzeile. Dieses Attribut hat keinen Einfluß bei Streaming-Devices vom Typ "switched".    
    </li>
    <br>    
    
    <a name="hideDisplayName"></a>
    <li><b>hideDisplayName</b><br>
      Verbirgt den Device/Alias-Namen (Link zur Detailansicht).    
    </li>
    <br>
    
    <a name="hideDisplayNameFTUI"></a>
    <li><b>hideDisplayNameFTUI</b><br>
      Verbirgt den Device/Alias-Namen (Link zur Detailansicht) im TabletUI.    
    </li>
    <br>
    
    <a name="htmlattr"></a>
    <li><b>htmlattr</b><br>
      Zusätzliche HTML Tags zur Darstellung im Streaming Device. 
      <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; htmlattr width="580" height="460"  <br>
      </ul>
    </li>
    <br>
    
    <a name="htmlattrFTUI"></a>
    <li><b>htmlattrFTUI</b><br>
      Zusätzliche HTML Tags zur Darstellung des Streaming Device im TabletUI. 
      <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; htmlattr width="580" height="460"  <br>
      </ul>
    </li>
    <br>
    
    <a name="noLink"></a>
    <li><b>noLink</b><br>
      Der Devicename oder Alias enthält keinen Link zur Detailansicht. 
    </li>
    <br>
    
    <a name="popupStreamFW"></a>
    <li><b>popupStreamFW</b><br>
      Es kann mit diesem Attribut das FHEMWEB-Device bestimmt werden, auf dessen Browserseiten sich Popup-Fenster mit 
      "set &lt;name&gt; popupStream" öffnen sollen (default: alle aktiven FHEMWEB-Devices).
    </li>
    <br>
    
    <a name="popupStreamTo"></a>
    <li><b>popupStreamTo [OK | &lt;Sekunden&gt;]</b><br>
      Das Attribut "popupStreamTo" legt die Art des Popup-Fensters fest welches mit der set-Funktion "popupStream" geöffnet wird.
      Ist "OK" eingestellt, öffnet sich ein OK-Dialogfenster. Die angegebene Zahl in Sekunden schließt das Fenster nach dieser 
      Zeit automatisch (default 5 Sekunden).
      <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; popupStreamTo 10  <br>
      </ul>
      <br>
    </li>
    
    <a name="popupWindowSize"></a>
    <li><b>popupWindowSize</b><br>
      Bei geeigneten Wiedergabeinhalten (Videostream oder Schnappschußgalerie) öffnet ein Klick auf den Bildinhalt ein 
      Popup-Fenster mit diesem Inhalt. Die Darstellungsgröße kann mit diesem Attribut eingestellt werden. 
      Das Attribut gilt ebenfalls für die set-Funktion "popupStream".
      <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; popupWindowSize width="600" height="425"  <br>
      </ul>
    </li>
    <br>
    
    <a name="ptzButtonSize"></a>
    <li><b>ptzButtonSize</b><br>
      Legt die Größe der Drucktasten des PTZ Paneels fest (in %).
    </li>
    <br>
    
    <a name="ptzButtonSizeFTUI"></a>
    <li><b>ptzButtonSizeFTUI</b><br>
      Legt die Größe der Drucktasten des PTZ Paneels in einem Tablet UI fest (in %).
    </li>

  </ul>
  </ul>
  
</ul>

=end html_DE

=for :application/json;q=META.json 49_SSCamSTRM.pm
{
  "abstract": "Definition of a streaming device by the SSCam module",
  "x_lang": {
    "de": {
      "abstract": "Erstellung eines Streaming-Device durch das SSCam-Modul"
    }
  },
  "keywords": [
    "camera",
    "streaming",
    "PTZ",
    "Synology Surveillance Station",
    "MJPEG",
    "HLS",
    "RTSP"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014       
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station",
      "title": "SSCAM - Steuerung von Kameras in Synology Surveillance Station"
    }
  }
}
=end :application/json;q=META.json

=cut
