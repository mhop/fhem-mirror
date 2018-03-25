=for comment

# $Id$

This script free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
any later version.

The GNU General Public License can be found at
http://www.gnu.org/copyleft/gpl.html.
A copy is found in the textfile GPL.txt and important notices to the license
from the author is found in LICENSE.txt distributed with these scripts.

This script is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut

package main;
use strict;
use warnings;
use HttpUtils;

my $c_system  = 'system';
my $c_noModel = 'noModel';

my %fhemInfo    = ();
my @ignoreList  = qw(Global);
my @noModelList = qw(readingsgroup lacrosse zwdongle wol weekdaytimer 
   cul_rfr solarview lw12 tscul knx dummy at archetype weather pushover twilight hminfo readingsgroup);

sub fheminfo_Initialize($$) {
  my %hash = (
    Fn  => "CommandFheminfo",
    Hlp => "[send],show or send Fhem statistics",
    uri => "https://fhem.de/stats/statistics2.cgi",
  );
  $cmds{fheminfo} = \%hash;
}

sub CommandFheminfo($$) {
  my ($cl,$param) = @_;
  my @args = split("[ \t]+", $param);
  $args[0] = defined($args[0]) ? lc($args[0]) : "";
  my $doSend = ($args[0] eq 'send') ? 1 : 0;

  return "Unknown argument $args[0], usage: fheminfo [send]"
    if($args[0] ne "send" && $args[0] ne "");

  return "Won't send, as sendStatistics is set to 'never'."
    if($doSend && lc(AttrVal("global","sendStatistics","")) eq "never");

  _fi2_Count();

  if (defined($args[1]) && $args[1] eq 'debug') {
     $fhemInfo{$c_system}{'uniqueID'} = _fi2_shortId();
     return toJSON(\%fhemInfo);
  }

  _fi2_Send($cl) if $doSend;

  # do not return statistics data if called from update
  return "Statistics data sent to server. See Logfile (level 4) for details." unless defined($cl);

  return _fi2_TelnetTable($doSend) if ($cl && $cl->{TYPE} eq 'telnet');
  return _fi2_HtmlTable($doSend);
}

################################################################
# tools
#
sub _fi2_Count() {
   my $uniqueID = getUniqueId();
   my $os       = $^O;
   my $perl     = sprintf("%vd", $^V);

   %fhemInfo = ();

   $fhemInfo{$c_system}{'uniqueID'}   = $uniqueID;
   $fhemInfo{$c_system}{'os'}         = $os;
   $fhemInfo{$c_system}{'perl'}       = $perl;
   $fhemInfo{$c_system}{'revision'}   = _fi2_findRev();
   $fhemInfo{$c_system}{'configType'} = configDBUsed() ? 'configDB' : 'configFile';

   foreach my $key ( keys %defs )
   {
# 1. skip if device is TEMPORARY or VOLATILE
      next if (defined($defs{$key}{'TEMPORARY'}) || defined($defs{$key}{'VOLATILE'})); 

      my $name  = $defs{$key}{NAME};
      my $type  = $defs{$key}{TYPE};
      my $model = $c_noModel;

# 2. look for model information in internals
      unless (lc($type) eq 'knx') {
         $model = defined($defs{$key}{model}) ? $defs{$key}{model} : $model;
         $model = defined($defs{$key}{MODEL}) ? $defs{$key}{MODEL} : $model;
      }

# 3. look for model information in attributes
      $model = AttrVal($name,'model',$model);

# 4. look for model information in readings
      $model = ReadingsVal($name,'model',$model);

      # special reading for BOSEST
      $model = ReadingsVal($name,'type',$model)
               if (lc($type) eq 'bosest');
      # special reading for ZWave
      if (lc($type) eq 'zwave') {
         $model = ReadingsVal($name,'modelId',undef);
         next unless (defined($model));
         next if ($model =~ /^0x.... /);
         $model = _fi2_zwave($model);
      }
      
# 5. ignore model for some modules
      foreach my $i (@noModelList) {
         $model = $c_noModel if (lc($type) eq $i);
      }
      
# 6. check if model is a scalar
      $model = $c_noModel if (ref($model) eq 'HASH');

# 7. skip for some special cases found in database
      next if ( ($model =~ /^unkno.*/i) || 
                ($model =~ /virtual.*/i) || 
                ($model eq '?') || 
                ($model eq '1') || 
                (defined($defs{$key}{'chanNo'})) ||
                ($name =~ m/^unknown_/) );

# 8. finally count it :)
      $fhemInfo{$type}{$model}++ ;
   }

# now do some more special handlings

   # add model info for configDB if used
   eval { $fhemInfo{'configDB'}{_cfgDB_type()}++ if configDBUsed(); };

   # delete all modules listed in ignoreList
   foreach my $i (@ignoreList) { delete $fhemInfo{$i}; }

   return;
}

