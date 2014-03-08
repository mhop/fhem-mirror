# $Id$
# Wrapper module for configDB
package main;

use strict;
use warnings;
use feature qw/say switch/;

sub configDBwrap_Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}     = "configDBwrap_Define";
  $hash->{SetFn}     = "configDBwrap_Set";
  $hash->{GetFn}     = "configDBwrap_Get";
  $hash->{AttrList}  = "private:1,0 ";
}

sub configDBwrap_Define($$) {
  return "configDB not enabled!" unless $attr{global}{configfile} eq 'configDB';
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  return "Wrong syntax: use define <name> configDB" if(int(@a) != 2);
  my @version = split(/ /,cfgDB_svnId);
  readingsSingleUpdate($hash, 'version', "$version[3] - $version[4]", 0);
  readingsSingleUpdate($hash, 'state', 'active', 0);
  return undef;
}

sub configDBwrap_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage = "Unknown argument, choose one of reorg recover";
	return $usage if(int(@a) < 2);
	my $ret;

	given ($a[1]) {

		when ('reorg') {
			$a[2] = $a[2] ? $a[2] : 3;
			$ret = cfgDB_Reorg($a[2]);
		}

		when ('recover') {
			$a[2] = $a[2] ? $a[2] : 3;
			$ret = cfgDB_Recover($a[2]);
		}

		default { $ret = $usage; }

	}

	return $ret;

}

sub configDBwrap_Get($@) {

	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage = "Unknown argument, choose one of diff info:noArg list uuid";
	return $usage if(int(@a) < 2);
	my $ret;

	given ($a[1]) {

		when ('info') {
			$ret = cfgDB_Info;
		}

		when ('list') {
			$a[2] = $a[2] ? $a[2] : '%';
			$a[3] = $a[3] ? $a[3] : 0;
			$ret = cfgDB_List($a[2],$a[3]);
		}

		when ('diff') {
			$ret = cfgDB_Diff($a[2],$a[3]);
		}

		when ('uuid') {
			$ret = _cfgDB_Uuid;
		}

		default { $ret = $usage; }

	}

	return $ret;
}

1;

=pod
=begin html

<a name="configDBwrap"></a>
<h3>configDBwrap</h3>
<ul>
	This module is a wrapper to support set and get compatibility <br/>
	for additional functions provided by configDB.<br/>
	<br/>
	<a name="GDSdefine"></a>
	<b>Define</b>
	<ul>
		<br/>
		<code>define configDB configDBwrap</code>
		<br/><br/>
		Important: the name <b>must</b> be configDB!
	</ul>
	<br/>
	<br/>
	<a name="GDSset"></a>
	<b>Set-Commands</b><br/>
	<br/>
	<ul>
			<li><code>set configDB reorg [keep]</code></li><br/>
				Deletes all stored versions with version number higher than [keep].<br/>
				Default value for optional parameter keep = 3.<br/>
				This function can be used to create a nightly running job for<br/>
				database reorganisation when called from an at-Definition.<br/>
			<br/>

			<li><code>set configDB recover &lt;version&gt;</code></li><br/>
				Restores an older version from database archive.<br/>
				<code>set configDB recover 3</code> will <b>copy</b> version #3 from database 
				to version #0.<br/>
				Original version #0 will be lost.<br/><br/>
				<b>Important!</b><br/>
				The restored version will <b>NOT</b> be activated automatically!<br/>
				You must do a <code>rereadcfg</code> or - even better - <code>shutdown restart</code> yourself.<br/>
	</ul>
	<br/>
	<br/>
	<a name="GDSget"></a>
	<b>Get-Commands</b><br/>
	<br/>
	<ul>
		<li><code>get configDB info</code></li><br/>
			Returns some database statistics<br/>
<pre>
--------------------------------------------------------------------------------
 configDB Database Information
--------------------------------------------------------------------------------
 dbconn: SQLite:dbname=/opt/fhem/configDB.db
 dbuser: 
 dbpass: 
 dbtype: SQLITE
