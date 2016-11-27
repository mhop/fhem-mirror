
# $Id$

package main;

use strict;
use warnings;

use JSON;

sub
alexa_Initialize($)
{
  my ($hash) = @_;

  #$hash->{ReadFn}   = "alexa_Read";

  $hash->{DefFn}    = "alexa_Define";
  #$hash->{NOTIFYDEV} = "global";
  #$hash->{NotifyFn} = "alexa_Notify";
  $hash->{UndefFn}  = "alexa_Undefine";
  $hash->{SetFn}    = "alexa_Set";
  $hash->{GetFn}    = "alexa_Get";
  #$hash->{AttrFn}   = "alexa_Attr";
  $hash->{AttrList} = "alexaMapping:textField-long articles prepositions $readingFnAttributes";
}

#####################################

sub
alexa_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> alexa"  if(@a != 2);

  my $name = $a[0];
  $hash->{NAME} = $name;

  my $d = $modules{$hash->{TYPE}}{defptr};
  return "$hash->{TYPE} device already defined as $d->{NAME}." if( defined($d) );
  $modules{$hash->{TYPE}}{defptr} = $hash;

  addToAttrList("$hash->{TYPE}Name");

  $hash->{STATE} = 'active';

  return undef;
}

sub
alexa_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  return undef;
}

sub
alexa_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}