sub _fi2_Send($) {
   my ($cl) = shift;
   $cl //= undef;
   my $sendType = defined($cl) ? 'nonblocking' : 'blocking';

   my $json = toJSON(\%fhemInfo);

   Log3("fheminfo",4,"fheminfo send ($sendType): $json");

   my %hu_hash = ();
   $hu_hash{url}      = $cmds{fheminfo}{uri};
   $hu_hash{data}     = "uniqueID=".$fhemInfo{$c_system}{'uniqueID'}."&json=$json";
   $hu_hash{header}   = "User-Agent: FHEM";
   if (defined($cl)) {
     $hu_hash{callback} = sub($$$) {
        my ($hash, $err, $data) = @_;
        if($err) {
          Log 1, "fheminfo send: Server ERROR: $err";
        } else {
          Log3("fheminfo",4,"fheminfo send: Server RESPONSE: $data");
        }
      };
      HttpUtils_NonblockingGet(\%hu_hash);
   } else {
      my ($err, $data) = HttpUtils_BlockingGet(\%hu_hash);
      if($err) {
        Log 1, "fheminfo send: Server ERROR: $err";
      } else {
        Log3("fheminfo",4,"fheminfo send: Server RESPONSE: $data");
      }
   }
   return;
}

sub _fi2_TelnetTable($) {
  my ($doSend) = shift;
  my $str;
  $str .= "Following statistics data will be sent to server:\n(see Logfile level 4 for server response)\n\n" if($doSend == 1);
  $str .= "System Info\n";
  $str .= sprintf("  ConfigType%*s: %s\n",3," ",$fhemInfo{$c_system}{'configType'});
  $str .= sprintf("  SVN revision%*s: %s\n",0," ",$fhemInfo{$c_system}{'revision'})
                  if (defined($fhemInfo{$c_system}{'revision'}));
  $str .= sprintf("  OS%*s: %s\n",11," ",$fhemInfo{$c_system}{'os'});
  $str .= sprintf("  Perl%*s: %s\n",9," ",$fhemInfo{$c_system}{'perl'});
  $str .= sprintf("  uniqueID%*s: %s\n",5," ",_fi2_shortId());

   my @keys = keys %fhemInfo;
   foreach my $type (sort @keys)
   {
      next if $type eq $c_system;
      $str .= "\nType: $type ";
      $str .= "Count: ".$fhemInfo{$type}{$c_noModel} if defined $fhemInfo{$type}{$c_noModel};
      $str .= "\n";
      while ( my ($model, $count) = each(%{$fhemInfo{$type}}) )
      { $str .= "     $model = $fhemInfo{$type}{$model}\n" unless $model eq $c_noModel; }
   }

  return $str;
}

sub _fi2_HtmlTable($) {
   my ($doSend) = shift;
   my $result  = "<html><table>";
      $result .= "<tr><td colspan='3'>Following statistics data will be sent to server:</br>(see Logfile level 4 for server response)</td></tr>" if($doSend == 1);
      $result .= "<tr><td><b>System Info</b></td></tr>";
      $result .= "<tr><td> </td><td>ConfigType:</td><td>$fhemInfo{$c_system}{'configType'}</td></tr>";
      $result .= "<tr><td> </td><td>SVN rev:</td><td>$fhemInfo{$c_system}{'revision'}</td></tr>" 
                  if (defined($fhemInfo{$c_system}{'revision'}));
      $result .= "<tr><td> </td><td>OS:</td><td>$fhemInfo{$c_system}{'os'}</td></tr>";
      $result .= "<tr><td> </td><td>Perl:</td><td>$fhemInfo{$c_system}{'perl'}</td></tr>";
      $result .= "<tr><td> </td><td>uniqueId:</td><td>"._fi2_shortId()."</td></tr>";
      $result .= "<tr><td colspan=3>&nbsp;</td></tr>";
      $result .= "<tr><td><b>Modules</b></td><td><b>Model</b></td><td><b>Count</b></td></tr>";

   my @keys = keys %fhemInfo;
   foreach my $type (sort @keys)
   {
      next if ($type eq $c_system);
      $fhemInfo{$type}{$c_noModel} //= '';
      $result .= "<tr><td>$type</td><td> </td><td>$fhemInfo{$type}{$c_noModel}</td></tr>";
      while ( my ($model, $count) = each(%{$fhemInfo{$type}}) )
      { $result .= "<tr><td> </td><td>$model</td><td>$fhemInfo{$type}{$model}</td></tr>" unless $model eq $c_noModel; }
   }  

   $result .= "</table></html>";
   return $result;
}

