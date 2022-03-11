########################################################################################################################
# $Id: API.pm 22832 2020-09-23 15:04:42Z DS_Starter $
#########################################################################################################################
#       API.pm
#
#       (c) 2020 - 2022 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module provides Synology API information.
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

package FHEM::SynoModules::API;                                          

use strict;           
use warnings;
use utf8;
use Carp qw(croak carp);

use version; our $VERSION = version->declare('1.3.0');

# use lib qw(/opt/fhem/FHEM  /opt/fhem/lib);                              # für Syntaxcheck mit: perl -c /opt/fhem/lib/FHEM/SynoModules/API.pm

use Exporter ('import');
our @EXPORT_OK   = qw(apistatic);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

my %hspecs = (                                                           # Hash der verfügbaren API-Specs
  surveillance => {fn => \&_staticSurveillance },
  chat         => {fn => \&_staticChat         },
  calendar     => {fn => \&_staticCalendar     },
  file         => {fn => \&_staticFile         },
);

########################################################################
#      Liefert die statischen Informationen der angefoderten API
#      $pec = surveillance | chat
########################################################################
sub apistatic {
  my $spec = shift // carp "got no API specification !" && return;
   
  if($hspecs{$spec} && defined &{$hspecs{$spec}{fn}}) {
      my $h = q{};
      $h    = &{$hspecs{$spec}{fn}};
      
      $h->{INFO}{PATH} = "query.cgi";
      $h->{INFO}{VER}  = 1;
      
      return $h;
  }

  carp qq{API specification "$spec" not found !};

return;
}


########################################################################
#      Liefert die statischen Informationen der Surveillance API
#   mk : 1 - API Key muss vorhanden sein
#        0 - API Key kann vorhanden sein
########################################################################
sub _staticSurveillance {
  my %hapi = (                                                                    
      INFO      => { NAME => "SYNO.API.Info",                              mk => 1 },      # Info-Seite für alle API's, einzige statische Seite !    
      AUTH      => { NAME => "SYNO.API.Auth",                              mk => 1 },      # API used to perform session login and logout
      SVSINFO   => { NAME => "SYNO.SurveillanceStation.Info",              mk => 1 },
      EVENT     => { NAME => "SYNO.SurveillanceStation.Event",             mk => 1 },
      EXTREC    => { NAME => "SYNO.SurveillanceStation.ExternalRecording", mk => 1 },
      EXTEVT    => { NAME => "SYNO.SurveillanceStation.ExternalEvent",     mk => 1 },
      CAM       => { NAME => "SYNO.SurveillanceStation.Camera",            mk => 1 },      # stark geändert ab API v2.8
      SNAPSHOT  => { NAME => "SYNO.SurveillanceStation.SnapShot",          mk => 1 },      # This API provides functions on snapshot, including taking, editing and deleting snapshots.
      PTZ       => { NAME => "SYNO.SurveillanceStation.PTZ",               mk => 1 },
      PRESET    => { NAME => "SYNO.SurveillanceStation.PTZ.Preset",        mk => 1 },
      CAMEVENT  => { NAME => "SYNO.SurveillanceStation.Camera.Event",      mk => 1 },
      VIDEOSTM  => { NAME => "SYNO.SurveillanceStation.VideoStreaming",    mk => 1 },      # verwendet in Response von "SYNO.SurveillanceStation.Camera: GetLiveViewPath" -> StreamKey-Methode
      STM       => { NAME => "SYNO.SurveillanceStation.Stream",            mk => 1 },      # Beschreibung ist falsch und entspricht "SYNO.SurveillanceStation.Streaming" auch noch ab v2.8
      HMODE     => { NAME => "SYNO.SurveillanceStation.HomeMode",          mk => 0 },
      LOG       => { NAME => "SYNO.SurveillanceStation.Log",               mk => 1 },
      AUDIOSTM  => { NAME => "SYNO.SurveillanceStation.AudioStream",       mk => 0 },      # Audiostream mit SID, removed in API v2.8 (noch undokumentiert verfügbar vor SVS 9.0.0 / API V 3.11)
      VIDEOSTMS => { NAME => "SYNO.SurveillanceStation.VideoStream",       mk => 0 },      # Videostream mit SID, removed in API v2.8 (noch undokumentiert verfügbar vor SVS 9.0.0 / API V 3.11)
      REC       => { NAME => "SYNO.SurveillanceStation.Recording",         mk => 1 },      # This API provides method to query recording information.
);

return \%hapi;
}

