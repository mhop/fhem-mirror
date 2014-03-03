# $Id$
##############################################################################
#
# configDB.pm
#
# A fhem library to enable configuration from sql database
# instead of plain text file, e.g. fhem.cfg
#
# READ COMMANDREF DOCUMENTATION FOR CORRECT USE!
#
# Copyright: betateilchen ®
# e-mail: fhem.development@betateilchen.de
#
# This file is part of fhem.
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fhem. If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#
# ChangeLog
#
# 2014-03-01 - SVN 5080 - initial release of interface inside fhem.pl
#            - initial release of configDB.pm
#
# 2014-03-02 - added     template files for sqlite in contrib/configDB
#            - updated   commandref (EN) documentation
#            - added     commandref (DE) documentation
#
##############################################################################
#

use DBI;

##################################################
# Forward declarations for functions in fhem.pl
#
sub AnalyzeCommandChain($$;$);
sub Debug($);
sub Log3($$$);

#$cfgDB_svnId = '$Id$';

##################################################
# Read configuration file
#
if(!open(CONFIG, 'configDB.conf')) {
	Log3('configDB', 1, 'Cannot open database configuration file configDB.conf');
	return 0;
}
my @config=<CONFIG>;
close(CONFIG);

my %dbconfig;
eval join("", @config);

my $cfgDB_dbconn	= $dbconfig{connection};
my $cfgDB_dbuser	= $dbconfig{user};
my $cfgDB_dbpass	= $dbconfig{password};
my $cfgDB_dbtype;

(%dbconfig, @config) = (undef,undef);

if($cfgDB_dbconn =~ m/pg:/i) {
	$cfgDB_dbtype ="POSTGRESQL";
	} elsif ($cfgDB_dbconn =~ m/mysql:/i) {
	$cfgDB_dbtype = "MYSQL";
#	} elsif ($cfgDB_dbconn =~ m/oracle:/i) {
#	$cfgDB_dbtype = "ORACLE";
	} elsif ($cfgDB_dbconn =~ m/sqlite:/i) {
	$cfgDB_dbtype = "SQLITE";
	} else {
	$cfgDB_dbtype = "unknown";
}

sub cfgDB_svnId { return "# ".'$Id$' }

##################################################
# Connect to database and return handle
#
sub cfgDB_Connect {
	my $fhem_dbh = DBI->connect(
	"dbi:$cfgDB_dbconn", 
	$cfgDB_dbuser,
	$cfgDB_dbpass,
	{ AutoCommit => 0, RaiseError => 1 },
	) or die $DBI::errstr;
	return $fhem_dbh;
}

sub cfgDB_Uuid{
	my $fhem_dbh = cfgDB_Connect;
	my $uuid;
	$uuid = $fhem_dbh->selectrow_array('select lower(hex(randomblob(16)))') if($cfgDB_dbtype eq 'SQLITE');
	$uuid = $fhem_dbh->selectrow_array('select uuid()') if($cfgDB_dbtype eq 'MYSQL');
	$uuid = $fhem_dbh->selectrow_array('select uuid_generate_v4()') if($cfgDB_dbtype eq 'POSTGRESQL');
	$fhem_dbh->disconnect();
	return $uuid;
}

