########################################################################################
#
# Shares.pm
#
# FHEM module for display of stock market shares (stocks, ETF, funds)
#
# Prof. Dr. Peter A. Henning
# based on the module 98_STOCKQUOTES.pm by vbs
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
use Blocking;
use Finance::Quote;
use Encode qw(decode encode);

#-- global variables
my $version = "1.0";

my %shares_transtable_DE = ( 
    "symbol"            =>  "Symbol",
    "share"             =>  "Wertpapier",
    "value"             =>  "Wert",
    "change"            =>  "Änderung",
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

my %shares_transtable_EN = ( 
    "symbol"            =>  "Symbol",
    "share"             =>  "Stock",
    "value"             =>  "Value",
    "change"            =>  "Change",
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
    "realestate"        =>  "RelaEstate",
    "sales"             =>  "Sales",
    "semiconductor"     =>  "Semiconductor",
    "software"          =>  "Software",
    "tech"              =>  "Technology"
    );

my $shares_tt;

#########################################################################################
#
# Shares_Initialize 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################
 
sub Shares_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "Shares_Define";
  $hash->{UndefFn}   = "Shares_Undefine";
  $hash->{SetFn}     = "Shares_Set";
  $hash->{GetFn}     = "Shares_Get";
  $hash->{AttrFn}    = "Shares_Attr";
  
  my $attr = "pollInterval queryTimeout colors depotCurrency shareCurrency defaultSource sources sourcesLinks stocks:textField-long ".
             "shareFurtherReadings:multiple,open,close,last,return,high,low,value_entry,value_prev,div_yield,eps,volume,year_range ".
             "$main::readingFnAttributes";        
  $hash->{AttrList} = $attr;
  
  if( !defined($shares_tt) ){
    #-- in any attribute redefinition readjust language
    my $lang = AttrVal("global","language","EN");
    if( $lang eq "DE"){
      $shares_tt = \%shares_transtable_DE;
    }else{
      $shares_tt = \%shares_transtable_EN;
    }
  }
}

#########################################################################################
#
# Shares_Define 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_Define($$){
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  $attr{$name}{"pollInterval"}    = 1800;
  $attr{$name}{"queryTimeout"}    = 120;
  $attr{$name}{"defaultSource"}   = "yahoo_json";
  $attr{$name}{"depotCurrency"}   = "EUR:€";
  $attr{$name}{"shareCurrency"}   = "EUR:€";
  
  #-- readjust language
  if( !defined($shares_tt) ){
    #-- in any attribute redefinition readjust language
    my $lang = AttrVal("global","language","EN");
    if( $lang eq "DE"){
      $shares_tt = \%shares_transtable_DE;
    }else{
      $shares_tt = \%shares_transtable_EN;
    }
  }
 
  $hash->{QUOTER} = Finance::Quote->new(currency_rates => {order => ['ECB','AlphaVantage'], 'alphavantage' => {API_KEY => 'VCJX1KJV1260XUOD'}});
  $hash->{QUOTER}->timeout(300); # Cancel fetch operation if it takes too long
    
  Shares_UpdateCurrency($hash);
  Shares_QueueTimer($hash, 5);

  readingsSingleUpdate($hash, "state", "Initialized",1);
  
  return undef;
}

#########################################################################################
#
# Shares_Attr 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_Attr(@){
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  if( $aName =~/.*Currency/) {
    return Shares_UpdateCurrency($hash);
  }
  elsif($aName eq "sources") {
    return Shares_ClearReadings($hash);
  }
  return undef;
}

#########################################################################################
#
# Shares_UpdateCurrency 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_UpdateCurrency($){
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  
  my $cur    = (split(':',AttrVal($name, "shareCurrency", "")))[0]; 
  my $depcur = (split(':',AttrVal($name, "depotCurrency", "")))[0]; 
  
  if( !defined($hash->{QUOTER})){
    Log3 $name, 1, "[Shares_UpdateCurrency] no quoter defined for depot $name";
    return 1;
  }
  Shares_DeleteReadings($hash, undef);
  $hash->{QUOTER}->set_currency($cur);
  my $exr = $hash->{QUOTER}->currency($cur,"EUR");
  readingsSingleUpdate($hash,"exchangerate",$exr." $depcur/$cur",1);
  Log3 $name, 4, "[Shares_UpdateCurrency] exchangerate = $exr for $depcur/$cur in depot $name";

  return undef;
}

#########################################################################################
#
# Shares_Undefine 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_Undefine($$){
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
}

#########################################################################################
#
# Helper functions
# 
#########################################################################################

sub shares_round($){
  my ($num) = @_;
  return sprintf("%.2f",$num)
}

#########################################################################################
#
# Shares_GetLinkHashes 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_GetLinkHashes($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $sstring = AttrVal($name, "sourcesLinks", "");
  my @links = split (',',$sstring);

  my %linkHash = ();

  foreach my $link (@links) {
    my @toks = split ":", $link;
    $linkHash{$toks[0]} = $toks[1];
  }
  return \%linkHash;
}

