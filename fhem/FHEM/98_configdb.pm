# $Id$
#

package main;
use strict;
use warnings;
use POSIX;
use configDB;

sub CommandConfigdb;
sub _cfgDB_readConfig();

my @pathname;

sub configdb_Initialize {
  my %hash = (  Fn => "CommandConfigdb",
               Hlp => "help     ,access additional functions from configDB" );
  $cmds{configdb} = \%hash;
}



sub CommandConfigdb {
	my ($cl, $param) = @_;

	sub makeFilename{
		my $f = shift;
		my $filename = "";
		$f =~ s/^["']//; # fix pah strange ideas
		$f =~ s/["']$//; # dto.
		if($f =~ m,^[./],) {
			$filename = $f;
		} else {
			$filename  = $attr{global}{modpath};
			$filename .= "/$f";
		}
		return $filename;
	}

	my @a = split("[ \t][ \t]*", $param);
	my ($cmd, $param1, $param2) = @a;
	$cmd    //= "";
	$param1 //= "";
	$param2 //= "";

	my $configfile = $attr{global}{configfile};
	return "\n error: configDB not used!" unless($configfile eq 'configDB' || $cmd eq 'migrate');

	my $ret;

	if ($cmd eq 'attr') {
		Log3('configdb', 4, "configdb: attr $param1 $param2 requested.");
		if ($param1 eq '' && $param2 eq '') {
		# list attributes
			foreach my $c (sort keys %{$configDB{attr}}) {
				my $val = $configDB{attr}{$c};
				$val =~ s/;/;;/g;
				$val =~ s/\n/\\\n/g;
				$ret .= "configdb attr $c $val\n";
			}
		} elsif(lc($param1) eq '?' || lc($param1) eq 'help') {
		# list all available attributes
				my $l = 0;
			foreach my $c (sort keys %{$configDB{knownAttr}}) {
					$l = length($c) > $l ? length($c) : $l;
				}
			foreach my $c (sort keys %{$configDB{knownAttr}}) {
				my $val = $configDB{knownAttr}{$c};
				$val =~ s/;/;;/g;
				$val =~ s/\n/\\\n/g;
				$ret .= sprintf("%-*s : ",$l,$c)."$val\n";
			}
		} elsif($param2 eq '') {
		# delete attribute
			delete $configDB{attr}{$param1};
			$ret = " attribute $param1 deleted";
			addStructChange('configdb attr',undef,"$param1 (deleted)");

		} else {
		# set attribute
			$configDB{attr}{$param1} = $param2;
			$ret = " attribute $param1 set to value $param2";
							addStructChange('configdb attr',undef,"$param1 $param2 (set)");
		}
	} elsif ($cmd eq 'dump') {
		return _cfgDB_dump($param1);
	} elsif ($cmd eq 'diff') {
		return "\n Syntax: configdb diff <device> <version>" if @a != 3;
		return "Invalid paramaeter '$param2' for diff. Must be a number."
			unless (looks_like_number($param2) || $param2 eq 'current');
		Log3('configdb', 4, "configdb: diff requested for device: $param1 in version $param2.");
		$ret = _cfgDB_Diff($param1, $param2);
	} elsif ($cmd eq 'filedelete') {
		return "\n Syntax: configdb filedelete <pathToFile>" if @a != 2;
		my $filename = makeFilename($param1);
		$ret  = "File $filename ";
		$ret .= defined(_cfgDB_Filedelete($filename)) ? "deleted from" : "not found in";
		$ret .= " database.";
	} elsif ($cmd eq 'fileexport') {
		return "\n Syntax: configdb fileexport <pathToFile>" if @a != 2;
		if ($param1 ne 'all') {
			my $filename = makeFilename($param1);
			$ret = _cfgDB_Fileexport $filename;
		} else { # start export all
			my $flist    = _cfgDB_Filelist(1);
			my @filelist = split(/\n/,$flist);
			undef $flist;
			foreach my $f (@filelist) {
				Log3 (4,undef,"configDB: exporting $f");
				my ($path,$file) = $f =~ m|^(.*[/\\])([^/\\]+?)$|;
				$path = "/tmp/$path";
				eval { qx(mkdir -p $path) } unless (-e "$path");
				$ret .= _cfgDB_Fileexport $f; 
				$ret .= "\n";
			}
		} # end export all
	} elsif ($cmd eq 'fileimport') {
		return "\n Syntax: configdb fileimport <pathToFile>" if @a != 2;
		my $filename = makeFilename($param1);
		if ( -r $filename ) {
			my $filesize = -s $filename;
			$ret = _cfgDB_binFileimport($filename,$filesize);
		} elsif ( -e $filename) {
			$ret = "\n Read error on file $filename";
		} else {
			$ret = "\n File $filename not found.";
		}
	} elsif ($cmd eq 'filelist') {
		return _cfgDB_Filelist;
	} elsif ($cmd eq 'filemove') {
		return "\n Syntax: configdb filemove <pathToFile>" if @a != 2;
		my $filename = makeFilename($param1);
		if ( -r $filename ) {
			my $filesize = -s $filename;
			$ret  = _cfgDB_binFileimport ($filename,$filesize,1);
			$ret .= "\nFile $filename deleted from local filesystem.";
		} elsif ( -e $filename) {
			$ret = "\n Read error on file $filename";
		} else {
			$ret = "\n File $filename not found.";
		}
	} elsif ($cmd eq 'fileshow') {
		return "\n Syntax: configdb fileshow <pathToFile>" if @a != 2;
		my @rets = cfgDB_FileRead($param1);
		my $r = (int(@rets)) ? join "\n",@rets : "File $param1 not found in database.";
		return $r;
	} elsif ($cmd eq 'info') {
		my $raw = lc($param1) eq 'raw' ? 1 : 0;
		Log3('configdb', 4, "info requested.");
		$ret = _cfgDB_Info('$Id$',$raw);
	} elsif ($cmd eq 'list') {
		$param1 = $param1 ? $param1 : '%';
		$param2 = looks_like_number($param2) ? $param2 : 0;
		$ret = "list not allowed for configDB itself.";
		return $ret if($param1 =~ m/configdb/i);
		Log3('configdb', 4, "configdb: list requested for device: $param1 in version $param2.");
		$ret = _cfgDB_Search($param1,$param2,1);
	} elsif ($cmd eq 'migrate') {
		return "\n Migration not possible. Already running with configDB!" if $configfile eq 'configDB';
		$data{cfgDB_debug} = 1 if (lc($param1) eq 'debug');
		Log3('configdb', 4, "configdb: migration requested.");
		$ret = _cfgDB_Migrate;
	} elsif ($cmd eq 'rawList'){
		$data{cfgDB_rawList} = 1;
		my @out = cfgDB_SaveCfg();
		delete $data{cfgDB_rawList};
		return join("\n",@out);
	} elsif ($cmd eq 'recover') {
		return "\n Syntax: configdb recover <version>" if @a != 2;
		return "Invalid paramaeter '$param1' for recover. Must be a number."
			unless looks_like_number($param1);
		Log3('configdb', 4, "configdb: recover for version $param1 requested.");
		$ret = _cfgDB_Recover($param1);
	} elsif ($cmd eq 'renum') {
		Log3('configdb', 4, "configdb: renum requested for device: $param1.");
		return "Unknown device $param1" if !defined $defs{$param1};
		my $oldnum = $defs{$param1}{NR};
		$defs{$param1}{NR} = 2;
		$ret  = "configdb: renum requested for device: $param1 \n";
		$ret .= "use 'save config' and 'shutdown restart' to make changes persistant.";
	} elsif ($cmd eq 'reorg') {
		$param1 = 3 unless $param1;
		return "Invalid paramaeter '$param1' for reorg. Must be a number."
			unless looks_like_number($param1);
		Log3('configdb', 4, "configdb: reorg requested with keep: $param1.");
		$ret = _cfgDB_Reorg($param1);
	} elsif ($cmd eq 'search') {
		return "\n Syntax: configdb search <searchTerm> [searchVersion]" if @a < 2;
		$param1 = $param1 ? $param1 : '%';
		$param2 = looks_like_number($param2) ? $param2 : 0;
		Log3('configdb', 4, "configdb: list requested for device: $param1 in version $param2.");
		$ret = _cfgDB_Search($param1,$param2,0);
	} elsif ($cmd eq 'uuid') {
		$param1 = createUniqueId();
		Log3('configdb', 4, "configdb: uuid requested: $param1");
		$ret = $param1;
	} else { 	
		$ret =	"\n Syntax:\n".
				"         configdb attr [attribute] [value]\n".
				"         configdb diff <device> <version>\n".
				"         configdb dump\n".
				"         configDB filedelete <pathToFilename>\n".
				"         configDB fileimport <pathToFilename>\n".
				"         configDB fileexport <pathToFilename>\n".
				"         configDB filelist\n".
				"         configDB filemove <pathToFilename>\n".
				"         configDB fileshow <pathToFilename>\n".
				"         configdb info\n".
				"         configdb list [device] [version]\n".
				"         configdb migrate\n".
				"         configdb rawList\n".
				"         configdb recover <version>\n".
				"         configdb reorg [keepVersions]\n".
				"         configdb search <searchTerm> [version]\n".
				"         configdb uuid\n".
				"";
	}

	return $ret;
	
}

sub _cfgDB_readConfig() {
	my ($conf,@config);
	if(!open($conf, '<', 'configDB.conf')) {
		Log3('configDB', 1, 'Cannot open database configuration file configDB.conf');
		return 0;
	}
	@config=<$conf>;
	close($conf);

	use vars qw(%configDB);

	my %dbconfig;
## no critic
	eval join("", @config) ;
## use critic

	my $cfgDB_dbconn	= $dbconfig{connection};
	my $cfgDB_dbuser	= $dbconfig{user};
	my $cfgDB_dbpass	= $dbconfig{password};
	my $cfgDB_dbtype;

	%dbconfig = ();
	@config   = ();

	if($cfgDB_dbconn =~ m/pg:/i) {
			$cfgDB_dbtype ="POSTGRESQL";
		} elsif ($cfgDB_dbconn =~ m/mysql:/i) {
			$cfgDB_dbtype = "MYSQL";
		} elsif ($cfgDB_dbconn =~ m/mariadb:/i) {
			$cfgDB_dbtype = "MARIADB";
		} elsif ($cfgDB_dbconn =~ m/sqlite:/i) {
			$cfgDB_dbtype = "SQLITE";
		} else {
			$cfgDB_dbtype = "unknown";
	}

	return($cfgDB_dbconn,$cfgDB_dbuser,$cfgDB_dbpass,$cfgDB_dbtype);
}

1;

=pod
=item command
=item summary    frontend command for configDB configuration
=item summary_DE Befehl zur Konfiguration der configDB
=begin html

<a name="configdb"></a>
<h3>configdb</h3>
	<ul>
		<a href="https://forum.fhem.de/index.php?board=46.0">Link to FHEM forum</a><br/><br/>
		Starting with version 5079, fhem can be used with a configuration database instead of a plain text file (e.g. fhem.cfg).<br/>
		This offers the possibility to completely waive all cfg-files, "include"-problems and so on.<br/>
		Furthermore, configDB offers a versioning of several configuration together with the possibility to restore a former configuration.<br/>
		Detailed information about the available recovery and rescue modes can be found in this forum thread:<br/>
		<a href=https://forum.fhem.de/index.php/topic,86225.0.html>https://forum.fhem.de/index.php/topic,86225.0.html</a> </br> 
		Access to database is provided via perl's database interface DBI.<br/>
		<br/>

		<b>Interaction with other modules</b><br/>
		<ul><br/>
			Currently the fhem modules<br/>
			<br/>
			<li>02_RSS.pm</li>
			<li>10_RHASSPY.pm</li>
			<li>31_Lightscene.pm</li>
			<li>55_InfoPanel.pm</li>
			<li>91_eventTypes</li>
			<li>93_DbLog.pm</li>
			<li>95_holiday.pm</li>
			<li>98_SVG.pm</li>
			<li>98_weekprofile.pm</li>
			<br/>
			will use configDB to read their configuration data from database<br/> 
			instead of formerly used configuration files inside the filesystem.<br/>
			<br/>
			This requires you to import your configuration files from filesystem into database.<br/>
			<br/>
			Examples:<br/>
			<code>configdb fileimport FHEM/nrw.holiday</code><br/>
			<code>configdb fileimport FHEM/myrss.layout</code><br/>
			<code>configdb fileimport www/gplot/xyz.gplot</code><br/>
			<br/>
			<b>This does not affect the definitons of your holiday or RSS entities.</b><br/>
			<br/>
			<b>During migration all external configfiles used in current configuration<br/>
			will be imported aufmatically.</b><br>
			<br/>
			Each fileimport into database will overwrite the file if it already exists in database.<br/>
			<br/>
		</ul><br/>
<br/>

		<b>Prerequisits / Installation</b><br/>
		<ul><br/>
		<li>Please install perl package Text::Diff if not already installed on your system.</li><br/>
		<li>You must have access to a SQL database. Supported database types are SQLITE, MYSQL/MARIADB and POSTGRESQL.</li><br/>
		<li>The corresponding DBD module must be available in your perl environment,<br/>
				e.g. sqlite3 running on a Debian systems requires package libdbd-sqlite3-perl</li><br/>
		<li>Create an empty database, e.g. with sqlite3:<br/>
			<pre>
	mba:fhem udo$ sqlite3 configDB.db

	SQLite version 3.7.13 2012-07-17 17:46:21
	Enter ".help" for instructions
	Enter SQL statements terminated with a ";"
	sqlite> pragma auto_vacuum=2;
	sqlite> .quit

	mba:fhem udo$ 
			</pre></li>
		<li>The database tables will be created automatically.</li><br/>
		<li>Create a configuration file containing the connection string to access database.<br/>
			<br/>
			<b>IMPORTANT:</b>
			<ul><br/>
				<li>This file <b>must</b> be named "configDB.conf"</li>
				<li>This file <b>must</b> be located in the same directory containing fhem.pl and configDB.pm, e.g. /opt/fhem</li>
			</ul>
			<br/>
			<pre>
## for MariaDB
################################################################
#%dbconfig= (
#	connection => "MariaDB:database=configdb;host=127.0.0.1;port=3306",
#	user => "fhemuser",
#	password => "fhempassword",
#);
################################################################
#
## for MySQL
################################################################
#%dbconfig= (
#	connection => "mysql:database=configDB;host=db;port=3306",
#	user => "fhemuser",
#	password => "fhempassword",
#);
################################################################
#
## for PostgreSQL
################################################################
#%dbconfig= (
#        connection => "Pg:database=configDB;host=localhost",
#        user => "fhemuser",
#        password => "fhempassword"
#);
################################################################
#
## for SQLite (username and password stay empty for SQLite)
################################################################
#%dbconfig= (
#        connection => "SQLite:dbname=/opt/fhem/configDB.db",
#        user => "",
#        password => ""
#);
################################################################
			</pre></li><br/>
		</ul>

		<b>Start with a complete new "fresh" fhem Installation</b><br/>
		<ul><br/>
			It's easy... simply start fhem by issuing following command:<br/><br/>
			<ul><code>perl fhem.pl configDB</code></ul><br/>

			<b>configDB</b> is a keyword which is recognized by fhem to use database for configuration.<br/>
			<br/>
			<b>That's all.</b> Everything (save, rereadcfg etc) should work as usual.
		</ul>

		<br/>
		<b>or:</b><br/>
		<br/>

		<b>Migrate your existing fhem configuration into the database</b><br/>
		<ul><br/>
			It's easy, too... <br/>
			<br/>
			<li>start your fhem the last time with fhem.cfg<br/><br/>
				<ul><code>perl fhem.pl fhem.cfg</code></ul></li><br/>
			<br/>
			<li>transfer your existing configuration into the database<br/><br/>
				<ul>enter<br/><br/><code>configdb migrate</code><br/>
				<br/>
				into frontend's command line</ul><br/></br>
				Be patient! Migration can take some time, especially on mini-systems like RaspberryPi or Beaglebone.<br/>
				Completed migration will be indicated by showing database statistics.<br/>
				Your original configfile will not be touched or modified by this step.</li><br/>
			<li>shutdown fhem</li><br/>
			<li>restart fhem with keyword configDB<br/><br/>
			<ul><code>perl fhem.pl configDB</code></ul></li><br/>
			<b>configDB</b> is a keyword which is recognized by fhem to use database for configuration.<br/>
			<br/>
			<b>That's all.</b> Everything (save, rereadcfg etc) should work as usual.
		</ul>
		<br/><br/>

		<b>Additional functions provided</b><br/>
		<ul><br/>
			A new command <code>configdb</code> is propagated to fhem.<br/>
			This command can be used with different parameters.<br/>
			<br/>

		<li><code>configdb attr [attribute] [value]</code></li><br/>
			Provides the possibility to pass attributes to backend and frontend.<br/>
			<br/>
			<code> configdb attr private 1</code> - set the attribute named 'private' to value 1.<br/>
			<br/>
			<code> configdb attr private</code> - delete the attribute named 'private'<br/>
			<br/>
			<code> configdb attr</code> - show all defined attributes.<br/>
			<br/>
			<code> configdb attr ?|help</code> - show a list of available attributes.<br/>
			<br/>

		<li><code>configdb diff &lt;device&gt; &lt;version&gt;</code></li><br/>
			Compare configuration dataset for device &lt;device&gt; 
			from current version 0 with version &lt;version&gt;<br/>
			Example for valid request:<br/>
			<br/>
			<code>configdb diff telnetPort 1</code><br/>
			<br/>
			will show a result like this:
			<pre>
compare device: telnetPort in current version 0 (left) to version: 1 (right)
+--+--------------------------------------+--+--------------------------------------+
| 1|define telnetPort telnet 7072 global  | 1|define telnetPort telnet 7072 global  |
* 2|attr telnetPort room telnet           *  |                                      |
+--+--------------------------------------+--+--------------------------------------+</pre>
			<b>Special: configdb diff all current</b><br/>
			<br/>
			Will show a diff table containing all changes between saved version 0<br/>
			and UNSAVED version from memory (currently running installation).<br/>
<br/>

		<li><code>configdb dump [unzipped]</code></li><br/>
			Create a gzipped dump file from from database.<br/>
			If optional parameter 'unzipped' provided, dump file will be written unzipped.<br/>
			<br/>
<br/>

		<li><code>configdb filedelete &lt;Filename&gt;</code></li><br/>
			Delete file from database.<br/>
			<br/>
<br/>

		<li><code>configdb fileexport &lt;targetFilename&gt;|all</code></li><br/>
			Exports specified file (or all files) from database into filesystem.<br/>
			Example:<br/>
			<br/>
			<code>configdb fileexport FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb fileimport &lt;sourceFilename&gt;</code></li><br/>
			Imports specified text file from from filesystem into database.<br/>
			Example:<br/>
			<br/>
			<code>configdb fileimport FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb filelist</code></li><br/>
			Show a list with all filenames stored in database.<br/>
			<br/>
<br/>

		<li><code>configdb filemove &lt;sourceFilename&gt;</code></li><br/>
			Imports specified fhem file from from filesystem into database and<br/>
			deletes the file from local filesystem afterwards.<br/>
			Example:<br/>
			<br/>
			<code>configdb filemove FHEM/99_myUtils.pm</code><br/>
			<br/>
<br/>

		<li><code>configdb fileshow &lt;Filename&gt;</code></li><br/>
			Show content of specified file stored in database.<br/>
			<br/>
<br/>

		<li><code>configdb info [raw]</code></li><br/>
			Returns some database statistics<br/>
			if optional "raw" selected, version infos will be returned as json"<br/>
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

		<li><code>configdb list [device] [version]</code></li><br/>
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

		<li><code>configdb rawList</code></li><br/>
		    Lists the running configuration in the same order that <br/>
		    would be written to a configuration file.<br/>
		<br/>

		<li><code>configdb recover &lt;version&gt;</code></li><br/>
			Restores an older version from database archive.<br/>
			<code>configdb recover 3</code> will <b>copy</b> version #3 from database 
			to version #0.<br/>
			Original version #0 will be lost.<br/><br/>
			<b>Important!</b><br/>
			The restored version will <b>NOT</b> be activated automatically!<br/>
			You must do a <code>rereadcfg</code> or - even better - <code>shutdown restart</code> yourself.<br/>
<br/>

		<li><code>configdb reorg [keep]</code></li><br/>
			Deletes all stored versions with version number higher than [keep].<br/>
			Default value for optional parameter keep = 3.<br/>
			This function can be used to create a nightly running job for<br/>
			database reorganisation when called from an at-Definition.<br/>
		<br/>

		<li><code>configdb search <searchTerm> [searchVersion]</code></li><br/>
			Search for specified searchTerm in any given version (default=0)<br/>
<pre>
Example:

configdb search %2286BC%

Result:

search result for: %2286BC% in version: 0 
-------------------------------------------------------------------------------- 
define az_RT CUL_HM 2286BC 
define az_RT_Clima CUL_HM 2286BC04 
define az_RT_Climate CUL_HM 2286BC02 
define az_RT_ClimaTeam CUL_HM 2286BC05 
define az_RT_remote CUL_HM 2286BC06 
define az_RT_Weather CUL_HM 2286BC01 
define az_RT_WindowRec CUL_HM 2286BC03 
attr Melder_FAl peerIDs 00000000,2286BC03, 
attr Melder_FAr peerIDs 00000000,2286BC03, 
</pre>
<br/>

		<li><code>configdb uuid</code></li><br/>
			Returns a uuid that can be used for own purposes.<br/>
<br/>

		</ul>
<br/>
<br/>
		<b>Author's notes</b><br/>
		<br/>
		<ul>
			<li>You can find two template files for datebase and configfile (sqlite only!) for easy installation.<br/>
				Just copy them to your fhem installation directory (/opt/fhem) and have fun.</li>
			<br/>
			<li>The frontend option "Edit files"-&gt;"config file" will be removed when running configDB.</li>
			<br/>
			<li>Please be patient when issuing a "save" command 
			(either manually or by clicking on "save config").<br/>
			This will take some moments, due to writing version informations.<br/>
			Finishing the save-process will be indicated by a corresponding message in frontend.</li>
			<br/>
			<li>There still will be some more (planned) development to this extension, 
			especially regarding some perfomance issues.</li>
			<br/>
			<li>Have fun!</li>
		</ul>

	</ul>

=end html

=cut