sub cfgDB_Init {
##################################################
#	Create non-existing database tables 
#	Create default config entries if necessary
#
	my $fhem_dbh = cfgDB_Connect;

	eval { $fhem_dbh->do("CREATE EXTENSION \"uuid-ossp\"") if($cfgDB_dbtype eq 'POSTGRESQL'); };

#	create TABLE fhemconfig if nonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemconfig(COMMAND CHAR(32), DEVICE CHAR(32), P1 CHAR(50), P2 TEXT, VERSION INT, VERSIONUUID CHAR(50))");
#	check TABLE fhemconfig already populated
	my $count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemconfig');
	if($count < 1) {
#		insert default entries to get fhem running
		my $uuid = cfgDB_Uuid;
		$fhem_dbh->do("INSERT INTO fhemversions values (0, '$uuid')");
		cfgDB_InsertLine($fhem_dbh, $uuid, '# added by cfgDB_Init');
		cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global logfile ./log/fhem-%Y-%m-%d.log');
		cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global modpath .');
		cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global userattr devStateIcon devStateStyle icon sortby webCmd');
		cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global verbose 3');
		cfgDB_InsertLine($fhem_dbh, $uuid, 'define telnetPort telnet 7072 global');
		cfgDB_InsertLine($fhem_dbh, $uuid, 'define WEB FHEMWEB 8083 global');
		cfgDB_InsertLine($fhem_dbh, $uuid, 'define Logfile FileLog ./log/fhem-%Y-%m-%d.log fakelog');
#	} else {
#		if entries found and any database changes necessary, they will be done now.
#			eval { $fhem_dbh->do("ALTER TABLE fhemconfig ADD VERSIONUUID VARCHAR(50)"); };
	}

#	create TABLE fhemstate if nonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemstate(stateString TEXT)");

#	create TABLE fhemversions ifnonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemversions(VERSION INT, VERSIONUUID CHAR(50))");

#	close database connection
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();

	return;
}

sub cfgDB_Info {
	my $l = '--------------------';
	$l .= $l;
	$l .= $l;
	$l .= "\n";
	my $r = $l;
	$r .= " configDB Database Information\n";
	$r .= $l;
	$r .= " dbconn: $cfgDB_dbconn\n";
	$r .= " dbuser: $cfgDB_dbuser\n";
	$r .= " dbpass: $cfgDB_dbpass\n";
	$r .= " dbtype: $cfgDB_dbtype\n";
	$r .= " Unknown dbmodel type in configuration file.\n" if $dbtype eq 'unknown';
	$r .= " Only Mysql, Postgresql, Oracle, SQLite are fully supported.\n" if $dbtype eq 'unknown';
	$r .= $l;

	my $fhem_dbh = cfgDB_Connect;
	my ($sth, @line, $row);

#	read versions table statistics
	my $count;
	$count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemconfig');
	$r .= " fhemconfig: $count entries\n\n";
#	read versions creation time
#	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE COMMAND ='#created' ORDER by VERSION" );  
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig as c join fhemversions as v on v.versionuuid=c.versionuuid WHERE COMMAND ='#created' ORDER by v.VERSION" );  
	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$row	 = " Ver $line[6] saved: $line[1] $line[2] $line[3] def: ".
				$fhem_dbh->selectrow_array("SELECT COUNT(*) from fhemconfig where COMMAND = 'define' and VERSIONUUID = '$line[5]'");
		$row	.= " attr: ".
				$fhem_dbh->selectrow_array("SELECT COUNT(*) from fhemconfig where COMMAND = 'attr' and VERSIONUUID = '$line[5]'");
		$r		.= "$row\n";
	}
	$r .= $l;

#	read state table statistics
	$count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemstate');
	$r .= " fhemstate: $count entries saved: ";
#	read state table creation time
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemstate WHERE STATESTRING like '#%'" );  
	$sth->execute();
	while ($row = $sth->fetchrow_array()) {
		(undef,$row) = split(/#/,$row);
		$r .= "$row\n";
	}
	$r .= $l;

	$fhem_dbh->disconnect();

	return $r;
}

