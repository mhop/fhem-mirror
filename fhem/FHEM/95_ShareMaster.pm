########################################################################################
#
# ShareMaster.pm
#
# FHEM module for display of stock market shares (stocks, ETF, funds)
#
# Prof. Dr. Peter A. Henning
#
# $Id$
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#########################################################################################

package main;

use strict;
use warnings;

#-- global variables
my $version = "1.0";

my %sharemaster_transtable_DE = ( 
    "symbol"            =>  "Symbol",
    "share"             =>  "Wertpapier",
    "value"             =>  "Wert",
    "change"            =>  "Änderung",
    "absolute"          =>  "abs.",
    "relative"          =>  "rel.",
    "trend"             =>  "Trend",
    "rate"              =>  "Kurs",
    "count"             =>  "Anzahl",
    "total"             =>  "Total",
    "category"          =>  "Kategorie",
    "automotive"        =>  "Auto",
    "bio"               =>  "Bio",
    "chemistry"         =>  "Chemie",
    "commodity"         =>  "Rohstoff",
    "energy"            =>  "Energie",
    "finance"           =>  "Finanz",
    "h2"                =>  "Wasserstoff",
    "health"            =>  "Gesundheit",
    "mobility"          =>  "Mobilität",
    "pharma"            =>  "Pharma",
    "realestate"        =>  "Immo",
    "sales"             =>  "Handel",
    "semiconductor"     =>  "Halbleiter",
    "software"          =>  "Software",
    "tech"              =>  "Technologie"
    );

my %sharemaster_transtable_EN = ( 
    "symbol"            =>  "Symbol",
    "share"             =>  "Stock",
    "value"             =>  "Value",
    "change"            =>  "Change",
    "absolute"          =>  "abs.",
    "relative"          =>  "rel.",
    "trend"             =>  "Trend",
    "rate"              =>  "Rate",
    "count"             =>  "Count",
    "total"             =>  "Total",
    "category"          =>  "Category",
    "automotive"        =>  "Auto",
    "bio"               =>  "Bio",
    "chemistry"         =>  "Chemistry",
    "commodity"         =>  "Commodity",
    "energy"            =>  "Energy",
    "finance"           =>  "Finance",
    "h2"                =>  "Hydrogen",
    "health"            =>  "Health",
    "mobility"          =>  "Mobility",
    "pharma"            =>  "Pharma",
    "realestate"        =>  "RealEstate",
    "sales"             =>  "Sales",
    "semiconductor"     =>  "Semiconductor",
    "software"          =>  "Software",
    "tech"              =>  "Technology"
    );

my $sharemaster_tt;

#########################################################################################
#
# ShareMaster_Initialize 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################
 
sub ShareMaster_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "ShareMaster_Define";
  $hash->{UndefFn}   = "ShareMaster_Undefine";
  $hash->{SetFn}     = "ShareMaster_Set";
  $hash->{GetFn}     = "ShareMaster_Get";
  $hash->{AttrFn}    = "ShareMaster_Attr";
  
  my $attr = "pollInterval colors categories depotCurrency $main::readingFnAttributes";        
  $hash->{AttrList} = $attr;
  
  $hash->{FW_summaryFn} = 'ShareMaster_CollectTables';
  #$hash->{FW_detailFn}  = 'ShareMaster_CollectTables';
  
  if( !defined($sharemaster_tt) ){
    #-- in any attribute redefinition readjust language
    my $lang = AttrVal("global","language","EN");
    if( $lang eq "DE"){
      $sharemaster_tt = \%sharemaster_transtable_DE;
    }else{
      $sharemaster_tt = \%sharemaster_transtable_EN;
    }
  }
}

