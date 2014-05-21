##############################################
# $Id$
##############################################
package GPUtils;
use Exporter qw( import );

use strict;
use warnings;

our %EXPORT_TAGS = (all => [qw(GP_Define GP_Catch GP_ForallClients)]);
Exporter::export_ok_tags('all');

sub GP_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $module = $main::modules{$hash->{TYPE}};
  return $module->{NumArgs}." arguments expected" if ((defined $module->{NumArgs}) and ($module->{NumArgs} ne scalar(@a)-2));
  $hash->{STATE} = 'defined';
  if ($main::init_done) {
    eval { &{$module->{InitFn}}( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return GP_Catch($@) if $@;
  }
  return undef;
}

sub GP_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub GP_ForallClients($$$)
{
  my ($hash,$fn,$args) = @_;
  foreach my $d ( sort keys %main::defs ) {
    if (   defined( $main::defs{$d} )
      && defined( $main::defs{$d}{IODev} )
      && $main::defs{$d}{IODev} == $hash ) {
      	&$fn($main::defs{$d},$args);
    }
  }
  return undef;
}

1;

