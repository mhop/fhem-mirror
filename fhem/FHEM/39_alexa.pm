
# $Id$

package main;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use vars qw(%modules);
use vars qw(%defs);
use vars qw(%attr);
use vars qw($readingFnAttributes);
sub Log($$);
sub Log3($$$);

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
  $hash->{AttrFn}   = "alexa_Attr";
  $hash->{AttrList} = "alexaMapping:textField-long alexaTypes:textField-long fhemIntents:textField-long ".
                      "articles prepositions ".
                      "echoRooms:textField-long ".
                      "alexaConfirmationLevel:2,1,0 alexaStatusLevel:2,1 ".
                      "skillId:textField ".
                      $readingFnAttributes;
}

#####################################

sub
alexa_AttrDefaults($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( !AttrVal( $name, 'alexaMapping', undef ) ) {
    CommandAttr(undef,"$name alexaMapping #Characteristic=<name>=<value>,...\n".
                                         "On=verb=schalte,valueOn=an;ein,valueOff=aus,valueToggle=um\n\n".

                                         "Brightness=verb=stelle,property=helligkeit,valuePrefix=auf,values=AMAZON.NUMBER,valueSuffix=prozent\n\n".

                                         "Hue=verb=stelle,valuePrefix=auf,values=rot:0;grün:128;blau:200\n".
                                         "Hue=verb=färbe,values=rot:0;grün:120;blau:220\n\n".

                                         "Saturation=verb=stelle,property=sättigung,valuePrefix=auf,values=AMAZON.NUMBER\n".
                                         "Saturation=verb=sättige,values=AMAZON.NUMBER\n\n".

                                         "TargetPosition=verb=mach,articles=den;die,values=auf:100;zu:0\n".
                                         "TargetPosition=verb=stelle,valuePrefix=auf,values=AMAZON.NUMBER,valueSuffix=prozent\n\n".

                                         "TargetTemperature=verb=stelle,valuePrefix=auf,values=AMAZON.NUMBER,valueSuffix=grad\n\n".

                                         "Volume:verb=stelle,valuePrefix=auf,values=AMAZON.NUMBER,valueSuffix=prozent\n\n".

                                         "#Weckzeit=verb=stelle,valuePrefix=auf;für,values=AMAZON.TIME,valueSuffix=uhr" );
  }

  if( !AttrVal( $name, 'alexaTypes', undef ) ) {
    CommandAttr(undef,"$name alexaTypes #Type=<alias>[,<alias2>[,...]]\n".
                                       "light=licht,lampen\n".
                                       "blind=rolladen,rolläden,jalousie,jalousien,rollo,rollos" );
  }

  if( !AttrVal( $name, 'echoRooms', undef ) ) {
    CommandAttr(undef,"$name echoRooms #<deviceId>=<room>\n" );
  }


  if( !AttrVal( $name, 'fhemIntents', undef ) ) {
    CommandAttr(undef,"$name fhemIntents #IntentName=<sample utterance>\n".
                                        "gutenMorgen=guten morgen\n".
                                        "guteNacht=gute nacht" );
  }

}

sub
alexa_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> alexa"  if(@a != 2);

  my $name = $a[0];
  $hash->{NAME} = $name;

  my $d = $modules{$hash->{TYPE}}{defptr};
  return "$hash->{TYPE} device already defined as $d->{NAME}." if( defined($d) && $name ne $d->{NAME} );
  $modules{$hash->{TYPE}}{defptr} = $hash;

  addToAttrList("$hash->{TYPE}Name");
  addToAttrList("$hash->{TYPE}Room");

  alexa_AttrDefaults($hash);

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

  my $list = "reload:noArg skillId";

  if( $cmd eq 'reload' ) {
    $hash->{".triggerUsed"} = 1;
    if( @args ) {
      FW_directNotify($name, "reload $args[0]");
    } else {
      FW_directNotify($name, 'reload');
    }

    return undef;
  } elsif( $cmd eq 'execute' ) {
    my ($intent,$applicationId) = split(':', shift @args, 2 );
    return 'usage $cmd execute <intent> [json]' if( !$intent );

    my $json = join(' ',@args);
    my $decoded = eval { decode_json($json) };
    if( $@ ) {
      my $msg = "json error: $@ in $json";
      Log3 $name, 2, "$name: $msg";
      return $msg;
    }
    Log3 $name, 5, "$name: \"$json\" -> ". Dumper $decoded;

    my $cmd = '{Log 1, "test"; return "result";}';
    Log3 $name, 5, "$name: cmd: $cmd";

    if( ref($decoded->{slots}) eq 'HASH' ) {
      $hash->{active} = 1;
      my $intent = $intent;
      $intent = "$intent:$applicationId" if( $applicationId );
      readingsSingleUpdate($hash, 'fhemIntent', $intent, 1 );
      my $exec = EvalSpecials($cmd, %{$decoded->{slots}});
      Log3 $name, 5, "$name: exec: $exec";
      my $ret = AnalyzeCommandChain($hash, $exec);
      Log3 $name, 5, "$name: ret ". ($ret?$ret:"undefined");
      $hash->{active} = 0;

      return $ret;
    }

    return undef;
  } elsif( $cmd eq 'skillId' ) {

    return CommandAttr(undef,"$name skillId $args[0]" );
  }

  return "Unknown argument $cmd, choose one of $list";
}



