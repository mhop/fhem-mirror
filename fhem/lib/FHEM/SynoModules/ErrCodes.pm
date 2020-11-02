########################################################################################################################
# $Id$
#########################################################################################################################
#       ErrCodes.pm
#
#       (c) 2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module provides Synology API Error Codes.
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

package FHEM::SynoModules::ErrCodes;                                          

use strict;           
use warnings;
use utf8;
use Carp qw(croak carp);

use version; our $VERSION = version->declare('1.3.4');

use Exporter ('import');
our @EXPORT_OK   = qw(expErrorsAuth expErrors);                 
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

# Standard Rückgabewert wenn keine Message zum Error Code / keine Rückgabefunktion gefunden wurde
my $nofound    = qq{Message not found for error code:};
my $noauthres  = qq{No authentication error resolution Hash defined for module type:};
my $nores      = qq{No error resolution Hash defined for module type:};

##############################################################################
#                             Error Code Hashes 
##############################################################################
## SSCam ##
my %errauthsscam = (                                                    # Authentification Error Codes der Surveillance Station API
  100  => "Unknown error",
  101  => "The account parameter is not specified",
  102  => "API does not exist",
  400  => "Invalid user or password",
  401  => "Guest or disabled account",
  402  => "Permission denied - DSM-Session: make sure user is member of Admin-group, SVS-Session: make sure SVS package is started, make sure FHEM-Server IP won't be blocked in DSM automated blocking list",
  403  => "One time password not specified",
  404  => "One time password authenticate failed",
  405  => "method not allowd - maybe the password is too long",
  406  => "OTP code enforced",
  407  => "Max Tries (if auto blocking is set to true) - make sure FHEM-Server IP won't be blocked in DSM automated blocking list",
  408  => "Password Expired Can not Change",
  409  => "Password Expired",
  410  => "Password must change (when first time use or after reset password by admin)",
  411  => "Account Locked (when account max try exceed)",
);

my %errsscam = (                                                       # Standard Error Codes der Surveillance Station API                 
  100  => "Unknown error",
  101  => "Invalid parameters",
  102  => "API does not exist",
  103  => "Method does not exist",
  104  => "This API version is not supported",
  105  => "Insufficient user privilege",
  106  => "Connection time out",
  107  => "Multiple login detected",
  117  => "need manager rights in SurveillanceStation for operation",
  400  => "Execution failed",
  401  => "Parameter invalid",
  402  => "Camera disabled",
  403  => "Insufficient license",
  404  => "Codec activation failed",
  405  => "CMS server connection failed",
  407  => "CMS closed",
  410  => "Service is not enabled",
  412  => "Need to add license",
  413  => "Reach the maximum of platform",
  414  => "Some events not exist",
  415  => "message connect failed",
  417  => "Test Connection Error",
  418  => "Object is not exist",
  419  => "Visualstation name repetition",
  439  => "Too many items selected",
  502  => "Camera disconnected",
  600  => "Presetname and PresetID not found in Hash",
  806  => "couldn't get Synology Surveillance Station API informations",
  9000 => "malformed JSON string received",
  9001 => "API keys and values not completed",
);

## SSCal ##
my %errauthsscal = (                                                   # Authentification Error Codes der Calendar API
  400  => "No such account or the password is incorrect",
  401  => "Account disabled",
  402  => "Permission denied",
  403  => "2-step verification code required",
  404  => "Failed to authenticate 2-step verification code",
);

