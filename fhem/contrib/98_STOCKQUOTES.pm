# $Id$

package main;

use strict;
use warnings;
use Blocking;
use Finance::Quote;
use Encode qw(decode encode);
 
sub STOCKQUOTES_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "STOCKQUOTES_Define";
  $hash->{UndefFn}   = "STOCKQUOTES_Undefine";
  $hash->{SetFn}     = "STOCKQUOTES_Set";
  $hash->{GetFn}     = "STOCKQUOTES_Get";
  $hash->{AttrFn}    = "STOCKQUOTES_Attr";
  $hash->{AttrList}  = "pollInterval queryTimeout defaultSource sources stocks currency $main::readingFnAttributes";
}

sub STOCKQUOTES_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  if (scalar(@a) != 2) {
    return "Invalid arguments! Define as 'define <name> STOCKQUOTES'";
  }

  $attr{$hash->{NAME}}{"pollInterval"} = 300;
  $attr{$hash->{NAME}}{"queryTimeout"} = 120;
  $attr{$hash->{NAME}}{"defaultSource"} = "europe";
  $attr{$hash->{NAME}}{"currency"} = "EUR";
  
  $hash->{QUOTER} = Finance::Quote->new;
  $hash->{QUOTER}->timeout(300); # Cancel fetch operation if it takes

  readingsSingleUpdate($hash, "state", "Initialized",1);
  
  STOCKQUOTES_UpdateCurrency($hash);
  STOCKQUOTES_QueueTimer($hash, 5);
  
  return undef;
}

sub STOCKQUOTES_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  if($aName eq "currency") {
    return STOCKQUOTES_UpdateCurrency($hash, $aVal);
  }
  elsif($aName eq "sources") {
    return STOCKQUOTES_ClearReadings($hash);
  }
  
  return undef;
}

sub STOCKQUOTES_UpdateCurrency($;$)
{
  my ($hash, $cur) = @_;
  $cur = AttrVal($hash->{NAME}, "currency", "") if not defined $cur;
  Log3 $hash->{NAME}, 4, "STOCKQUOTES_UpdateCurrency to $cur";
  $hash->{QUOTER}->set_currency($cur);
  
  # delete all readings for the previous currency
  STOCKQUOTES_DeleteReadings($hash, undef);
  
  return undef;
}

sub STOCKQUOTES_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
}

sub STOCKQUOTES_SetStockHashes($$)
{
  my ($hash, $stocks) = @_;
  
  my $str = "";
  my $first = 1;
  foreach my $ex (keys %{ $stocks }) {
    $str .= "," unless $first;
    $first = 0;
    Log3 $hash->{NAME}, 4, "KEY: $ex";
    
    $str .= $ex . ":" . $stocks->{$ex}[0] . ":" . $stocks->{$ex}[1];
  }
  
  Log3 $hash->{NAME}, 5, "STOCKQUOTES_SetStockHashes: $str";
  $attr{$hash->{NAME}}{"stocks"} = $str;
  
  return undef;
}

sub STOCKQUOTES_GetStockHashes($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my @stocks = split ',', AttrVal($name, "stocks", "");

  my %stockHash = ();

  foreach my $stock (@stocks) {
    my @toks = split ":", $stock;
    $stockHash{$toks[0]} = [$toks[1], $toks[2]];
  }
  return \%stockHash;
}

sub STOCKQUOTES_ClearReadings($)
{
  my ($hash, $stockName) = @_;
  delete $hash->{READINGS};
  return undef;
}

sub STOCKQUOTES_DeleteReadings($$)
{
  my ($hash, $prefix) = @_;

  my $delStr = defined($prefix) ? ".*" . $prefix . "_.*" : ".*";
  fhem("deletereading $hash->{NAME} $delStr", 1);
  return undef;
}

sub STOCKQUOTES_RemoveStock($$)
{
  my ($hash, $stockName) = @_;

  my $stocks = STOCKQUOTES_GetStockHashes($hash);
  
  if (not exists $stocks->{$stockName}) {
    return "There is no stock named '$stockName' to delete!";
  }

  Log3 $hash->{NAME}, 3, "STOCKQUOTES_RemoveStock: Removing $stockName";
  delete $stocks->{$stockName};
  if (not exists $stocks->{$stockName}) {
    Log3 $hash->{NAME}, 3, "DELETED";
  }
  
  STOCKQUOTES_SetStockHashes($hash, $stocks);
  
  STOCKQUOTES_DeleteReadings($hash, $stockName);
  
  return undef;
}