sub _fi2_findRev() {
   my $cf = 'controls_fhem.txt';
   my $filename = (-e "./$cf") ? "./$cf" : AttrVal("global","modpath",".")."/FHEM/$cf";
   my ($err, @content) = FileRead({FileName => $filename, ForceType => "file"});
   return if $err;
   my (undef,$rev) = split (/ /,$content[0]);
   return $rev;
}

sub _fi2_zwave($) {
  my ($zwave) = @_;

  my ($mf, $prod, $id) = split(/-/,$zwave);
  ($mf, $prod, $id) = (lc($mf), lc($prod), lc($id)); # Just to make it sure

  my $xml = $attr{global}{modpath}.
            "/FHEM/lib/openzwave_manufacturer_specific.xml";
  my ($err,@data) = FileRead({FileName => $xml, ForceType=>'file'});
  return $err if($err);

  my ($lastMf, $mName, $ret) = ("","");
  foreach my $l (@data) {
    if($l =~ m/<Manufacturer.*id="([^"]*)".*name="([^"]*)"/) {
      $lastMf = lc($1);
      $mName = $2;
      next;
    }
    if($l =~ m/<Product type\s*=\s*"([^"]*)".*id\s*=\s*"([^"]*)".*name\s*=\s*"([^"]*)"/) {
      if($mf eq $lastMf && $prod eq lc($1) && $id eq lc($2)) {
        $ret = "$mName $3";
        last;
      }
    }
  }
  return $ret if($ret);
  return $zwave;
}

sub _fi2_shortId() {
  return substr($fhemInfo{$c_system}{'uniqueID'},0,3)."...";
}

1;

=pod
=item command
=item summary    display information about the system and FHEM definitions
=item summary_DE zeigt Systeminformationen an
=begin html

<a name="fheminfo"></a>
<h3>fheminfo</h3>
<ul>
  <code>fheminfo [send]</code>
  <br>
  <br>
    fheminfo displays information about the system and FHEM definitions.
  <br>
  <br>
    The optional parameter <code>send</code> transmitts the collected data
    to a central server in order to support the development of FHEM. <br/>
    The submitted data is processed graphically. The results can be viewed
    on <a href="https://fhem.de/stats/statistics.html">http://fhem.de/stats/statistics.html</a>.<br/>
    The IP address will not be stored in database, only used for region determination during send.
  <br>
  <br>
    Features:<br>
    <ul>
      <li>ConfigType (configDB|configFILE)</li>
      <li>SVN rev number</li>
      <li>Operating System Information</li>
      <li>Installed Perl version</li>
      <li>Defined modules</li>
      <li>Defined models per module</li>
    </ul>
  <br>

  <a name="fheminfoattr"></a>
  <b>Attributes</b>
  <br>
  <br>
    The following attributes are used only in conjunction with the
    <code>send</code> parameter. They are set on <code>attr global</code>.
  <br>
  <br>
  <ul>
    <li>sendStatistics<br>
      This attribute is used in conjunction with the <code>update</code> command.
      <br>
      <code>onUpdate</code>: transfer of data on every update (recommended setting).
      <br>
      <code>manually</code>: manually transfer of data via the <code>fheminfo send</code> command.
      <br>
      <code>never</code>: prevents transmission of data at anytime.
    </li>
    <br>
  </ul>
</ul>

=end html
=cut