sub
alexa_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "customSlotTypes:noArg interactionModel:noArg skillId:noArg";

  if( lc($cmd) eq 'customslottypes' ) {
    if( $hash->{CL} ) {
      FW_directNotify($name, "customSlotTypes $hash->{CL}{NAME}");
    } else {
      FW_directNotify($name, 'customSlotTypes');
    }

    return undef;

  } elsif( lc($cmd) eq 'interactionmodel' ) {
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
            $p[1] =~ s/\+/ /g;
            my @values = split(';', $p[1]);
            my @values2 = grep {$_ ne ''} @values;

            $characteristic{$p[0]} = \@values2;

            if( scalar @values != scalar @values2 ) {
              $characteristic{"_$p[0]"} = \@values;
              $characteristic{$p[0]} = $values2[0] if( scalar @values2 == 1 );
            }
          } else {
            $p[1] =~ s/\+/ /g;
            $characteristic{$p[0]} = $p[1];
          }
        }

        $mappings{$characteristic} = [] if( !$mappings{$characteristic} );
        push @{$mappings{$characteristic}}, \%characteristic;
      }
    }
#Log 1, Dumper \%mappings;

    my %types;
    if( my $entries = AttrVal( $name, 'alexaTypes', undef ) ) {
      sub append($$$) {
        my($a, $c, $v) = @_;

        if( !defined($a->{$c}) ) {
          $a->{$c} = {};
        }
        $a->{$c}{$v} = 1;
      }

      sub merge($$) {
       my ($a, $b) = @_;
       return $a if( !defined($b) );

       my @result = ();

       if( ref($b) eq 'ARRAY' ) {
         @result = sort keys %{{map {((split(':',$_,2))[0] => 1)} (@{$a}, @{$b})}};
       } else {
         push @{$a}, $b;
         return $a;
       }

       return \@result;
     }

      foreach my $entry ( split( / |\n/, $entries ) ) {
        next if( !$entry );
        next if( $entry =~ /^#/ );

        my ($type, $remainder) = split( /:|=/, $entry, 2 );
        $types{$type} = [];
        my @names = split( /,/, $remainder );
        foreach my $name (@names) {
          push @{$types{$type}}, $name;
        }
      }
    }
Log 1, Dumper \%types;

    my $verbsOfIntent = {};
    my $intentsOfVerb = {};
    my $valuesOfIntent = {};
    my $intentsOfCharacteristic = {};
    my $characteristicsOfIntent = {};
    foreach my $characteristic ( keys %mappings ) {
      my $mappings = $mappings{$characteristic};
      $mappings = [$mappings] if( ref($mappings) ne 'ARRAY');
      my $i = 0;
      foreach my $mapping (@{$mappings}) {
        if( !$mapping->{verb} ) {
          Log3 $name, 2, "alexaMapping: no verb given for $characteristic characteristic";
          next;
        }

        $mapping->{property} = '' if( !$mapping->{property} );
        $mapping->{property} = [$mapping->{property}] if( ref($mapping->{property}) ne 'ARRAY' );
        foreach my $property (@{$mapping->{property}}) {
          my $intent = $characteristic;
          $intent = lcfirst($mapping->{valueSuffix}) if( !$property && $mapping->{valueSuffix} );
          $intent .= 'Intent';

          my $values = [];
          $values = merge( $values, $mapping->{values} );
          $values = merge( $values, $mapping->{valueOn} );
          $values = merge( $values, $mapping->{valueOff} );
          $values = merge( $values, $mapping->{valueToggle} );

          append($verbsOfIntent, $intent, $mapping->{verb} );
          append($intentsOfVerb, $mapping->{verb}, $intent );
          append($valuesOfIntent, $intent, join( ',', @{$values} ) );
          append($intentsOfCharacteristic, $characteristic, $intent );
          append($characteristicsOfIntent, $intent, $characteristic );
        }
      }
    }
Log 1, Dumper $verbsOfIntent;
Log 1, Dumper $intentsOfVerb;
Log 1, Dumper $valuesOfIntent;
Log 1, Dumper $intentsOfCharacteristic;
Log 1, Dumper $characteristicsOfIntent;

    my $intents = {};
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

        my $values = [];
        $values = merge( $values, $mapping->{values} );
        $values = merge( $values, $mapping->{valueOn} );
        $values = merge( $values, $mapping->{valueOff} );
        $values = merge( $values, $mapping->{valueToggle} );

        $mapping->{property} = '' if( !$mapping->{property} );
        $mapping->{property} = [$mapping->{property}] if( ref($mapping->{property}) ne 'ARRAY' );
        foreach my $property (@{$mapping->{property}}) {

          my $nr = $i?chr(65+$i):'';
          $nr = '' if( $mapping->{valueSuffix} );
          #my $intent = $characteristic .'Intent'. $nr;
          my $intent = $characteristic;
          $intent = lcfirst($mapping->{valueSuffix}) if( !$property && $mapping->{valueSuffix} );
          $intent .= 'Intent';
          $intent .= $nr;


          next if( $intents->{$intent} );
          $intents->{$intent} = 1;

          my $slots = [];
          my $samples2 = [];
          push @{$slots}, { name => 'article', type => 'FHEM_article' };
          push @{$slots}, { name => 'Device', type => 'FHEM_Device' } if( !$mapping->{device} );
          push @{$slots}, { name => 'preposition', type => 'FHEM_preposition' };
          push @{$slots}, { name => 'Room', type => 'FHEM_Room' };
          if( ref($mapping->{valuePrefix}) eq 'ARRAY' ) {
            push @{$slots}, { name => "${characteristic}_valuePrefix$nr", type => "${characteristic}_prefix$nr" };
            $types->{"${characteristic}_prefix$nr"} = $mapping->{valuePrefix};
          }
          my $slot_name = "${characteristic}_Value$nr";
          $slot_name = lcfirst($mapping->{valueSuffix})."_Value$nr" if( !$property && $mapping->{valueSuffix} );
          if( $mapping->{values} && $mapping->{values} =~ /^AMAZON/ ) {
            push @{$slots}, { name => $slot_name, type => $mapping->{values} };
          } else {
            push @{$slots}, { name => $slot_name, type => "${characteristic}_Value$nr" };
            $types->{$slot_name} = $values if( $values->[0] );
          }
          if( ref($mapping->{valueSuffix}) eq 'ARRAY' ) {
            push @{$slots}, { name => "${characteristic}_valueSuffix$nr", type => "${characteristic}_suffix$nr" };
            $types->{"${characteristic}_suffix"} = $mapping->{valueSuffix$nr};
          }

          if( ref($mapping->{articles}) eq 'ARRAY' ) {
            $types->{"${characteristic}_article$nr"} = $mapping->{articles};
          }

          $mapping->{verb} = [$mapping->{verb}] if( ref($mapping->{verb}) ne 'ARRAY' );
          foreach my $verb (@{$mapping->{verb}}) {
            $samples .= "\n" if( $samples );

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
                $line .= " $property" if( $property );
                $line .= " $article" if( $article );
                $line .= $mapping->{device}?" $mapping->{device}":' {Device}';
                $line .= " {preposition} $room" if( $room );
                if( ref($mapping->{valuePrefix}) eq 'ARRAY' ) {
                  $line .= " {${characteristic}_valuePrefix$nr}";
                } else {
                  $line .= " $mapping->{valuePrefix}" if( $mapping->{valuePrefix} );
                }
                $line .= " {$slot_name}";
                if( ref($mapping->{_valueSuffix}) eq 'ARRAY' ) {
                  $line .= "\n$line";
                }
                if( ref($mapping->{valueSuffix}) eq 'ARRAY' ) {
                  $line .= " {${characteristic}_valueSuffix$nr}";
                } else {
                  $line .= " $mapping->{valueSuffix}" if( $mapping->{valueSuffix} );
                }

                push @{$samples2}, $line;

                $samples .= "\n" if( $samples );
                $samples .= $line;
              }
            }
          }
          push @{$schema->{intents}}, {intent => $intent, slots => $slots};
          #push @{$schema->{intents}}, {intent => $intent, slots => $slots, samples => $samples2};
        }

        ++$i;
      }
      $samples .= "\n";
    }

    if( my $entries = AttrVal( $name, 'fhemIntents', undef ) ) {
      my %intents;
      foreach my $entry ( split( /\n/, $entries ) ) {
        next if( !$entry );
        next if( $entry =~ /^#/ );

        my $slots = [];

        my ($intent, $remainder) = split( /:|=/, $entry, 2 );
        my @parts = split( /,/, $remainder );
        my $utterance = $parts[$#parts];

        my $intent_name = "FHEM${intent}Intent";
        if( $intent =~ m/^(set|get|attr)\s/ ) {
          $intent_name = "FHEM${1}Intent";
          my $i = 1;
          while( defined($intents{$intent_name}) ) {
            $intent_name = "FHEM${1}Intent".chr(65+$i);
            ++$i;
          }
        } elsif( $intent =~ m/^{.*}$/ ) {
          $intent_name = 'FHEMperlCodeIntent';
          my $nr = '';
          my $i = 1;
          while( defined($intents{$intent_name}) ) {
            if( $i < 26 ) {
              $nr = chr(65+$i);
            } else {
              $nr = chr(64+int($i/26)).chr(65+$i%26);
            }
            ++$i;
            $intent_name = "FHEMperlCodeIntent$nr";
          }

          my $slot_names = {};
          my $u = $utterance;
          while( $u =~ /\{(.*?)\}/g ) {
            my $slot = $1;
            my ($name, $values) = split( /:|=/, $slot, 2 );

            my $slot_name = "${intent_name}_${name}";
            next if( $slot_names->{$slot_name} );
            $slot_names->{$slot_name} = 1;

            if( $values ) {
              if( $values && $values =~ /^AMAZON/ ) {
                push @{$slots}, { name => $slot_name, type => $values };
              } else {
                push @{$slots}, { name => $slot_name, type => "${intent_name}_${name}_Value" };
                $values =~ s/\+/ /g;
                my @values = split(';', $values );
                $types->{"${intent_name}_${name}_Value"} = \@values if( $values[0] );
              }

              $slot =~ s/\+/\\\+/g;
              $utterance =~ s/\{$slot\}/\{$slot_name\}/;

            } else {
              push @{$slots}, { name => $name, type => "FHEM_$name" };

            }
          }

        }
        $intent_name =~ s/ //g;
        $intents{$intent_name} = $intent;

        if( @{$slots} ) {
          push @{$schema->{intents}}, {intent => $intent_name, slots => $slots };
        } else {
          push @{$schema->{intents}}, {intent => $intent_name };
        }

        foreach my $u ( split( '\|', $utterance ) ) {
          $samples .= "\n$intent_name $u";
        }
      }
      $samples .= "\n";
    }

    push @{$schema->{intents}}, {intent => "StatusIntent",
                                 slots => [ { name => 'Device', type => 'FHEM_Device' },
                                            { name => 'preposition', type => 'FHEM_preposition' },
                                            { name => 'Room', type => 'FHEM_Room' } ]};
    push @{$schema->{intents}}, {intent => "RoomAnswerIntent",
                                 slots => [ { name => 'preposition', type => 'FHEM_preposition' },
                                            { name => 'Room', type => 'FHEM_Room' } ]};
    push @{$schema->{intents}}, {intent => "RoomListIntent", };
    push @{$schema->{intents}}, {intent => "DeviceListIntent",
                                 slots => [ { name => 'article', type => 'FHEM_article' },
                                            { name => 'Room', type => 'FHEM_Room' } ]};
    push @{$schema->{intents}}, {intent => "AMAZON.CancelIntent", };
    push @{$schema->{intents}}, {intent => "AMAZON.StopIntent", };

    $samples .= "\nStatusIntent status";
    $samples .= "\nStatusIntent {Device} status";
    $samples .= "\nStatusIntent status von {Device}";
    $samples .= "\nStatusIntent wie ist der status von {Device}";
    $samples .= "\nStatusIntent wie ist der status {preposition} {Room}";
    $samples .= "\n";

    $samples .= "\nRoomAnswerIntent {preposition} {Room}";
    $samples .= "\n";

    $samples .= "\nRoomListIntent raumliste";
    $samples .= "\nDeviceListIntent geräteliste";
    $samples .= "\nDeviceListIntent geräteliste {Room}";
    $samples .= "\nDeviceListIntent geräteliste für {article} {Room}";
    $samples .= "\n";

    my $json = JSON->new;
    $json->pretty(1);

    my $t;
    foreach my $type ( sort keys %{$types} ) {
      $t .= "\n" if( $t );
      $t .= "$type\n  ";
      $t .= join("\n  ", @{$types->{$type}} );
    }

    return "Intent Schema:\n".
           "--------------\n".
           $json->utf8->encode( $schema ) ."\n".
           "Custom Slot Types:\n".
           "------------------\n".
           $t. "\n\n".
           "Sample Utterances:\n".
           "------------------\n".
           $samples.
           "\nreload 39_alexa\n".
           "get alexa interactionmodel\n";

    return undef;
  } elsif( $cmd eq 'skillId' ) {
    my $skillId = AttrVal($name, 'skillId', undef);

    return 'no skillId set' if( !$skillId );

    $skillId = alexa_decrypt( $skillId );

    return "skillId: $skillId";
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
alexa_encrypt($)
{
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /^crypt:(.*)/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'. $encoded;
}
sub
alexa_decrypt($)
{
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  $encoded = $1 if( $encoded =~ /^crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}

sub
alexa_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  my $hash = $defs{$name};
  if( $attrName eq "disable" ) {
  } elsif( $attrName eq 'skillId' ) {
    if( $cmd eq "set" && $attrVal ) {

      if( $attrVal =~ /^crypt:/ ) {
        return;

      } elsif( $attrVal !~ /(^amzn1\.ask\.skill\.[0-9a-f\-]+)|(^amzn1\.echo-sdk-ams\.app\.[0-9a-f\-]+)/ ) {
        return "$attrVal is not a valid skill id";
      }

      $attrVal = alexa_encrypt($attrVal);

      if( $orig ne $attrVal ) {
        $attr{$name}{$attrName} = $attrVal;
        return "stored obfuscated skillId";
      }
    }
  }


  if( $cmd eq 'set' ) {

  } else {
    delete $attr{$name}{$attrName};

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday(), "alexa_AttrDefaults", $hash, 0);
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
  Module to control the integration of Amazon Alexa devices with FHEM.<br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
  </ul>

  <a name="alexa_Set"></a>
  <b>Set</b>
  <ul>
    <li>reload [name]<br>
      Reloads the device <code>name</code> or all devices in alexa-fhem. Subsequently you have to start a device discovery
      for the home automation skill in the amazon alexa app.</li>
  </ul>

  <a name="alexa_Get"></a>
  <b>Get</b>
  <ul>
    <li>customSlotTypes<br>
      Instructs alexa-fhem to write the device specific Custom Slot Types for the Interaction Model
      configuration to the alexa-fhem console and if possible to the requesting fhem frontend.</li>
    <li>interactionModel<br>
      Get Intent Schema, non device specific Custom Slot Types and Sample Utterances for the Interaction Model
      configuration.</li>
    <li>skillId<br>
      shows the configured skillId.</li>
  </ul>

  <a name="alexa_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>alexaName<br>
      The name to use for a device with alexa.</li>
    <li>alexaRoom<br>
      The room name to use for a device with alexa.</li>
    <li>articles<br>
      defaults to: der,die,das,den</li>
    <li>prepositions<br>
      defaults to: in,im,in der</li>
    <li>alexaMapping<br>
      maps spoken commands to intents for certain characteristics.</li>
    <li>alexaTypes<br>
      maps spoken device types to ServiceClasses. eg: attr alexa alexaTypes light:licht,lampe,lampen blind:rolladen,jalousie,rollo Outlet:steckdose TemperatureSensor:thermometer LockMechanism:schloss OccupancySensor: anwesenheit</li>
    <li>echoRooms<br>
      maps echo devices to default rooms.</li>
    <li>fhemIntents<br>
      maps spoken commands directed to fhem as a whole (i.e. not to specific devices) to events from the alexa device.</li>
    <li>alexaConfirmationLevel<br>
      </li>
    <li>alexaStatusLevel<br>
      </li>
    <li>skillId<br>
      skillId to use for automatic interaction model upload (not yet finished !!!)
      </li>
    Note: changes to attributes of the alexa device will automatically trigger a reconfiguration of
          alxea-fhem and there is no need to restart the service.
  </ul>
</ul><br>

=end html
=cut
