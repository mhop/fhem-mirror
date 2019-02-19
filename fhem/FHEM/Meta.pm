###############################################################################
# $Id$
#
# Metadata handling for FHEM modules

# define package
package FHEM::Meta;
use strict;
use warnings;

use GPUtils qw(GP_Import);
use File::stat;
use Encode;
use Data::Dumper;

# Run before module compilation
BEGIN {

    # Import from main::
    GP_Import(
        qw(
          modules
          defs
          attr
          Log
          Debug
          devspec2array
          genUUID
          TimeNow
          FmtDateTime
          fhemTimeGm
          )
    );
}

# Get our own Metadata
my %META;
my $ret = __GetMetadata( __FILE__, \%META );
return "$@" if ($@);
return $ret if ($ret);
use version 0.77; our $VERSION = $META{version};

# sub import(@) {
#     my $pkg = caller(0);
#     if ( $pkg ne "main" ) {
#     }
# }

# Loads Metadata for a module
sub Load($$;$) {
    my ( $filePath, $modHash, $runInLoop ) = @_;

    my $ret = __PutMetadata( $filePath, $modHash, 1, $runInLoop );

    if ($@) {
        Log 1, __PACKAGE__ . "::Load: ERROR: \$\@:\n" . $@;
        return "$@";
    }
    elsif ($ret) {
        Log 1, __PACKAGE__ . "::Load: ERROR: \$ret:\n" . $ret;
        return $ret;
    }

    if ( defined( $modHash->{META} ) && defined( $modHash->{META}{x_file} ) ) {

        # Add name to module hash
        $modHash->{NAME} = $modHash->{META}{x_file}[4];
        $modHash->{NAME} =~ s/^.*://g;    # strip away any parent module names

        # only run when module is reloaded
        if (   defined( $modules{ $modHash->{NAME} } )
            && defined( $modules{ $modHash->{NAME} }{NAME} )
            && $modHash->{NAME} eq $modules{ $modHash->{NAME} }{NAME} )
        {
            foreach my $devName ( devspec2array( 'TYPE=' . $modHash->{NAME} ) )
            {
                __CopyMetaToInternals( $defs{$devName}, $modHash->{META} );
            }
        }
    }

    return undef;
}

#TODO allow to have array of module names as optional parameter, use keys %modules when not given
#     Then make this function to be called by X_Initialize(). Problem: We don't know the module name yet, just filename.
#     So maybe one can give wither filepath or modulename as parameter?
# Load Metadata for non-loaded modules
sub LoadAll(;$$) {
    my ( $unused, $reload ) = @_;
    my $t = TimeNow();
    my $v = __PACKAGE__->VERSION();
    my @rets;

    foreach my $modName ( keys %modules ) {

        # Only add META to loaded modules
        #  if not enforced for all
        next
          unless (
            $unused
            || ( defined( $modules{$modName}{LOADED} )
                && $modules{$modName}{LOADED} eq '1' )
          );

        # Abort when module file was not indexed by
        #   fhem.pl before.
        # Only continue if META was not loaded
        #   or should explicitly reloaded.
        next
          if (
            !defined( $modules{$modName}{ORDER} )
            || (   !$reload
                && defined( $modules{$modName}{META} )
                && ref( $modules{$modName}{META} ) eq "HASH" )
          );

        delete $modules{$modName}{META};

        my $filePath;
        if ( $modName eq 'Global' ) {
            $filePath = $attr{global}{modpath} . "/fhem.pl";
        }
        else {
            $filePath =
                $attr{global}{modpath}
              . "/FHEM/"
              . $modules{$modName}{ORDER} . '_'
              . $modName . '.pm';
        }

        my $ret = Load( $filePath, $modules{$modName}, 1 );
        push @rets, $@   if ( $@   && $@ ne "" );
        push @rets, $ret if ( $ret && $ret ne "" );

        $modules{$modName}{META}{generated_by} = $META{name} . " $v, $t"
          if ( defined( $modules{$modName}{META} ) );
    }

    SetInternals( $defs{'global'} );

    if (@rets) {
        $@ = join( "\n", @rets );
        return "$@";
    }

    return undef;
}

