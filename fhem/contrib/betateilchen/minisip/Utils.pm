#  $Id$

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

package FHEM::MiniSIP::Utils;

use strict;
use warnings;

use GPUtils         qw(:all);

use Exporter ('import');
our @EXPORT_OK = qw(test);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

BEGIN {
    GP_Import( qw(
        Log3
        Debug
      )
    );
};

sub test {
Debug "testSub erreicht";
}

1;

__END__