sub cfgDB_Recover($) {
	my ($version) = @_;
	my ($cmd, $count, $ret);

	if($version > 0) {
		my $fhem_dbh = cfgDB_Connect;
		$cmd = "SELECT count(*) FROM fhemconfig WHERE VERSIONUUID in (select versionuuid from fhemversions where version = $version)";
		$count = $fhem_dbh->selectrow_array($cmd);

		if($count > 0) {
			my $fromuuid = $fhem_dbh->selectrow_array("select versionuuid from fhemversions where version = $version");
			my $touuid   = cfgDB_Uuid;
#			Delete current version 0
			$fhem_dbh->do("DELETE FROM fhemconfig WHERE VERSIONUUID in (select versionuuid from fhemversions where version = 0)");
			$fhem_dbh->do("update fhemversions set versionuuid = '$touuid' where version = 0");

#			Copy selected version to version 0
			my ($sth, $sth2, @line);
			$cmd = "SELECT * FROM fhemconfig WHERE VERSIONUUID = '$fromuuid'";
			$sth = $fhem_dbh->prepare($cmd);  
			$sth->execute();
			$sth2 = $fhem_dbh->prepare('INSERT INTO fhemconfig values (?, ?, ?, ?, ?, ?)');
			while (@line = $sth->fetchrow_array()) {
				$sth2->execute($line[0], $line[1], $line[2], $line[3], -1, $touuid);
			}
			$fhem_dbh->commit();
			$fhem_dbh->disconnect();

#			Inform user about restart or rereadcfg needed
			$ret  = "Version 0 deleted.\n";
			$ret .= "Version $version copied to version 0\n\n";
			$ret .= "Please use rereadcfg or restart to activate configuration.";
		} else {
			$fhem_dbh->disconnect();
			$ret = "No entries found in version $version.\nNo changes committed to database.";
		}
	} else {
		$ret = 'Please select version 1..n for recovery.';
	}
	return $ret;
}

sub cfgDB_Reorg(;$) {
	my ($lastversion) = @_;
	$lastversion = ($lastversion > 0) ? $lastversion : 3;
	Log3('configDB', 4, "DB Reorg started, keeping last $lastversion versions.");
	my $fhem_dbh = cfgDB_Connect;
	$fhem_dbh->do("delete FROM fhemconfig   where versionuuid in (select versionuuid from fhemversions where version > $lastversion)");
	$fhem_dbh->do("delete from fhemversions where version > $lastversion");
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return " Result after database reorg:\n".cfgDB_Info;
}

sub cfgDB_InsertLine($$$) {
	my ($fhem_dbh, $uuid, $line) = @_;
	my ($c,$d,$p1,$p2) = split(/ /, $line, 4);
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemconfig values (?, ?, ?, ?, ?, ?)');
	$sth->execute($c, $d, $p1, $p2, -1, $uuid);
	return;
}

sub cfgDB_Execute($@) {
	my ($cl, @dbconfig) = @_;
	foreach (@dbconfig){
		my $l = $_;
		$l =~ s/[\r\n]//g;
		AnalyzeCommandChain($cl, $l);
	}
	return;
}

sub cfgDB_SaveCfg {
	my (%devByNr, @rowList);

	map { $devByNr{$defs{$_}{NR}} = $_ } keys %defs;

	for(my $i = 0; $i < $devcount; $i++) {

		my ($h, $d);
		if($comments{$i}) {
			$h = $comments{$i};
		} else {
			$d = $devByNr{$i};
			next if(!defined($d) ||
				$defs{$d}{TEMPORARY} || # e.g. WEBPGM connections
				$defs{$d}{VOLATILE});   # e.g at, will be saved to the statefile
			$h = $defs{$d};
		}

		if(!defined($d)) {
			push @rowList, $h->{TEXT};
			next;
		}

		if($d ne "global") {
			my $def = $defs{$d}{DEF};
			if(defined($def)) {
				$def =~ s/;/;;/g;
				$def =~ s/\n/\\\n/g;
			} else {
				$dev = "";
			}
			push @rowList, "define $d $defs{$d}{TYPE} $def";
		}

		foreach my $a (sort keys %{$attr{$d}}) {
			next if($d eq "global" &&
				($a eq "configfile" || $a eq "version"));
			my $val = $attr{$d}{$a};
			$val =~ s/;/;;/g;
			$val =~ s/\n/\\\n/g;
			push @rowList, "attr $d $a $val";
		}
	}
	
# Insert @rowList into database table
	my $fhem_dbh = cfgDB_Connect;
	my $uuid = cfgDB_Rotate($fhem_dbh);
	$t = localtime;
	$out = "#created $t";
	push @rowList, $out;
	foreach (@rowList) { cfgDB_InsertLine($fhem_dbh, $uuid, $_); }
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return 'configDB saved.';
}