--------------------------------------------------------------------------------
 fhemconfig: 7707 entries

 Ver 0 saved: Sat Mar  1 11:37:00 2014 def: 293 attr: 1248
 Ver 1 saved: Fri Feb 28 23:55:13 2014 def: 293 attr: 1248
 Ver 2 saved: Fri Feb 28 23:49:01 2014 def: 293 attr: 1248
 Ver 3 saved: Fri Feb 28 22:24:40 2014 def: 293 attr: 1247
 Ver 4 saved: Fri Feb 28 22:14:03 2014 def: 293 attr: 1246
--------------------------------------------------------------------------------
 fhemstate: 1890 entries saved: Sat Mar  1 12:05:00 2014
--------------------------------------------------------------------------------
</pre>
Ver 0 always indicates the currently running configuration.<br/>
<br/>

		<li><code>get configDB list [device] [version]</code></li><br/>
			Search for device named [device] in configuration version [version]<br/>
			in database archive.<br/>
			Default value for [device] = % to show all devices.<br/>
			Default value for [version] = 0 to show devices from current version.<br/>
			Examples for valid requests:<br/>
			<br/>
			<code>get configDB list</code><br/>
			<code>get configDB list global</code><br/>
			<code>get configDB list '' 1</code><br/>
			<code>get configDB list global 1</code><br/>
		<br/>

		<li><code>get configDB diff &lt;device&gt; &lt;version&gt;</code></li><br/>
			Compare configuration dataset for device &lt;device&gt; 
			from current version 0 with version &lt;version&gt;<br/>
			Example for valid request:<br/>
			<br/>
			<code>get configDB telnetPort 1</code><br/>
			<br/>
			will show a result like this:
			<pre>
compare device: telnetPort in current version 0 (left) to version: 1 (right)
+--+--------------------------------------+--+--------------------------------------+
| 1|define telnetPort telnet 7072 global  | 1|define telnetPort telnet 7072 global  |
* 2|attr telnetPort room telnet           *  |                                      |
+--+--------------------------------------+--+--------------------------------------+</pre>

		<li><code>get configDB uuid</code></li><br/>
			Returns a uuid that can be used for own purposes.<br/>
	</ul>
	<br/>
	<a name="GDSattr"></a>
	<b>Attributes</b><br/>
	<br/>
	<ul>
		<li><code>private &lt;1|0&gt;</code></li><br/>
			If set to 1 user and password info will not be shown in get ... info.<br/>
	</ul>
	<br/>
	<b>Author's notes</b><br/>
	<br/>
	<ul>
		<li>You may need to install perl package Text::Diff to use the diff-function.</li>
		<br/>
		<li>There still will be some more (planned) development to this extension.</li>
		<br/>
		<li>Have fun!</li>
	</ul>
</ul>

=end html

=begin html_DE

<a name="configDBwrap"></a>
<h3>configDBwrap</h3>
<ul>
	Ein Wrapper-Modul, um die von configDB bereitgestellten Zusatzfunktionen<br/>
	mit regul&auml;ren set und get Befehlen nutzen zu k&ouml;nnen.<br/>
	<br/>
	<a name="GDSdefine"></a>
	<b>Define</b>
	<ul>
		<br/>
		<code>define configDB configDBwrap</code>
		<br/><br/>
		Wichtig: der Name <b>muss</b> configDB lauten!
	</ul>
	<br/>
	<br/>
	<a name="GDSset"></a>
	<b>Set-Befehle</b><br/>
	<br/>
	<ul>
		<li><code>set configDB reorg [keep]</code></li><br/>
			L&ouml;scht alle gespeicherten Konfigurationen mit Versionsnummern gr&ouml;&szlig;er als [keep].<br/>
			Standardwert f&uuml;r den optionalen Parameter keep = 3.<br/>
			Mit dieser Funktion l&auml;&szlig;t sich eine n&auml;chtliche Reorganisation per at umsetzen.<br/>
		<br/>

		<li><code>set configDB recover &lt;version&gt;</code></li><br/>
			Stellt eine &auml;ltere Version aus dem Datenbankarchiv wieder her.<br/>
			<code>set configDB recover 3</code>  <b>kopiert</b> die Version #3 aus der Datenbank 
			zur Version #0.<br/>
			Die urspr&uuml;ngliche Version #0 wird dabei gel&ouml;scht.<br/><br/>
			<b>Wichtig!</b><br/>
			Die zur&uuml;ckgeholte Version wird <b>NICHT</b> automatisch aktiviert!<br/>
			Ein <code>rereadcfg</code> oder - besser - <code>shutdown restart</code> muss manuell erfolgen.<br/>
	</ul>
	<br/>
	<br/>
	<a name="GDSget"></a>
	<b>Get-Befehle</b><br/>
	<br/>
	<ul>
		<li><code>get configDB info</code></li><br/>
			Liefert eine Datenbankstatistik<br/>