#########################################################################################
#
# Shares_SetStockHashes
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_SetStockHashes($$){
  my ($hash, $stocks) = @_;
  my $name  = $hash->{NAME};
  
  #-- attribute stocks contains share informations in format: 
  #   <Symbol>:<Count>:<Value_entry>:<Category>
  #   IMPORTANT
  #   <Value_entry> in attribute is in depot currency
  #   <Value_entry> in hash is in share currency 
  
  my $cur    = (split(':',AttrVal($name, "shareCurrency", "")))[0];
  my $depcur = (split(':',AttrVal($name, "depotCurrency", "")))[0];
  my $exr    = ReadingsNum($name, "exchangerate", 1);
  if( $exr == 0 ){
    Log3 $name,1,"[Shares_SetStockHashes] error: exchangerate is zero ";
    return
  }
  
  my $buyval;
  my $str   = "";
  my $first = 1;
  foreach my $stock (sort keys %{ $stocks }) {
    $str .= ",\n" unless $first;
    $first = 0;
    #-- buy value
    if( $depcur eq $cur ){
      $buyval = $stocks->{$stock}[1];
    }else{
      $buyval = shares_round($stocks->{$stock}[1]*$exr);
      Log3 $name,5,"[Shares_SetStockHashes] share ".$stock." transforming buy value ".$stocks->{$stock}[1]." $cur into $buyval $depcur";
    }
    $str .= $stock.":".$stocks->{$stock}[0].":".$buyval.":".lc($stocks->{$stock}[2]);
  }
  
  Log3 $name, 4, "[Shares_SetStockHashes] setting stocks attribute to $str";
  $attr{$name}{"stocks"} = $str;
  
  return undef;
}

#########################################################################################
#
# Shares_GetStockHashes 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_GetStockHashes($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  #-- attribute stocks contains share informations in format: 
  #   <Symbol>:<Count>:<Value_entry>:<Category>
  #   IMPORTANT
  #   <Value_entry> in attribute is in depot currency
  #   <Value_entry> in hash is in share currency 
  
  my $sstring = AttrVal($name, "stocks", "");
  $sstring =~ s/[\#\n]//g;
  my @stocks = split (',',$sstring);
  
  my $cur    = (split(':',AttrVal($name, "shareCurrency", "")))[0];
  my $depcur = (split(':',AttrVal($name, "depotCurrency", "")))[0];
  my $exr    = ReadingsNum($name, "exchangerate", 1);
  my ($buyval,$category);

  my %stockHash = ();

  foreach my $stock (@stocks) {
    my @toks = split ":", $stock;
    #-- buy value
    if( $depcur eq $cur ){
      $buyval = $toks[2];
    }else{
      $buyval = shares_round($toks[2]/$exr);
      Log3 $name,5,"[Shares_GetStockHashes] share ".$toks[0]." transforming buy value ".$toks[2]." $depcur into $buyval $cur";
    }
    #-- category
    if( !defined($toks[3])){
      Log3 $name,4,"[Shares_GetStockHashes] Share: ".$toks[0]." does not have a category assigned";
      $category = "";
    }else{
      $category = $toks[3];
    }
    $stockHash{$toks[0]} = [$toks[1], $buyval, $category];
  }
  return \%stockHash;
}

#########################################################################################
#
# Shares_ClearReadings 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_ClearReadings($){
  my ($hash, $stockName) = @_;
  delete $hash->{READINGS};
  return undef;
}

#########################################################################################
#
# Shares_DeleteReadings 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_DeleteReadings($$){
  my ($hash, $prefix) = @_;

  my $delStr = defined($prefix) ? ".*".$prefix."_.*" : ".*";
  fhem("deletereading $hash->{NAME} $delStr", 1);
  return undef;
}

#########################################################################################
#
# Shares_RemoveStock 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_RemoveStock($$){
  my ($hash, $stockName) = @_;

  my $stocks = Shares_GetStockHashes($hash);
  
  if (not exists $stocks->{$stockName}) {
    return "[Shares_RemoveStock] error: no share named '$stockName' to delete!";
  }

  Log3 $hash->{NAME}, 3, "[Shares_RemoveStock] removing share $stockName";
  delete $stocks->{$stockName};
  if (not exists $stocks->{$stockName}) {
    Log3 $hash->{NAME}, 3, "DELETED";
  }
  
  Shares_SetStockHashes($hash, $stocks);
  Shares_DeleteReadings($hash, $stockName);
  
  return undef;
}

