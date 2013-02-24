# $Id$
##############################################################################
#
#     71_DENON_AVR.pm
#     An FHEM Perl module for controlling Denon AV-Receivers
#     via network connection. 
#
#     Copyright by Boris Pruessmann
#     e-mail: boris@pruessmann.org
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;

###################################
sub
DENON_AVR_Initialize($)
{
    my ($hash) = @_;

    $hash->{GetFn}     = "DENON_AVR_Get";
    $hash->{SetFn}     = "DENON_AVR_Set";
    $hash->{DefFn}     = "DENON_AVR_Define";
    $hash->{UndefFn}   = "DENON_AVR_Undefine";

    $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,1,2,3,4,5 ".$readingFnAttributes;
}

###################################
sub
YAMAHA_AVR_Get($@)
{
    my ($hash, @a) = @_;

    return "Not yet implemented.";
}

###################################
sub
YAMAHA_AVR_Set($@)
{
    my ($hash, @a) = @_;

    return "Not yet implemented.";
}

###################################
sub
YAMAHA_AVR_Define($$)
{
    my ($hash, $def) = @_;

    return undef;
}

#############################
sub
YAMAHA_AVR_Undefine($$)
{
    my($hash, $name) = @_;

    return undef;
}
