#############################################
package main;

use strict;
use warnings;

use vars qw(%fht8v_c2b); # would Peter like to access it from outside too? ;-)

# defptr{XMIT BTN}{DEVNAME} -> Ptr to global defs entry for this device
my %defptr;

# my %follow;

sub
FHT8V_Initialize($)
{
  my ($hash) = @_;

#  $hash->{Match}     = "^([0-9]{2}:2[0-9A-F]{3} )*([0-9]{2}:2[0-9A-F]{3})\$";
  $hash->{SetFn}     = "FHT8V_Set";
  $hash->{DefFn}     = "FHT8V_Define";
  $hash->{UndefFn}   = "FHT8V_Undef";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 dummy:1,0 showtime:1,0 loglevel:0,1,2,3,4,5,6";

}


###################################
sub FHT8V_valve_position(@)
{
  my ($hash, @a) = @_;
  my $na = int(@a);
  my $v;

  my $arg2_percent=0;
  if ( $na > 3 ) {
    $arg2_percent=$a[3] eq "%";
  }
  if ( $a[2] =~ m/^[0-9]{1,3}%$/ || $a[2] =~ m/^[0-9]{1,3}$/ && $arg2_percent ) {
    my $num;
    if ( $arg2_percent ) {
      $num=$a[2];
    } else {
      $num=substr($a[2],0,-1);
    }
    return "Out of range." if ( $num > 100 || $num < 0 );
    $num=255 if ( $num == 100 );
    $v=sprintf("%.0f",2.56*$num);
  } else {
    return "Argument hast invalid value \"$a[2]\"." if ( $a[2] !~ m/^[0-9]{1,3}$/ );
    return "Out of range. Range: 0..255." if ( $a[2] > 255 || $a[2] < 0 );
    $v = $a[2];
  }

  Log GetLogLevel($a[2],2), "FHT8V $a[0]: v: $v";

  IOWrite($hash, "", sprintf("T".$hash->{XMIT}."%02X26%02X",$hash->{NO}, $v))                # CUL hack
        if($hash->{IODev} && $hash->{IODev}->{TYPE} eq "CUL");

  $hash->{STATE}=sprintf("%d%%", $v*0.390625);
  return undef;
}

sub FHT8V_beep(@)
{
  my ($hash, @a) = @_;

  IOWrite($hash, "", sprintf("T".$hash->{XMIT}."%02X2E00",$hash->{NO}))                # CUL hack
        if($hash->{IODev} && $hash->{IODev}->{TYPE} eq "CUL");

  $hash->{STATE}="beep";
  return undef;
}

sub FHT8V_open(@)
{
  my ($hash, @a) = @_;

  IOWrite($hash, "", sprintf("T".$hash->{XMIT}."%02X2100",$hash->{NO}))                # CUL hack
        if($hash->{IODev} && $hash->{IODev}->{TYPE} eq "CUL");

  $hash->{STATE}="open";
  return undef;
}

sub FHT8V_off(@)
{
  my ($hash, @a) = @_;

  IOWrite($hash, "", sprintf("T".$hash->{XMIT}."%02X2000",$hash->{NO}))                # CUL hack
        if($hash->{IODev} && $hash->{IODev}->{TYPE} eq "CUL");

  $hash->{STATE}="off";
  return undef;
}

sub FHT8V_close(@)
{
  my ($hash, @a) = @_;

  IOWrite($hash, "", sprintf("T".$hash->{XMIT}."%02X2200",$hash->{NO}))                # CUL hack
        if($hash->{IODev} && $hash->{IODev}->{TYPE} eq "CUL");

  $hash->{STATE}="close";
  return undef;
}

sub
FHT8V_assign(@)
{
  my ($hash, @a) = @_;
  my $na = int(@a);
  my $v = 0;

  if ( $na > 2 ) {
    return "Parameter \"".$a[3]."\" defining offset must be numerical." if ( $a[3] !~ /[0-9]+/ );
    $v=int($a[3]);
  }
  IOWrite($hash, "", sprintf("T".$hash->{XMIT}."%02X2F%02X",$hash->{NO},$v))                # CUL hack
        if($hash->{IODev} && $hash->{IODev}->{TYPE} eq "CUL");

  # not sure if this is nessesary but I saw it in the documentation...
  IOWrite($hash, "", sprintf("T".$hash->{XMIT}."%02X2600",$hash->{NO},$v))                # CUL hack
        if($hash->{IODev} && $hash->{IODev}->{TYPE} eq "CUL");
  $hash->{STATE}="assigning";
  return undef;
}