<pre>
--------------------------------------------------------------------------------
 configDB Database Information
--------------------------------------------------------------------------------
 dbconn: SQLite:dbname=/opt/fhem/configDB.db
 dbuser: 
 dbpass: 
 dbtype: SQLITE
--------------------------------------------------------------------------------
 fhemconfig: 7707 entries

 Ver 0 saved: Sat Mar  1 11:37:00 2014 def: 293 attr: 1248
 Ver 1 saved: Fri Feb 28 23:55:13 2014 def: 293 attr: 1248
 Ver 2 saved: Fri Feb 28 23:49:01 2014 def: 293 attr: 1248
 Ver 3 saved: Fri Feb 28 22:24:40 2014 def: 293 attr: 1247
 Ver 4 saved: Fri Feb 28 22:14:03 2014 def: 293 attr: 1246
--------------------------------------------------------------------------------
 fhemstate: 1890 entries saved: Sat Mar  1 12:05:00 2014
--------------------------------------------------------------------------------
</pre>
Ver 0 bezeichnet immer die aktuell verwendete Konfiguration.<br/>
<br/>

		<li><code>get configDB list [device] [version]</code></li><br/>
			Sucht das Ger&auml;t [device] in der Konfiguration der Version [version]<br/>
			in der Datenbank.<br/>
			Standardwert f&uuml;r [device] = % um alle Ger&auml;te anzuzeigen<br/>
			Standardwert f&uuml;r [version] = 0 um Ger&auml;te in der aktuellen Version anzuzeigen.<br/>
			Beispiele f&uuml;r g&uuml;ltige Aufrufe:<br/>
			<br/>
			<code>get configDB list</code><br/>
			<code>get configDB list global</code><br/>
			<code>get configDB list '' 1</code><br/>
			<code>get configDB list global 1</code><br/>
		<br/>

		<li><code>get configDB diff &lt;device&gt; &lt;version&gt;</code></li><br/>
			Vergleicht die Konfigurationsdaten des Ger&auml;tes &lt;device&gt; aus der aktuellen Version 0 mit den Daten aus Version &lt;version&gt;<br/>
			Beispielaufruf:<br/>
			<br/>
			<code>get configDB diff telnetPort 1</code><br/>
			<br/>
			liefert ein Ergebnis &auml;hnlich dieser Ausgabe:
			<pre>
compare device: telnetPort in current version 0 (left) to version: 1 (right)
+--+--------------------------------------+--+--------------------------------------+
| 1|define telnetPort telnet 7072 global  | 1|define telnetPort telnet 7072 global  |
* 2|attr telnetPort room telnet           *  |                                      |
+--+--------------------------------------+--+--------------------------------------+</pre>

		<li><code>get configDB uuid</code></li><br/>
			Liefert eine uuid, die man f&uuml;r eigene Zwecke verwenden kann.<br/>
	</ul>
	<br/>
	<a name="GDSattr"></a>
	<b>Attribute</b><br/>
	<br/>
	<ul>
		<li><code>private &lt;1|0&gt;</code></li><br/>
			Benutzername und Passwort werden in get ... info nicht angezeigt, wenn private auf 1 gesetzt wird.<br/>
	</ul>
	<br/>
	<b>Hinweise:</b><br/>
	<br/>
	<ul>
			<br/>
			<li>F&uumlr die Nutzung von get ... diff wird das perl Paket Text::Diff ben&ouml;tigt.</li>
			<br/>
			<li>Diese Erweiterung wird laufend weiterentwickelt.</li>
			<br/>
			<li>Viel Spass!</li>
	</ul>
</ul>

=end html_DE

=cut