#########################################################################################
#
# Shares_ChangeAmount 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_ChangeAmount($$$$){
  my ($hash, $stockName, $count, $buyval) = @_;
  my $name = $hash->{NAME};
  
  #   IMPORTANT: parameter $buyval is in depot currency
  #   <Value_entry> in hash is in share currency 
  
  my $stocks = Shares_GetStockHashes($hash);
   
  my $cur    = (split(':',AttrVal($name, "shareCurrency", "")))[0];
  my $depcur = (split(':',AttrVal($name, "depotCurrency", "")))[0];
  my $exr    = ReadingsNum($name, "exchangerate", 1);
  if( $exr == 0 ){
    Log3 $name,1,"[Shares_ChangeAmount] error: exchangerate is zero ";
    return
  }
  
  #-- buy value
  if( $depcur ne $cur ){
    $buyval = shares_round($buyval/$exr);
    Log3 $name,5,"[Shares_ChangeAmount] share ".$stockName." transforming buy value from $depcur into $cur";
  }
      
  if (exists $stocks->{$stockName}) {
    $stocks->{$stockName}->[0] += $count;
    $stocks->{$stockName}->[0] = 0 if ($stocks->{$stockName}[0] < 0);

    Log3 $name, 5, "[Shares_ChangeAmount] previous buy value = ".$stocks->{$stockName}->[1].
      " $cur will be increased by ".$buyval." $cur" ;
    $stocks->{$stockName}->[1] += $buyval;
    
    if ($stocks->{$stockName}->[0] == 0)
    {
      Log3 $hash->{NAME}, 3, "[Shares_ChangeAmount] removing share: $stockName";
      delete $stocks->{$stockName};
      Shares_DeleteReadings($hash, $stockName);
    }
  }
  else {
    $stocks->{$stockName}->[0] = $count;
    $stocks->{$stockName}->[1] = $buyval;
  }

  Shares_SetStockHashes($hash, $stocks);
  Shares_QueueTimer($hash, 0);
  
  return undef;
}

#########################################################################################
#
# Shares_ChangeCategory 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_ChangeCategory($$$){
  my ($hash, $stockName, $category) = @_;

  my $stocks = Shares_GetStockHashes($hash);
  if (not exists $stocks->{$stockName}) {
    return "[Shares_ChangeCategory] error: no share named '$stockName' to change!";
  }
   
  $stocks->{$stockName}->[2] = $category;
  
  Shares_SetStockHashes($hash, $stocks);
  Shares_QueueTimer($hash, 0);

  return undef;
}

#########################################################################################
#
# Shares_Set 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_Set($@){
  my ($hash, $name, $cmd, @args) = @_;
  
  if($cmd eq "buy" or $cmd eq "sell") {
    my $depcur = AttrVal($name,"depotCurrency","");
    if (int(@args) != 3) {
      return "[Shares_Set] invalid arguments, usage 'set $name $cmd <sharename> <count> <price in $depcur>";
    }
    my $stockName = $args[0];
    my $count = $args[1];
    my $price = $args[2];
    my $fac = ($cmd eq "buy") ? 1 : -1;
    my $str = Shares_ChangeAmount($hash, $stockName, $fac * $count, $fac * $price);
    Shares_QueueTimer($hash, 0);
    return $str;
  }
  elsif($cmd eq "add") {
    if (int(@args) != 1) {
      return "[Shares_Set] invalid arguments, usage 'set $name add <sharename>";
    }
    return Shares_ChangeAmount($hash, $args[0], 0 ,0);
  }
  elsif($cmd eq "remove") {
    if (int(@args) != 1) {
      return "[Shares_Set] invalid arguments, usage 'set $name remove <sharename>";
    }
    return Shares_RemoveStock($hash, $args[0]);
  }
  if($cmd eq "update") {
    return Shares_QueueTimer($hash, 0);
  }
  elsif($cmd eq "category") {
   if (int(@args) != 2) {
      return "[Shares_Set] invalid arguments, usage 'set $name category <sharename> <comma separated list of categories>";
    }
    return Shares_ChangeCategory($hash, $args[0], $args[1]);
  }
  elsif($cmd eq "clearReadings") {
    return Shares_ClearReadings($hash);
  }
  
  my $res = "Unknown argument ".$cmd.", choose one of update:noArg clearReadings:noArg buy sell add remove";
    
  return $res ;
}

#########################################################################################
#
# Shares_Get 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_Get($@){
  my ($hash, $name, $cmd, @args) = @_;
  
  if($cmd eq "sources") {
    if (int(@args) != 0) {
      return "Invalid arguments, usage 'get $name $cmd'";
    }
    return "Available sources: ".join("\n", $hash->{QUOTER}->sources());
  }
  elsif($cmd eq "currencies") {
    if (int(@args) != 0) {
      return "Invalid arguments, usage 'get $name $cmd'";
    }
    my $currs = $hash->{QUOTER}->currency_lookup( name => $args[0] );
    return "Found currencies: ".join(",", keys %{ $currs });
  }

  my $res = "Unknown argument ".$cmd.", choose one of ".
    "sources currencies";
  return $res ;
}

