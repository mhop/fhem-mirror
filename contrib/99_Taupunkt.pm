#
# Taupunkt.pm
#
# 2011-12-21 Michael Bussmann <support@mb-net.net>
#

package main;

use strict;
use warnings;
use POSIX;

sub
Taupunkt_Initialize($$)
{
  my ($hash) = @_;
}


#
# calc_sdd(T)
#
# Sättigungsdampfdruck [hPa] ( Temperatur t [C] )
# über ebenen Wasseroberflächen
#
# Nach Magnus-Formel
#
#	E_w (t)= 6.112 hPa * e ^ (17.62*T / ( 243.12 °C + T))
#	für -45 °C <= t <= 60 °C
#
# Nach D.Sonntag (Wikipedia)
# http://de.wikibooks.org/wiki/Tabellensammlung_Chemie/_Stoffdaten_Wasser
#
sub
calc_sdd($)
{
	my ($t) = @_;
	my $tk = $t+273.15;

	# Magnus
	#return ( 6.112 * exp( (17.62*$t)/(243.12+$t)) );

	# Wikipedia/D.Sonntag
	return ( exp( (-6094.4642/$tk) + 21.1249952 - ($tk*2.7245552e-2) + ($tk**2 * 1.6853396e-5 ) + ( 2.4575506*log($tk)) ) / 100 );
}

#
# calc_dd(r, T)
#
# Dampfdruck [hPa] (rel. Feuchte r [%], Temperatur T [C] )
#
# DD = r/100 * sdd(T)
#
sub
calc_dd($$)
{
	my ($r, $t) = @_;

	return ( $r*calc_sdd($t)/100.0 );
}

#
# calc_dewpoint(r, T)
#
# Taupunkt [C] (rel. Feuchte r [%], Temperatur T [C] )
#
# Taupunkt (ü.W.): a = 7.5, b = 237.3 (für T>=0)
# Taupunkt (ü.W.): a = 7.6, b = 240.7 (für T<0)
# Frostpunkt:      a = 9.5, b = 265.5 (für T<0)
# 
# TD(r,T) = b*v/(a-v) mit v(r,T) = log10(DD(r,T)/6.1078)
#
sub
calc_dewpoint($$)
{
	my ($r, $t) = @_;
	my ($a, $b, $v);

	if ($t>=0) {
		$a=7.5; $b=237.3;
	} else {
		$a=7.6; $b=240.7;
	}

	$v=log10(calc_dd($r, $t)/6.1078);

	return ( ($b*$v)/($a-$v) );
}

#
# calc_af(r, T)
#
# Absolute Feuchte [g/m^3] (rel. Feuchte r [%], Temperatur T [C] )
#
# auf 1 bar (10^5 Pa)
#
# R* = 8314.3 J/(kmol*K)
# mw = 18.016 kg
#
#    AF(r,TK)  = 10^5 * mw/R* * DD(r,T)/TK
#    AF(TD,TK) = 10^5 * mw/R* * SDD(TD)/TK
#
sub
calc_af($$)
{
	my ($r, $t) = @_;
	my $tk = $t+273.15;

	return ( (1801600/8314.3) * (calc_dd($r, $t)/$tk) );
	### return ( (1801600/8314.3) * (calc_sdd(calc_dewpoint($r, $t))/$tk) );
}

1;
