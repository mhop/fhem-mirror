##############################################
# $Id: 30_pilight_raw.pm 0.11 2015-07-27 Risiko $
#
# Usage
# 
# define <name> pilight_raw
#
# Changelog
#
# V 0.10 2015-07-21 - initial beta version
# V 0.11 2015-07-27 - SetExtensions on-for-timer
############################################## 

package main;

use strict;
use warnings;
use Switch;  #libswitch-perl

use SetExtensions;

my %sets = ("on:noArg"=>0, "off:noArg"=>0, "code:textField-long"=>1);

sub pilight_raw_Parse($$);
sub pilight_raw_Define($$);

sub pilight_raw_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_raw_Define";
  $hash->{Match}    = "^PIRAW";
  $hash->{SetFn}    = "pilight_raw_Set";
  $hash->{AttrList} = "onCode:textField-long offCode:textField-long ".$readingFnAttributes;
}

#####################################
sub pilight_raw_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 2) {
    my $msg = "wrong syntax: define <name> pilight_raw";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $me = $a[0];
  
  $hash->{PROTOCOL} = "raw"; 
  #$attr{$me}{verbose} = 5;
  
  $modules{pilight_raw}{defptr}{"raw"}{$me} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub pilight_raw_Set($$)
{  
  my ($hash, $me, $cmd, @a) = @_;

  my $v = join(" ", @a);
  Log3 $me, 4, "$me(Set): $v";
  
  #-- check argument
  return "no set value specified" unless defined($cmd);
  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  return SetExtensions($hash, join(" ", keys %sets), $me, $cmd, @a) unless @match == 1;
  #return "$cmd expects $sets{$match[0]} parameters" unless (@a eq $sets{$match[0]});
  
  my $code_on = $attr{$me}{onCode};
  my $code_off = $attr{$me}{offCode};
  my $code = "";
  my $updateReading = 0;
  
  switch($cmd){
    case "on"    { $code = $code_on; $updateReading = 1;}
    case "off"   { $code = $code_off; $updateReading = 1;}
    case "code"  { $v =~ s/code//g; $code=$v;}
  }  
  
  if($code eq "") {
    Log3 $me, 2, "$me(Set): No value for code given"; 
    return "No value for code given";
  }
  
  my $msg = "$me,$code";
  IOWrite($hash, $msg);
  
  readingsSingleUpdate($hash,"state",$cmd,1) if($updateReading == 1);
  return undef;
}


1;

=pod
=begin html

<a name="pilight_raw"></a>
<h3>pilight_raw</h3>
<ul>
  With pilight_raw it si possible to send raw codes<br>
  You have to define the base device pilight_ctrl first.<br>
  <br>
  <a name="pilight_raw_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; pilight_raw</code>    
  </ul>
  <br>
  <a name="pilight_raw_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <b>on</b>
      Send 'onCode' as raw code
    </li>
    <li>
      <b>off</b>
      Send 'offCode' as raw code
    </li>
    <li>
      <b>code <value></b>
      Send <value> as raw code
    </li>
    <li>
      <a href="#setExtensions">set extensions</a> are supported<br>
    </li>
  </ul>  
  <br>
  <a name="pilight_raw_readings"></a>
  <p><b>Readings</b></p>
  <ul>    
    <li>
      state<br>
      state on or off
    </li>
  </ul>
  <br>
  <a name="pilight_raw_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="onCode">onCode</a><br>
        raw code for state on
    </li>
    <li><a name="offCode">onCode</a><br>
        raw code for state off
    </li>
  </ul>
</ul>

=end html

=cut