#########################################################################################
#
# Shares_QueueTimer 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_QueueTimer($$){
  my ($hash, $pollInt) = @_;
  Log3 $hash->{NAME}, 4, "[Shares_QueueTimer] $pollInt seconds";
  
  RemoveInternalTimer($hash);
  delete($hash->{helper}{RUNNING_PID});
  InternalTimer(time() + $pollInt, "Shares_QueryQuotes", $hash, 0);
  
  return undef;
}

#########################################################################################
#
# Shares_QueryQuotes 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_QueryQuotes($){
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if (not exists($hash->{helper}{RUNNING_PID})) {
    Log3 $hash->{NAME}, 4, '[Shares_QueryQuotes] start blocking query';
    readingsSingleUpdate($hash, "state", "Updating",1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("Shares_QueryQuotesBlocking", 
                                                $hash, 
                                                "Shares_QueryQuotesFinished", 
                                                AttrVal($hash, "queryTimeout", 120),
                                                "Shares_QueryQuotesAbort", 
                                                $hash);
  }
  else {
    Log3 $hash->{NAME}, 4, '[Shares_QueryQuotes] blocking not started because one running already';
  }
  return undef;
}

#########################################################################################
#
# Shares_GetSource 
#
# return the source that should be used for a share
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_GetSource($$){
  my ($hash, $stock) = @_;
  
  my $name = $hash->{NAME};
  my @exs = split ",", AttrVal($name, "sources", "");
  
  my %exHash = ();
  foreach my $ex (@exs) {
    my @tok = split ":", $ex;
    $exHash{$tok[0]} = $tok[1];
  }
  
  if (exists($exHash{$stock})) {
    return $exHash{$stock};
  }
  
  return AttrVal($name, "defaultSource", "europe");
}

#########################################################################################
#
# Shares_QueryQuotesBlocking 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_QueryQuotesBlocking($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 4, '[Shares_QueryQuotesBlocking]';

  my $stocks = Shares_GetStockHashes($hash);
  
  my %sources = ();
  foreach my $symbol (keys %{ $stocks }) {
    my @toks = split ':', $symbol;
    my $symbName = $toks[0];
    
    my $targetSource = Shares_GetSource($hash, $symbName);
    if (not exists $sources{$targetSource}) {
      $sources{$targetSource} = ();
    }
    push(@{$sources{$targetSource}}, $symbName);

    Log3 $name, 4, "[Shares_QueryQuotesBlocking] query share: $symbName from source $targetSource"; 
  }
  
  my $ret = $hash->{NAME};
  foreach my $srcKey (keys %sources) {
    Log3 $name, 4, "[Shares_QueryQuotesBlocking] fetching from source: $srcKey"; 
    my %quotes = $hash->{QUOTER}->fetch($srcKey, @{$sources{$srcKey}});

    foreach my $tag (keys %quotes) {
      my @keys = split($;, $tag);
      
      next if $quotes{$keys[0], 'success'} != 1;
      
      my $val = $quotes{$keys[0], $keys[1]};
      next if (not defined $val);
      
      $ret .= "|".join("&", @keys)."&";
      $val = encode('UTF-8', $val, Encode::FB_CROAK) if ($keys[1] eq "name");
      $ret .= $val;
    }
  }
  
  Log3 $name, 4, '[Shares_QueryQuotesBlocking] return value: '.$ret;
  
  return $ret;
}

#########################################################################################
#
# Shares_QueryQuotesAbort 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_QueryQuotesAbort($$$){
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, '[Shares_QueryQuotesAbort] blocking call aborted due to timeout!';
  readingsSingleUpdate($hash, "state", "Update aborted",1);

  delete($hash->{helper}{RUNNING_PID});
  Shares_QueueTimer($hash, AttrVal($name, "pollInterval", 300));
  
  return undef;
}

#########################################################################################
#
# Shares_QueryQuotesFinished 
# 
# Parameter string = long string with all data obtained from sources
#                    first piece = name of depot 
#
#########################################################################################