#########################################################################################
#
# ShareMaster_Define 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  
  Log 1,"[ShareMaster_Define] defining a master depot";
  $hash->{DepotType} = "master";
  $attr{$name}{"pollInterval"}    = 60;
  $attr{$name}{"depotCurrency"}   = "EUR";
  $attr{$name}{"categories"}   = "Automotive,Bio,Chemistry,Commodity,Energy,Finance,H2,Health,Pharma,RealEstate,Sales,Software,Tech";
  my @depots = ();
  for( my $i=2; $i<int(@a); $i++){
    my $singlehash = $defs{$a[$i]};
    my $singlescur = AttrVal($a[$i],"shareCurrency","");
    my $singledcur = AttrVal($a[$i],"depotCurrency","");
    Log 1,"[ShareMaster_Define] integrating single depot ".$a[$i]." with depotCurrency $singledcur and shareCurrency $singlescur";
    push(@depots,$a[$i]);
  } 
  $hash->{"depots"} = \@depots;
  
  if( !defined($sharemaster_tt) ){
    #-- in any attribute redefinition readjust language
    my $lang = AttrVal("global","language","EN");
    if( $lang eq "DE"){
      $sharemaster_tt = \%sharemaster_transtable_DE;
    }else{
      $sharemaster_tt = \%sharemaster_transtable_EN;
    }
  }

  ShareMaster_QueueTimer($hash, 5);
  
  readingsSingleUpdate($hash, "state", "Initialized",1);
  
  return undef;
}

#########################################################################################
#
# ShareMaster_Attr 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  
  if( !defined($sharemaster_tt) ){
    #-- in any attribute redefinition readjust language
    my $lang = AttrVal("global","language","EN");
    if( $lang eq "DE"){
      $sharemaster_tt = \%sharemaster_transtable_DE;
    }else{
      $sharemaster_tt = \%sharemaster_transtable_EN;
    }
  }
  
  return undef;
}

#########################################################################################
#
# ShareMaster_Undefine 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_Undefine($$){
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  return undef;
}
#########################################################################################
#
# ShareMaster_ClearReadings 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_ClearReadings($)
{
  my ($hash, $stockName) = @_;
  delete $hash->{READINGS};
  return undef;
}

#########################################################################################
#
# ShareMaster_DeleteReadings 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_DeleteReadings($$)
{
  my ($hash, $prefix) = @_;

  my $delStr = defined($prefix) ? ".*" . $prefix . "_.*" : ".*";
  fhem("deletereading $hash->{NAME} $delStr", 1);
  return undef;
}

#########################################################################################
#
# ShareMaster_Set 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
   
  if($cmd eq "update") {
    return ShareMaster_QueueTimer($hash, 0);
  }
  elsif($cmd eq "category") {
   if (int(@args) != 2) {
      return "[ShareMaster_Set] invalid arguments, usage 'set $name category <sharename> <comma separated list of categories>";
    }
    return ShareMaster_ChangeCategory($hash, $args[0], $args[1]);
  }
  elsif($cmd eq "clearReadings") {
    return ShareMaster_ClearReadings($hash);
  }
  
  my $res = "Unknown argument " . $cmd . ", choose one of update:noArg clearReadings:noArg";
    
  return $res ;
}

#########################################################################################
#
# ShareMaster_Get 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $res = "Unknown argument " . $cmd . ", choose one of " . 
    "";
  return $res ;
}

#########################################################################################
#
# ShareMaster_QueueTimer 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_QueueTimer($$)
{
  my ($hash, $pollInt) = @_;
  Log3 $hash->{NAME}, 4, "[ShareMaster_QueueTimer] $pollInt seconds";
  
  RemoveInternalTimer($hash);
  delete($hash->{helper}{RUNNING_PID});
  InternalTimer(time() + $pollInt, "ShareMaster_CollectSubdepots", $hash, 0);
  
  return undef;
}