sub cfgDB_SaveState {
	my ($out,$val,$r,$rd,$t,@rowList);

	$t = localtime;
	$out = "#$t";
	push @rowList, $out;

	foreach my $d (sort keys %defs) {
		next if($defs{$d}{TEMPORARY});
		if($defs{$d}{VOLATILE}) {
			$out = "define $d $defs{$d}{TYPE} $defs{$d}{DEF}";
			push @rowList, $out;
		}
		$val = $defs{$d}{STATE};
		if(defined($val) &&
			$val ne "unknown" &&
			$val ne "Initialized" &&
			$val ne "???") {
			$val =~ s/;/;;/g;
			$val =~ s/\n/\\\n/g;
			$out = "setstate $d $val";
			push @rowList, $out;
		}
		$r = $defs{$d}{READINGS};
		if($r) {
			foreach my $c (sort keys %{$r}) {
				$rd = $r->{$c};
				if(!defined($rd->{TIME})) {
					Log3(undef, 4, "WriteStatefile $d $c: Missing TIME, using current time");
					$rd->{TIME} = TimeNow();
				}
				if(!defined($rd->{VAL})) {
					Log3(undef, 4, "WriteStatefile $d $c: Missing VAL, setting it to 0");
					$rd->{VAL} = 0;
				}
				$val = $rd->{VAL};
				$val =~ s/;/;;/g;
				$val =~ s/\n/\\\n/g;
				$out = "setstate $d $rd->{TIME} $c $val";
				push @rowList, $out;
			}
		}
	}

	my $fhem_dbh = cfgDB_Connect;
	$fhem_dbh->do("DELETE FROM fhemstate");
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemstate values ( ? )');
	foreach (@rowList) { $sth->execute( $_ ); }
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return;
}

sub cfgDB_ReadCfg(@) {
	my (@dbconfig) = @_;
	my $fhem_dbh = cfgDB_Connect;
	my ($sth, @line, $row);

	my $uuid = $fhem_dbh->selectrow_array('SELECT VERSIONUUID FROM fhemversions WHERE VERSION = 0');
	if($uuid){
Debug("V0 from uuid: $uuid");
		$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE VERSIONUUID = '$uuid'" );  
	} else {
Debug("V0 from V0");
		$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE VERSION = 0" );  
	}
	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$row = "$line[0] $line[1] $line[2] $line[3]";
		push @dbconfig, $row;
	}
	$fhem_dbh->disconnect();
	return @dbconfig;
}

sub cfgDB_ReadState(@) {
	my (@dbconfig) = @_;
	my $fhem_dbh = cfgDB_Connect;
	my ($sth, $row);

	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemstate" );  
	$sth->execute();
	while ($row = $sth->fetchrow_array()) {
		push @dbconfig, $row;
	}
	$fhem_dbh->disconnect();
	return @dbconfig;
}

sub cfgDB_GlobalAttr {
	my ($sth, @line, $row, @dbconfig);

	my $fhem_dbh = cfgDB_Connect;
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE DEVICE = 'global'" );  
	$sth->execute();

	while (@line = $sth->fetchrow_array()) {
		$row = "$line[0] $line[1] $line[2] $line[3]";
		$line[3] =~ s/#.*//;
		$line[3] =~ s/ .*$//;
		$attr{global}{$line[2]} = $line[3];
	}
	$fhem_dbh->disconnect();
	return;
}

sub cfgDB_Rotate($) {
	my ($fhem_dbh) = @_;
	my $uuid = cfgDB_Uuid;
#	$fhem_dbh->do("UPDATE fhemconfig SET VERSION = VERSION+1");
	$fhem_dbh->do("UPDATE fhemversions SET VERSION = VERSION+1");
	$fhem_dbh->do("INSERT INTO fhemversions values (0, '$uuid')");
	return $uuid;
}

