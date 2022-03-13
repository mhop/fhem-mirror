########################################################################################################################
# $Id$
#########################################################################################################################
#       CTZ.pm
#
#       (c) 2022 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This module enables the conversion of the time specification of a time zone to another time zone (e.g. UTC).
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

# Version History
# 0.0.3  13.03.2022 publish func reqModFail
# 0.0.2  12.03.2022 check required Perl modules 
# 0.0.1  10.03.2022 initial

package FHEM::Utility::CTZ;                                          

use strict;           
use warnings;
use utf8;

# use lib qw(/opt/fhem/FHEM  /opt/fhem/lib);                              # für Syntaxcheck mit: perl -c /opt/fhem/lib/FHEM/Utility/CTZ.pm

use GPUtils qw( GP_Import GP_Export );

eval "use DateTime;1"                    or my $abs0 = 'DateTime';
eval "use DateTime::Format::Strptime;1"  or my $abs1 = 'DateTime::Format::Strptime';

use version 0.77; our $VERSION = version->declare('0.0.1');

use Exporter ('import');
our @EXPORT_OK = qw(
                     convertTimeZone
                     getTZNames
                     reqModFail
                   );
                     
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          Log
          Log3
        )
  );  
};

my $pkg = __PACKAGE__;

####################################################################################################
#  https://stackoverflow.com/questions/411740/how-can-i-parse-dates-and-convert-time-zones-in-perl
#  
#  name      : name of caller module
#  dtstring  : datetime string to convert, format: YYYY-MM-DD hh:mm:ss[.xxx]
#  tzcurrent : timezone of original timestamp
#  tzconv    : timezone the datetime string is to converted to
#  writelog  : 0 - no write to log, 1 - write to log
#
####################################################################################################
sub convertTimeZone { 
  my $paref = shift // q{};  
  my $err   = q{};  

  if(ref $paref ne "HASH") {
     $err = "function convertTimeZone got no data or data type is not of type HASH";
     return $err;
  }
  
  my $rmf = reqModFail();
  return $rmf if($rmf);

  my $name      = $paref->{name}      // $pkg;
  my $dtstring  = $paref->{dtstring}  // q{};
  my $tzcurrent = $paref->{tzcurrent} // 'local';
  my $tzconv    = $paref->{tzconv}    // 'UTC';
  my $writelog  = $paref->{writelog}  // 0;
  my $ms        = q{};
  
  return "no valid timezone $tzcurrent" if(!checkValidName($tzcurrent));
  return "no valid timezone $tzconv"    if(!checkValidName($tzconv)   );
  
  if ($dtstring =~ m/\.(\d+)/xs) {                                        # datetime enthält Millisekunden                            
      $ms = '.'.$1; 
  }
  
  my $strptime = new DateTime::Format::Strptime ( pattern   => '%Y-%m-%d %H:%M:%S',
                                                  time_zone => $tzcurrent,
                                                );

  my $date = $strptime->parse_datetime($dtstring) or do { $err = $strptime->errmsg;
                                                          return $err;
                                                        };

  Log3 ($name, 1, "$pkg - original timestring: ".$date->strftime("%Y-%m-%d %H:%M:%S$ms %Z")) if($writelog);

  $date->set_time_zone($tzconv);
  
  my $dtconv = $date->strftime("%Y-%m-%d %H:%M:%S");
             
  Log3 ($name, 1, "$pkg - converted timestring: ".$date->strftime("%Y-%m-%d %H:%M:%S$ms %Z")) if($writelog);
          
return ($err, $dtconv.$ms);
}

sub checkValidName {
  my $tz = shift;
  
  my $valid = DateTime::TimeZone->is_valid_name($tz);
          
return $valid;
}

###############################################################################
# returns an array reference list of all possible time zone names
###############################################################################
sub getTZNames {
  
  my $rmf = reqModFail();
  if($rmf) {
      $rmf = "ERROR - ".$rmf;
      Log (1, "$pkg - $rmf");
      return [($rmf)];
  }
  
  my $atz = DateTime::TimeZone->all_names;
          
return $atz;
}

###############################################################################
# Check required Perl modules
###############################################################################
sub reqModFail {
  
  if ($abs0 || $abs1) {
      my @ma;
      push @ma, $abs0 if($abs0);
      push @ma, $abs1 if($abs1);
      
      my $err = "required perl module not installed: ".join ", ", @ma;
      
      return $err;
  }
          
return;
}

1;