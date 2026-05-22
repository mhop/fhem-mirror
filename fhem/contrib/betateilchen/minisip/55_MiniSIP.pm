#  $Id: 55_minisip.pm 31259 2026-05-22 07:08:28Z betateilchen $

################################################################
#
#  Copyright notice
#
#  (c) 2026 - today
#  Copyright: betateilchen (betateilchen dot quantentunnel dot de)
#  All rights reserved
#
#  This program is part of FHEM; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License V2.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
#  See the GNU General Public License V2 for more details.
#
################################################################

package FHEM::MiniSIP;

use strict;
use warnings;

require FHEM::Core::MiniSIP;

sub ::MiniSIP_Initialize { goto &_Initialize}

sub _Initialize($) {
  my ($hash) = @_;
  $hash->{parseParams} = 1;
  $hash->{DefFn}    = \&FHEM::Core::MiniSIP::Define;
  $hash->{ReadFn}   = \&FHEM::Core::MiniSIP::Read;
  $hash->{UndefFn}  = \&FHEM::Core::MiniSIP::Undef;
  $hash->{SetFn}    = \&FHEM::Core::MiniSIP::Set;
  $hash->{GetFn}    = \&FHEM::Core::MiniSIP::Get;
#  $hash->{AttrFn}   = \&FHEM::Core::MiniSIP::Attr;
  $hash->{AttrList} = "disable:1,0 "
                    ."logFullMessage:0,1 "
                    ."showFullMessage:0,1 "
                    .$::readingFnAttributes;
}

1;


__END__