my %errsscal = (                                                       # Standard Error Codes der Calendar API 
  100  => "Unknown error",
  101  => "No parameter of API, method or version",
  102  => "The requested API does not exist - may be the Synology Calendar package is stopped",
  103  => "The requested method does not exist",
  104  => "The requested version does not support the functionality",
  105  => "The logged in session does not have permission",
  106  => "Session timeout",
  107  => "Session interrupted by duplicate login",
  114  => "Missing required parameters",
  117  => "Unknown internal error",
  119  => "session id not valid",
  120  => "Invalid parameter",
  160  => "Insufficient application privilege",
  400  => "Invalid parameter of file operation",
  401  => "Unknown error of file operation",
  402  => "System is too busy",
  403  => "The user does not have permission to execute this operation",
  404  => "The group does not have permission to execute this operation",
  405  => "The user/group does not have permission to execute this operation",
  406  => "Cannot obtain user/group information from the account server",
  407  => "Operation not permitted",
  408  => "No such file or directory",
  409  => "File system not supported",
  410  => "Failed to connect internet-based file system (ex: CIFS)",
  411  => "Read-only file system",
  412  => "Filename too long in the non-encrypted file system",
  413  => "Filename too long in the encrypted file system",
  414  => "File already exists",
  415  => "Disk quota exceeded",
  416  => "No space left on device",
  417  => "Input/output error",
  418  => "Illegal name or path",
  419  => "Illegal file name",
  420  => "Illegal file name on FAT file system",
  421  => "Device or resource busy",
  599  => "No such task of the file operation",
  800  => "malformed or unsupported URL",
  805  => "empty API data received - may be the Synology cal Server package is stopped",
  806  => "couldn't get Synology calendar API informations",
  810  => "The credentials couldn't be retrieved",
  900  => "malformed JSON string received from Synology Calendar Server",
  910  => "Wrong timestamp definition. Check attributes \"cutOlderDays\", \"cutLaterDays\". ",
  9000 => "malformed JSON string received",
  9001 => "API keys and values not completed",
);

## SSChatBot ##
my %errsschat = (                                                       # Standard Error Codes des Chat Servers
  100  => "Unknown error",
  101  => "Payload is empty",
  102  => "API does not exist - may be the Synology Chat Server package is stopped",
  117  => "illegal file name or path",
  120  => "payload has wrong format",
  404  => "bot is not legal - may be the bot is not active or the botToken is wrong",
  407  => "record not valid",
  409  => "exceed max file size",
  410  => "message too long",
  800  => "malformed or unsupported URL",
  805  => "empty API data received - may be the Synology Chat Server package is stopped",
  806  => "couldn't get Synology Chat API informations",
  810  => "The botToken couldn't be retrieved",
  9000 => "malformed JSON string received",
  9001 => "API keys and values not completed",
);

## SSFile ##
my %errauthssfile = (                                                   # Authentification Error Codes der File Station API
  400  => "No such account or incorrect password",
  401  => "Account disabled",
  402  => "Permission denied",
  403  => "2-step verification code required",
  404  => "Failed to authenticate 2-step verification code",
);