#########################################################################################
#
# ShareMaster_CollectSubdepots 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub ShareMaster_CollectSubdepots($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  #-- depot data
  my %depotSummary = ();
  $depotSummary{"depot_value"} = 0;
  $depotSummary{"depot_diff"} = 0;
  $depotSummary{"depot_value_prev"} = 0;
  $depotSummary{"depot_value_entry"} = 0;
  
  my $exrate = ReadingsNum("$name","exchangerate",1);
  my $cur    = AttrVal("$name","shareCurrency","");
  my $depcur = AttrVal("$name","depotCurrency","");

  
  #-- Categories
  my %depotCategories = ();
  my $cat;
  my $cread  = AttrVal($name,"categories",undef);
  my @acread = ();
  if( $cread ){
    @acread = split(',',$cread);
  }
  
  #-- 
  foreach (@{$hash->{"depots"}}){
    my $subname = $_;
    my $subhash = $defs{$subname};
    $depotSummary{"depot_value"}       += ReadingsVal($subname,"depot_value",0);
    $depotSummary{"depot_value_entry"} += ReadingsVal($subname,"depot_value_entry",0);
    $depotSummary{"depot_diff_day"}    += ReadingsVal($subname,"depot_diff_day",0);
    $depotSummary{"depot_diff"}        += ReadingsVal($subname,"depot_diff",0);
    
    foreach $cat (@acread){
      $cat = lc($cat);
      if (exists($subhash->{DATA}{"categories"}{$cat})){
        $depotCategories{$cat}{"depot_value"} += $subhash->{DATA}{"categories"}{$cat}{"depot_value"};
        $depotCategories{$cat}{"depot_value_entry"} += $subhash->{DATA}{"categories"}{$cat}{"depot_value_entry"};
        $depotCategories{$cat}{"depot_value_prev"} += $subhash->{DATA}{"categories"}{$cat}{"depot_value_prev"};   
      }
    }
  }
  
  #--
  if( $depotSummary{"depot_value"} && ($depotSummary{"depot_value"} > 0)){
    $depotSummary{"depot_change_day"} =  100*$depotSummary{"depot_diff_day"} / ( $depotSummary{"depot_value"} - $depotSummary{"depot_diff_day"} );
  }else{
    $depotSummary{"depot_change_day"} = 0.0;
  }
  if( $depotSummary{"depot_value_entry"} && ($depotSummary{"depot_value_entry"} > 0)){
    $depotSummary{"depot_change"}       =  100*$depotSummary{"depot_diff"} / $depotSummary{"depot_value_entry"};
  }else{
    $depotSummary{"depot_change"} = 0.0;
  }
  
  #-- cleanup readings
  $depotSummary{"depot_value"}        =  sprintf("%.2f", $depotSummary{"depot_value"});
  $depotSummary{"depot_value_entry"}  =  sprintf("%.2f", $depotSummary{"depot_value_entry"});
  $depotSummary{"depot_diff_day"}     =  sprintf("%.2f", $depotSummary{"depot_diff_day"});
  $depotSummary{"depot_diff"}         =  sprintf("%.2f", $depotSummary{"depot_diff"}); 
  $depotSummary{"depot_change_day"}   =  sprintf("%.2f", $depotSummary{"depot_change_day"});
  $depotSummary{"depot_change"}       =  sprintf("%.2f", $depotSummary{"depot_change"}); 
  
  foreach $cat (@acread){
      $cat = lc($cat);
      if (exists($depotCategories{$cat})){
        $depotCategories{$cat}{"depot_value"} = sprintf("%.2f", $depotCategories{$cat}{"depot_value"});
        $depotCategories{$cat}{"depot_value_entry"} = sprintf("%.2f", $depotCategories{$cat}{"depot_value_entry"});
        $depotCategories{$cat}{"depot_value_prev"} = sprintf("%.2f", $depotCategories{$cat}{"depot_value_prev"});   
        $depotCategories{$cat}{"depot_change"} = sprintf("%.2f", 
          (defined($depotCategories{$cat}{"depot_value_entry"}) && $depotCategories{$cat}{"depot_value_entry"} > 0)?100*($depotCategories{$cat}{"depot_value"}/$depotCategories{$cat}{"depot_value_entry"}-1):"0.0");
        $depotCategories{$cat}{"depot_change_day"} = sprintf("%.2f", 
          (defined($depotCategories{$cat}{"depot_value_prev"}) && $depotCategories{$cat}{"depot_value_prev"} > 0)? 100*($depotCategories{$cat}{"depot_value"}/$depotCategories{$cat}{"depot_value_prev"}-1):"0.0");     
      }
  }
  $hash->{DATA}{"categories"} = \%depotCategories;
  #-- 
  readingsBeginUpdate($hash);

  readingsBulkUpdate($hash, "depot_value",  $depotSummary{"depot_value"});
  readingsBulkUpdate($hash, "depot_value_entry",  $depotSummary{"depot_value_entry"});
  readingsBulkUpdate($hash, "depot_diff_day",   $depotSummary{"depot_diff_day"});
  readingsBulkUpdate($hash, "depot_diff", $depotSummary{"depot_diff"});
  readingsBulkUpdate($hash, "depot_change_day",   $depotSummary{"depot_change_day"});
  readingsBulkUpdate($hash, "depot_change",   $depotSummary{"depot_change"});
  readingsBulkUpdate($hash, "depot_summary", 
    $depotSummary{"depot_value"}." ".$depotSummary{"depot_value_entry"}." ".$depotSummary{"depot_change"});
  
  my $str = "";
  foreach $cat (sort keys %depotCategories){
    $cat = lc($cat);
    readingsBulkUpdate($hash, $cat."_depot_value",$depotCategories{$cat}{"depot_value"});
    readingsBulkUpdate($hash, $cat."_depot_change",$depotCategories{$cat}{"depot_change"});
    readingsBulkUpdate($hash, $cat."_depot_change_day",$depotCategories{$cat}{"depot_change_day"});    
    $str .= $cat." ".$depotCategories{$cat}{"depot_value"}." ";
  }
  readingsBulkUpdate($hash, "depot_cat_summary",$str);
  
  readingsEndUpdate($hash, 1);
  
  ShareMaster_QueueTimer($hash, AttrVal($name, "pollInterval", 300));
}