sub STOCKQUOTES_ChangeAmount($$$$)
{
  my ($hash, $stockName, $amount, $price) = @_;

  my $stocks = STOCKQUOTES_GetStockHashes($hash);
  
  if (exists $stocks->{$stockName}) {
    $stocks->{$stockName}->[0] += $amount;
    $stocks->{$stockName}->[0] = 0 if ($stocks->{$stockName}[0] < 0);
    $stocks->{$stockName}->[1] += $price;
    
    if ($stocks->{$stockName}->[0] == 0)
    {
      Log3 $hash->{NAME}, 3, "STOCKQUOTES_ChangeAmount: Amount set to 0. Removing stock: $stockName";
      delete $stocks->{$stockName};
      STOCKQUOTES_DeleteReadings($hash, $stockName);
    }
  }
  else {
    $stocks->{$stockName}->[0] = $amount;
    $stocks->{$stockName}->[1] = $price;
  }

  STOCKQUOTES_SetStockHashes($hash, $stocks);
  
  STOCKQUOTES_QueueTimer($hash, 0);
  
  return undef;
}

sub STOCKQUOTES_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  if($cmd eq "buy" or $cmd eq "sell") {
    if (scalar(@args) != 3) {
      return "Invalid arguments! Usage 'set $name $cmd <stockname> <count> <price total>";
    }
    my $stockName = $args[0];
    my $amount = $args[1];
    my $price = $args[2];
    my $fac = ($cmd eq "buy") ? 1 : -1;
    my $str = STOCKQUOTES_ChangeAmount($hash, $stockName, $fac * $amount, $fac * $price);
    STOCKQUOTES_QueueTimer($hash, 0);
    return $str;
  }
  elsif($cmd eq "add") {
    if (scalar(@args) != 1) {
      return "Invalid arguments! Usage 'set $name add <stockname>";
    }
    return STOCKQUOTES_ChangeAmount($hash, $args[0], 0 ,0);
  }
  elsif($cmd eq "remove") {
    if (scalar(@args) != 1) {
      return "Invalid arguments! Usage 'set $name remove <stockname>";
    }
    return STOCKQUOTES_RemoveStock($hash, $args[0]);
  }
  elsif($cmd eq "update") {
    return STOCKQUOTES_QueueTimer($hash, 0);
  }
  elsif($cmd eq "clearReadings") {
    return STOCKQUOTES_ClearReadings($hash);
  }
  
  my $res = "Unknown argument " . $cmd . ", choose one of " . 
    "update buy sell add remove clearReadings";
  return $res ;
}

sub STOCKQUOTES_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  if($cmd eq "sources") {
    if (scalar(@args) != 0) {
      return "Invalid arguments! Usage 'get $name $cmd'";
    }
    return "Available sources: " . join("\n", $hash->{QUOTER}->sources());
  }
  elsif($cmd eq "currency") {
    if (scalar(@args) != 1) {
      return "Invalid arguments! Usage 'get $name $cmd <case-sensitive search name>'";
    }
    my $currs = $hash->{QUOTER}->currency_lookup( name => $args[0] );
    return "Found currencies: " . join(",", keys %{ $currs });
  }

  my $res = "Unknown argument " . $cmd . ", choose one of " . 
    "sources currency";
  return $res ;
}

sub STOCKQUOTES_QueueTimer($$)
{
  my ($hash, $pollInt) = @_;
  Log3 $hash->{NAME}, 4, "STOCKQUOTES_QueueTimer: $pollInt seconds";
  
  RemoveInternalTimer($hash);
  delete($hash->{helper}{RUNNING_PID});
  InternalTimer(time() + $pollInt, "STOCKQUOTES_QueryQuotes", $hash, 0);
  
  return undef;
}

