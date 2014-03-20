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
# 2014-03-03 - changed   performance optimized by using version uuid table
#            - updated   commandref docu for migration
#            - added     cfgDB_svnId for fhem.pl CommandVersion
#            - added     cfgDB_List to show device info from database
#            - updated   commandref docu for cfgDB_List
#
# 2014-03-06 - added     cfgDB_Diff to compare device in two versions
#
# 2014-03-07 - changed   optimized cfgDB_Diff
#                        restructured libraray internally
#                        improved source code documentation
#
##############################################################################
#

use DBI;

##################################################
# Forward declarations for functions in fhem.pl
#
sub AnalyzeCommandChain($$;$);
sub AttrVal($$$);
sub Debug($);
sub Log3($$$);

##################################################
# Forward declarations inside this library
#

sub _cfgDB_Connect;
sub _cfgDB_InsertLine($$$);
sub _cfgDB_Execute($@);
sub _cfgDB_ReadCfg(@);
sub _cfgDB_ReadState(@);
sub _cfgDB_Rotate($);
sub _cfgDB_Uuid;

##################################################
# Read configuration file for DB connection
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
	} elsif ($cfgDB_dbconn =~ m/sqlite:/i) {
	$cfgDB_dbtype = "SQLITE";
	} else {
	$cfgDB_dbtype = "unknown";
}

##################################################
# Basic functions needed for DB configuration
# directly called from fhem.pl
#
# cfgDB_Init, cfgDB_GlobalAttr, cfgDB_ReadAll
# cfgDB_SaveCfg, cfgDB_SaveState, cfgDB_svnId
#

# initialize database, create tables if necessary
sub cfgDB_Init {
##################################################
#	Create non-existing database tables 
#	Create default config entries if necessary
#

	my $fhem_dbh = _cfgDB_Connect;

	eval { $fhem_dbh->do("CREATE EXTENSION \"uuid-ossp\"") if($cfgDB_dbtype eq 'POSTGRESQL'); };

#	create TABLE fhemversions ifnonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemversions(VERSION INT, VERSIONUUID CHAR(50))");

#	create TABLE fhemconfig if nonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemconfig(COMMAND CHAR(32), DEVICE CHAR(32), P1 CHAR(50), P2 TEXT, VERSION INT, VERSIONUUID CHAR(50))");
#	check TABLE fhemconfig already populated
	my $count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemconfig');
	if($count < 1) {
#		insert default entries to get fhem running
		my $uuid = _cfgDB_Uuid;
		$fhem_dbh->do("INSERT INTO fhemversions values (0, '$uuid')");
		_cfgDB_InsertLine($fhem_dbh, $uuid, '#created by cfgDB_Init');
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global logfile ./log/fhem-%Y-%m-%d.log');
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global modpath .');
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global userattr devStateIcon devStateStyle icon sortby webCmd');
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global verbose 3');
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define telnetPort telnet 7072 global');
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define WEB FHEMWEB 8083 global');
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define Logfile FileLog ./log/fhem-%Y-%m-%d.log fakelog');
	}

#	create TABLE fhemstate if nonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemstate(stateString TEXT)");

#	close database connection
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();

	return;
}

# read and set attributes for 'global'
sub cfgDB_GlobalAttr {
	my ($sth, @line, $row, @dbconfig);

	my $fhem_dbh = _cfgDB_Connect;
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE DEVICE = 'global'" );  
	$sth->execute();

	while (@line = $sth->fetchrow_array()) {
		$row = "$line[0] $line[1] $line[2] $line[3]";
		$line[3] =~ s/#.*//;
		$line[3] =~ s/ .*$//;
		$attr{global}{$line[2]} = $line[3];
	}

	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE DEVICE = 'configdb'" );  
	$sth->execute();

	while (@line = $sth->fetchrow_array()) {
		$row = "$line[0] $line[1] $line[2] $line[3]";
		$line[3] =~ s/#.*//;
		$line[3] =~ s/ .*$//;
		$attr{configdb}{$line[2]} = $line[3];
	}

	$fhem_dbh->disconnect();
	return;
}

