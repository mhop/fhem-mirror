# $Id$

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

our %moduleMaintainers;

our $coreUpdate;
our %corePackageUpdates;
our %coreFileUpdates;

our %moduleUpdates;
our %packageUpdates;
our %fileUpdates;

sub import(@) {
    my $pkg = caller(0);

    # Initially load information
    #   to be ready for meta analysis
    __GetUpdatedata() unless ( defined($coreUpdate) );
    __GetMaintainerdata() unless ( keys %moduleMaintainers > 0 );

    if ( $pkg ne "main" ) {
    }
}

# Loads Metadata for single module, based on filename
sub InitMod($$;$) {
    my ( $filePath, $modHash, $runInLoop ) = @_;

    my $ret = __PutMetadata( $filePath, $modHash, 1, $runInLoop );

    if ($@) {
        Log 1, __PACKAGE__ . "::InitMod: ERROR: \$\@:\n" . $@;
        return "$@";
    }
    elsif ($ret) {
        Log 1, __PACKAGE__ . "::InitMod: ERROR: \$ret:\n" . $ret;
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

# Load Metadata for a list of modules
sub Load(;$$) {
    my ( $modList, $reload ) = @_;
    my $t = TimeNow();
    my $v = __PACKAGE__->VERSION();
    my @rets;

    my $unused = 0;
    my @lmodules;

    # if modList is undefined or is equal to '1'
    if ( !$modList || ( !ref($modList) && $modList eq '1' ) ) {
        $unused = 1 if ( $modList && $modList eq '1' );

        foreach ( keys %modules ) {

            # Only process loaded modules
            #   unless unused modules were
            #   explicitly requested
            push @lmodules,
              $_
              if (
                $unused
                || ( defined( $modules{$_}{LOADED} )
                    && $modules{$_}{LOADED} eq '1' )
              );
        }
    }

    # if a single module name was given
    elsif ( !ref($modList) ) {
        push @lmodules, $modList;
    }

    # if a list of module names was given
    elsif ( ref($modList) eq 'ARRAY' ) {
        foreach ( @{$modList} ) {
            push @lmodules, $_;
        }
    }

    # if a hash was given, assume every
    #   key is a module name
    elsif ( ref($modList) eq 'HASH' ) {
        foreach ( keys %{$modList} ) {
            push @lmodules, $_;
        }
    }

    # Wrong method use
    else {
        $@ = __PACKAGE__ . "::Load: ERROR: Unknown parameter value";
        Log 1, $@;
        return "$@";
    }

    if ($reload) {
        __GetUpdatedata();
        __GetMaintainerdata();
    }

    foreach my $modName (@lmodules) {

        # Abort when module file was not indexed by
        #   fhem.pl before.
        # Only continue if META was not loaded
        #   or should explicitly be reloaded.
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

        my $ret = InitMod( $filePath, $modules{$modName}, 1 );
        push @rets, $@   if ( $@   && $@ ne '' );
        push @rets, $ret if ( $ret && $ret ne '' );

        $modules{$modName}{META}{generated_by} = $META{name} . " $v, $t"
          if ( defined( $modules{$modName}{META} ) );

        foreach my $devName ( devspec2array( 'TYPE=' . $modName ) ) {
            SetInternals( $defs{$devName} );
        }
    }

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

    $devHash->{'.FhemMetaInternals'} = 1;
    __CopyMetaToInternals( $devHash, $modMeta );

    return 1;
}

# Get metadata
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
    return unless ( defined( $devHash->{'.FhemMetaInternals'} ) );
    return unless ( defined($modMeta) && ref($modMeta) eq "HASH" );

    $devHash->{FVERSION} = $modMeta->{x_version}
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

# Extract metadata from FHEM module file
sub __GetMetadata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ( $filePath, $modMeta, $runInLoop, $metaSection ) = @_;
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
    if ( $filePath =~ m/^((?:\.\/)?(.+\/)((?:(\d+)_)?(.+)\.(.+)))$/ ) {
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
        my %json;

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
        my $currentJson    = '';
        while ( my $l = <$fh> ) {
            next if ( $l eq '' || $l =~ m/^\s+$/ );

            # # Track comments section at the beginning of the document
            # if ( $searchComments && $l !~ m/^#|\s*$/ ) {
            #     $searchComments = 0;
            # }

            # extract VCS info from $Id:
            if (   $skip
                && !@vcs
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
#                 $authorName = '' unless ($authorName);
#             }

            ######
            # get legacy style version directly from
            #  within sourcecode if we are lucky
            #

            # via $VERSION|$version variable
            elsif ($skip
                && !$version
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
            elsif ($skip
                && !$version
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
            elsif ($skip
                && !$item_modtype
                && $l =~ m/^=item\s+(device|helper|command)\s*$/i )
            {
                return "=item (device|helper|command) pod must occur only once"
                  if ($item_modtype);
                $item_modtype = lc($1);
            }
            elsif ($skip
                && !$item_summary_DE
                && $l =~ m/^=item\s+(summary_DE)\s+(.+)$/i )
            {
                return "=item summary_DE pod must occur only once"
                  if ($item_summary_DE);
                $item_summary_DE =
                  ( $encoding && $encoding eq "utf8" ) ? encode_utf8($2) : $2;
            }
            elsif ($skip
                && !$item_summary
                && $l =~ m/^=item\s+(summary)\s+(.+)$/i )
            {
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
            elsif ($skip
                && $l =~
m/^=for\s+:application\/json;q=META\.json\s+([^\s\.]+\.[^\s\.]+)\s*$/i
              )
            {
                $skip               = 0;
                $currentJson        = $1;
                $json{$currentJson} = '';
            }
            elsif ( !$skip
                && $l =~ m/^=end\s+:application\/json\;q=META\.json/i )
            {
                $skip = 1;
            }
            elsif ( !$skip ) {
                $json{$currentJson} .= $l;
            }
        }

        # if we were unable to get version,
        #   let's also try the initial comments block
        unless ( keys %json > 0 || $version ) {
            seek $fh, 0, 0;

            while ( my $l = <$fh> ) {
                next if ( $l eq '' || $l =~ m/^\s+$/ );

                # Only seek the document until code starts
                if ( $l !~ m/^#/ && $l !~ m/^=[A-Za-z]+/i ) {
                    last;
                }

                # via Version:
                elsif ( !$version
                    && $l =~
m/(^#\s+Version:?\s+[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?))(?:\s+.*)?)$/i
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

                # via changelog, assuming latest version comes first;
                #   might include false-positives
                elsif ( !$version
                    && $l =~
m/(^#\s+(?:\d{1,2}\.\d{1,2}\.(?:\d{2}|\d{4})\s+)?[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?))(?:\s+.*)?)$/i
                  )
                {
                    my $extr = $2;

                    # filter false-positives that are actually dates
                    next
                      if ( $extr =~ m/^\d{2}\.\d{2}\.(\d{2})$/ && $1 ge 13 );

                    $version =
                      ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
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

        if ( keys %json > 0 ) {
            eval {
                require JSON;
                1;
            };

            if ( !$@ ) {
                foreach ( keys %json ) {
                    next
                      if (
                        (
                            !$metaSection
                            && lc($_) ne lc( $modMeta->{x_file}[2] )
                        )
                        || ( $metaSection && $_ ne $metaSection )
                      );

                    eval {
                        my $t;
                        if ( $encoding ne 'latin1' ) {
                            if ( $encoding eq "utf8" ) {
                                $t = encode_utf8( $json{$_} );
                            }
                            elsif ( $encoding =~
                                /^(latin1|utf8|koi8-r|ShiftJIS|big5)$/ )
                            {
                                $@ = "Encoding type $encoding is not supported";
                            }
                            else {
                                $@ = "Invalid encoding type $encoding";
                            }
                        }
                        else {
                            $t = $json{$_};
                        }

                        return "$@" if ($@);

                        my $decoded = JSON::decode_json($t);
                        while ( my ( $k, $v ) = each %{$decoded} ) {
                            $modMeta->{$k} = $v;
                        }

                        1;
                    } or do {
                        $@ = "$_: Error while parsing META.json: $@";
                        return "$@";
                    };
                }
                return undef if ($metaSection);
            }
            else {
                $@ = undef;
            }
        }

        # special place for fhem.pl is this module file
        elsif ( $modMeta->{x_file}[2] eq 'fhem.pl' ) {
            my %fhempl;
            my $ret = __GetMetadata( __FILE__, \%fhempl, undef, 'fhem.pl' );
            delete $fhempl{x_file};

            while ( my ( $k, $v ) = each %fhempl ) {
                $modMeta->{$k} = $v;
            }
        }

        # Detect prereqs if not provided via META.json
        if ( !defined( $modMeta->{prereqs} ) ) {
            eval {
                require Perl::PrereqScanner::NotQuiteLite;
                1;
            };

            if ( !$@ ) {
                my $scanner = Perl::PrereqScanner::NotQuiteLite->new(
                    parsers  => [qw/:installed -UniversalVersion/],
                    suggests => 1,
                );
                my $context      = $scanner->scan_file($filePath);
                my $requirements = $context->requires;
                my $recommends   = $context->recommends;
                my $suggestions = $context->suggests;    # requirements in evals

                $modMeta->{x_prereqs_src} = 'scanner';

                # requires
                foreach ( keys %{ $requirements->{requirements} } ) {
                    if (
                        defined( $requirements->{requirements}{$_}{minimum} )
                        && defined(
                            $requirements->{requirements}{$_}{minimum}{original}
                        )
                      )
                    {
                        $modMeta->{prereqs}{runtime}{requires}{$_} =
                          $requirements->{requirements}{$_}{minimum}{original};
                    }
                    else {
                        $modMeta->{prereqs}{runtime}{requires}{$_} = 0;
                    }
                }

                # recommends
                foreach ( keys %{ $recommends->{requirements} } ) {
                    if (
                        defined( $recommends->{requirements}{$_}{minimum} )
                        && defined(
                            $recommends->{requirements}{$_}{minimum}{original}
                        )
                      )
                    {
                        $modMeta->{prereqs}{runtime}{recommends}{$_} =
                          $recommends->{requirements}{$_}{minimum}{original};
                    }
                    else {
                        $modMeta->{prereqs}{runtime}{recommends}{$_} = 0;
                    }
                }

                # suggests
                foreach ( keys %{ $suggestions->{requirements} } ) {
                    if (
                        defined( $suggestions->{requirements}{$_}{minimum} )
                        && defined(
                            $suggestions->{requirements}{$_}{minimum}{original}
                        )
                      )
                    {
                        $modMeta->{prereqs}{runtime}{suggests}{$_} =
                          $suggestions->{requirements}{$_}{minimum}{original};
                    }
                    else {
                        $modMeta->{prereqs}{runtime}{suggests}{$_} = 0;
                    }
                }
            }
            else {
                $@ = undef;
            }
        }
        else {
            $modMeta->{x_prereqs_src} = 'META.json';
        }
    }

    # Get some other info about fhem.pl
    if ( $modMeta->{x_file}[2] eq 'fhem.pl' ) {
        $versionFrom = 'attr/featurelevel+vcs';
        $version     = 'v' . $1 . '.' . $vcs[5]
          if ( $modules{'Global'}{AttrList} =~ m/\W*featurelevel:([^,]+)/ );
        $modMeta->{version} = $version;
    }

    ########
    # Metadata refactoring starts here
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
        }

        # we don't know anything about this module at all
        else {
            $versionFrom = 'generated/blank';
            $modMeta->{version} .= '0';
        }
    }

    push @{ $modMeta->{x_file} }, $versionFrom;
    push @{ $modMeta->{x_file} }, $version;

    # Do not use repeating 0 in version
    $modMeta->{version} = version->parse( $modMeta->{version} )->stringify
      if ( defined( $modMeta->{version} ) );

    $@ .=
      $modMeta->{x_file}[2] . ": Invalid version format '$modMeta->{version}'"
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
    $modMeta->{x_lang}{de}{abstract} = $item_summary_DE
      if ( $item_summary_DE && !defined( $modMeta->{x_lang}{de}{abstract} ) );

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

    # mandatory
    unless ( $modMeta->{description} ) {
        $modMeta->{description} = 'n/a';
    }

    # mandatory
    unless ( $modMeta->{release_status} ) {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{release_status} = 'stable';
        }
        else {
            $modMeta->{release_status} = 'unstable';
        }
    }

    # mandatory
    unless ( $modMeta->{license} ) {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{license} = 'GPL_2';
        }
        else {
            $modMeta->{license} = 'unknown';
        }
    }

    # mandatory
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

    unless ( defined( $modMeta->{resources} )
        && defined( $modMeta->{resources}{license} ) )
    {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{resources}{license} =
              ['https://fhem.de/#License'];
        }
    }

    unless ( defined( $modMeta->{resources} )
        && defined( $modMeta->{resources}{x_wiki} ) )
    {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{resources}{x_wiki}{web}     = 'https://wiki.fhem.de/';
            $modMeta->{resources}{x_wiki}{modpath} = 'wiki/';
        }
    }

    unless ( defined( $modMeta->{resources} )
        && defined( $modMeta->{resources}{x_commandref} ) )
    {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{resources}{x_commandref}{web} =
              'https://fhem.de/commandref.html';
            $modMeta->{resources}{x_commandref}{modpath} = '#';
        }
    }

    unless ( defined( $modMeta->{resources} )
        && defined( $modMeta->{resources}{x_support_community} ) )
    {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{resources}{x_support_community}{web} =
              'https://forum.fhem.de/';
        }
    }

    unless ( defined( $modMeta->{resources} )
        && defined( $modMeta->{resources}{repository} ) )
    {
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{resources}{repository}{type} = 'svn';
            $modMeta->{resources}{repository}{web} =
              'https://svn.fhem.de/trac/browser/';
            $modMeta->{resources}{repository}{url} =
              'https://svn.fhem.de/fhem/';
            $modMeta->{resources}{repository}{x_branch_master} = 'trunk';
            $modMeta->{resources}{repository}{x_branch_dev}    = 'trunk';
            $modMeta->{resources}{repository}{x_filepath}      = 'fhem/FHEM/';
        }
    }

    # Static meta information
    $modMeta->{dynamic_config} = 1;
    $modMeta->{'meta-spec'} = {
        "version" => 2,
        "url"     => "https://metacpan.org/pod/CPAN::Meta::Spec"
    };

    # generate x_version
    __SetXVersion($modMeta);

    return "$@" if ($@);
    return undef;
}

sub __GetMaintainerdata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my $fh;
    %moduleMaintainers = ();

    if ( open( $fh, '<' . $attr{global}{modpath} . '/MAINTAINER.txt' ) ) {
        my $skip = 1;
        while ( my $l = <$fh> ) {
            $skip = 0 if ( $l =~ m/^===+$/ );
            next if ($skip);

            my @line = map {
                s/^\s+//;    # strip leading spaces
                s/\s+$//;    # strip trailing spaces
                $_           # return the modified string
            } split( "[ \t][ \t]*", $l, 3 );

            if ( $line[0] =~ m/^((.+\/)?((?:(\d+)_)?(.+)\.(.+)))$/ ) {

                # Ignore all files that are not a main module for now
                next unless ($4);

                my @maintainer;
                $maintainer[0][0] = $1;    # complete match
                $maintainer[0][1] = $2;    # relative file path
                $maintainer[0][2] = $3;    # file name
                $maintainer[0][3] = $4;    # order number, may be undefined
                $maintainer[0][4] =
                  $3 eq 'fhem.pl' ? 'Global' : $5;    # FHEM module name
                $maintainer[0][5] = $6;               # file extension
                $maintainer[1]    = $line[1];         # Maintainer alias name
                $maintainer[2]    = $line[2];         # Forum support section

                if ( defined( $moduleMaintainers{ $maintainer[0][4] } ) ) {
                    Log 1,
                        __PACKAGE__
                      . "::__GetMaintainerdata ERROR: Duplicate entry:\n"
                      . ' 1st: '
                      . $moduleMaintainers{ $maintainer[0][4] }[0][0] . ' '
                      . $moduleMaintainers{ $maintainer[0][4] }[1] . ' '
                      . $moduleMaintainers{ $maintainer[0][4] }[2]
                      . "\n 2nd: "
                      . join( ' ', @line );
                }
                else {
                    $moduleMaintainers{ $maintainer[0][4] } = \@maintainer;
                }
            }
        }

        close($fh);
    }
}

sub __GetUpdatedata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my $fh;
    my @fileList;
    $coreUpdate         = undef;
    %corePackageUpdates = ();
    %coreFileUpdates    = ();
    %moduleUpdates  = ();
    %packageUpdates = ();
    %fileUpdates    = ();

    # if there are 3rd party source file repositories involved
    if ( open( $fh, '<' . $attr{global}{modpath} . '/FHEM/controls.txt' ) ) {
        while ( my $l = <$fh> ) {
            push @fileList, $1 if ( $l =~ m/([^\/\s]+)$/ );
        }
        close($fh);
    }

    # FHEM core update control file only
    else {
        push @fileList, 'controls_fhem.txt';
    }

    # loop through control files
    foreach my $file (@fileList) {
        if ( open( $fh, '<' . $attr{global}{modpath} . '/FHEM/' . $file ) ) {
            my $filePrefix;
            my $srcRepoName;
            my $fileExtension;

            if ( $file =~ m/^([^_\s\.]+)_([^_\s\.]+)\.([^_\s\.]+)$/ ) {
                $filePrefix    = $1;
                $srcRepoName   = $2;
                $fileExtension = $3;
            }

            while ( my $l = <$fh> ) {

                if ( $l =~
m/^((\S+) (((....)-(..)-(..))_((..):(..):(..))) (\d+) (?:\.\/)?((.+\/)?((?:(\d+)_)?(.+)\.(.+))))$/
                  )
                {
                    # this is a FHEM core update
                    #   under path ./
                    if ( $2 eq 'UPD' && !$14 ) {

                        # core updates may only origin
                        #  from original fhem source repo
                        if ( $srcRepoName ne 'fhem' ) {
                            Log 1,
                                __PACKAGE__
                              . "::__GetUpdatedata: ERROR: Core file '"
                              . $13
                              . '\' can only be updated from FHEM original update server';
                            next;
                        }

                        my @update;
                        $update[0]  = $srcRepoName;     # source repository name
                        $update[1]  = $1;               # complete match
                        $update[2]  = $2;               # controls command
                        $update[3]  = $4 . ' ' . $8;    # date and time
                        $update[4]  = $4;               # date
                        $update[5]  = $5;               # year
                        $update[6]  = $6;               # month
                        $update[7]  = $7;               # day
                        $update[8]  = $8;               # time
                        $update[9]  = $9;               # hour
                        $update[10] = $10;              # minute
                        $update[11] = $11;              # second
                        $update[12] = $12;              # size in bytes
                        $update[13] = $13;              # relative file path
                        $update[14] = $14;              # relative path
                        $update[15] = $15;              # file name
                        $update[16] = $16;    # order number, may be undefined
                        $update[17] = $17;    # FHEM module name
                        $update[18] = $18;    # file extension

                        # this is a FHEM core update
                        if ( $15 eq 'fhem.pl' ) {
                            $coreUpdate = undef;
                            $coreUpdate = \@update;
                        }

                        # this is a FHEM core Perl package update
                        elsif ( $18 eq 'pm' ) {
                            delete $corePackageUpdates{$17}
                              if ( defined( $corePackageUpdates{$17} ) );
                            $corePackageUpdates{$17} = \@update;
                        }

                        # this is a FHEM core file update
                        else {
                            # our %coreFileUpdates;
                        }
                    }

                    # this is a FHEM module or Perl package update
                    #   under path ./FHEM/
                    elsif ( $2 eq 'UPD' && $14 eq 'FHEM/' && $18 eq 'pm' ) {
                        my @update;
                        $update[0]  = $srcRepoName;     # source repository name
                        $update[1]  = $1;               # complete match
                        $update[2]  = $2;               # controls command
                        $update[3]  = $4 . ' ' . $8;    # date and time
                        $update[4]  = $4;               # date
                        $update[5]  = $5;               # year
                        $update[6]  = $6;               # month
                        $update[7]  = $7;               # day
                        $update[8]  = $8;               # time
                        $update[9]  = $9;               # hour
                        $update[10] = $10;              # minute
                        $update[11] = $11;              # second
                        $update[12] = $12;              # size in bytes
                        $update[13] = $13;              # relative file path
                        $update[14] = $14;              # relative path
                        $update[15] = $15;              # file name
                        $update[16] = $16;    # order number, may be undefined
                        $update[17] = $17;    # FHEM module name
                        $update[18] = $18;    # file extension

                        # this is a FHEM module update
                        if ($16) {
                            if ( defined( $moduleUpdates{$17} ) ) {

                                # We're not overwriting update info
                                #  if source repo name does not match
                                if ( ref( $moduleUpdates{$17} ) eq 'ARRAY'
                                    && $moduleUpdates{$17}[0] ne $update[0] )
                                {
                                    Log 1,
                                        __PACKAGE__
                                      . "::__GetUpdatedata: ERROR: "
                                      . $update[13]
                                      . ' belongs to source repository "'
                                      . $moduleUpdates{$17}[0]
                                      . '". Ignoring identical file name from source repository '
                                      . $update[0];
                                    next;
                                }

                                else {
                                    delete $moduleUpdates{$17};
                                }
                            }

                            $moduleUpdates{$17} = \@update;
                        }

                        # this is a FHEM Perl package update
                        else {
                            if ( defined( $packageUpdates{$17} ) ) {

                                # We're not overwriting update info
                                #  if source repo name does not match
                                if ( ref( $packageUpdates{$17} ) eq 'ARRAY'
                                    && $packageUpdates{$17}[0] ne $update[0] )
                                {
                                    Log 1,
                                        __PACKAGE__
                                      . "::__GetUpdatedata: ERROR: "
                                      . $update[13]
                                      . ' belongs to source repository "'
                                      . $packageUpdates{$17}[0]
                                      . '". Ignoring identical file name from source repository '
                                      . $update[0];
                                    next;
                                }

                                else {
                                    delete $packageUpdates{$17};
                                }
                            }

                            $packageUpdates{$17} = \@update;
                        }
                    }

                    # this is a FHEM file update
                    #   under any other path
                    else {
                        # our %fileUpdates;
                    }
                }
            }
            close($fh);
        }
    }
}