sub Shares_QueryQuotesFinished($){
  my ($string) = @_;
 
  return unless(defined($string));
 
  #-- split into array
  my @a = split("\\|",$string);
  my $name = $a[0];
  my $hash = $defs{$name};
  Log3 $name, 4, '[Shares_QueryQuotesFinished]';
  delete($hash->{helper}{RUNNING_PID});
  
  #-- update exchange rate
  Shares_UpdateCurrency($hash);
  
  #-- depot data
  my %depotSummary = ();
  $depotSummary{"depot_value"} = 0;
  $depotSummary{"depot_diff"} = 0;
  $depotSummary{"depot_value_prev"} = 0;
  $depotSummary{"depot_value_entry"} = 0;
  
  my %depotCategories = ();
  #$depotCategories{$j}{"depot_value"} = 0; 
  #$depotCategories{$j}{"depot_value_entry"} = 0; 
  #$depotCategories{$j}{"depot_value_prev"} = 0;  
  
  my $exrate = ReadingsNum("$name","exchangerate",1);
  my $cur    = (split(':',AttrVal($name, "shareCurrency", "")))[0];
  my $depcur = (split(':',AttrVal($name, "depotCurrency", "")))[0];

  my $stocks = Shares_GetStockHashes($hash);
  
  #-- We get lots of data here
  #   needed and present only locally: count[0], value_entry[1]
  #   needed: name,last,close
  #   calculated value,diff,change,diff_daily,change_daily,value_prev,
  #   optionally displayed:  value_entry,quote_entry,open,close,div_yield,high,low,eps,volume,year_range
  #   not needed: currency,date,isodate,exchange,method,success,symbol,type
  
  my $fread = AttrVal($name,"shareFurtherReadings",undef);
  if( $fread){
    $fread = "((".$fread."))";
    $fread =~ s/,/\)\|\(/g
  }else{
    $fread = "empty"
  }

  #-- Categories
  my $cread  = AttrVal($name,"categories",undef);
  my @acread = ();
  if( $cread ){
    @acread = split(',',$cread);
  }
  
  #-- First run through all shares: take long string apart
  my %stockState = ();
  my ($symb,$sname);
  
  readingsBeginUpdate($hash);
  for my $i (1 .. $#a){
    my @toks = split '&',$a[$i];
    #-- take out symbol from name
    if( $toks[1] eq "name"){  
      $symb  = $toks[0];
      $sname = $toks[2];
      $sname =~ /$symb\s\((.*)\)/;
      $sname = $1
        if( $1 ne "" );
      readingsBulkUpdate($hash, $toks[0]."_name" , $sname);
      $stockState{$toks[0]}{"name"}     = $toks[2];
    }elsif( $toks[1] eq "return"){
      readingsBulkUpdate($hash, $toks[0]."_return" , $toks[2]);
      $stockState{$toks[0]}{"return"} = $toks[2];
    }elsif( $toks[1] eq "last"){
      readingsBulkUpdate($hash, $toks[0]."_last" , $toks[2]);
      $stockState{$toks[0]}{"last"} = $toks[2];
    }elsif( $toks[1] eq "close"){
      #-- not yet in readings, need to process after last is defined
      $stockState{$toks[0]}{"close"} = $toks[2];
    #-- take out p from change
    }elsif( $toks[1] eq "p_change"){
      chop $toks[2] if ($toks[2] =~ /%$/);
      readingsBulkUpdate($hash, $toks[0]."_change", $toks[2]);
      $stockState{$toks[0]}{"change"} = $toks[2];
    #-- leave out exchange by default
    }elsif( $toks[1] eq "exchange"){
      readingsBulkUpdate($hash, $toks[0]."_exchange", $toks[2])
        if( "exch" =~ /$fread/ );
      $stockState{$toks[0]}{"exchange"} = $toks[2];
    #-- all others as they are
    }else{
      readingsBulkUpdate($hash, $toks[0]."_".$toks[1], $toks[2])
        if( $toks[1] =~ /$fread/ );
      $stockState{$toks[0]}{$toks[1]} = $toks[2];
    }  
  }
  readingsEndUpdate($hash, 1);
  
  #-- Second run through all shares: derived values
  my ($count,$last,$value,$close,$value_close,$value_entry,$value_diff);
  readingsBeginUpdate($hash);
  
  foreach my $stock (keys %stockState) {
  
    $count = $stocks->{$stock}->[0];
    readingsBulkUpdate($hash, $stock."_count", $count); 
       
    #-- this is in stock currency, remember !
    if( exists $stockState{$stock}{"last"} ){ 
      $last  = $stockState{$stock}{"last"};
      #-- already in readings, but in case we have a return value this must be corrected
      if( $stockState{$stock}{"return"} ){
        $last = $stockState{$stock}{"return"};
        Log3 $name, 1, "[Shares_QueryQuotesFinished] reading \"last\" replaced by \"return\" for $stock";
        readingsBulkUpdate($hash, $stock."_last" , $last);
      }
      $value = $count * $last;
      $depotSummary{"depot_value"} += $value*$exrate;
      readingsBulkUpdate($hash, $stock."_value", shares_round($value));
            
    }else{
      $last  = undef;
      #$value = ??
    }
    
    #-- this is in stock currency, remember !
    if( exists $stockState{$stock}{"close"} ){
      $close = $stockState{$stock}{"close"};
      #-- in London, close value is sometimes 100*close
      if( $last && ($last != 0 ) && (abs($close/$last) > 5)){
        Log3 $name, 1, "[Shares_QueryQuotesFinished] reading \"close\" rescaled by 0.01 for $stock"; 
        $close *= 0.01;
      }
    }else{
      Log3 $name, 1, "[Shares_QueryQuotesFinished] reading \"close\" replaced by \"last\" for $stock";
      $close = $last;
    }  
    readingsBulkUpdate($hash, $stock."_close" , $close)
      if( "close" =~ /$fread/ );
    $value_close = $count * $close;
    readingsBulkUpdate($hash, $stock."_value_prev", shares_round( $value_close))
        if( "value_prev" =~ /$fread/ );
    $depotSummary{"depot_value_prev"} += $value_close*$exrate;
    #--
    if( defined($last) ){
      $value_diff = $count * ($last - $close); 
      readingsBulkUpdate($hash, $stock."_diff_day", shares_round($value_diff)) 
        if( "diff_day" =~ /$fread/ );
      readingsBulkUpdate($hash, $stock."_change_day", ($close != 0)?shares_round( 100.0 * ( $last / $close -1)):0.0) 
        if( "change_day" =~ /$fread/ );
    }
    
    #-- entry value has been transformed to stock currency, remember !
    $value_entry   = $stocks->{$stock}->[1];
    readingsBulkUpdate($hash, $stock."_diff", shares_round($value - $value_entry));
    readingsBulkUpdate($hash, $stock."_change", ($value_entry == 0) ? 0 : shares_round( 100.0 * (($value / $value_entry) - 1 )));
    readingsBulkUpdate($hash, $stock."_value_entry", $value_entry)
      if( "value_entry" =~ /$fread/ );
    readingsBulkUpdate($hash, $stock."_quote_entry", ($count == 0) ? 0 : shares_round( $value_entry / $count))
      if( "quote_entry" =~ /$fread/ );
    $depotSummary{"depot_value_entry"}  += $value_entry*$exrate;
    
    #-- category   
    my $category = $stocks->{$stock}->[2];   
    readingsBulkUpdate($hash, $stock."_category", $category);   
    $depotCategories{$category}{"depot_value"} += $value*$exrate
      if( defined($value));
    $depotCategories{$category}{"depot_value_entry"} += $value_entry*$exrate
      if( defined($value_entry)); 
    $depotCategories{$category}{"depot_value_prev"} += $value_close*$exrate
      if( defined($value_close));    
  }
  
  #-- cleanup readings
  $depotSummary{"depot_value"}       =  shares_round($depotSummary{"depot_value"});
  $depotSummary{"depot_value_entry"} =  shares_round($depotSummary{"depot_value_entry"});
  $depotSummary{"depot_diff_day"}    =  shares_round($depotSummary{"depot_value"} - $depotSummary{"depot_value_prev"});
  $depotSummary{"depot_diff"}        =  shares_round($depotSummary{"depot_value"} - $depotSummary{"depot_value_entry"});
 
  readingsBulkUpdate($hash, "depot_value",  $depotSummary{"depot_value"});
  readingsBulkUpdate($hash, "depot_value_entry",  $depotSummary{"depot_value_entry"});
  readingsBulkUpdate($hash, "depot_diff_day",   $depotSummary{"depot_diff_day"});
  readingsBulkUpdate($hash, "depot_diff", $depotSummary{"depot_diff"});
  
  foreach my $category (keys %depotCategories){
    $depotCategories{$category}{"depot_value"} = shares_round($depotCategories{$category}{"depot_value"});
    $depotCategories{$category}{"depot_value_entry"} = shares_round($depotCategories{$category}{"depot_value_entry"});
    $depotCategories{$category}{"depot_value_prev"} = shares_round($depotCategories{$category}{"depot_value_prev"});    
  }
  $hash->{DATA}{"categories"} = \%depotCategories;
  
  my $depot_change_day = 0.0;
  if ($depotSummary{"depot_value_prev"} > 0.0) {
    $depot_change_day = shares_round(100.0 * (($depotSummary{"depot_value"} / $depotSummary{"depot_value_prev"}) - 1 ));
  }
  readingsBulkUpdate($hash, "depot_change_day", $depot_change_day);

  my $depot_change = 0.0;
  if ($depotSummary{"depot_value_entry"} > 0.0) {
    $depot_change = shares_round(100.0 * (($depotSummary{"depot_value"} / $depotSummary{"depot_value_entry"}) - 1 ));
  }
  readingsBulkUpdate($hash, "depot_change", $depot_change);
  
  #-- todo replace by TIME from reading
  my $now = gettimeofday();
  my $fmtDateTime = FmtDateTime($now);
  
  readingsBulkUpdate($hash,"state",$depotSummary{"depot_value"}." $depcur ( ".$depot_change." % = ".$depotSummary{"depot_diff"}." $depcur)  ".$fmtDateTime);
  readingsEndUpdate($hash, 1);

  Shares_QueueTimer($hash, AttrVal($name, "pollInterval", 300));
  
  return undef;
}

