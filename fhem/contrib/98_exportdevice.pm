# $Id: 98_exportdevice.pm 12047 2016-08-22 08:06:24Z loredo $

package main;
use strict;
use warnings;

no if $] >= 5.017011, warnings => 'experimental';

sub CommandExportdevice($$);

########################################
sub exportdevice_Initialize($$) {
    my %hash = (
        Fn  => "CommandExportdevice",
        Hlp => "[devspec] [quote] [dependent]",
    );
    $cmds{exportdevice} = \%hash;
}

########################################
sub CommandExportdevice($$) {
    my ( $cl, $param ) = @_;
    my @a         = split( "[ \t][ \t]*", $param );
    my $quote     = 0;
    my $dependent = 0;
    my $str       = "";

    return "Usage: exportdevice [devspec] [quote] [dependent]"
      if ( $a[0] eq "?" );

    $dependent = 1
      if ( $a[0] eq "dependent"
        || $a[1] eq "dependent"
        || $a[1] eq "dependent" );

    $quote = 1
      if ( $a[0] eq "quote" || $a[1] eq "quote" || $a[2] eq "quote" );

    $a[0] = ".*"
      if ( int(@a) < 1
        || $a[0] eq "quote"
        || $a[0] eq "dependent" );

    my $mname = "";
    my @objects;
    foreach my $d ( devspec2array( $a[0], $cl ) ) {
        next if ( !$defs{$d} || $d ~~ @objects );

        push( @objects, $d );

        # w/ module header
        if ( $mname ne $defs{$d}{TYPE} ) {
            $mname = $defs{$d}{TYPE};
            $str .= CommandExportdeviceGetBlock( $d, $quote, 1 );
        }

        # w/o module header
        else {
            $str .= CommandExportdeviceGetBlock( $d, $quote );
        }

        if ($dependent) {

            # dependent objects
            my $dc = 0;
            foreach my $do ( CommandExportdeviceGetDependentObjects($d) ) {
                next if ( !$do || $do eq $d || $do ~~ @objects );

                push( @objects, $do );
                $dc++;

                $str .= "#+++ Dependent objects"
                  if $dc == 1;

                # w/ module header
                if ( $mname ne $defs{$do}{TYPE} ) {
                    $mname = $defs{$do}{TYPE};
                    my $s = CommandExportdeviceGetBlock( $do, $quote, 1 );
                    $s =~ s/\n/\n    /g;
                    $str .= $s;
                }

                # w/o module header
                else {
                    my $s = CommandExportdeviceGetBlock( $do, $quote );
                    $s =~ s/\n/\n    /g;
                    $str .= $s;
                }
            }
        }

    }

    my $return;
    $return = "#\n# Flat Export created by "
      if ( !$quote );
    $return = "#\n# Quoted Export created by "
      if ($quote);

    return
        $return
      . AttrVal( "global", "version", "fhem.pl:?/?" )
      . "\n# at "
      . TimeNow() . "\n#"
      . $str . "\n\n"
      if ( $str ne "" );
    return "No device found: $a[0]";
}

sub CommandExportdeviceGetBlock($$;$) {
    my ( $d, $quote, $h ) = @_;
    my $str = "";
    return if ( !$defs{$d} );

    # module header (only once)
    if ($h) {
        my $ver = fhem( "version " . $defs{$d}{TYPE}, 1 );
        $ver =~ s/\n+/\n# /g;
        $ver =~ s/^/# /g;
        $str .= "\n\n### TYPE: $defs{$d}{TYPE}\n$ver\n\n";
    }

    # device definition
    if ( $d ne "global" ) {
        my $def = $defs{$d}{DEF};
        if ( defined($def) ) {
            if ($quote) {
                $def =~ s/;/;;/g;
                $def =~ s/\n/\\\n/g;
            }
            $str .= "define $d $defs{$d}{TYPE} $def\n";
        }
        else {
            $str .= "define $d $defs{$d}{TYPE}\n";
        }
    }

    # device attributes
    foreach my $a (
        sort {
            return -1
              if ( $a eq "userattr" );    # userattr must be first
            return 1 if ( $b eq "userattr" );
            return $a cmp $b;
        } keys %{ $attr{$d} }
      )
    {
        next
          if ( $d eq "global"
            && ( $a eq "configfile" || $a eq "version" ) );
        my $val = $attr{$d}{$a};
        if ($quote) {
            $val =~ s/;/;;/g;
            $val =~ s/\n/\\\n/g;
        }
        $str .= "attr $d $a $val\n";
    }

    $str .= "\n";

    return $str;
}