# Initializes a device instance of a FHEM module
sub SetInternals($) {
    my ($devHash) = @_;
    $devHash = $defs{$devHash} unless ( ref($devHash) );
    my $devName = $devHash->{NAME}   if ( defined( $devHash->{NAME} ) );
    my $modName = $devHash->{TYPE}   if ( defined( $devHash->{TYPE} ) );
    my $modHash = $modules{$modName} if ($modName);
    my $modMeta = $modHash->{META}   if ($modHash);

    unless ( defined($modHash) && ref($modHash) eq "HASH" ) {
        $@ = __PACKAGE__ . "::SetInternals: ERROR: Module hash not found";
        return 0;
    }

    return 0
      unless ( defined( $modHash->{LOADED} ) && $modHash->{LOADED} eq '1' );

    $devHash->{'.MetaInternals'} = 1;
    __CopyMetaToInternals( $devHash, $modMeta );

    return 1;
}

# Get meta data
sub Get($$) {
    my ( $devHash, $field ) = @_;
    $devHash = $defs{$devHash} unless ( ref($devHash) );
    my $devName = $devHash->{NAME}   if ( defined( $devHash->{NAME} ) );
    my $modName = $devHash->{TYPE}   if ( defined( $devHash->{TYPE} ) );
    my $modHash = $modules{$modName} if ($modName);
    my $modMeta = $modHash->{META}   if ($modHash);

    unless ( defined($modHash) && ref($modHash) eq "HASH" ) {
        $@ = __PACKAGE__ . "::Get: ERROR: Module hash not found";
        return 0;
    }

    return $modMeta->{$field}
      if ( $modMeta && ref($modMeta) && defined( $modMeta->{$field} ) );
    return undef;
}

##########
# Private functions
#

sub __CopyMetaToInternals {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ( $devHash, $modMeta ) = @_;
    return unless ( defined( $devHash->{'.MetaInternals'} ) );
    return unless ( defined($modMeta) && ref($modMeta) eq "HASH" );

    $devHash->{VERSION} = $modMeta->{x_version}
      if ( defined( $modMeta->{x_version} ) );
}

# Initializes FHEM module Metadata
sub __PutMetadata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ( $filePath, $modHash, $reload, $runInLoop ) = @_;

    return
      if ( !$reload
        && defined( $modHash->{META} )
        && ref( $modHash->{META} ) eq "HASH"
        && scalar keys %{ $modHash->{META} } > 0 );

    delete $modHash->{META};

    my %meta;
    my $ret = __GetMetadata( $filePath, \%meta, $runInLoop );
    return "$@" if ($@);
    return $ret if ($ret);

    $modHash->{META} = \%meta;

    return undef;
}