sub
alexa_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "reload";

  if( $cmd eq 'reload' ) {
    $hash->{".triggerUsed"} = 1;
    if( @args ) {
      FW_directNotify($name, "reload $args[0]");
    } else {
      FW_directNotify($name, 'reload');
    }

    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
alexa_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "customSlotTypes";

  if( lc($cmd) eq 'customslottypes' ) {
    if( $hash->{CL} ) {
      FW_directNotify($name, "customSlotTypes $hash->{CL}{NAME}");
    } else {
      FW_directNotify($name, 'customSlotTypes');
    }

    my %mappings;
    if( my $mappings = AttrVal( $name, 'alexaMapping', undef ) ) {
      foreach my $mapping ( split( / |\n/, $mappings ) ) {
        next if( !$mapping );
        next if( $mapping =~ /^#/ );

        my %characteristic;
        my ($characteristic, $remainder) = split( /:|=/, $mapping, 2 );
        if( $characteristic =~ m/([^.]+)\.([^.]+)/ ) {
          $characteristic = $1;
          $characteristic{device} = $2;
        }

        my @parts = split( /,/, $remainder );
        foreach my $part (@parts) {
          my @p = split( '=', $part );
          if( $p[1] =~ m/;/ ) {
            my @values = split(';', $p[1]);
            my @values2 = grep {$_ ne ''} @values;

            $characteristic{$p[0]} = \@values2;

            if( scalar @values != scalar @values2 ) {
              $characteristic{"_$p[0]"} = \@values;
              $characteristic{$p[0]} = $values2[0] if( scalar @values2 == 1 );
            }
          } else {
            $characteristic{$p[0]} = $p[1];
          }
        }

        $mappings{$characteristic} = [] if( !$mappings{$characteristic} );
        push $mappings{$characteristic}, \%characteristic;
      }
    }
#Log 1, Dumper \%mappings;

    my $schema = { intents => [] };
    my $types = {};
    $types->{FHEM_article} = [split( /,|;/, AttrVal( $name, 'articles', 'der,die,das,den' ) ) ];
    $types->{FHEM_preposition} = [split( /,|;/, AttrVal( $name, 'prepositions', 'in,im,in der' ) ) ];
    my $samples = '';
    foreach my $characteristic ( keys %mappings ) {
      my $mappings = $mappings{$characteristic};
      $mappings = [$mappings] if( ref($mappings) ne 'ARRAY');
      my $i = 0;
      foreach my $mapping (@{$mappings}) {
        if( !$mapping->{verb} ) {
          Log3 $name, 2, "alexaMapping: no verb given for $characteristic characteristic";
          next;
        }

        sub merge($$) {
          my ($a, $b) = @_;
          return $a if( !defined($b) );

          my @result = ();

          if( ref($b) eq 'ARRAY' ) {
            @result = keys %{{map {((split(':',$_,2))[0] => 1)} (@{$a}, @{$b})}};
          } else {
            push @{$a}, $b;
            return $a;
          }

          return \@result;
        }

        my $values = [];
        $values = merge( $values, $mapping->{values} );
        $values = merge( $values, $mapping->{valueOn} );
        $values = merge( $values, $mapping->{valueOff} );
        $values = merge( $values, $mapping->{valueToggle} );


        my $nr = $i?chr(65+$i):'';
        my $intent = $characteristic .'Intent'. $nr;

        my $slots = [];
        push $slots, { name => 'article', type => 'FHEM_article' };
        push $slots, { name => 'Device', type => 'FHEM_Device' } if( !$mapping->{device} );
        push $slots, { name => 'preposition', type => 'FHEM_preposition' };
        push $slots, { name => 'Room', type => 'FHEM_Room' };
        if( ref($mapping->{valuePrefix}) eq 'ARRAY' ) {
          push $slots, { name => "${characteristic}_valuePrefix$nr", type => "${characteristic}_prefix$nr" };
          $types->{"${characteristic}_prefix$nr"} = $mapping->{valuePrefix};
        }
        if( $mapping->{values} && $mapping->{values} =~ /^AMAZON/ ) {
          push $slots, { name => "${characteristic}_Value$nr", type => $mapping->{values} };
        } else {
          push $slots, { name => "${characteristic}_Value$nr", type => "${characteristic}_Value$nr" };
          $types->{"${characteristic}_Value$nr"} = $values if( $values->[0] );
        }
        if( ref($mapping->{valueSuffix}) eq 'ARRAY' ) {
          push $slots, { name => "${characteristic}_valueSuffix$nr", type => "${characteristic}_suffix$nr" };
          $types->{"${characteristic}_suffix"} = $mapping->{valueSuffix$nr};
        }

        if( ref($mapping->{articles}) eq 'ARRAY' ) {
          $types->{"${characteristic}_article$nr"} = $mapping->{articles};
        }

        $mapping->{verb} = [$mapping->{verb}] if( ref($mapping->{verb}) ne 'ARRAY' );
        foreach my $verb (@{$mapping->{verb}}) {
          my @articles = ('','{article}');
          if( ref($mapping->{articles}) eq 'ARRAY' ) {
            $articles[1] = "{${characteristic}_article}";
          } elsif( $mapping->{articles} ) {
            @articles = ($mapping->{articles});
          }
          foreach my $article (@articles) {
            foreach my $room ('','{Room}') {
              my $line;

              $line .= "$intent $verb";
              $line .= " $article" if( $article );
              $line .= $mapping->{device}?" $mapping->{device}":' {Device}';
              $line .= " {preposition} $room" if( $room );
              if( ref($mapping->{valuePrefix}) eq 'ARRAY' ) {
                $line .= " {${characteristic}_valuePrefix$nr}";
              } else {
                $line .= " $mapping->{valuePrefix}" if( $mapping->{valuePrefix} );
              }
              $line .= " {${characteristic}_Value$nr}";
              if( ref($mapping->{_valueSuffix}) eq 'ARRAY' ) {
                $line .= "\n$line";
              }
              if( ref($mapping->{valueSuffix}) eq 'ARRAY' ) {
                $line .= " {${characteristic}_valueSuffix$nr}";
              } else {
                $line .= " $mapping->{valueSuffix}" if( $mapping->{valueSuffix} );
              }

              $samples .= "\n" if( $samples );
              $samples .= $line;
            }
          }
        }
        push $schema->{intents}, {intent => $intent, slots => $slots};

        ++$i;
      }
      $samples .= "\n";
    }

    my $json = JSON->new;
    $json->pretty(1);

    my $t;
    foreach my $type ( sort keys %{$types} ) {
      $t .= "\n" if( $t );
      $t .= "$type\n  ";
      $t .= join("\n  ", sort @{$types->{$type}} );
    }

    return "Intent Schema:\n".
           "--------------\n".
           $json->utf8->encode( $schema ) ."\n".
           "Custom Slot Types:\n".
           "----------_-------\n".
           $t. "\n\n".
           "Sample Utterances:\n".
           "------------------\n".
           $samples.
           "\nreload 39_alexa\n".
           "get alexa customSlotTypes\n";

    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
alexa_Parse($$;$)
{
  my ($hash,$data,$peerhost) = @_;
  my $name = $hash->{NAME};
}

sub
alexa_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $len;
  my $buf;

  $len = $hash->{CD}->recv($buf, 1024);
  if( !defined($len) || !$len ) {
Log 1, "!!!!!!!!!!";
    return;
  }

  alexa_Parse($hash, $buf, $hash->{CD}->peerhost);
}

sub
alexa_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  my $hash = $defs{$name};
  if( $attrName eq "disable" ) {
  }

  if( $cmd eq 'set' ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}


1;

=pod
=item summary    Module to control the FHEM/Alexa integration
=item summary_DE Modul zur Konfiguration der FHEM/Alexa Integration
=begin html

<a name="alexa"></a>
<h3>alexa</h3>
<ul>
  Module to control the FHEM/Alexa integration.<br><br>

  Notes:
  <ul>
    <li><br>
    </li>
  </ul>

  <a name="alexa_Set"></a>
  <b>Set</b>
  <ul>
    <li>reload [name]<br>
      Reloads the device <it>name</it> or all devices in alexa-fhem. Subsequently you have to start a device discovery in alexa.
    </li>
  </ul>

  <a name="alexa_Get"></a>
  <b>Get</b>
  <ul>
    <li>customSlotTypes<br>
      Instructs alexa-fhem to write the Custom Slot Types for the Interaction Model to the alexa-fhem console
      and if possible to the requesting fhem frontend.
    </li>
  </ul>

  <a name="alexa_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>alexaName<br>
      The name to use for a device with alexa.
    </li>
  </ul>
</ul><br>

=end html
=cut