sub CommandExportdeviceGetDependentObjects($) {
    my ($d) = @_;
    my @dob;

    foreach my $dn ( sort keys %defs ) {
        next if ( !$dn || $dn eq $d );
        my $dh = $defs{$dn};
        if (   ( $dh->{DEF} && $dh->{DEF} =~ m/\b$d\b/ )
            || ( $defs{$d}{DEF} && $defs{$d}{DEF} =~ m/\b$dn\b/ ) )
        {
            push( @dob, $dn );
        }
    }

    return @dob;
}

1;

=pod
=item command
=item summary exports definition and attributes of devices
=item summary_DE exportiert die Definition und die Attribute von Ger&auml;ten
=begin html

<a name="exportdevice"></a>
<h3>exportdevice</h3>
<ul>
  <code>exportdevice [devspec] [quote] [dependent]</code>
  <br><br>
  Output a complete device and attribute definition of FHEM devices. This is
  one of the few commands which return a string in a normal case.<br>
  See the <a href="#devspec">Device specification</a> section for details on
  &lt;devspec&gt;.
  <br><br>
  The output can be used for reimport using FHEMWEB or telnet command line.<br>
  The optional paramter "quote" may be added to receive fhem.cfg compatible output.
  <br><br>

  Example:
  <pre><code>  fhem> exportdevice Office

# 
# Export created by fhem.pl:12022/2016-08-21 
# on 2016-08-22 01:02:59 
# 


### TYPE: FS20 
# File       Rev   Last Change 
# 10_FS20.pm 11984 2016-08-19 12:47:50Z rudolfkoenig 

define Office FS20 1234 12 
attr Office userattr Light Light_map structexclude 
attr Office IODev CUL_0 
attr Office Light AllLights 
attr Office group Single Lights 
attr Office icon light_office 
attr Office model fs20st 
attr Office room Light

  </code></pre>
</ul>

=end html
=begin html_DE

<a name="exportdevice"></a>
<h3>exportdevice</h3>
<ul>
  <code>exportdevice [devspec] [quote] [dependent]</code>
  <br><br>
  Gibt die komplette Definition und Attribute eines FHEM Ger&auml;tes aus. Dies
  ist eines der wenigen Befehle, die im Normalfall eine Zeichenkette ausgeben.<br>
  Siehe den Abschnitt &uuml;ber <a href="#devspec">Ger&auml;te-Spezifikation</a>
  f&uuml;r Details der &lt;devspec&gt;.
  <br><br>
  Die Ausgabe kann f&uuml;r einen Reimport mittels FHEMWEB oder Telnet
  Kommandozeile verwendet werden.<br>
  Der optionale Parameter "quote" kann genutzt werden, um eine fhem.cfg
  kompatible Ausgabe zu erhalten.
  <br><br>
  Beispiel:
  <pre><code>  fhem> exportdevice Office

# 
# Export created by fhem.pl:12022/2016-08-21 
# on 2016-08-22 01:02:59 
# 


### TYPE: FS20 
# File       Rev   Last Change 
# 10_FS20.pm 11984 2016-08-19 12:47:50Z rudolfkoenig 

define Office FS20 1234 12 
attr Office userattr Light Light_map structexclude 
attr Office IODev CUL_0 
attr Office Light AllLights 
attr Office group Single Lights 
attr Office icon light_office 
attr Office model fs20st 
attr Office room Light

  </code></pre>
</ul>

=end html_DE
=cut