#########################################################################################
#
# ShareMaster_CollectTables 
# 
# Parameters
#
#########################################################################################

sub ShareMaster_CollectTables($$$$){
  my ($FW_wname, $devname, $room, $extPage) = @_;
  
  my $hash = $defs{$devname};
  my $name = $hash->{NAME};
  
  my $ret;
  
  my @colors =  split(',',AttrVal($name, "colors","green,seagreen,black,orangered,red"));
  
  #-- formats for table borders
    my ($stopleft,$stopmid,$stopright,$sbotleft,$sbotmid,$sbotright,$smidleft,$smidmid,$smidright,$saround);
    $stopleft = "border-left:1px solid gray;border-top:1px solid gray;border-top-left-radius:10px;border-top-right-radius:0px;border-bottom-left-radius:0px;";  
    $stopmid  = "border-top:1px solid gray;border-radius:0px;";
    $stopright= "border-right:1px solid gray;border-top:1px solid gray;border-top-right-radius:10px;border-top-left-radius:0px;border-bottom-right-radius:0px;";
    $sbotleft = "border-left:1px solid gray;border-bottom:1px solid gray;border-bottom-left-radius:10px;border-bottom-right-radius:0px;border-top-left-radius:0px;";
    $sbotmid  = "border-bottom:1px solid gray;border-radius:0px;";
    $sbotright= "border-right:1px solid gray;border-bottom:1px solid gray;border-bottom-right-radius:10px;border-top-right-radius:0px;border-bottom-left-radius:0px;";
    $smidleft = "border-left:1px solid gray;border-radius:0px;";
    $smidmid  = "border:none";
    $smidright= "border-right:1px solid gray;border-radius:0px;";
    $saround  = "padding:5px;vertical-align:top;border:1px solid gray;border-radius:10px;";
  
  #-- depot total
  my $change   = $hash->{READINGS}{"depot_change"}{VAL};
  my $changest = 'text-align:right;color:'.(($change>1)?$colors[0]:(($change>0.1)?$colors[1]:(($change==0)?$colors[2]:(($change>-0.1)?$colors[3]:$colors[4]))));
  my $trend   = $hash->{READINGS}{"depot_change_day"}{VAL};
  my $trendf   = $trend."% ".(($trend>1)?"&#129153;":(($trend>0.1)?"&#129157;":(($trend==0)?"&#129154;":(($trend>-0.1)?"&#129158;":"&#129155;"))));
  my $trendst = 'text-align:right;color:'.(($trend>1)?$colors[0]:(($trend>0.1)?$colors[1]:(($trend==0)?$colors[2]:(($trend>-0.1)?$colors[3]:$colors[4]))));        
  
  my $tables = "<table class=\"block wide internals\" style=\"text-align:left;padding-left:6px;padding-right:6px\">\n".
               "<tr class=\"even\" style=\"font-weight:bold;text-align:right\"><td colspan=\"5\" >".
               "<table class=\"block wide internals\" style=\"text-align:left;padding-left:6px;padding-right:6px\">\n".
               "<tr class=\"even\" style=\"font-weight:bold;text-align:right\"><td style=\"$stopleft\" colspan=\"2\">".$hash->{READINGS}{"depot_value"}{TIME}."</td>\n".
                   "<td style=\"text-align:right;$stopmid\">".$sharemaster_tt->{"value"}."</td>\n".
                   "<td style=\"$stopmid;text-align:center\" colspan=\"2\">".$sharemaster_tt->{"change"}."</td>\n".
                   "<td style=\"$stopright;text-align:center\" colspan=\"2\">".$sharemaster_tt->{"trend"}."</td></tr>\n".
                 "<tr class=\"even\" style=\"background-color:#aaaaff;font-weight:bold;text-align:right\"><td style=\"$smidleft\"><a href=\"/fhem?detail=$name\">$name</a></td><td>".$sharemaster_tt->{"total"}."</td>\n".
                   "<td style=\"text-align:right\">".$hash->{READINGS}{"depot_value"}{VAL}."€</td>\n".
                   "<td style=\"$changest\">$change%</td>\n".
                   "<td style=\"$changest\">".$hash->{READINGS}{"depot_diff"}{VAL}."€</td>\n".
                   "<td style=\"$trendst\">$trendf</td>\n".
                   "<td style=\"$trendst;$smidright\">".$hash->{READINGS}{"depot_diff_day"}{VAL}."€</td></tr>\n";
  
  #-- categories
  my %depotCategories = ();
  my $cat;
  my $cread  = AttrVal($name,"categories",undef);
  my @acread = ();
  if( $cread ){
    @acread = split(',',$cread); 
  };  
  
  my $oddeven = 1;
  my $estyle;
  
  foreach $cat (@acread){
    $cat      = lc($cat);
    next if( !exists($hash->{DATA}{"categories"}{$cat }{"depot_value"}));
    $estyle   = ($oddeven == 1)?" class=\"odd\"":" class=\"even\"";
    $oddeven  = 1- $oddeven;
    $change   = $hash->{DATA}{"categories"}{$cat}{"depot_change"};
    $changest = 'text-align:right;color:'.(($change>1)?$colors[0]:(($change>0.1)?$colors[1]:(($change==0)?$colors[2]:(($change>-0.1)?$colors[3]:$colors[4]))));
    $trend    = $hash->{DATA}{"categories"}{$cat}{"depot_change_day"};
    $trendf   = $trend."% ".(($trend>1)?"&#129153;":(($trend>0.1)?"&#129157;":(($trend==0)?"&#129154;":(($trend>-0.1)?"&#129158;":"&#129155;"))));
    $trendst  = 'text-align:right;color:'.(($trend>1)?$colors[0]:(($trend>0.1)?$colors[1]:(($trend==0)?$colors[2]:(($trend>-0.1)?$colors[3]:$colors[4])))); 
    $tables  .= "<tr $estyle style=\"font-weight:normal;text-align:right\"><td style=\"text-align:right;$smidleft\"></td><td style=\"text-align:right\">".$sharemaster_tt->{$cat}."</td><td>".$hash->{DATA}{"categories"}{$cat}{"depot_value"}. 
               "€</td><td style=\"$changest\">$change%</td><td></td><td style=\"$trendst\">$trendf</td><td style=\"$smidright\"></td></tr>\n";
  }
  $tables .=   "<tr $estyle style=\"font-weight:normal;text-align:right\"><td style=\"text-align:right;$sbotleft\"></td><td colspan=\"5\" style=\"$sbotmid\"></td><td style=\"$sbotright\"></td></tr>\n";
  $tables .=   "</table><tr><td></td></tr><tr style=\"font-weight:bold\"><td style=\"$stopleft\">".$sharemaster_tt->{"symbol"}."</td><td style=\"$stopmid\">".$sharemaster_tt->{"share"}."</td>".
               "<td style=\"$stopmid\">".$sharemaster_tt->{"value"}."</td>".
               "<td style=\"$stopmid\">".$sharemaster_tt->{"change"}." ".$sharemaster_tt->{"relative"}."</td><td style=\"$stopmid\">".$sharemaster_tt->{"change"}." ".$sharemaster_tt->{"absolute"}."</td>".
               "<td style=\"$stopmid\">".$sharemaster_tt->{"trend"}."</td><td style=\"$stopmid\">".$sharemaster_tt->{"rate"}."</td><td style=\"$stopmid\">".$sharemaster_tt->{"count"}."</td>".
               "<td style=\"$stopright\">".$sharemaster_tt->{"category"}."</td></tr>\n";
                          
  #-- 
  foreach (@{$hash->{"depots"}}){
    my $subname = $_;
    my $subhash = $defs{$subname};
    $tables .= Shares_MakeTable($subhash);
    Log3 $name, 4,"[ShareMaster_CollectTables] integrating table from single depot ".$subname;
    
  }
  $tables .= "<tr style=\"font-weight:bold\"><td style=\"$sbotleft\"></td><td style=\"$sbotmid\" colspan=\"7\"></td><td style=\"$sbotright\"></td></tr></table>";
    
  $ret = "<div class=\"col2\">".$tables."</div>";
  return $ret;

}

