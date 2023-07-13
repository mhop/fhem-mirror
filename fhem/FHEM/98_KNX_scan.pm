## no critic (Modules::RequireVersionVar)
# $Id$
# CommandModule for KNX utilities
# executing functions and detailed cmd-ref are defined in KNX-module. 
################################################################################
### changelog:
# 2023/07/xx initial version


package main;
use strict;
use warnings;

### perlcritic parameters
## no critic (ControlStructures::ProhibitPostfixControls)
## no critic (Documentation::RequirePodSections)

sub KNX_scan_Initialize {

	$cmds{KNX_scan} = { Fn  => 'CommandKNX_scan', 
	                    Hlp => '[<devspec>] request values from KNX-Hardware. Use "help KNX_scan" for more help'};
	return;
}

#####################################
sub CommandKNX_scan {
	my $cl = shift;
	my $devs = shift;

	$devs = 'TYPE=KNX' if (! defined($devs) || $devs eq q{}); # select all if nothing defined
	if (exists($modules{KNX}->{LOADED})) { # check for KNX-module ready
		main::KNX_scan($devs);
	} 
	else {
		Log3 undef, 2, "KNX_scan for $devs aborted - KNX-module not loaded!";
	}
	return;
}

1;

=pod

=encoding utf8

=item command
=item summary  scans KNX-Bus devices to syncronize the status of KNX-devices with FHEM.
=item summary_DE gleicht den Status der KNX-Bus Geräte mit FHEM ab.
=begin html

<a id="KNX_scan"></a>
<h3>KNX_scan</h3>
<ul>
<li>KNX_scan is a utility funtion to syncronize the status of KNX-hardware with FHEM.<br>
Syntax:<br>
<code>&nbsp;&nbsp;&nbsp;KNX_scan &lt;KNX-device&gt; or<br>
&nbsp;&nbsp;&nbsp;KNX_scan &lt;KNX-devspec&gt;</code> 
<p>A detailed description and examples of the <a href="#KNX-utilities">KNX_scan</a> cmd is here.</p>
</li></ul> 

=end html

=cut