# Extract meta data from FHEM module file
sub __GetMetadata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ( $filePath, $modMeta, $runInLoop ) = @_;
    my @vcs;
    my $fh;
    my $encoding;
    my $version;
    my $versionFrom;
    my $authorName;    # not in use, see below
    my $authorMail;    # not in use, see below
    my $item_modtype;
    my $item_summary;
    my $item_summary_DE;

    # extract all info from file name
    if ( $filePath =~ m/^((.+\/)((?:(\d+)_)?(.+)\.(.+)))$/ ) {
        my @file;
        $file[0] = $1;    # complete match
        $file[1] = $2;    # relative file path
        $file[2] = $3;    # file name
        $file[3] = $4;    # order number, may be undefined
        $file[4] = $3 eq 'fhem.pl' ? 'Global' : $5;    # FHEM module name
        $file[5] = $6;                                 # file extension

        # These items are added later in the code:
        #   $file[6] - array with file system info
        #   $file[7] - source the version was extracted from
        #   $file[8] - plain extracted version number, may be undefined

        $modMeta->{x_file} = \@file;
    }

    # grep info from file content
    if ( open( $fh, '<' . $filePath ) ) {
        my $skip = 1;
        my $json;

        # get file stats
        push @{ $modMeta->{x_file} }, [ @{ stat($fh) } ];
        foreach ( 8, 9, 10 ) {
            my $t = $modMeta->{x_file}[6][$_];
            my $s = FmtDateTime($t);
            $modMeta->{x_file}[6][$_] =
              [ $t, $1, $2, $3, $4, $5, $6, $7, $8, $9 ]
              if ( $s =~ m/^(((....)-(..)-(..)) ((..):(..):(..)))$/ );
        }

        my $searchComments = 1;    # not in use, see below
        while ( my $l = <$fh> ) {

            # # Track comments section at the beginning of the document
            # if ( $searchComments && $l !~ m/^#|\s*$/ ) {
            #     $searchComments = 0;
            # }

            # extract VCS info from $Id$
            if (  !@vcs
                && $l =~
m/(\$Id\: ((?:([0-9]+)_)?([\w]+)\.([\w]+))\s([0-9]+)\s((([0-9]+)-([0-9]+)-([0-9]+))\s(([0-9]+):([0-9]+):([0-9]+)))(?:[\w]+?)\s([\w.-]+)\s\$)/
              )
            {
                $vcs[0] = $1;    # complete match
                $vcs[1] = $2;    # file name
                $vcs[2] =
                  $2 eq 'fhem.pl' ? '-1' : $3;  # order number, may be indefined
                $vcs[3] = $2 eq 'fhem.pl' ? 'Global' : $4;   # FHEM module name
                $vcs[4] = $5;                                # file extension
                $vcs[5] = $6;                                # svn base revision
                $vcs[6]  = $7;     # commit datetime string
                $vcs[7]  = $8;     # commit date
                $vcs[8]  = $9;     # commit year
                $vcs[9]  = $10;    # commit month
                $vcs[10] = $11;    # commit day
                $vcs[11] = $12;    # commit time
                $vcs[12] = $13;    # commit hour
                $vcs[13] = $14;    # commit minute
                $vcs[14] = $15;    # commit second
                $vcs[15] = $16;    # svn username (COULD be maintainer)

                # These items are added later in the code:
                #   $vcs[16] - commit unix timestamp
            }

#             # extract author name and email from comments
#             elsif ($searchComments
#                 && !$authorMail
#                 && $l =~
# m/(^#.*?([A-Za-z]+ +[A-Za-z]+?) +[<(]?\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b[>)]?)/i
#               )
#             {
#                 $searchComments = 0;
#                 $authorName     = $2 if ($2);
#                 $authorMail     = $3 if ($3);
#                 $authorName     = $authorMail
#                   if ( $authorName && $authorName =~ m/written| from| by/i );
#
#                 $authorName = "" unless ($authorName);
#             }

            ######
            # get legacy style version directly from
            #  within sourcecode if we are lucky
            #

            # via $VERSION|$version variable
            elsif ( !$version
                && $l =~
m/((?:(?:my|our)\s+)?\$VERSION\s+=\s+[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?)))/i
              )
            {
                my $extr = $2;
                $version = ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
                  if ($extr);
                $version .= '.0'
                  if ( $version && $version !~ m/v\d+\.\d+\.\d+/ );

                $versionFrom = 'source/1' if ($version);
            }

            # via $hash->{VERSION}|$hash->{version}
            elsif ( !$version
                && $l =~
m/(->\{VERSION\}\s+=\s+[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?)))/i
              )
            {
                my $extr = $2;
                $version = ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
                  if ($extr);
                $version .= '.0'
                  if ( $version && $version !~ m/v\d+\.\d+\.\d+/ );

                $versionFrom = 'source/2' if ($version);
            }

            #
            ######

            # read items from POD
            elsif ( !$item_modtype
                && $l =~ m/^=item\s+(device|helper|command)/i )
            {
                return "=item (device|helper|command) pod must occur only once"
                  if ($item_modtype);
                $item_modtype = lc($1);
            }
            elsif ( !$item_summary_DE
                && $l =~ m/^=item\s+(summary_DE)\s+(.*)$/i )
            {
                return "=item summary_DE pod must occur only once"
                  if ($item_summary_DE);
                $item_summary_DE =
                  ( $encoding && $encoding eq "utf8" ) ? encode_utf8($2) : $2;
            }
            elsif ( !$item_summary && $l =~ m/^=item\s+(summary)\s+(.*)$/i ) {
                return "=item summary_DE pod must occur only once"
                  if ($item_summary);
                $item_summary =
                  ( $encoding && $encoding eq "utf8" ) ? encode_utf8($2) : $2;
            }

            # read encoding from POD
            elsif ( $skip && $l =~ m/^=encoding\s+(.+)/i ) {
                return "=encoding pod must occur only once" if ($encoding);
                $encoding = lc($1);
            }

            # read META.json from POD
            elsif ( $skip && $l =~ m/^=begin\s+META.json/i ) {
                $skip = 0;
                $json = "";
            }
            elsif ( !$skip && $l =~ m/^=end\s+META.json/i ) {
                last;
            }
            elsif ( !$skip ) {
                $json .= $l;
            }
        }

        # if we were unable to get version,
        #   let's also try the initial comments block
        unless ( $json || $version ) {
            seek $fh, 0, 0;

            while ( my $l = <$fh> ) {

                # Only seek the document until code starts
                if ( $l !~ m/^#|\s*$/ ) {
                    last;
                }

                # via Version:
                elsif ( !$version
                    && $l =~
m/(^#\s+Version:?\s+[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?)))/i
                  )
                {
                    my $extr = $2;
                    $version =
                      ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
                      if ($extr);
                    $version .= '.0'
                      if ( $version && $version !~ m/v\d+\.\d+\.\d+/ );

                    $versionFrom = 'comment/1' if ($version);
                }

                # via vX.X.X, assuming latest version comes first;
                #  might include false-positives
                elsif ( !$version
                    && $l =~
                    m/(^#\s+(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?)))(?:\s+.*)?$/i
                  )
                {
                    my $extr = $2;
                    $version = ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $2 ) )
                      if ($extr);
                    $version .= '.0'
                      if ( $version && $version !~ m/v\d+\.\d+\.\d+/ );

                    $versionFrom = 'comment/2' if ($version);
                }

                last if ($version);
            }
        }

        close($fh);

        $encoding = 'latin1' unless ($encoding);

        if ( defined($json) ) {
            eval {
                use JSON;
                1;
            };

            unless ($@) {
                eval {
                    my $t;
                    if ( $encoding ne 'latin1' ) {
                        if ( $encoding eq "utf8" ) {
                            $t = encode_utf8($json);
                        }
                        elsif ( $encoding =~
                            /^(latin1|utf8|koi8-r|ShiftJIS|big5)$/ )
                        {
                            return "Encoding type $encoding is not supported";
                        }
                        else {
                            return "Invalid encoding type $encoding";
                        }
                    }
                    else {
                        $t = $json;
                    }

                    my $decoded = decode_json($t);
                    while ( my ( $k, $v ) = each %{$decoded} ) {
                        $modMeta->{$k} = $v;
                    }

                    1;
                } or do {
                    return "Error while parsing META.json from $_[0]: $@";
                };
            }
        }
    }

    # Get some other info about fhem.pl
    if ( $modMeta->{x_file}[2] eq 'fhem.pl' ) {

        # grep Makefile
        if ( open( $fh, '<' . $modMeta->{x_file}[1] . 'Makefile' ) ) {
            while ( my $l = <$fh> ) {
                if ( $l =~ /(^VERS\s*=\s*(\d{1,3}\.\d{1,3})\s*)/i ) {
                    my $extr = $2;

                    $versionFrom = 'Makefile+vcs';
                    $version =
                      ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
                      if ($extr);

                    if ($version) {
                        $version .= '.' . $vcs[5];
                        $modMeta->{version} = $version;
                        $modMeta->{x_version} =
                          $modMeta->{x_file}[2] . ':' . $version;
                    }
                }

                if ( $l =~ /(^DATE\s*=\s*(\d{4}-\d{2}-\d{2})\s*)/i ) {
                    $modMeta->{x_release_date} = $2 if ($2);
                }

                last if ( $version && $modMeta->{x_release_date} );
            }
        }
        close($fh);
    }

    ########
    # Meta data refactoring starts here
    #

    #TODO
    # - check VCS data against update data
    # - get dependencies via Perl module
    # - add info from MAINTAINER.txt

    # use VCS info 'as is', but only when:
    #   - file name matches
    if ( @vcs && $vcs[1] eq $modMeta->{x_file}[2] ) {
        push @vcs,
          fhemTimeGm(
            $vcs[14], $vcs[13], $vcs[12], $vcs[10],
            ( $vcs[9] - 1 ),
            ( $vcs[8] - 1900 )
          );
        $modMeta->{x_vcs} = \@vcs;
    }

    # author has put version into JSON
    if ( defined( $modMeta->{version} ) ) {
        $versionFrom = 'META.json' unless ($versionFrom);
    }

    # author has put version somewhere else in the file
    elsif ($version) {
        $modMeta->{version} = $version;
    }

    # seems the author didn't put any explicit
    #   version number we could find ...
    else {
        $modMeta->{version} = "v0.0.";

        if ( defined( $modMeta->{x_vcs} )
            && $modMeta->{x_vcs}[5] ne '' )
        {
            $versionFrom = 'generated/vcs';
            $modMeta->{version} .= $modMeta->{x_vcs}[5];

            # Generate extended version info based
            #   on base revision
            $modMeta->{x_version} =
              $modMeta->{x_file}[2] . ':'
              . (
                $modMeta->{version} =~ m/0+\.0+(?:\.0+)?$/
                ? '?'
                : $modMeta->{version}
              );
        }

        # we don't know anything about this module at all
        else {
            $versionFrom = 'generated/blank';
            $modMeta->{version} .= '0';

            # Generate generic version to fill the gap
            $modMeta->{x_version} = $modMeta->{x_file}[2] . ':?';
        }
    }

    push @{ $modMeta->{x_file} }, $versionFrom;
    push @{ $modMeta->{x_file} }, $version;

    # Do not use repeating 0 in version
    #FIXME breaks modules starting with 00_
    $modMeta->{version} =~ s/0{2,}/0/g if ( defined( $modMeta->{version} ) );
    $modMeta->{x_version} =~ s/0{2,}/0/g
      if ( defined( $modMeta->{x_version} ) );

    # Generate extended version info with added base revision
    $modMeta->{x_version} =
      $modMeta->{x_file}[2] . ':'
      . (
        $modMeta->{version} =~ m/^v0+\.0+(?:\.0+)*?$/
        ? '?'
        : $modMeta->{version}
      )
      . '-s'    # assume we only have Subversion for now
      . $modMeta->{x_vcs}[5]
      if ( !$modMeta->{x_version}
        && defined( $modMeta->{x_vcs} )
        && $modMeta->{x_vcs}[5] ne '' );

    # Add modified date to extended version
    if ( defined( $modMeta->{x_version} ) ) {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{x_version} .= '/' . $modMeta->{x_vcs}[7];

            # #FIXME can't use modified time because FHEM Update currently
            # #      does not set it based on controls_fhem.txt :-(
            # #      We need the block size from controls_fhem.txt here but
            # #      doesn't make sense to load that file here...
            # $modMeta->{x_version} .= '/' . $modMeta->{x_file}[6][9][2];
            # $modMeta->{x_version} .= '+modified'
            #   if ( defined( $modMeta->{x_vcs} )
            #     && $modMeta->{x_vcs}[16] ne $modMeta->{x_file}[6][9][0] );
        }
        else {
            $modMeta->{x_version} .= '/' . $modMeta->{x_file}[6][9][2];
        }
    }

    return "Invalid version format '$modMeta->{version}'"
      if ( defined( $modMeta->{version} )
        && $modMeta->{version} !~ m/^v\d+\.\d+\.\d+$/ );

    # meta name
    unless ( defined( $modMeta->{name} ) ) {
        if ( defined( $modMeta->{x_vcs} ) ) {
            if ( $modMeta->{x_file}[4] eq 'Global' ) {
                $modMeta->{name} = 'FHEM';
            }
            else {
                $modMeta->{name} = $modMeta->{x_file}[1];
                $modMeta->{name} =~ s/^\.\///;
                $modMeta->{name} =~ s/\/$//;
                $modMeta->{name} =~ s/FHEM\/lib//;
                $modMeta->{name} =~ s/\//::/g;
            }
        }
        if ( $modMeta->{x_file}[4] ne 'Global' ) {
            $modMeta->{name} .= '::' if ( $modMeta->{name} );
            $modMeta->{name} .= $modMeta->{x_file}[4];
        }
    }

    # add legacy POD info as Metadata
    push @{ $modMeta->{keywords} },
      "fhem-mod-$item_modtype"
      if (
        $item_modtype
        && (   !defined( $modMeta->{keywords} )
            || !grep ( "fhem-mod-$item_modtype", @{ $modMeta->{keywords} } ) )
      );
    $modMeta->{abstract} = $item_summary
      if ( $item_summary && !defined( $modMeta->{abstract} ) );
    $modMeta->{x_lang}{DE}{abstract} = $item_summary_DE
      if ( $item_summary_DE && !defined( $modMeta->{x_lang}{DE}{abstract} ) );

    $modMeta->{description} = "/./docs/commandref.html#" . $modMeta->{x_file}[4]
      unless ( defined( $modMeta->{description} ) );
    $modMeta->{x_lang}{DE}{description} =
      "/./docs/commandref_DE.html#" . $modMeta->{x_file}[4]
      unless ( defined( $modMeta->{x_lang}{DE}{description} ) );

    # Only when this package is reading its own metadata.
    # Other modules shall get this added elsewhere for performance reasons
    if ( $modMeta->{name} eq __PACKAGE__ ) {
        $modMeta->{generated_by} =
          $modMeta->{name} . ' ' . $modMeta->{version} . ', ' . TimeNow();
    }

    # If we are not running in loop, this is not time consuming for us here
    elsif ( !$runInLoop ) {
        $modMeta->{generated_by} =
          $META{name} . ' ' . __PACKAGE__->VERSION() . ', ' . TimeNow();
    }

    unless ( $modMeta->{release_status} ) {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{release_status} = 'stable';
        }
        else {
            $modMeta->{release_status} = 'unstable';
        }
    }

    unless ( $modMeta->{license} ) {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{license} = 'GPL_3';
        }
        else {
            $modMeta->{license} = 'unknown';
        }
    }

    unless ( $modMeta->{author} ) {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{author} = [ $modMeta->{x_vcs}[15] . ' <>' ];
        }
        else {
            $modMeta->{author} = ['unknown <>'];
        }
    }
    unless ( $modMeta->{x_fhem_maintainer} ) {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{x_fhem_maintainer} = [ $modMeta->{x_vcs}[15] ];
        }
        else {
            $modMeta->{x_fhem_maintainer} = ['<unknown>'];
        }
    }

    # Static meta information
    $modMeta->{dynamic_config} = 1;
    $modMeta->{'meta-spec'} = {
        "version" => 2,
        "url"     => "https://metacpan.org/pod/CPAN::Meta::Spec"
    };

    return undef;
}