########################################################################
#      Liefert die statischen Informationen der Chat API
########################################################################
sub _staticChat {
  my %hapi = (                                                    
      INFO     => { NAME => "SYNO.API.Info",      mk => 1 }, 
      EXTERNAL => { NAME => "SYNO.Chat.External", mk => 1 },
  );

return \%hapi;
}

########################################################################
#      Liefert die statischen Informationen der Calendar API
########################################################################
sub _staticCalendar {
  my %hapi = (                                                    
      INFO   => { NAME => "SYNO.API.Info",    mk => 1 },                                          
      AUTH   => { NAME => "SYNO.API.Auth",    mk => 1 },     # API used to perform session login and logout  
      CAL    => { NAME => "SYNO.Cal.Cal",     mk => 1 },     # API to manipulate calendar
      EVENT  => { NAME => "SYNO.Cal.Event",   mk => 1 },     # Provide methods to manipulate events in the specific calendar
      SHARE  => { NAME => "SYNO.Cal.Sharing", mk => 1 },     # Get/set sharing setting of calendar
      TODO   => { NAME => "SYNO.Cal.Todo",    mk => 1 },     # Provide methods to manipulate events in the specific calendar
  );

return \%hapi;
}

########################################################################
#      Liefert die statischen Informationen der File Station API
########################################################################
sub _staticFile {
  my %hapi = (                                                    
      INFO      => { NAME => "SYNO.API.Info",                    mk => 1 },                                          
      AUTH      => { NAME => "SYNO.API.Auth",                    mk => 1 },     # Perform login and logout
      FSINFO    => { NAME => "SYNO.FileStation.Info",            mk => 1 },     # Provide File Station info
      LIST      => { NAME => "SYNO.FileStation.List",            mk => 1 },     # List all shared folders, enumerate files in a shared folder, and get detailed file information
      SEARCH    => { NAME => "SYNO.FileStation.Search",          mk => 1 },     # Search files on given criteria
      LVFOLDER  => { NAME => "SYNO.FileStation.VirtualFolder",   mk => 1 },     # List all mount point folders of virtual file system, ex: CIFS or ISO
      FAVORITE  => { NAME => "SYNO.FileStation.Favorite",        mk => 1 },     # Add a folder to user’s favorites or do operations on user’s favorites
      THUMB     => { NAME => "SYNO.FileStation.Thumb",           mk => 1 },     # Get a thumbnail of a file
      DIRSIZE   => { NAME => "SYNO.FileStation.DirSize",         mk => 1 },     # Get the total size of files/folders within folder(s)
      MD5       => { NAME => "SYNO.FileStation.MD5",             mk => 1 },     # Get MD5 of a file
      CHECKPERM => { NAME => "SYNO.FileStation.CheckPermission", mk => 1 },     # Check if the file/folder has a permission of a file/folder or not
      UPLOAD    => { NAME => "SYNO.FileStation.Upload",          mk => 1 },     # Upload a file
      DOWNLOAD  => { NAME => "SYNO.FileStation.Download",        mk => 1 },     # Download files/folders
      SHARING   => { NAME => "SYNO.FileStation.Sharing",         mk => 1 },     # Generate a sharing link to share files/folders with other people and perform operations on sharing links
      CFOLDER   => { NAME => "SYNO.FileStation.CreateFolder",    mk => 1 },     # Create folder(s)
      RENAME    => { NAME => "SYNO.FileStation.Rename",          mk => 1 },     # Rename a file/folder
      COPYMOVE  => { NAME => "SYNO.FileStation.CopyMove",        mk => 1 },     # Copy/Move files/folders
      DELETE    => { NAME => "SYNO.FileStation.Delete",          mk => 1 },     # Delete files/folders
      EXTRACT   => { NAME => "SYNO.FileStation.Extract",         mk => 1 },     # Extract an archive and do operations on an archive
      COMPRESS  => { NAME => "SYNO.FileStation.Compress",        mk => 1 },     # Compress files/folders
      BGTASK    => { NAME => "SYNO.FileStation.BackgroundTask",  mk => 1 },     # Get information regarding tasks of file operations which are run as the background process including copy, move, delete, compress and extract tasks or perform operations on these background tasks
  );

return \%hapi;
}

1;