my %errssfile = (                                                       # Standard Error Codes der File Station API
  100  => "Unknown error",
  101  => "No parameter of API, method or version",
  102  => "The requested API does not exist",
  103  => "The requested method does not exist",
  104  => "The requested version does not support the functionality",
  105  => "The logged in session does not have permission",
  106  => "Session timeout",
  107  => "Session interrupted by duplicate login",
  400  => "Invalid parameter of file operation",
  401  => "Unknown error of file operation",
  402  => "System is too busy",
  403  => "Invalid user does this file operation",
  404  => "Invalid group does this file operation",
  405  => "Invalid user and group does this file operation",
  406  => "Can’t get user/group information from the account server",
  407  => "Operation not permitted",
  408  => "No such file or directory",
  409  => "Non-supported file system",
  410  => "Failed to connect internet-based file system (ex: CIFS)",
  411  => "Read-only file system",
  412  => "Filename too long in the non-encrypted file system",
  413  => "Filename too long in the encrypted file system",
  414  => "File already exists",
  415  => "Disk quota exceeded",
  416  => "No space left on device",
  417  => "Input/output error",
  418  => "Illegal name or path",
  419  => "Illegal file name",
  420  => "Illegal file name on FAT file system",
  421  => "Device or resource busy",
  599  => "No such task of the file operation",
  800  => "A folder path of favorite folder is already added to user’s favorites",
  801  => "A name of favorite folder conflicts with an existing folder path in the user's favorites",
  802  => "There are too many favorites to be added",
  900  => "Failed to delete file(s)/folder(s). More information in <errors> object.",
  1000 => "Failed to copy files/folders. More information in <errors> object.",
  1001 => "Failed to move files/folders. More information in <errors> object.",
  1002 => "An error occurred at the destination. More information in <errors> object",
  1003 => "Cannot overwrite or skip the existing file because no overwrite parameter is given.",
  1004 => "File cannot overwrite a folder with the same name, or folder cannot overwrite a file with the same name.",
  1006 => "Cannot copy/move file/folder with special characters to a FAT32 file system.",
  1007 => "Cannot copy/move a file bigger than 4G to a FAT32 file system.",
  1100 => "Failed to create a folder. More information in <errors> object",
  1101 => "The number of folders to the parent folder would exceed the system limitation",
  1200 => "Failed to rename it. More information in <errors> object",
  1300 => "Failed to compress files/folders",
  1301 => "Cannot create the archive because the given archive name is too long",
  1400 => "Failed to extract files.",
  1401 => "Cannot open the file as archive",
  1402 => "Failed to read archive data error",
  1403 => "Wrong password",
  1404 => "Failed to get the file and dir list in an archive",
  1405 => "Failed to find the item ID in an archive file",
  1800 => "There is no Content-Length information in the HTTP header or the received size doesn't match the value of Content-Length information in the HTTP header",
  1801 => "Wait too long, no date can be received from client (Default maximum wait time is 3600 seconds)",
  1802 => "No filename information in the last part of file content",
  1803 => "Upload connection is cancelled",
  1804 => "Failed to upload too big file to FAT file system",
  1805 => "Can't overwrite or skip the existed file, if no overwrite parameter is given",
  2000 => "Sharing link does not exist",
  2001 => "Cannot generate sharing link because too many sharing links exist",
  2002 => "Failed to access sharing links",
  9000 => "malformed JSON string received",
  9001 => "API keys and values not completed",
  9002 => "File not found",
  9003 => "Bad Request",
);

my %hterr = (                                                           # Hash der TYPE Error Code Spezifikationen
  SSCam     => {errauth => \%errauthsscam,  errh => \%errsscam  },    
  SSCal     => {errauth => \%errauthsscal,  errh => \%errsscal  },
  SSChatBot => {                            errh => \%errsschat },
  SSFile    => {errauth => \%errauthssfile, errh => \%errssfile },
);

##############################################################################
#              Auflösung Errorcodes bei Login / Logout
##############################################################################
sub expErrorsAuth {
  my $hash      = shift // carp "got no hash value !"           && return;
  my $errorcode = shift // carp "got no error code to analyse"  && return;
  my $type      = $hash->{TYPE};
   
  if($hterr{$type} && %{$hterr{$type}{errauth}}) {
      my $errauth = $hterr{$type}{errauth};                               # der Error Kodierungshash
      my $error   = $errauth->{$errorcode} // $nofound." ".$errorcode;
      return $error;
  }
  
  carp $noauthres." ".$type;

return q{};
}

##############################################################################
#               Auflösung Standard Errorcodes 
##############################################################################
sub expErrors {
  my $hash      = shift // carp "got no hash value !"           && return;
  my $errorcode = shift // carp "got no error code to analyse"  && return;
  my $type      = $hash->{TYPE};
   
  if($hterr{$type} && %{$hterr{$type}{errh}}) {
	  my $errh  = $hterr{$type}{errh};                                    # der Error Kodierungshash
	  my $error = $errh->{$errorcode} // $nofound." ".$errorcode;
      return $error;
  }
  
  carp $nores." ".$type;

return q{};
}

1;