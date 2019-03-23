# $Id$

package main;
use strict;
use warnings;
use FHEM::Meta;

sub search_Initialize($$) {
    my ($modHash) = @_;
    my %hash = (
        Fn  => "FHEM::search::run",
        Hlp => "<search expression>",
    );
    $cmds{search} = \%hash;

    return FHEM::Meta::InitMod( __FILE__, $modHash );
}

# define package
package FHEM::search;
use strict;
use warnings;
use POSIX;

use GPUtils qw(GP_Import);

# Run before module compilation
BEGIN {
    # Import from main::
    GP_Import(
        qw(
          modules
          defs
          fhem
          )
    );
}

sub run {
    my ( $cl, $search ) = @_;
    my $hash;
    my $name = 'fhemInstaller';
    if (   defined( $modules{Installer} )
        && defined( $modules{Installer}{defptr} )
        && defined( $modules{Installer}{defptr}{localhost} ) )
    {
        $hash = $modules{Installer}{defptr}{localhost};
    }
    else {
        my $no      = 1;
        my $newname = $name;
        while ( defined( $defs{$newname} ) ) {
            $newname = $name . $no++;
        }
        fhem "define $newname Installer";
        $hash = $modules{Installer}{defptr}{localhost};
    }

    return 'Not a hash reference: ' unless ( $hash && ref($hash) eq 'HASH' );
    $name = $hash->{NAME};

    $hash->{CL} = $cl if ($cl);
    my $ret = FHEM::Installer::Get( $hash, $name, 'search', $search );
    delete $hash->{CL} if ($cl);
    return $ret;
}

1;

=pod
=encoding utf8
=item command
=item summary Search through this FHEM instance
=item summary_DE Durchsucht die FHEM Instanz

=begin html

<a name="search"></a>
<h3>search</h3>
<ul>
  <code>search &lt;search expression&gt;</code>
  <br />
  Searches FHEM for devices, modules, developer packages, keywords, authors/maintainers and Perl packages.<br />
  This command requires a device instance of the FHEM Installer module. If no local Installer device is present,
  the first run of this command will create one.<br />
  <br />
  Have a look to the 'Get search' command of the FHEM Installer to learn more about how to search.
</ul>

=end html

=begin html_DE

<a name="search"></a>
<h3>search</h3>
<ul>
  <code>search &lt;Suchausdruck&gt;</code>
  <br />
  Durchsucht FHEM nach Ger&auml;ten, Modulen, Entwickler Paketen, Schl&uuml;sselw&ouml;rtern und Perl Paketen.<br />
  Dieses Kommando ben&ouml;tigt eine Ger&auml;teinstanz des FHEM Installer Moduls. Sofern kein lokales Installer Ger&auml;t
  vorhanden ist, wird beim ersten ausf&uuml;hren dieses Kommandos eines angelegt.<br />
  <br />
  Das 'Get search' Kommando des FHEM Installer verr&auml;t mehr dar&auml;ber, wie die Suche funktioniert. 
</ul>

=end html_DE

=for :application/json;q=META.json 98_search.pm
{
  "version": "v0.9.0",
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
  ]
}
=end :application/json;q=META.json

=cut