sub cfgDB_ReadAll($){
	my ($cl) = @_;
	# add Config Rows to commandfile
	my @dbconfig = cfgDB_ReadCfg(@dbconfig);
	# add State Rows to commandfile
	@dbconfig = cfgDB_ReadState(@dbconfig);
	# AnalyzeCommandChain for all entries
	cfgDB_Execute($cl, @dbconfig);
	return;
}

sub cfgDB_Migrate {
	Log3('configDB',4,'Starting migration.');
	Log3('configDB',4,'Processing: cfgDB_Init.');
	cfgDB_Init;
	Log3('configDB',4,'Processing: cfgDB_SaveCfg.');
	cfgDB_SaveCfg;
	Log3('configDB',4,'Processing: cfgDB_SaveState.');
	cfgDB_SaveState;
	Log3('configDB',4,'Migration finished.');
	return 'Migration finished.';
}

sub cfgDB_List($) {
	my ($search) = @_;
	my $fhem_dbh = cfgDB_Connect;
	my ($sth, @line, $row, @result, $ret);

	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE VERSION = 0 AND DEVICE like '$search'" );  
	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$row = "$line[0] $line[1] $line[2] $line[3]";
		push @result, "$row";
	}
	$row = $fhem_dbh->do("select lower(hex(randomblob(16)))");
	push @result, "$row";
	$fhem_dbh->disconnect();
	$ret = join("\n", @result);
	return $ret;
}


1;

=pod
=begin html

<a name="configDB"></a>
<h3>configDB</h3>
	<ul>
		Starting with version 5079, fhem can be used with a configuration database instead of a plain text file (e.g. fhem.cfg).<br/>
		This offers the possibility to completely waive all cfg-files, "include"-problems and so on.<br/>
		Furthermore, configDB offers a versioning of several configuration together with the possibility to restore a former configuration.<br/>
		Access to database is provided via perl's database interface DBI.<br/>
		<br/>
		<b>Prerequisits / Installation</b><br/>
		<ul><br/>
		<li>You must have access to a SQL database. Supported database types are SQLITE, MYSQL and POSTGRESQL.</li><br/>
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
				<li>This file <b>must</b> be located in your fhem main directory, e.g. /opt/fhem</li>
			</ul>
			<br/>
			<pre>
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
				<ul>enter <code>{cfgDB_Migrate}</code> into frontend's command line</ul><br/></br>
				Be patient! Migration can take some time, especially on mini-systems like RaspberryPi or Beaglebone.<br/>
				Completed migration will be indicated by a message "Migration finished."<br/>
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
			All functions are called from fhem commandline!<br/>
			<br/>
			<li><code>{cfgDB_Info}</code></li><br/>
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

			<li><code>{cfgDB_Reorg [keep]}</code></li><br/>
				Deletes all stored versions with version number higher than [keep].<br/>
				Default value for optional parameter keep = 3.<br/>
				In above example. <code>{cfgDB_Reorg 2}</code> will delete versions #3 and #4.<br/>
				This function can be used to create a nightly running job for<br/>
				database reorganisation when called from an at-Definition.<br/>
			<br/>

			<li><code>{cfgDB_Recover &lt;version&gt;}</code></li><br/>
				Restores an older version from database archive.<br/>
				<code>{cfgDB_Recover 3}</code> will <b>copy</b> version #3 from database 
				to version #0.<br/>
				Original version #0 will be lost.<br/><br/>
				<b>Important!</b><br/>
				The restored version will <b>NOT</b> be activated automatically!<br/>
				You must do a <code>rereadcfg</code> or - even better - <code>shutdown restart</code> yourself.<br/>
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

=begin html_DE