# read and execute all commands from
# fhemconfig and fhemstate
sub cfgDB_ReadAll($){
	my ($cl) = @_;
	my $ret;
	# add Config Rows to commandfile
	my @dbconfig = _cfgDB_ReadCfg(@dbconfig);
	# add State Rows to commandfile
	@dbconfig = _cfgDB_ReadState(@dbconfig);
	# AnalyzeCommandChain for all entries
	$ret .= _cfgDB_Execute($cl, @dbconfig);
	return $ret if($ret);
	return undef;
}

# rotate all older versions to versionnumber+1
# save running configuration to version 0
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

		foreach my $a (sort keys %{$attr{configdb}}) {
			my $val = $attr{configdb}{$a};
			$val =~ s/;/;;/g;
			$val =~ s/\n/\\\n/g;
			push @rowList, "attr configdb $a $val";
		}

# Insert @rowList into database table
	my $fhem_dbh = _cfgDB_Connect;
	my $uuid = _cfgDB_Rotate($fhem_dbh);
	$t = localtime;
	$out = "#created $t";
	push @rowList, $out;
	foreach (@rowList) { _cfgDB_InsertLine($fhem_dbh, $uuid, $_); }
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return 'configDB saved.';
}

# save statefile
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

	my $fhem_dbh = _cfgDB_Connect;
	$fhem_dbh->do("DELETE FROM fhemstate");
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemstate values ( ? )');
	foreach (@rowList) { $sth->execute( $_ ); }
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return;
}

# return SVN Id, called by fhem's CommandVersion
sub cfgDB_svnId { 
	return "# ".'$Id$' 
}

##################################################
# Basic functions needed for DB configuration
# but not called from fhem.pl directly
#

# connect do database
sub _cfgDB_Connect {
	my $fhem_dbh = DBI->connect(
	"dbi:$cfgDB_dbconn", 
	$cfgDB_dbuser,
	$cfgDB_dbpass,
	{ AutoCommit => 0, RaiseError => 1 },
	) or die $DBI::errstr;
	return $fhem_dbh;
}

# add configuration entry into fhemconfig
sub _cfgDB_InsertLine($$$) {
	my ($fhem_dbh, $uuid, $line) = @_;
	my ($c,$d,$p1,$p2) = split(/ /, $line, 4);
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemconfig values (?, ?, ?, ?, ?, ?)');
	$sth->execute($c, $d, $p1, $p2, -1, $uuid);
	return;
}

# pass command table to AnalyzeCommandChain
sub _cfgDB_Execute($@) {
	my ($cl, @dbconfig) = @_;
	my $ret;
	foreach (@dbconfig){
		my $l = $_;
		$l =~ s/[\r\n]//g;
		$ret .= AnalyzeCommandChain($cl, $l);
	}
	return $ret if($ret);
	return undef;
}

# read all entries from fhemconfig
# and add them to command table for execution
sub _cfgDB_ReadCfg(@) {
	my (@dbconfig) = @_;
	my $fhem_dbh = _cfgDB_Connect;
	my ($sth, @line, $row);

# using a join would be much nicer, but does not work due to sort of join's result
	my $uuid = $fhem_dbh->selectrow_array('SELECT versionuuid FROM fhemversions WHERE version = 0');
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE versionuuid = '$uuid'" );  

	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$row = "$line[0] $line[1] $line[2] $line[3]";
		push @dbconfig, $row;
	}
	$fhem_dbh->disconnect();
	return @dbconfig;
}

# read all entries from fhemstate
# and add them to command table for execution
sub _cfgDB_ReadState(@) {
	my (@dbconfig) = @_;
	my $fhem_dbh = _cfgDB_Connect;
	my ($sth, $row);

	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemstate" );  
	$sth->execute();
	while ($row = $sth->fetchrow_array()) {
		push @dbconfig, $row;
	}
	$fhem_dbh->disconnect();
	return @dbconfig;
}

# rotate all versions to versionnum + 1
# return uuid for new version 0
sub _cfgDB_Rotate($) {
	my ($fhem_dbh) = @_;
	my $uuid = _cfgDB_Uuid;
	$fhem_dbh->do("UPDATE fhemversions SET VERSION = VERSION+1");
	$fhem_dbh->do("INSERT INTO fhemversions values (0, '$uuid')");
	return $uuid;
}