sub STOCKQUOTES_QueryQuotes($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
 
  if (not exists($hash->{helper}{RUNNING_PID})) {
    Log3 $hash->{NAME}, 4, 'STOCKQUOTES: Start blocking query';
    readingsSingleUpdate($hash, "state", "Updating",1);
    $hash->{helper}{RUNNING_PID} = BlockingCall("STOCKQUOTES_QueryQuotesBlocking", 
                                                $hash, 
                                                "STOCKQUOTES_QueryQuotesFinished", 
                                                AttrVal($hash, "queryTimeout", 120),
                                                "STOCKQUOTES_QueryQuotesAbort", 
                                                $hash);
  }
  else {
    Log3 $hash->{NAME}, 4, 'STOCKQUOTES_QueryQuotes: Blocking not started because still one running';
  }
  
  return undef;
}

# return the source that should be used for a stock
sub STOCKQUOTES_GetSource($$)
{
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

sub STOCKQUOTES_QueryQuotesBlocking($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 4, 'STOCKQUOTES_QueryQuotesBlocking';

  my $stocks = STOCKQUOTES_GetStockHashes($hash);
  
  my %sources = ();
  foreach my $symbol (keys %{ $stocks }) {
    my @toks = split ':', $symbol;
    my $symbName = $toks[0];
    
    my $targetSource = STOCKQUOTES_GetSource($hash, $symbName);
    if (not exists $sources{$targetSource}) {
      $sources{$targetSource} = ();
    }
    push(@{$sources{$targetSource}}, $symbName);

    Log3 $name, 4, "STOCKQUOTES_QueryQuotesBlocking: Query stockname: $symbName from source $targetSource"; 
  }
  
  my $ret = $hash->{NAME};
  foreach my $srcKey (keys %sources) {
    Log3 $name, 4, "STOCKQUOTES_QueryQuotesBlocking: Fetching from source: $srcKey"; 
    my %quotes = $hash->{QUOTER}->fetch($srcKey, @{$sources{$srcKey}});

    foreach my $tag (keys %quotes) {
      my @keys = split($;, $tag);
      
      next if $quotes{$keys[0], 'success'} != 1;
      
      my $val = $quotes{$keys[0], $keys[1]};
      next if (not defined $val);
      
      $ret .= "|" . join("&", @keys) . "&";
      $val = encode('UTF-8', $val, Encode::FB_CROAK) if ($keys[1] eq "name");
      $ret .= $val;
    }
  }
  
  Log3 $name, 4, 'STOCKQUOTES_QueryQuotesBlocking Return value: ' . $ret;
  
  #$ret = "myC|A0M16S&currency&EUR|A0M16S&last&125.94|A0M16S&errormsg&|A0M16S&symbol&LU0321021155|A0M16S&time&17:52|A0M16S&isodate&2015-02-16|A0M16S&name&VERMöGENSMANAGEMENT BALANCE A€|A0M16S&source&VWD|A0M16S&price&125.94|A0M16S&date&02/16/2015|A0M16S&success&1";
  return $ret;
}

sub STOCKQUOTES_QueryQuotesAbort($$$)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, 'STOCKQUOTES_QueryQuotesAbort: Blocking call aborted due to timeout!';
  readingsSingleUpdate($hash, "state", "Update aborted",1);

  delete($hash->{helper}{RUNNING_PID});
  STOCKQUOTES_QueueTimer($hash, AttrVal($name, "pollInterval", 300));
  
  return undef;
}