1;

=pod

=encoding utf8

=begin META.json
{
  "name": "FHEM::Meta",
  "abstract": "FHEM component module to enable Metadata support",
  "description": "n/a",
  "x_lang": {
    "de": {
      "abstract": "FHEM Modul Komponente, um Metadaten Unterstützung zu aktivieren",
      "description": "n/a"
    }
  },
  "keywords": [
    "fhem-core",
    "metadata",
    "meta"
  ],
  "version": "v0.0.1",
  "release_status": "testing",
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "perl": 5.014,
        "GPUtils qw(GP_Import)": 0,
        "File::stat": 0,
        "Data::Dumper": 0,
        "Encode": 0
      },
      "recommends": {
        "JSON": 0,
        "Time::Local": 0
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_os": {
    "runtime": {
      "requires": {
      },
      "recommends": {
        "debian|ubuntu": 0
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_os_debian": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_os_ubuntu": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_nodejs": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_python": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_binary_exec": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_sudo": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_permissions_fileown": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_permissions_filemod": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "license": [
      "https://fhem.de/#License"
    ],
    "homepage": "https://fhem.de/",
    "bugtracker": {
      "web": "https://forum.fhem.de/index.php/board,48.0.html",
      "x_web_title": "FHEM Development"
    },
    "repository": {
      "type": "svn",
      "url": "https://svn.fhem.de/fhem/",
      "x_branch_master": "trunk",
      "x_branch_dev": "trunk",
      "web": "https://svn.fhem.de/"
    }
  }
}
=end META.json

=cut
