# $Id$
####################################################################################################
#
#   A FHEM Perl module to retrieve data from an APC uninterruptible power supply
#
#   This file is part of fhem.
#
#   Fhem is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 2 of the License, or
#   (at your option) any later version.
#
#   Fhem is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
####################################################################################################

package FHEM::apcstatus;

use strict;
use warnings;
use POSIX;
#use FHEM::Meta;

# Import aus der fhem.pl
use GPUtils qw(GP_Import);

BEGIN {

    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          ReadingsTimestamp
          defs
          readingFnAttributes
          modules
          Log3
          CommandAttr
          attr
          AttrVal
          ReadingsVal
          Value
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          Debug
          InternalTimer
          RemoveInternalTimer)
    );
}

our $pkg;

sub _Export {
    no strict qw/refs/;
    $pkg     =  caller(0);
    my $main =  $pkg;
    $main    =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
    foreach (@_) {
        *{ $main . $_ } = *{ $pkg . '::' . $_ };
    }
    use strict qw/refs/;
}

_Export(
    qw(
      Initialize
      )
);

sub Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = "$pkg::Define";
#    $hash->{SetFn}      = "$pkg::Set";
#    $hash->{GetFn}      = "$pkg::Get";
#    $hash->{NotifyFn}   = "$pkg::Notify";
    $hash->{UndefFn}    = "$pkg::Undef";
#    $hash->{DeleteFn}   = "$pkg::Delete";
#    $hash->{ShutDownFn} = "$pkg::ShutDown";
    $hash->{AttrFn}     = "$pkg::Attr";
    $hash->{AttrList}   =
        "disable:1,0 "
      . "disabledForIntervals "
#      . "upgradeListReading:1 "
#      . "distupgrade:1 "
      . $readingFnAttributes;

#    foreach my $d ( sort keys %{ $modules{AptToDate}{defptr} } ) {
#        my $hash = $modules{AptToDate}{defptr}{$d};
#        $hash->{VERSION} = $VERSION;
#    }
    
#    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define($$) {
Debug "test: $pkg";
}
sub Undef($$) {}
sub Attr(@) {}

1;

=pod
=item device
=item summary       Modul
=item summary_DE    Modul

=begin html

<a name="apcstatus"></a>
<h3>apcstatus</h3>
<ul>
  apcstatus<br>
  <br><br>

  <a name=apcstatusdefine"></a>
  <b>Define</b>
  <br>

  <a name="apcstatusattr"></a>
  <b>Attributes</b>
  <br>
  
  <a name="apcstatusreadings"></a>
  <b>Readings</b>
  <br>
</ul>

=end html
=cut