sub STOCKQUOTES_QueryQuotesFinished($)
{
  my ($string) = @_;
 
  return unless(defined($string));
 
  my @a = split("\\|",$string);
  my $name = $a[0];
  my $hash = $defs{$name};
  Log3 $name, 4, 'STOCKQUOTES_QueryQuotesFinished';
  delete($hash->{helper}{RUNNING_PID});

  my $stocks = STOCKQUOTES_GetStockHashes($hash);

  my %stockState = ();
  readingsBeginUpdate($hash);
  for my $i (1 .. $#a)
  {
    my @toks = split '&',$a[$i];
    
    # HACK: replace "3.2%" with "3.2" since we dont want units
    chop $toks[2] if ($toks[1] eq "p_change" and $toks[2] =~ /%$/);

    readingsBulkUpdate($hash, $toks[0] . "_" . $toks[1], $toks[2]);
    
    # build a hash filled with current values
    $stockState{$toks[0]}{$toks[1]} = $toks[2];
  }
  readingsEndUpdate($hash, 1);

  # build depot status
  readingsBeginUpdate($hash);

  foreach my $i (keys %stockState) {
    # we assume that every stockname is also in our stocks-hash. Otherwise something went terribly wrong
    my $stockCount = $stocks->{$i}->[0];
    my $stockBuyPrice = $stocks->{$i}->[1];
    my $last = (exists $stockState{$i}{"last"}) ? $stockState{$i}{"last"} : undef;
    my $previous = (exists $stockState{$i}{"previous"}) ? $stockState{$i}{"previous"} : undef;
    my $stockValue = (defined $last) ? $stockCount * $last : undef;
    my $stockValuePrev = (defined $previous) ? $stockCount * $previous : undef;
        
    # statics
    readingsBulkUpdate($hash, $i . "_d_stockcount", $stockCount);    
    readingsBulkUpdate($hash, $i . "_d_buy_value_total", $stockBuyPrice);
    readingsBulkUpdate($hash, $i . "_d_buy_quote", ($stockCount == 0) ? 0 : sprintf("%.2f", $stockBuyPrice / $stockCount));
    # end
    
    if (defined($stockValue))
    {
        readingsBulkUpdate($hash, $i . "_d_cur_value_total", sprintf("%.2f", $stockValue));
        readingsBulkUpdate($hash, $i . "_d_value_diff_total", sprintf("%.2f", $stockValue - $stockBuyPrice));
        readingsBulkUpdate($hash, $i . "_d_p_change_total", ($stockBuyPrice == 0) ? 0 : sprintf("%.2f", 100.0 * (($stockValue / $stockBuyPrice) - 1 )));
        
        my $valueDiff = (defined $previous and defined $last) ? $stockCount * ($last - $previous) : undef;
        readingsBulkUpdate($hash, $i . "_d_value_diff", sprintf("%.2f", $valueDiff)) if defined $valueDiff;
    }
    if (defined($stockValuePrev))
    {
        readingsBulkUpdate($hash, $i . "_d_prev_value_total", sprintf("%.2f", $stockValuePrev));
    }   
  }
  
  # update depot data
  my %depotSummary = ();
  $depotSummary{"depot_cur_value_total"} = 0;
  $depotSummary{"depot_prev_value_total"} = 0;
  $depotSummary{"depot_value_diff"} = 0;
  $depotSummary{"depot_buy_value_total"} = 0;
  foreach my $i (keys %stockState) {
    $depotSummary{"depot_buy_value_total"} += ReadingsVal($name, $i . "_d_buy_value_total", 0);
    $depotSummary{"depot_cur_value_total"} += ReadingsVal($name, $i . "_d_cur_value_total", 0);
    $depotSummary{"depot_prev_value_total"} += ReadingsVal($name, $i . "_d_prev_value_total", 0);
    $depotSummary{"depot_value_diff"} += ReadingsVal($name, $i . "_d_value_diff", 0);
  }

  readingsBulkUpdate($hash, "depot_buy_value_total", $depotSummary{"depot_buy_value_total"});
  readingsBulkUpdate($hash, "depot_cur_value_total", $depotSummary{"depot_cur_value_total"});
  readingsBulkUpdate($hash, "depot_value_diff_total", sprintf("%.2f", $depotSummary{"depot_cur_value_total"} - $depotSummary{"depot_buy_value_total"}));
  readingsBulkUpdate($hash, "depot_value_diff", sprintf("%.2f", $depotSummary{"depot_value_diff"}));
  
  my $depot_p_change = 0.0;
  if ($depotSummary{"depot_prev_value_total"} > 0.0) {
    $depot_p_change = sprintf("%.2f", 100.0 * (($depotSummary{"depot_cur_value_total"} / $depotSummary{"depot_prev_value_total"}) - 1 ));
  }
  readingsBulkUpdate($hash, "depot_p_change", $depot_p_change);

  my $depot_p_change_total = 0.0;
  if ($depotSummary{"depot_buy_value_total"} > 0.0) {
    $depot_p_change_total = sprintf("%.2f", 100.0 * (($depotSummary{"depot_cur_value_total"} / $depotSummary{"depot_buy_value_total"}) - 1 ));
  }
  readingsBulkUpdate($hash, "depot_p_change_total", $depot_p_change_total);
  
  my $now = gettimeofday();
  my $fmtDateTime = FmtDateTime($now);
  readingsBulkUpdate($hash, "state", $fmtDateTime);
  readingsEndUpdate($hash, 1);

  STOCKQUOTES_QueueTimer($hash, AttrVal($name, "pollInterval", 300));
  
  return undef;
}

1;

=pod
=item device
=item summary fetches stock quotes from data sources
=item summary_DE Kursdaten von Wertpapieren
=begin html

<a name="STOCKQUOTES"></a>
<h3>STOCKQUOTES</h3>
(en | <a href="commandref_DE.html#STOCKQUOTES">de</a>)
<ul>
	<a name="STOCKQUOTES"></a>
    Fetching actual stock quotes from various sources<br>
    <b>Preliminary</b><br>
    Perl module  Finance::Quote must be installed:<br>
    <code>cpan install Finance::Quote</code> or <code>sudo apt-get install libfinance-quote-perl</code><br><br>
    
	<b>Define</b>
	<ul>
		<code>define Depot STOCKQUOTES</code><br><br>
	</ul>

	<a name="STOCKQUOTESset"></a>
	<b>Set</b>
	<ul>
		&lt;Symbol&gt; depends on source. May also an WKN.<br><br>
		<li><code>set &lt;name&gt; buy &lt;Symbol&gt; &lt;Amount&gt; &lt;Value of amount&gt;</code><br>
			Add a stock exchange security. If stock exchange security already exists, new values will be added to old values.<br><br>
		</li>
		<li><code>set &lt;name&gt; sell &lt;Symbol&gt; &lt;Amount&gt; &lt;Value of amount&gt;</code><br>
			Remove a stock exchange security (or an part of it).<br><br>
		</li>
		<li><code>set &lt;name&gt; add &lt;Symbol&gt;</code><br>
			Watch only<br><br>
		</li>
		<li><code>set &lt;name&gt; remove &lt;Symbol&gt;</code><br>
			Remove watched stock exchange security.<br><br>
		</li>
		<li><code>set &lt;name&gt; clearReadings</code><br>
			Clears all readings.<br><br>
		</li>
		<li><code>set &lt;name&gt; update</code><br>
			Refresh all readings.<br><br>
		</li>
	</ul>
  
	<a name="STOCKQUOTESget"></a>
	<b>Get</b>
	<ul>
		<li><code>get &lt;name&gt; sources</code><br>
			Lists all avaiable data sources.<br><br>
		</li>
		<li><code>get &lt;name&gt; currency &lt;Symbol&gt;</code><br>
			Get currency of stock exchange securities<br><br>
		</li>
	</ul>

	<a name="STOCKQUOTESattr"></a>
	<b>Attributes</b>
	<ul>
		<li>currency<br>
			All stock exchange securities will shown in this currency.<br>
			Default: EUR<br><br>
		</li>
		<li>defaultSource<br>
			Default source for stock exchange securities values.<br>
			Default: europe, valid values: from <code>get &lt;name&gt; sources</code><br><br>
		</li>
		<li>queryTimeout<br>
			Fetching timeout in seconds.<br>
			Standard: 120, valid values: Number<br><br>
		</li>
		<li>pollInterval<br>
			Refresh interval in seconds.<br>
			Standard: 300, valid values: Number<br><br>
		</li>		
		<li>sources<br>
			An individual data source can be set for every single stock exchange securities.<br>
			Data sources can be fetched with: <code>get &lt;name&gt; sources</code>.<br>
			Format: &lt;Symbol&gt;:&lt;Source&gt;[,&lt;Symbol&gt;:&lt;Source&gt;...]<br>
			Example: <code>A0M16S:vwd,532669:unionfunds,849104:unionfunds</code><br>
			Stock exchange securities not listed in sources will be updated from defaultSource.<br><br>
		</li>
		<li>stocks<br>
			Will be created/modified via buy/sell/add/remove<br>
			Contains stock exchange securities informations in format: &lt;Symbol&gt;:&lt;Anzahl&gt;:&lt;Einstandswert&gt;[,&lt;Symbol&gt;:&lt;Anzahl&gt;:&lt;Einstandswert&gt;...]<br><br>
		</li>
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="STOCKQUOTES"></a>
<h3>STOCKQUOTES</h3>
(<a href="commandref.html#STOCKQUOTES">en</a> | de)
<ul>
	<a name="STOCKQUOTES"></a>
	Wertpapierdaten von verschiedenen Quellen holen<br>
	<b>Vorbereitung</b><br>
	Perl Modul Finance::Quote muss installiert werden:<br>
	<code>cpan install Finance::Quote</code> oder <code>sudo apt-get install libfinance-quote-perl</code><br><br>
		
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; STOCKQUOTES</code><br><br>
	</ul>

	<a name="STOCKQUOTESset"></a>
	<b>Set</b>
	<ul>
		&lt;Symbol&gt; h&auml;ngt von den jeweiligen Quellen ab. Kann auch eine WKN sein. Hier muss ggf. experimentiert werden.<br><br>
		<li><code>set &lt;name&gt; buy &lt;Symbol&gt; &lt;Menge&gt; &lt;Gesamtpreis&gt;</code><br>
			Wertpapier in Depot einbuchen. Wenn dieses Wertpapier bereits vorhanden ist, werden die Neuen einfach dazuaddiert.<br><br>
		</li>
		<li><code>set &lt;name&gt; sell &lt;Symbol&gt; &lt;Menge&gt; &lt;Gesamtpreis&gt;</code><br>
			Wertpapier (auch Teilmenge) wieder ausbuchen.<br><br>
		</li>
		<li><code>set &lt;name&gt; add &lt;Symbol&gt;</code><br>
			Wertpapier nur beobachten<br><br>
		</li>
		<li><code>set &lt;name&gt; remove &lt;Symbol&gt;</code><br>
			Entferne Wertpapier das nur beobachtet wird.<br><br>
		</li>
		<li><code>set &lt;name&gt; clearReadings</code><br>
			Alle Readings l&ouml;schen.<br><br>
		</li>
		<li><code>set &lt;name&gt; update</code><br>
			Alle Readings aktualisieren.<br><br>
		</li>
	</ul>
	
	<a name="STOCKQUOTESget"></a>
	<b>Get</b>
	<ul>
		<li><code>get &lt;name&gt; sources</code><br>
			Verf&uuml;gbare Datenquellen auflisten. Diese werden f&uuml;r die Attribute defaultSource und sources ben&ouml;tigt<br><br>
		</li>
		<li><code>get &lt;name&gt; currency &lt;Symbol&gt;</code><br>
			Wertpapierw&auml;hrung ermitteln<br><br>
		</li>
	</ul>

	<a name="STOCKQUOTESattr"></a>
	<b>Attribute</b>
	<ul>
		<li>currency<br>
			W&auml;hrung, in der die Wertpapiere angezeigt werden.<br>
			Default: EUR, g&uuml;ltige Werte: W&auml;hrungsk&uuml;rzel<br><br>
		</li>
		<li>defaultSource<br>
			Standardquelle f&uuml;r die Wertpapierdaten.<br>
			Default: europe, g&uuml;ltige Werte: alles was <code>get &lt;name&gt; sources</code> ausgibt.<br><br>
		</li>
		<li>queryTimeout<br>
			Timeout beim holen der Daten in Sekunden.<br>
			Standard: 120, g&uuml;ltige Werte: Zahl<br><br>
		</li>
		<li>pollInterval<br>
			Aktualisierungsintervall in Sekunden.<br>
			Standard: 300, g&uuml;ltige Werte: Zahl<br><br>
		</li>		
		<li>sources<br>
			F&uuml;r jedes Wertpapier kann eine eigene Datenquelle definiert werden.<br>
			Die Datenquellen k&ouml;nnen &uuml;ber <code>get &lt;name&gt; sources</code> angefragt werden.<br>
			Format: &lt;Symbol&gt;:&lt;Source&gt;[,&lt;Symbol&gt;:&lt;Source&gt;...]<br>
			Beispiel: <code>A0M16S:vwd,532669:unionfunds,849104:unionfunds</code><br>
			Alle nicht aufgef&uuml;hrten Werpapiere werden &uuml;ber die defaultSource abgefragt.<br><br>
		</li>
		<li>stocks<br>
			Wird &uuml;ber buy/sell/add/remove angelegt/modifiziert<br>
			Enth&auml;lt die Werpapiere im Format &lt;Symbol&gt;:&lt;Anzahl&gt;:&lt;Einstandswert&gt;[,&lt;Symbol&gt;:&lt;Anzahl&gt;:&lt;Einstandswert&gt;...]<br><br>
		</li>
	</ul><br>
</ul>

=end html_DE
=cut