<a name="configDB"></a>
<h3>configDB</h3>
	<ul>
		Seit version 5079 unterst&uuml;tzt fhem die Verwendung einer SQL Datenbank zum Abspeichern der kompletten Konfiguration<br/>
		Dadurch kann man auf alle cfg Dateien, includes usw. verzichten und die daraus immer wieder resultierenden Probleme vermeiden.<br/>
		Desweiteren gibt es damit eine Versionierung von Konfigurationen und die M&ouml;glichkeit, 
		jederzeit eine &auml;ltere Version wiederherstellen zu k&ouml;nnen.<br/>
		Der Zugriff auf die Datenbank erfolgt &uuml;ber die perl-eigene Datenbankschnittstelle DBI.<br/>
		<br/>
		<b>Voraussetzungen / Installation</b><br/>
		<ul><br/>
		<li>Es muss eine SQL Datenbank verf&uuml;gbar sein, untsrst&uuml;tzt werden SQLITE, MYSQL und POSTGRESQLL.</li><br/>
		<li>Das zum Datenbanktype geh&ouml;rende DBD Modul muss in perl installiert sein,<br/>
				f&uuml;r sqlite3 auf einem Debian System z.B. das Paket libdbd-sqlite3-perl</li><br/>
		<li>Eine leere Datenbank muss angelegt werden, z.B. in sqlite3:<br/>
			<pre>
	mba:fhem udo$ sqlite3 configDB.db

	SQLite version 3.7.13 2012-07-17 17:46:21
	Enter ".help" for instructions
	Enter SQL statements terminated with a ";"
	sqlite> pragma auto_vacuum=2;
	sqlite> .quit

	mba:fhem udo$ 
			</pre></li>
		<li>Die ben&ouml;tigten Datenbanktabellen werden automatisch angelegt.</li><br/>
		<li>Eine Konfigurationsdatei f&uuml;r die Verbindung zur Datenbank muss angelegt werden.<br/>
			<br/>
			<b>WICHTIG:</b>
			<ul><br/>
				<li>Diese Datei <b>muss</b> den Namen "configDB.conf" haben</li>
				<li>Diese Datei <b>muss</b> im fhem Verzeichnis liegen, z.B. /opt/fhem</li>
			</ul>
			<br/>
			<pre>