# return a UUID based on DB-model
sub _cfgDB_Uuid{
	my $fhem_dbh = _cfgDB_Connect;
	my $uuid;
	$uuid = $fhem_dbh->selectrow_array('select lower(hex(randomblob(16)))') if($cfgDB_dbtype eq 'SQLITE');
	$uuid = $fhem_dbh->selectrow_array('select uuid()') if($cfgDB_dbtype eq 'MYSQL');
	$uuid = $fhem_dbh->selectrow_array('select uuid_generate_v4()') if($cfgDB_dbtype eq 'POSTGRESQL');
	$fhem_dbh->disconnect();
	return $uuid;
}

##################################################
# Additional backend functions
# not called from fhem.pl directly
#

# migrate existing fhem config into database
sub _cfgDB_Migrate {
	my $ret;
	$ret = "Starting migration...\n";
	Log3('configDB',4,'Starting migration.');
	$ret .= "Processing: database initialization.\n";
	Log3('configDB',4,'Processing: cfgDB_Init.');
	cfgDB_Init;
	$ret .= "Processing: save config.\n";
	Log3('configDB',4,'Processing: cfgDB_SaveCfg.');
	cfgDB_SaveCfg;
	$ret .= "Processing: save state.\n";
	Log3('configDB',4,'Processing: cfgDB_SaveState.');
	cfgDB_SaveState;
	$ret .= "Migration completed.\n\n";
	Log3('configDB',4,'Migration finished.');
	$ret .= _cfgDB_Info;
	return $ret;

}

# show database statistics
sub _cfgDB_Info {
	my ($l, @r);
	for my $i (1..65){ $l .= '-';}
#	$l .= "\n";
	push @r, $l;
	push @r, " configDB Database Information";
	push @r, $l;
	push @r, " ".cfgDB_svnId;
	push @r, $l;
	push @r, " dbconn: $cfgDB_dbconn";
	push @r, " dbuser: $cfgDB_dbuser" if !$attr{configdb}{private};
	push @r, " dbpass: $cfgDB_dbpass" if !$attr{configdb}{private};
	push @r, " dbtype: $cfgDB_dbtype";
	push @r, " Unknown dbmodel type in configuration file." if $dbtype eq 'unknown';
	push @r, " Only Mysql, Postgresql, SQLite are fully supported." if $dbtype eq 'unknown';
	push @r, $l;

	my $fhem_dbh = _cfgDB_Connect;
	my ($sql, $sth, @line, $row);

# read versions table statistics
	my $count;
	$count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemconfig');
	push @r, " fhemconfig: $count entries\n";

# read versions creation time
	$sql = "SELECT * FROM fhemconfig as c join fhemversions as v on v.versionuuid=c.versionuuid ".
			"WHERE COMMAND like '#created%' ORDER by v.VERSION";
	$sth = $fhem_dbh->prepare( $sql );
	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$row	 = " Ver $line[6] saved: $line[1] $line[2] $line[3] def: ".
				$fhem_dbh->selectrow_array("SELECT COUNT(*) from fhemconfig where COMMAND = 'define' and VERSIONUUID = '$line[5]'");
		$row	.= " attr: ".
				$fhem_dbh->selectrow_array("SELECT COUNT(*) from fhemconfig where COMMAND = 'attr' and VERSIONUUID = '$line[5]'");
		push @r, $row;
	}
	push @r, $l;

# read state table statistics
	$count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemstate');
# read state table creation time
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemstate WHERE STATESTRING like '#%'" );  
	$sth->execute();
	while ($row = $sth->fetchrow_array()) {
		(undef,$row) = split(/#/,$row);
		$row = " fhemstate: $count entries saved: $row";
		push @r, $row;
	}
	push @r, $l;

	$fhem_dbh->disconnect();

	return join("\n", @r);
}