1;

=pod
=item device
=item summary Display of share values in a depot
=item summary_DE Anzeige der Kursdaten von Wertpapieren in einem Depot
=begin html

<a name="ShareMaster"></a>
<h3>ShareMaster</h3>
(en | <a href="commandref_DE.html#ShareMaster">de</a>)
<ul>
	<a name="ShareMaster"></a>
    Display of share values in a depot<br>
   
    
	<b>Define</b>
	<ul>
		<code>define Depot ShareMaster</code><br><br>
	</ul>

	<a name="ShareMasterset"></a>
	 Notes: <ul>
	    <li>The &lt;Symbol&gt; for a particular share depends very much on the source!</li>
        <li>This module uses the global attribute <code>language</code> to determine its output data<br/>
         (default: EN=english). For German output set <code>attr global language DE</code>.</li>
         </ul>
	<b>Set</b>
	<ul>
		<li><code>set &lt;name&gt; clearReadings</code><br>
			Clear all readings.<br><br>
		</li>
		<li><code>set &lt;name&gt; update</code><br>
			Refresh all readings.<br><br>
		</li>
	</ul>

	<a name="ShareMasterattr"></a>
	<b>Attributes</b>
	<ul>
		<li>depotCurrency<br>
            The total depot value will be shown in this currency, also the buy values in the <i>stocks</i> attribute are given in this currency<br>
			Default: EUR<br><br>
		</li>
		<li>categories<br>
		    Comma separated list of categories in this depot, e.g. type of share or industrial segment</li>
		<li>pollInterval<br>
			Refresh interval in seconds.<br>
			Standard: 300, valid values: Number<br><br>
		</li>		
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="ShareMaster"></a>
<h3>ShareMaster</h3>
<ul>
<a href="https://wiki.fhem.de/wiki/Modul_ShareMaster">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="commandref.html#ShareMaster">ShareMaster</a> 
</ul>

=end html_DE
=cut