#########################################################################################
#
# Shares_MakeTable 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Shares_MakeTable($){
  
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $exrate = ReadingsNum("$name","exchangerate",1);
  my $cur    = (split(':',AttrVal($name, "shareCurrency", "")))[0];
  my $depcur = (split(':',AttrVal($name, "depotCurrency", "")))[0];
  my @colors =  split(',',AttrVal($name, "colors","green,seagreen,black,orangered,red"));

  my $stocks = Shares_GetStockHashes($hash);
  my $links  = Shares_GetLinkHashes($hash);
  
  my ($estyle,$oddeven,$source,$stock,$estock,$count,$sname,$value,$change,$changest,
      $diff,$trend,$trendf,$trendst,$rate,$erate,$frate,$category);
      
  my $smidleft = "border-left:1px solid gray;border-radius:0px;";
  my $smidright= "border-right:1px solid gray;border-radius:0px;";
      
  $change   = $hash->{READINGS}{"depot_change"}{VAL};
  $changest = 'style="text-align:right;color:'.(($change>1)?$colors[0]:(($change>0.1)?$colors[1]:(($change==0)?$colors[2]:(($change>-0.1)?$colors[3]:$colors[4])))).'"';
  $trend   = $hash->{READINGS}{"depot_change_day"}{VAL};
  $trendf   = $trend."% ".(($trend>1)?"&#129153;":(($trend>0.1)?"&#129157;":(($trend==0)?"&#129154;":(($trend>-0.1)?"&#129158;":"&#129155;"))));
  $trendst = 'style="text-align:right;color:'.(($trend>1)?$colors[0]:(($trend>0.1)?$colors[1]:(($trend==0)?$colors[2]:(($trend>-0.1)?$colors[3]:$colors[4])))).'"';
         
  my $table = "<tr class=\"odd\" style=\"background-color:#aaaaff;font-weight:bold;text-align:right\">".
              "<td style=\"$smidleft\"><a href=\"/fhem?detail=$name\">$name</a></td><td colspan=\"2\" style=\"text-align:right\">".$hash->{READINGS}{"depot_value"}{VAL}.
              "€</td><td $changest>$change".
              "%</td><td $changest>".$hash->{READINGS}{"depot_diff"}{VAL}.
              "€</td><td $trendst>$trendf".
              "</td><td colspan=\"3\" style=\"text-align:right;$smidright\">".$hash->{READINGS}{"depot_value"}{TIME}.
              "</td></tr>\n";

 ##my $td_style = 'style="padding-left:6px;padding-right:6px;"';
   
  $oddeven = 0;
  foreach $stock (sort keys %{$stocks}) {
    #-- link defined?
    my $source = Shares_GetSource($hash, $stock);
    if (not exists $links->{$source}) {
      $estock = $stock;
    }else{
      $source = $links->{$source};
      $source =~ s/\$SYMBOL/$stock/g;
      $estock = "<a href=\"http://".$source."\" target=\"_blank\">$stock</a>";
    }
    $estyle   = ($oddeven == 1)?" class=\"odd\"":" class=\"even\"";
    $oddeven  = 1- $oddeven;
    $sname    = $hash->{READINGS}{$stock."_name"}{VAL};
    $value    = shares_round($hash->{READINGS}{$stock."_value"}{VAL}*$exrate);
    $change   = $hash->{READINGS}{$stock."_change"}{VAL};
    $changest = 'style="text-align:right;color:'.(($change>1)?$colors[0]:(($change>0.1)?$colors[1]:(($change==0)?$colors[2]:(($change>-0.1)?$colors[3]:$colors[4])))).'"';
    $diff     = shares_round($hash->{READINGS}{$stock."_diff"}{VAL}*$exrate);
    $trend    = $hash->{READINGS}{$stock."_change_day"}{VAL};
    $trendf   = $trend."% ".(($trend>1)?"&#129153;":(($trend>0.1)?"&#129157;":(($trend==0)?"&#129154;":(($trend>-0.1)?"&#129158;":"&#129155;"))));
    $trendst  = 'style="text-align:right;color:'.(($trend>1)?$colors[0]:(($trend>0.1)?$colors[1]:(($trend==0)?$colors[2]:(($trend>-0.1)?$colors[3]:$colors[4])))).'"';   
    $rate     = $hash->{READINGS}{$stock."_last"}{VAL};
    $erate    = shares_round($rate*$exrate);
    $frate    = ($cur ne $depcur)?"(".shares_round($rate)." $cur)":"";
    $count    = $stocks->{$stock}->[0];
    $category = $shares_tt->{$stocks->{$stock}->[2]};
    $table   .= "<tr $estyle><td style=\"$smidleft\">$estock</td><td>$sname</td><td>$value€</td><td ".$changest.">$change%</td><td ".$changest.
                ">$diff€</td><td ".$trendst.">$trendf</td><td>$erate€ $frate</td><td>$count</td><td style=\"$smidright\">$category</td></tr>\n";
  }

  return $table;
}