## f&uuml;r MySQL
################################################################
#%dbconfig= (
#	connection => "mysql:database=configDB;host=db;port=3306",
#	user => "fhemuser",
#	password => "fhempassword",
#);
################################################################
#
## f&uuml;r PostgreSQL
################################################################
#%dbconfig= (
#        connection => "Pg:database=configDB;host=localhost",
#        user => "fhemuser",
#        password => "fhempassword"
#);
################################################################
#
## f&uuml;r SQLite (username and password bleiben bei SQLite leer)
################################################################
#%dbconfig= (
#        connection => "SQLite:dbname=/opt/fhem/configDB.db",
#        user => "",
#        password => ""
#);
################################################################
			</pre></li><br/>
		</ul>

		<b>Aufruf mit einer vollst&auml;ndig neuen fhem Installation</b><br/>
		<ul><br/>
			Sehr einfach... fhem muss lediglich folgendermassen gestartet werden:<br/><br/>
			<ul><code>perl fhem.pl configDB</code></ul><br/>
			<b>configDB</b> ist das Schl&uuml;sselwort, an dem fhem erkennt, <br/>
				dass eine Datenbank f&uuml;r die Konfiguration verwendet werden soll.<br/>
			<br/>
			<b>Das war es schon.</b> Alle Befehle (save, rereadcfg etc) arbeiten wie gewohnt.
		</ul>

		<br/>
		<b>oder:</b><br/>
		<br/>

		<b>&uuml;bertragen einer bestehenden fhem Konfiguration in die Datenbank</b><br/>
		<ul><br/>
			Auch sehr einfach... <br/>
			<br/>
			<li>fhem wird zum letzten Mal mit der fhem.cfg gestartet<br/><br/>
				<ul><code>perl fhem.pl fhem.cfg</code></ul></li><br/>
			<br/>
			<li>Bestehende Konfiguration in die Datenbank &uuml;bertragen<br/><br/>
				<ul><code>{cfgDB_Migrate}</code> in die Befehlszeile der fhem-Oberfl&auml;che eingeben</ul><br/></br>
					Nicht die Geduld verlieren! Die Migration eine Weile dauern, speziell bei Mini-Systemen wie<br/>
					RaspberryPi or Beaglebone.<br/>
					Das Ende der Migration wird durch die Meldung "Migration finished." best&auml;tigt.<br/>
					Die urspr&uuml;ngliche Konfigurationsdatei wird bei diesem Vorgang nicht angetastet.</li><br/>
			<li>fhem beenden.</li><br/>
			<li>fhem mit dem Schl&uuml;sselwort configDB starten<br/><br/>
			<ul><code>perl fhem.pl configDB</code></ul></li><br/>
			<b>configDB</b> ist das Schl&uuml;sselwort, an dem fhem erkennt, <br/>
				dass eine Datenbank f&uuml;r die Konfiguration verwendet werden soll.<br/>
			<br/>
			<b>Das war es schon.</b> Alle Befehle (save, rereadcfg etc) arbeiten wie gewohnt.
		</ul>
		<br/><br/>

		<b>Zus&auml;tzliche Funktionen</b><br/>
		<ul><br/>
			Alle Funktionen werden in der Befehelszeile aufgerufen!<br/>
			<br/>
			<li><code>{cfgDB_Info}</code></li><br/>
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
Ver 0 bezeichnet immer die aktuell geladene Konfiguration.<br/>
<br/>

			<li><code>{cfgDB_Reorg [keep]}</code></li><br/>
				L&ouml;scht alle gespeicherten Versionen mit Versionsnummer &gt; [keep].<br/>
				Standardwert f&uuml;r den optionalen Parameter keep = 3.<br/>
				Im obigen Beispiel w&uuml;rde <code>{cfgDB_Reorg 2}</code> die Versionen #3 und #4 l&ouml;schen.<br/>
				Diese Funktion kann z.B. verwendet werden, um eine regelm&auml;&szlig;ige n&auml;chtliche<br/> 
				Datenbankreorganisation mit Hilfe einer at-Definition einzuplanen.<br/>
			<br/>

			<li><code>{cfgDB_Recover &lt;version&gt;}</code></li><br/>
				Stellt eine &auml;ltere Version aus dem Datenbankarchiv wieder her.<br/>
				<code>{cfgDB_Recover 3}</code>  <b>kopiert</b> die Version #3 aus der Datenbank 
				zur Version #0.<br/>
				Die urspr&uuml;ngliche Version #0 wird dabei gel&ouml;scht.<br/><br/>
				<b>Wichtig!</b><br/>
				Die zur&uuml;ckgeholte Version wird <b>NICHT</b> automatisch aktiviert!<br/>
				Ein <code>rereadcfg</code> oder - besser - <code>shutdown restart</code> muss manuell erfolgen.<br/>
		</ul>
		<br/>
		<br/>
		<b>Hinweise</b><br/>
		<br/>
		<ul>
			<li>Im Verzeichnis contrib/configDB befinden sich zwei Vorlagen f&uuml;r Datenbank und Konfiguration,<br/>
				die durch einfaches Kopieren in das fhem Verzeichnis sofort verwendet werden k&ouml;nnen (Nur f&uuml;r sqlite!).</li>
			<br/>
			<li>Der Men&uuml;punkt "Edit files"-&gt;"config file" wird bei Verwendung von configDB nicht mehr angezeigt.</li>
			<br/>
			<li>Beim Speichern einer Konfiguration nicht ungeduldig werden (egal ob manuell oder durch Klicken auf "save config")<br/>
				Durch das Schreiben der Versionsinformationen dauert das ein paar Sekunden.<br/>
				Der Abschluss des Speichern wird durch eine entsprechende Meldung angezeigt.</li>
			<br/>
			<li>Diese Erweiterung wird laufend weiterentwickelt. Speziell an der Verbesserung der Performance wird gearbeitet.</li>
			<br/>
			<li>Viel Spass!</li>
		</ul>

	</ul>

=end html_DE

=cut