# recover former config from database archive
sub _cfgDB_Recover($) {
	my ($version) = @_;
	my ($cmd, $count, $ret);

	if($version > 0) {
		my $fhem_dbh = _cfgDB_Connect;
		$cmd = "SELECT count(*) FROM fhemconfig WHERE VERSIONUUID in (select versionuuid from fhemversions where version = $version)";
		$count = $fhem_dbh->selectrow_array($cmd);

		if($count > 0) {
			my $fromuuid = $fhem_dbh->selectrow_array("select versionuuid from fhemversions where version = $version");
			my $touuid   = _cfgDB_Uuid;
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

# delete old configurations
sub _cfgDB_Reorg(;$) {
	my ($lastversion) = @_;
	$lastversion = ($lastversion > 0) ? $lastversion : 3;
	Log3('configDB', 4, "DB Reorg started, keeping last $lastversion versions.");
	my $fhem_dbh = _cfgDB_Connect;
	$fhem_dbh->do("delete FROM fhemconfig   where versionuuid in (select versionuuid from fhemversions where version > $lastversion)");
	$fhem_dbh->do("delete from fhemversions where version > $lastversion");
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return " Result after database reorg:\n"._cfgDB_Info;
}

# list device(s) from given version
sub _cfgDB_List(;$$) {
	my ($search,$searchversion) = @_;
	$search = $search ? $search : "%";
	$searchversion = $searchversion ? $searchversion : 0;
	my $fhem_dbh = _cfgDB_Connect;
	my ($sql, $sth, @line, $row, @result, $ret);
	$sql = "SELECT command, device, p1, p2 FROM fhemconfig as c join fhemversions as v ON v.versionuuid=c.versionuuid ".
	       "WHERE v.version = '$searchversion' AND command not like '#create%' AND device like '$search%' ORDER BY lower(device),command DESC";
	$sth = $fhem_dbh->prepare( $sql);
	$sth->execute();
	push @result, "search result for device: $search in version: $searchversion";
	push @result, "--------------------------------------------------------------------------------";
	while (@line = $sth->fetchrow_array()) {
		$row = "$line[0] $line[1] $line[2] $line[3]";
		push @result, "$row";
	}
	$fhem_dbh->disconnect();
	$ret = join("\n", @result);
	return $ret;
}

# called from cfgDB_Diff
sub __cfgDB_Diff($$$) {
	my ($fhem_dbh,$search,$searchversion) = @_;
	my ($sql, $sth, @line, $ret);
	$sql =	"SELECT command, device, p1, p2 FROM fhemconfig as c join fhemversions as v ON v.versionuuid=c.versionuuid ".
					"WHERE v.version = '$searchversion' AND device = '$search' ORDER BY command DESC";
	$sth = $fhem_dbh->prepare( $sql);
	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$ret .= "$line[0] $line[1] $line[2] $line[3]\n";
	}
	return $ret;
}

# compare device configurations from 2 versions
sub _cfgDB_Diff($$) {
	my ($search,$searchversion) = @_;
	use Text::Diff;
	my ($ret, $v0, $v1);
	my $fhem_dbh = _cfgDB_Connect;
		$v0 = __cfgDB_Diff($fhem_dbh,$search,0);
		$v1 = __cfgDB_Diff($fhem_dbh,$search,$searchversion);
	$fhem_dbh->disconnect();
	$ret = diff \$v0, \$v1, { STYLE => "Table" };
	$ret = "\nNo differences found!" if !$ret;
	$ret = "compare device: $search in current version 0 (left) to version: $searchversion (right)\n$ret\n";
	return $ret;
}

# backup database
sub _cfgDB_Export($$) {
	my ($filename,$version) = @_;
	my ($counter, $ret);

	my $sql =	"select command,device,p1,p2 from fhemconfig".
						" as c join fhemversions as v ON v.versionuuid=c.versionuuid ".
						"WHERE v.version = '$version' ORDER BY command DESC";

	my $fhem_dbh = _cfgDB_Connect;
	my $sth=$fhem_dbh->prepare( $sql );
	$sth->execute();

	open( FILE, ">./$filename" );
	while ( my $row = $sth->fetchrow_arrayref ) {
		$counter++;
		print FILE join( "|", @$row ), "\n";
	}
	close ( FILE );

	$sth->finish();
	$fhem_dbh->disconnect();

	$ret  = "\n $counter records exported ";
	$ret .= "from version $version ";
	$ret .= "to $filename";
}

1;

=pod

=begin html

<a name="configDB"></a>
<h3>configDB</h3>
	<ul>
	This is the core backend library for configuration from SQL database.<br/>
	See <a href="#configdb">configdb command documentation</a> for detailed info.<br/>
	</ul>

=end html

=begin html_DE

<a name="configDB"></a>
<h3>configDB</h3>
	<ul>
	configDB ist die Funktionsbibliothek f&uuml;r die Konfiguration aus einer SQL Datenbank.<br/>
	Die ausf&uuml;hrliche Dokumentation findet sich in der <a href="#configdb">configdb Befehlsbeschreibung</a>.
	</ul>

=end html_DE

=cut