1;

=pod
=item device
=item summary Acquisition and listing of share values  
=item summary_DE Beschaffung und Listing der Kursdaten von Wertpapieren
=begin html

<a name="Shares"></a>
<h3>Shares</h3>
(en | <a href="commandref_DE.html#Shares">de</a>)
<ul>
	<a name="Shares"></a>
   Acquire and display share values<br>
   
	<b>Define</b>
	<ul>
		<code>define Depot Shares</code><br><br>
	</ul>

	<a name="Sharesset"></a>
	 Notes: <ul>
	    <li>The &lt;Symbol&gt; for a particular share depends very much on the source!</li>
        <li>This module uses the global attribute <code>language</code> to determine its output data<br/>
         (default: EN=english). For German output set <code>attr global language DE</code>.</li>
         <li>This module needs the package Finance::Quote. Install with
    <code>cpan install Finance::Quote</code> or <code>sudo apt-get install libfinance-quote-perl</code><br><br></li>
         </ul>
	<b>Set</b>
	<ul>
		<li><code>set &lt;name&gt; buy &lt;Symbol&gt; &lt;Count&gt; &lt;Value <i>in depotCurrency</i>&gt;</code><br>
			Buy some shares. If this particular share already exists, new values will be added to old values.<br><br>
		</li>
		<li><code>set &lt;name&gt; sell &lt;Symbol&gt; &lt;Count&gt; &lt;Value <i>in depotCurrency</i>&gt;</code><br>
			Sell some shares<br><br>
		</li>
		<li><code>set &lt;name&gt; add &lt;Symbol&gt;</code><br>
			Watch this share<br><br>
		</li>
		<li><code>set &lt;name&gt; remove &lt;Symbol&gt;</code><br>
			Remove share from watch list<br><br>
		</li>
		<li><code>set &lt;name&gt; clearReadings</code><br>
			Clear all readings.<br><br>
		</li>
		<li><code>set &lt;name&gt; update</code><br>
			Refresh all readings.<br><br>
		</li>
	</ul>
  
	<a name="Sharesget"></a>
	<b>Get</b>
	<ul>
		<li><code>get &lt;name&gt; sources</code><br>
			Lists all avaialble data sources.<br><br>
		</li>
		<li><code>get &lt;name&gt; currencies</code><br>
			Lists all available currencies.<br><br>
		</li>
	</ul>

	<a name="Sharesattr"></a>
	<b>Attributes</b>
	<ul>
		<li>shareCurrency<br>
			Individual shares will be shown in this currency. <br> 
			Format: <code><ISO-Code for currency>[:<Currency Symbol>]</code><br>
			Default: EUR:€<br><br>
		</li>
		<li>depotCurrency<br>
            The total depot value will be shown in this currency, also the buy values in the <i>stocks</i> attribute are given in this currency<br>
			Format: <code><ISO-Code for currency>[:<Currency Symbol>]</code><br>
			Default: EUR:€<br><br>
		</li>
		<li>queryTimeout<br>
			Fetching timeout in seconds.<br>
			Standard: 120, valid values: Number<br><br>
		</li>
		<li>pollInterval<br>
			Refresh interval in seconds.<br>
			Standard: 300, valid values: Number<br><br>
		</li>		
		<li>defaultSource<br>
			Default source for share values.<br>
			Default: yahoo_json, valid values: from <code>get &lt;name&gt; sources</code><br><br>
		</li>
		<li>sources<br>
			An individual data source can be set for every single share.<br>
			Data sources can be fetched with: <code>get &lt;name&gt; sources</code>.<br>
			Format: &lt;Symbol&gt;:&lt;Source&gt;[,&lt;Symbol&gt;:&lt;Source&gt;...]<br>
			Shares not listed in sources will be updated from defaultSource.<br><br>
		</li>
		 <li>sourcesLinks<br>
			An individual link to obtain details and graphical data can be set for every source.<br>
			The string <code>$SYMBOL</code> in each link will be replaced by the symbol for a share.<br> 
			Format: &lt;Source&gt;:&lt;Link&gt;[,&lt;Source&gt;:&lt;Link&gt;...]<br>
			Example: yahoo_json:de.finance.yahoo.com/quote/$SYMBOL<br><br>	</li>
		<li>stocks<br>
			Will be created/modified via buy/sell/add/remove<br>
			Contains share informations in the format: &lt;Symbol&gt;:&lt;Number&gt;:&lt;Buy value in depotCurrency&gt;:&lt;Category&gt;<br><br>
		</li>
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="Shares"></a>
<h3>Shares</h3>
<ul>
<a href="https://wiki.fhem.de/wiki/Modul_Shares">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="commandref.html#Shares">Shares</a> 
</ul>

=end html_DE
=cut