# Set x_version based on existing metadata
sub __SetXVersion {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ($modMeta) = @_;
    my $modName = $modMeta->{x_file}[4];

    delete $modMeta->{x_version} if ( defined( $modMeta->{x_version} ) );

    # Special handling for fhem.pl
    if ( $modMeta->{x_file}[2] eq 'fhem.pl' ) {
        $modMeta->{x_version} = 'fhem.pl:' . $modMeta->{version};
    }

    # Generate extended version info based
    #   on base revision
    elsif ( defined( $modMeta->{x_vcs} ) ) {

        $modMeta->{x_version} =
          $modMeta->{x_file}[2] . ':'
          . (
            $modMeta->{version} =~ m/^v0+\.0+(?:\.0+)*?$/
            ? '?'
            : $modMeta->{version}
          )
          . (
            $modMeta->{x_file}[7] ne 'generated/vcs'
              && $modMeta->{x_vcs}[5] ne ''
            ? '-s'    # assume we only have Subversion for now
              . $modMeta->{x_vcs}[5]
            : ''
          );
    }

    # Generate generic version to fill the gap
    elsif ( $modMeta->{x_file}[7] eq 'generated/blank' ) {
        $modMeta->{x_version} = $modMeta->{x_file}[2] . ':?';
    }

    if ( defined( $modMeta->{x_version} ) ) {

        # Add modified date to extended version
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
}

1;

=pod

=encoding utf8

=for :application/json;q=META.json Meta.pm
{
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
  "version": "v0.1.6",
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
        "FHEM": 5.00918623,
        "perl": 5.014,
        "GPUtils": 0,
        "File::stat": 0,
        "Data::Dumper": 0,
        "Encode": 0
      },
      "recommends": {
        "JSON": 0,
        "Perl::PrereqScanner::NotQuiteLite": 0,
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
    "bugtracker": {
      "web": "https://forum.fhem.de/index.php/board,48.0.html",
      "x_web_title": "FHEM Forum: FHEM Development"
    }
  }
}
=end :application/json;q=META.json