sub
FHT8V_Set($@)
{
  my ($hash, @a) = @_;
  my $na = int(@a);

  return "Parameter missing" if ( $na < 2 );
  if ( $_[2] eq "valve" ) {
    return FHT8V_valve_position(@_);
  }
  if ( $_[2] eq "open" ) {
    return FHT8V_open(@_);
  }
  if ( $_[2] eq "close" ) {
    return FHT8V_close(@_);
  }
  if ( $_[2] eq "beep" ) {
    return FHT8V_beep(@_);
  }
  if ( $_[2] eq "assign" ) {
    return FHT8V_assign(@_);
  }
  if ( $_[2] eq "off" ) {
    return FHT8V_off(@_);
  }
  return "Could not set undefined parameter \"".$_[2]."\".";
}


#############################
sub
FHT8V_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $na = int(@a);

  my $u = "wrong syntax: define <name> FHT8V housecode " .
                        "addr";

  return $u if( $na < 3 );
  return "Define $a[0]: wrong housecode format: specify a 4 digit hex value ".
         "or an 8 digit quad value"
  		if( ($a[2] !~ m/^[a-f0-9]{4}$/i) && ($a[2] !~ m/^[1-4]{8}$/i) );

  if ( $na > 3 ) {
    return "Define $a[0]: wrong valve address format: specify a 2 digit hex value " .
         "or a 4 digit quad value"
  		if( ($a[3] !~ m/^[a-f0-9]{2}$/i) && ($a[3] !~ m/^[1-4]{4}$/i) );
  }

  my $housecode = $a[2];
  $housecode = four2hex($housecode,4) if (length($housecode) == 8);

  my $valve_number = 1;
  if ( $na > 3 ) {
    my $valve_number = $a[3];
    $valve_number = four2hex($valve_number,2) if (length($valve_number) == 4);
  }

  $hash->{XMIT} = lc($housecode);
  $hash->{NO}  = lc($valve_number);

  my $code = "$housecode $valve_number";
  my $ncode = 1;
  my $name = $a[0];

  $hash->{CODE}{$ncode++} = $code;
  $defptr{$code}{$name}   = $hash;

  for(my $i = 4; $i < int(@a); $i += 2) {

    return "No address specified for $a[$i]" if($i == int(@a)-1);

    $a[$i] = lc($a[$i]);
    if($a[$i] eq "fg") {
      return "Bad fg address for $name, see the doc"
        if( ($a[$i+1] !~ m/^f[a-f0-9]$/) && ($a[$i+1] !~ m/^44[1-4][1-4]$/));
    } elsif($a[$i] eq "lm") {
      return "Bad lm address for $name, see the doc"
        if( ($a[$i+1] !~ m/^[a-f0-9]f$/) && ($a[$i+1] !~ m/^[1-4][1-4]44$/));
    } elsif($a[$i] eq "gm") {
      return "Bad gm address for $name, must be ff"
        if( ($a[$i+1] ne "ff") && ($a[$i+1] ne "4444"));
    } else {
      return $u;
    }

    my $grpcode = $a[$i+1];
    if (length($grpcode) == 4) {
       $grpcode = four2hex($grpcode,2);
    }

    $code = "$housecode $grpcode";
    $hash->{CODE}{$ncode++} = $code;
    $defptr{$code}{$name}   = $hash;
  }
  $hash->{TYPE}="FHT8V";
  AssignIoPort($hash);
}

#############################
sub
FHT8V_Undef($$)
{
  my ($hash, $name) = @_;
  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $defptr{$c} }) {
      delete($defptr{$c}{$dname}) if($defptr{$c}{$dname} == $hash);
    }
  }
  return undef;
}

1;