=for :application/json;q=META.json fhem.pl
{
  "abstract": "FHEM® is a Perl server for house automation",
  "description": "FHEM® (registered trademark) is a GPL'd perl server for house automation. It is used to automate some common tasks in the household like switching lamps / shutters / heating / etc. and to log events like temperature / humidity / power consumption.\\n\\nThe program runs as a server, you can control it via web or smartphone frontends, telnet or TCP/IP directly.\\n\\nIn order to use FHEM you'll need a 24/7 server (NAS, RPi, PC, MacMini, etc) with a perl interpreter and some attached hardware like the CUL-, EnOcean-, Z-Wave-USB-Stick, etc. to access the actors and sensors.\\n\\nIt is pronounced without the h, like in feminine.",
  "x_lang": {
    "de": {
      "abstract": "FHEM® ist ein Perl Server zur Hausautomatisierung",
      "description": "FHEM® (eingetragene Marke) ist ein in Perl geschriebener, GPL lizensierter Server für die Heimautomatisierung. Man kann mit FHEM häufig auftretende Aufgaben automatisieren, wie z.Bsp. Lampen / Rollladen / Heizung / usw. schalten, oder Ereignisse wie Temperatur / Feuchtigkeit / Stromverbrauch protokollieren und visualisieren.\\n\\nDas Programm läuft als Server, man kann es über WEB, dedizierte Smartphone Apps oder telnet bedienen, TCP Schnittstellen für JSON und XML existieren ebenfalls.\\n\\nUm es zu verwenden benötigt man einen 24/7 Rechner (NAS, RPi, PC, MacMini, etc) mit einem Perl Interpreter und angeschlossene Hardware-Komponenten wie CUL-, EnOcean-, Z-Wave-USB-Stick, etc. für einen Zugang zu den Aktoren und Sensoren.\\n\\nAusgesprochen wird es ohne h, wie bei feminin."
    }
  },
  "keywords": [
    "fhem",
    "fhem-core"
  ],
  "x_copyright": "FHEM e.V., Rudolf König <vorstand@fhem.de>",
  "author": [
    "Rudolf König <r.koenig@koeniglich.de>"
  ],
  "x_fhem_maintainer": [
    "rudolfkoenig"
  ],
  "x_fhem_dependant_modules": [
  ],
  "x_fhem_parent_modules": [
  ],
  "x_fhem_child_modules": [
    "apptime", "backup", "cmdalias", "configdb", "copy", "count", "CULflash", "fhemdebug", "fheminfo", "IF", "MSG", "notice", "restore", "setuuid", "template", "update", "uptime", "version", "XmlList"
  ],
  "x_fhem_master_modules": [
  ],
  "x_fhem_slave_modules": [
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "perl": 5.006002,
        "constant": 0,
        "File::Copy": 0,
        "IO::Socket": 0,
        "IO::Socket::INET": 0,
        "lib": 0,
        "Math::Trig": 0,
        "POSIX": 0,
        "RTypes": 0,
        "Scalar::Util": 0,
        "strict": 0,
        "Time::HiRes": 0,
        "vars": 0,
        "warnings": 0
      },
      "recommends": {
        "Compress::Zlib": 0,
        "IO::Socket::INET6": 0,
        "Socket6": 0,
        "TimeSeries": 0
      },
      "suggests": {
        "Compress::Zlib": 0,
        "FHEM::WinService": 0,
        "IO::Socket::INET6": 0,
        "Socket6": 0
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
        "perl-base": ">= 5.6.2",
        "sqlite3": 0,
        "libcgi-pm-perl": 0,
        "libdbd-sqlite3-perl": 0,
        "libdevice-serialport-perl": ">= 1.0",
        "libio-socket-ssl-perl": ">= 1.0",
        "libjson-perl": 0,
        "libtext-diff-perl": 0,
        "libwww-perl": ">= 1.0"
      },
      "recommends": {
        "ttf-liberation": 0,
        "libarchive-extract-perl": 0,
        "libarchive-zip-perl": 0,
        "libgd-graph-perl": 0,
        "libgd-text-perl": 0,
        "libimage-info-perl": 0,
        "libimage-librsvg-perl": 0,
        "libio-socket-inet6-perl": 0,
        "liblist-moreutils-perl": 0,
        "libmail-imapclient-perl": 0,
        "libmime-base64-perl": 0,
        "libnet-server-perl": 0,
        "libsocket6-perl": 0,
        "libtext-csv-perl": 0,
        "libtimedate-perl": 0,
        "libusb-1.0-0-dev": 0,
        "libxml-simple-perl": 0
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
    "x_copyright": {
      "web": "https://verein.fhem.de/"
    },
    "x_privacy": {
      "web": "https://fhem.de/Impressum.html#Datenschutz",
      "title": "FHEM Data Privacy Statement"
    },
    "homepage": "https://fhem.de/",
    "repository": {
      "type": "svn",
      "web": "https://svn.fhem.de/trac/browser/",
      "url": "https://svn.fhem.de/fhem/",
      "x_branch_master": "trunk",
      "x_branch_dev": "trunk",
      "x_filepath": "fhem/"
    }
  }
}
=end :application/json;q=META.json

=cut
