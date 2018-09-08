# $Id$

=for comment

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
# 2014-03-20 - added     export/import
# 2014-04-01 - removed   export/import due to not working properly
#
# 2014-04-03 - fixed     global attributes not read from version 0
#
# 2014-04-18 - added     commands fileimport, fileexport
# 2014-04-19 - added     commands filelist, filedelete
#                        interface cfgDB_Readfile for interaction
#                        with other modules
#
# 2014-04-21 - added     interface functions for FHEMWEB and fhem.pl
#                        to show files in "Edit files" and use them
#                        with CommandReload() mechanism
#
#              modified  _cfgDB_Info to show number of files in db
#
# 2014-04-23 - added     command fileshow, filemove
#
# 2014-04-26 - added     migration to generic file handling
#              fixed     problem on migration of multiline DEFs
#
# 2014-04-27 - added     new functions for binfile handling
#
# 2014-05-11 - removed   command binfileimport
#              changed   store all files as binary
#              added     _cfgDB_Move to move all files from text 
#                        to binary filesave on first load of configDB
#
# 2014-05-12 - added     sorted write & read for config data
#
# 2014-05-15 - fixed     handling of multiline defs
#
# 2014-05-20 - removed   no longer needed functions for file handling
#              changed   code improvement; use strict; use warnings;
#
# 2014-08-22 - added     automatic fileimport during migration
#
# 2014-09-30 - added     support for device based userattr
#
# 2015-01-12 - changed   use fhem function createUniqueId()
#                        instead of database calls
#
# 2015-01-15 - changed   remove 99_Utils.pm from filelist
#
# 2015-01-17 - added     configdb diff all current
#                        shows diff table between version 0
#                        and currently running version (in memory)
#
# 2015-01-23 - changed   attribute handling for internal configDB attrs
#
# 2015-01-23 - added     FileRead() caching - experimental
#
# 2015-10-14 - changed   search conditions use ESCAPE, forum #42190
#
# 2016-03-19 - changed   use modpath, forum #51036
#
# 2016-03-26 - added     log entry for search (verbose=5)
#
# 2016-05-22 - added     configdb dump (for sqlite)
#
# 2016-05-28 - added     configdb dump (for mysql)
#
# 2016-05-29 - changed   improve support for postgresql (tnx to Matze)
#              added     configdb dump (for postgresql)
#
# 2016-07-03 - added     support for multiple hosts (experimental)
# 2016-07-04 - fixed     improve config file read
# 2016-07-07 - bugfix    select configuration
#
# 2017-03-24 - added     use index on fhemconfig (only sqlite)
#
# 2017-07-17 - changed   store files base64 encoded
#
# 2017-08-31 - changed   improve table_info for migration check
#
# 2018-02-17 - changed   remove experimenatal cache functions
# 2018-02-18 - changed   move dump processing to backend
#
# 2018-03-24 - changed   set privacy as default for username and password
# 2018-03-25 - changed   move rescue modes from ENV to config file
#
# 2018-06-17 - changed   remove migration on FHEM start by default
#                        check migration only if parameter migrate => 1 
#                        is set in configDB.conf
#
# 2018-07-04 - bugfix    change rescue mode persistence
#
# 2018-07-07 - change    lastReorg added to info output
#
# 2018-09-08 - change    remove base64 migration functions
#
##############################################################################
=cut

use strict;
use warnings;
use Text::Diff;
use DBI;
use Sys::Hostname;
use MIME::Base64;

##################################################
# Forward declarations for functions in fhem.pl
#
sub AnalyzeCommandChain($$;$);
sub Log($$);
sub Log3($$$);
sub createUniqueId();

##################################################
# Forward declarations inside this library
#
sub cfgDB_AttrRead($);
sub cfgDB_Init();
sub cfgDB_FileRead($);
sub cfgDB_FileUpdate($);
sub cfgDB_Fileversion($$);
sub cfgDB_FileWrite($@);
sub cfgDB_FW_fileList($$@);
sub cfgDB_Read99();
sub cfgDB_ReadAll($);
sub cfgDB_SaveCfg(;$);
sub cfgDB_SaveState();
sub cfgDB_svnId();

sub _cfgDB_binFileimport($$;$);
sub _cfgDB_Connect();
sub _cfgDB_DeleteTemp();
sub _cfgDB_Diff($$);
sub __cfgDB_Diff($$$$);
sub _cfgDB_InsertLine($$$$);
sub _cfgDB_Execute($@);
sub _cfgDB_Filedelete($);
sub _cfgDB_Fileexport($;$);
sub _cfgDB_Filelist(;$);
sub _cfgDB_Info($);
sub _cfgDB_Migrate();
sub _cfgDB_ReadCfg(@);
sub _cfgDB_ReadState(@);
sub _cfgDB_Recover($);
sub _cfgDB_Reorg(;$$);
sub _cfgDB_Rotate($$);
sub _cfgDB_Search($$;$);
sub _cfgDB_Uuid();
sub _cfgDB_table_exists($$);
sub _cfgDB_dump($);

##################################################
# Read configuration file for DB connection
#

if(!open(CONFIG, 'configDB.conf')) {
	Log3('configDB', 1, 'Cannot open database configuration file configDB.conf');
	return 0;
}

my @config;
while (<CONFIG>){
   my $line = $_;
   $line =~ s/^\s+|\s+$//g; # remove whitespaces etc.
   $line =~ s/;$/;;/;       # duplicate ; at end-of-line
   push (@config,$line) if($line !~ m/^#/ && length($line) > 0);
}
close CONFIG;

use vars qw(%configDB);

my %dbconfig;

my $configs  = join("",@config);
my @configs  = split(/;;/,$configs);
my $count    = @configs;
my $fhemhost = hostname;

if ($count > 1) {
   foreach my $c (@configs) {
      next unless $c =~ m/^%dbconfig.*/;
      $dbconfig{fhemhost} = "";
      eval $c;
      last if ($dbconfig{fhemhost} eq $fhemhost);
   }
   eval $configs[0] if ($dbconfig{fhemhost} eq "");
} else {
   eval $configs[0];
}

my $cfgDB_dbconn    = $dbconfig{connection};
my $cfgDB_dbuser    = $dbconfig{user};
my $cfgDB_dbpass    = $dbconfig{password};
my $cfgDB_dbtype;
my $cfgDB_filename;


if($cfgDB_dbconn =~ m/pg:/i) {
      $cfgDB_dbtype ="POSTGRESQL";
   } elsif ($cfgDB_dbconn =~ m/mysql:/i) {
      $cfgDB_dbtype = "MYSQL";
   } elsif ($cfgDB_dbconn =~ m/sqlite:/i) {
      $cfgDB_dbtype = "SQLITE";
      (undef,$cfgDB_filename) = split(/=/,$cfgDB_dbconn);
   } else {
      $cfgDB_dbtype = "unknown";
}

$configDB{attr}{nostate}     = defined($dbconfig{nostate})     ? $dbconfig{nostate}     : 0;
$configDB{attr}{rescue}      = defined($dbconfig{rescue})      ? $dbconfig{rescue}      : 0;
$configDB{attr}{loadversion} = defined($dbconfig{loadversion}) ? $dbconfig{loadversion} : 0;

%dbconfig = ();
@config   = ();
$configs  = undef;
$count    = undef;

##################################################
# Basic functions needed for DB configuration
# directly called from fhem.pl
#

# initialize database, create tables if necessary
sub cfgDB_Init() {
##################################################
# Create non-existing database tables 
# Create default config entries if necessary
#
	my $fhem_dbh = _cfgDB_Connect;

#	create TABLE fhemversions ifnonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemversions(VERSION INT, VERSIONUUID CHAR(50))");

#	create TABLE fhemconfig if nonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemconfig(COMMAND VARCHAR(32), DEVICE VARCHAR(64), P1 VARCHAR(50), P2 TEXT, VERSION INT, VERSIONUUID CHAR(50))");
	
#	create INDEX on fhemconfig if nonexistent (only if SQLITE)
	$fhem_dbh->do("CREATE INDEX IF NOT EXISTS config_idx on 'fhemconfig' (versionuuid,version)") 
	           if($cfgDB_dbtype eq "SQLITE");
		
#	check TABLE fhemconfig already populated
	my $count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemconfig');
	if($count < 1) {
#		insert default entries to get fhem running
		$fhem_dbh->commit();
		my $uuid = _cfgDB_Uuid;
		$fhem_dbh->do("INSERT INTO fhemversions values (0, '$uuid')");
		_cfgDB_InsertLine($fhem_dbh, $uuid, '#created by cfgDB_Init',0);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global logdir ./log',1);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global logfile %L/fhem-%Y-%m-%d.log',2);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global modpath .',3);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global userattr devStateIcon devStateStyle icon sortby webCmd',4);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global verbose 3',5);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define telnetPort telnet 7072 global',6);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define web FHEMWEB 8083 global',7);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr web allowfrom .*',8);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define Logfile FileLog %L/fhem-%Y-%m-%d.log fakelog',9);
	}

#	create TABLE fhemstate if nonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemstate(stateString TEXT)");

#	create TABLE fhemb64filesave if nonexistent
	if($cfgDB_dbtype eq "MYSQL") {
		$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemb64filesave(filename TEXT, content MEDIUMBLOB)");
	} elsif ($cfgDB_dbtype eq "POSTGRESQL") {
		$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemb64filesave(filename TEXT, content bytea)");
	} else {
		$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemb64filesave(filename TEXT, content BLOB)");
	}

# close database connection
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();

	return;
}

# read attributes
sub cfgDB_AttrRead($) {
	my ($readSpec) = @_;
	my ($row, $sql, @line, @rets);
	my $fhem_dbh = _cfgDB_Connect;
	my $uuid = $fhem_dbh->selectrow_array('SELECT versionuuid FROM fhemversions WHERE version = 0');
	$sql = "SELECT * FROM fhemconfig WHERE COMMAND = 'attr' AND DEVICE = '$readSpec' AND VERSIONUUID = '$uuid'";
	$sql = "SELECT * FROM fhemconfig WHERE COMMAND = 'attr' AND (DEVICE = 'global' OR DEVICE = 'configdb') and VERSIONUUID = '$uuid'" 
					if($readSpec eq 'global');  
	my $sth = $fhem_dbh->prepare( $sql );  
	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		if($line[1] eq 'configdb') {
           $configDB{attr}{$line[2]} = $line[3];
		} else {
			push @rets, "attr $line[1] $line[2] $line[3]";
		}
	}
	$fhem_dbh->disconnect();
	return @rets;
}

# generic file functions called from fhem.pl
sub cfgDB_FileRead($) {
	my ($filename) = @_;

	Log3(undef, 4, "configDB reading file: $filename");
	my ($err, @ret, $counter);
	my $fhem_dbh = _cfgDB_Connect;
	my $sth = $fhem_dbh->prepare( "SELECT content FROM fhemb64filesave WHERE filename LIKE '$filename'" );
	$sth->execute();
	my $blobContent = $sth->fetchrow_array();
	$sth->finish();
	$fhem_dbh->disconnect();
	$blobContent = decode_base64($blobContent) if ($blobContent);
	$counter = length($blobContent);
	if($counter) {
		@ret = split(/\n/,$blobContent);
		$err = "";
	} else {
		@ret = undef;
		$err = "Error on reading $filename from database!";
	}
	return ($err, @ret);
}

sub cfgDB_FileWrite($@) {
	my ($filename,@content) = @_;
	Log3(undef, 4, "configDB writing file: $filename");
	my $fhem_dbh = _cfgDB_Connect;
	$fhem_dbh->do("delete from fhemb64filesave where filename = '$filename'");
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemb64filesave values (?, ?)');
	$sth->execute($filename,encode_base64(join("\n", @content)));
	$sth->finish();
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return;
}

sub cfgDB_FileUpdate($) {
	my ($filename) = @_;
	my $fhem_dbh = _cfgDB_Connect;
	my $id = $fhem_dbh->selectrow_array("SELECT filename from fhemb64filesave where filename = '$filename'");
	$fhem_dbh->disconnect();
	if($id) {
		my $filesize = -s $filename;
		_cfgDB_binFileimport($filename,$filesize,1) if ($id) ;
		Log(5, "file $filename updated in configDB");
	}
	return;
}

# read and execute fhemconfig and fhemstate
sub cfgDB_ReadAll($) {
	my ($cl) = @_;
	my ($ret, @dbconfig);

	if ($configDB{attr}{rescue} == 1) {
		Log (0, 'configDB starting in rescue mode!');
		push (@dbconfig, 'attr global modpath .');
		push (@dbconfig, 'attr global verbose 3');
		push (@dbconfig, 'define telnetPort telnet 7072 global');
		push (@dbconfig, 'define web FHEMWEB 8083 global');
		push (@dbconfig, 'attr web allowfrom .*');
		push (@dbconfig, 'define Logfile FileLog ./log/fhem-%Y-%m-%d.log fakelog');
	} else {
		# add Config Rows to commandfile
		@dbconfig = _cfgDB_ReadCfg(@dbconfig);
		# add State Rows to commandfile
		@dbconfig = _cfgDB_ReadState(@dbconfig) unless $configDB{attr}{nostate} == 1;
	}

	# AnalyzeCommandChain for all entries
	$ret = _cfgDB_Execute($cl, @dbconfig);
	return $ret if($ret);
	return undef;
}

# save running configuration to version 0
sub cfgDB_SaveCfg(;$) {

	my ($internal) = shift;
	$internal = defined($internal) ? $internal : 0;
	my @dontSave = qw(configdb:rescue configdb:nostate configdb:loadversion 
	                  global:configfile global:version);
	my (%devByNr, @rowList, %comments, $t, $out);

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
				$def = "";
			}
			push @rowList, "define $d $defs{$d}{TYPE} $def";
		}

		foreach my $a (sort {
			return -1 if($a eq "userattr"); # userattr must be first
			return  1 if($b eq "userattr");
			return $a cmp $b;
			} keys %{$attr{$d}}) {
			next if (grep { $_ eq "$d:$a" } @dontSave);
			my $val = $attr{$d}{$a};
			$val =~ s/;/;;/g;
			push @rowList, "attr $d $a $val";
		}

	}

		foreach my $a (sort keys %{$configDB{attr}}) {
			my $val = $configDB{attr}{$a};
			next unless $val;
			$val =~ s/;/;;/g;
			push @rowList, "attr configdb $a $val";
		}

# Insert @rowList into database table
	my $fhem_dbh = _cfgDB_Connect;
	my $uuid = _cfgDB_Rotate($fhem_dbh,$internal);
	$t = localtime;
	$out = "#created $t";
	push @rowList, $out;
	my $counter = 0;
	foreach (@rowList) { 
		_cfgDB_InsertLine($fhem_dbh, $uuid, $_, $counter); 
		$counter++;
	}
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	my $maxVersions = $configDB{attr}{maxversions};
	$maxVersions = ($maxVersions) ? $maxVersions : 0;
	_cfgDB_Reorg($maxVersions,1) if($maxVersions && $internal != -1);
	return 'configDB saved.';
}

# save statefile
sub cfgDB_SaveState() {
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
			$val ne "" &&
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

# import existing files during migration 
sub cfgDB_MigrationImport() {

	my ($ret, $filename, @files, @def);
	my $modpath = AttrVal("global","modpath",".");

# find eventTypes file
	$filename = '';
	@def = '';
	@def = _cfgDB_findDef('TYPE=eventTypes');
	foreach $filename (@def) {
		next unless $filename;
		push @files, $filename;
	}

# import templateDB.gplot
	$filename = "$modpath/www/gplot/template.gplot";
	push @files, $filename;
	$filename = "$modpath/www/gplot/templateDB.gplot";
	push @files, $filename;

# import template.layout
	$filename = "$modpath/FHEM/template.layout";
	push @files, $filename;

# find used gplot files
	$filename ='';
	@def = '';
	@def = _cfgDB_findDef('TYPE=SVG','GPLOTFILE');
	foreach $filename (@def) {
		next unless $filename;
		push @files, "$modpath/www/gplot/".$filename.".gplot";
	}

# find DbLog configs
	$filename ='';
	@def = '';
	@def = _cfgDB_findDef('TYPE=DbLog','CONFIGURATION');
	foreach $filename (@def) {
		next unless $filename;
		push @files, $filename;
	}

# find RSS layouts
	$filename ='';
	@def = '';
	@def = _cfgDB_findDef('TYPE=RSS','LAYOUTFILE');
	foreach $filename (@def) {
		next unless $filename;
		push @files, $filename;
	}

# find InfoPanel layouts
	$filename ='';
	@def = '';
	@def = _cfgDB_findDef('TYPE=InfoPanel','LAYOUTFILE');
	foreach $filename (@def) {
		next unless $filename;
		push @files, $filename;
	}

# find holiday files
	$filename ='';
	@def = '';
	@def = _cfgDB_findDef('TYPE=holiday','NAME');
	foreach $filename (@def) {
		next unless $filename;
		if(defined($defs{$filename}{HOLIDAYFILE})) {
           push @files, $defs{$filename}{HOLIDAYFILE};
		} else {
           push @files, "$modpath/FHEM/".$filename.".holiday";
		}
	}

# import uniqueID file
	$filename = "$modpath/FHEM/FhemUtils/uniqueID";
	push @files,$filename if (-e $filename);   


# do the import
	$filename = '';
	foreach $filename (@files) {
		if ( -r $filename ) {
			my $filesize = -s $filename;
			_cfgDB_binFileimport($filename,$filesize);
			$ret .= "importing: $filename\n";
		}
	}

	return $ret;
}

# return SVN Id, called by fhem's CommandVersion
sub cfgDB_svnId() { 
	return "# ".'$Id$' 
}

# return filelist depending on directory and regexp
sub cfgDB_FW_fileList($$@) {
	my ($dir,$re,@ret) = @_;
	my @files = split(/\n/, _cfgDB_Filelist('notitle'));
	foreach my $f (@files) {
		next if( $f !~ m/^$dir/ );
		$f =~ s,$dir\/,,;
		next if($f !~ m,^$re$, || $f eq '99_Utils.pm');
		push @ret, "$f.configDB";
	}
	return @ret;
}

# read filelist containing 99_ files in database
sub cfgDB_Read99() {
  my $ret = "";
  my $fhem_dbh = _cfgDB_Connect;
  my $sth = $fhem_dbh->prepare( "SELECT filename FROM fhemb64filesave WHERE filename like '%/99_%.pm' group by filename" );
  $sth->execute();
  while (my $line = $sth->fetchrow_array()) {
    $line =~ m,^(.*)/([^/]*)$,; # Split into dir and file
    $ret .= "$2,"; # 
  }
  $sth->finish();
  $fhem_dbh->disconnect();
  $ret =~ s/,$//;
  return $ret;
}

# return SVN Id from file stored in database
sub cfgDB_Fileversion($$) {
  my ($file,$ret) = @_;
  $ret = "No Id found for $file";
  my ($err,@in) = cfgDB_FileRead($file);
  foreach(@in){ $ret = $_ if($_ =~ m/# \$Id:/); }
  return $ret;
}

##################################################
# Basic functions needed for DB configuration
# but not called from fhem.pl directly
#

# connect do database
sub _cfgDB_Connect() {
	my $fhem_dbh = DBI->connect(
	"dbi:$cfgDB_dbconn", 
	$cfgDB_dbuser,
	$cfgDB_dbpass,
	{ AutoCommit => 0, RaiseError => 1 },
	) or die $DBI::errstr;
	return $fhem_dbh;
}

# add configuration entry into fhemconfig
sub _cfgDB_InsertLine($$$$) {
	my ($fhem_dbh, $uuid, $line, $counter) = @_;
	my ($c,$d,$p1,$p2) = split(/ /, $line, 4);
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemconfig values (?, ?, ?, ?, ?, ?)');
	$sth->execute($c, $d, $p1, $p2, $counter, $uuid);
	return;
}

# pass command table to AnalyzeCommandChain
sub _cfgDB_Execute($@) {
	my ($cl, @dbconfig) = @_;
	my (@ret);

	foreach my $l (@dbconfig) {
		$l =~ s/[\r\n]/\n/g;
		$l =~ s/\\\n/\n/g;
		my $tret = AnalyzeCommandChain($cl, $l);
		push @ret, $tret if(defined($tret));
	}
	return join("\n", @ret) if(@ret);
	return undef;
}

# read all entries from fhemconfig
# and add them to command table for execution
sub _cfgDB_ReadCfg(@) {
	my (@dbconfig) = @_;
	my $fhem_dbh = _cfgDB_Connect;
	my ($sth, @line, $row);

    my $version = $configDB{attr}{loadversion};
    delete $configDB{attr}{loadversion};
    if ($version > 0) {
       my $count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemversions');
       $count--;
       $version = $version > $count ? $count : $version;
       Log 0, "configDB loading version $version on user request.";
    }    

# maybe this will be done with join later
	my $uuid = $fhem_dbh->selectrow_array("SELECT versionuuid FROM fhemversions WHERE version = '$version'");
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE versionuuid = '$uuid' and device <>'configdb' order by version" );  

	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$row  = "$line[0] $line[1] $line[2]";
		$row .= " $line[3]" if defined($line[3]);
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
sub _cfgDB_Rotate($$) {
	my ($fhem_dbh,$newversion) = @_;
	my $uuid = _cfgDB_Uuid;
	$fhem_dbh->do("UPDATE fhemversions SET VERSION = VERSION+1 where VERSION >= 0") if $newversion == 0;
	$fhem_dbh->do("INSERT INTO fhemversions values ('$newversion', '$uuid')");
	return $uuid;
}

# 2015-01-12 use the fhem default function
sub _cfgDB_Uuid() {
	return createUniqueId();
}

sub _cfgDB_filesize_str($) {
    my ($size) = @_;

    if ($size > 1099511627776)  #   TiB: 1024 GiB
    {
        return sprintf("%.2f TB", $size / 1099511627776);
    }
    elsif ($size > 1073741824)  #   GiB: 1024 MiB
    {
        return sprintf("%.2f GB", $size / 1073741824);
    }
    elsif ($size > 1048576)     #   MiB: 1024 KiB
    {
        return sprintf("%.2f MB", $size / 1048576);
    }
    elsif ($size > 1024)        #   KiB: 1024 B
    {
        return sprintf("%.2f KB", $size / 1024);
    }
    else                        #   bytes
    {
        return "$size byte" . ($size == 1 ? "" : "s");
    }
}

##################################################
# Additional backend functions
# not called from fhem.pl directly
#

# migrate existing fhem config into database
sub _cfgDB_Migrate() {
	my $ret;
	$ret = "Starting migration...\n";
	Log3('configDB',4,'Starting migration');
	$ret .= "Processing: database initialization\n";
	Log3('configDB',4,'Processing: cfgDB_Init');
	cfgDB_Init;
	$ret .= "Processing: save config\n";
	Log3('configDB',4,'Processing: cfgDB_SaveCfg');
	cfgDB_SaveCfg;
	$ret .= "Processing: save state\n";
	Log3('configDB',4,'Processing: cfgDB_SaveState');
	cfgDB_SaveState;
	$ret .= "Processing: fileimport\n";
	Log3('configDB',4,'Processing: cfgDB_MigrationImport');
	$ret .= cfgDB_MigrationImport;
	$ret .= "Migration completed\n\n";
	Log3('configDB',4,'Migration completed.');
	$ret .= _cfgDB_Info(undef);
	return $ret;
}

# show database statistics
sub _cfgDB_Info($) {
	my ($info2) = @_;
	$info2 //= 'unknown';
	my ($l, @r, $f);
	for my $i (1..65){ $l .= '-';}

    $configDB{attr}{private} //= 1;

	push @r, $l;
	push @r, " configDB Database Information";
	push @r, $l;
	my $info1 = cfgDB_svnId;
	$info1 =~ s/# //;
	push @r, " d:$info1";
	push @r, " c:$info2";
	push @r, $l;
	push @r, " dbconn: $cfgDB_dbconn";
	push @r, " dbuser: $cfgDB_dbuser" if !$configDB{attr}{private};
	push @r, " dbpass: $cfgDB_dbpass" if !$configDB{attr}{private};
	push @r, " dbtype: $cfgDB_dbtype";
	push @r, " Unknown dbmodel type in configuration file." if $cfgDB_dbtype eq 'unknown';
	push @r, " Only Mysql, Postgresql, SQLite are fully supported." if $cfgDB_dbtype eq 'unknown';
	if ($cfgDB_dbtype eq "SQLITE") {
	    my $size = -s $cfgDB_filename;
	    $size = _cfgDB_filesize_str($size);
		push @r, " dbsize: $size";
	}
	push @r, $l;
	my $fhem_dbh = _cfgDB_Connect;
	my ($sql, $sth, @line, $row);

# read versions table statistics
	my $maxVersions = $configDB{attr}{maxversions};
	$maxVersions = ($maxVersions) ? $maxVersions : 0;
	push @r, " max Versions: $maxVersions" if($maxVersions);
	push @r, " lastReorg:    ".$configDB{attr}{'lastReorg'};
	my $count;
	$count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemconfig');
	push @r, " config:       $count entries";
	push @r, "";

# read versions creation time
	$sql = "SELECT * FROM fhemconfig as c join fhemversions as v on v.versionuuid=c.versionuuid ".
			"WHERE COMMAND like '#created%' ORDER by v.VERSION";
	$sth = $fhem_dbh->prepare( $sql );
	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$line[3] = "" unless defined $line[3];
		$row	 = " Ver $line[6] saved: $line[1] $line[2] $line[3] def: ".
				$fhem_dbh->selectrow_array("SELECT COUNT(*) from fhemconfig where COMMAND = 'define' and VERSIONUUID = '$line[5]'");
		$row	.= " attr: ".
				$fhem_dbh->selectrow_array("SELECT COUNT(*) from fhemconfig where COMMAND = 'attr' and VERSIONUUID = '$line[5]'");
		push @r, $row;
	}
	push @r, $l;

# read state table statistics
	$count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemstate');
	$f = ($count>1) ? "s" : "";
# read state table creation time
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemstate WHERE STATESTRING like '#%'" );  
	$sth->execute();
	while ($row = $sth->fetchrow_array()) {
		(undef,$row) = split(/#/,$row);
		$row = " state: $count entrie$f saved: $row";
		push @r, $row;
	}
	push @r, $l;

	$row = $fhem_dbh->selectall_arrayref("SELECT filename from fhemb64filesave group by filename");
	$count = @$row;
	$count = ($count)?$count:'No';
	$f = ("$count" ne '1') ? "s" : "";
	$row = " filesave: $count file$f stored in database";
	push @r, $row;
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
				$sth2->execute($line[0], $line[1], $line[2], $line[3], $line[4], $touuid);
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
sub _cfgDB_Reorg(;$$) {
	my ($lastversion,$quiet) = @_;
	$lastversion = (defined($lastversion)) ? $lastversion : 3;
	Log3('configDB', 4, "DB Reorg started, keeping last $lastversion versions.");
	my $fhem_dbh = _cfgDB_Connect;
	my $uuid = $fhem_dbh->selectrow_array("select versionuuid from fhemversions where version = 0");
	$fhem_dbh->do("delete FROM fhemconfig   where versionuuid in (select versionuuid from fhemversions where version > $lastversion)");
	$fhem_dbh->do("delete from fhemversions where version > $lastversion");
	$fhem_dbh->do("delete FROM fhemconfig   where versionuuid in (select versionuuid from fhemversions where version = -1)");
	$fhem_dbh->do("delete from fhemversions where version = -1");
	my $ts = localtime(time);
	$configDB{attr}{'lastReorg'} = $ts;
	_cfgDB_InsertLine($fhem_dbh,$uuid,"attr configdb lastReorg $ts",-1); 
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	eval qx(sqlite3 $cfgDB_filename vacuum) if($cfgDB_dbtype eq "SQLITE");
	return if(defined($quiet));
	return " Result after database reorg:\n"._cfgDB_Info(undef);
}

# delete temporary version
sub _cfgDB_DeleteTemp() {
	Log3('configDB', 4, "configDB: delete temporary Version -1");
	my $fhem_dbh = _cfgDB_Connect;
	$fhem_dbh->do("delete FROM fhemconfig   where versionuuid in (select versionuuid from fhemversions where version = -1)");
	$fhem_dbh->do("delete from fhemversions where version = -1");
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return;
}

# search for device or fulltext in db
sub _cfgDB_Search($$;$) {
	my ($search,$searchversion,$dsearch) = @_;
	return 'Syntax error.' if(!(defined($search)));
	my $fhem_dbh = _cfgDB_Connect;
	my ($sql, $sth, @line, $row, @result, $ret, $text);
	$sql  = "SELECT command, device, p1, p2 FROM fhemconfig as c join fhemversions as v ON v.versionuuid=c.versionuuid ";
	$sql .= "WHERE v.version = '$searchversion' AND command not like '#create%' ";
	# 2015-10-24 - changed, forum #42190
	if($cfgDB_dbtype eq 'SQLITE') {;
		$sql .= "AND device like '$search%' ESCAPE '\\' " if($dsearch);
		$sql .= "AND (device like '$search%' ESCAPE '\\' OR P1 like '$search%' ESCAPE '\\' OR P2 like '$search%' ESCAPE '\\') " if(!$dsearch);
	} else {
		$sql .= "AND device like '$search%' " if($dsearch);
		$sql .= "AND (device like '$search%' OR P1 like '$search%' OR P2 like '$search%') " if(!$dsearch);
	}
	$sql .= "ORDER BY lower(device),command DESC";
	$sth = $fhem_dbh->prepare( $sql);
	Log 5,"configDB: $sql";
	$sth->execute();
	$text = " device" if($dsearch);
	push @result, "search result for$text: $search in version: $searchversion";
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
sub __cfgDB_Diff($$$$) {
	my ($fhem_dbh,$search,$searchversion,$svinternal) = @_;
	my ($sql, $sth, @line, $ret);
if($svinternal != -1) {
	$sql =	"SELECT command, device, p1, p2 FROM fhemconfig as c join fhemversions as v ON v.versionuuid=c.versionuuid ".
					"WHERE v.version = '$searchversion' AND device = '$search' ORDER BY command DESC";
} else {
	$sql =	"SELECT command, device, p1, p2 FROM fhemconfig as c join fhemversions as v ON v.versionuuid=c.versionuuid ".
					"WHERE v.version = '$searchversion' ORDER BY command DESC";
}
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
	my ($ret, $v0, $v1);

	if ($search eq 'all' && $searchversion eq 'current') {
		_cfgDB_DeleteTemp();
		cfgDB_SaveCfg(-1);
		$searchversion = -1;
	}

	my $fhem_dbh = _cfgDB_Connect;
		$v0 = __cfgDB_Diff($fhem_dbh,$search,0,$searchversion);
		$v1 = __cfgDB_Diff($fhem_dbh,$search,$searchversion,$searchversion);
	$fhem_dbh->disconnect();
	$ret = diff \$v0, \$v1, { STYLE => "Table" };
	if($searchversion == -1) {
		_cfgDB_DeleteTemp();
		$searchversion = "UNSAVED";
	}
	$ret = "\nNo differences found!" if !$ret;
	$ret = "compare device: $search in current version 0 (left) to version: $searchversion (right)\n$ret\n";
	return $ret;
}

# find DEF, input supports devspec definitions
sub _cfgDB_findDef($;$) {
	my ($search,$internal) = @_;
	$internal = 'DEF' unless defined($internal);

	my @ret;
	my @etDev = devspec2array($search);
	foreach my $d (@etDev) {
		next unless $d;
		push @ret, $defs{$d}{$internal};
	}

	return @ret;
}

sub _cfgDB_type() { 
   return "$cfgDB_dbtype (b64)";
}

sub _cfgDB_dump($) {
   my ($param1) = @_;
   $param1 //= '';

   my ($dbconn,$dbuser,$dbpass,$dbtype)  = _cfgDB_readConfig();
   my ($dbname,$dbhostname,$dbport,$gzip,$mp,$ret,$size,$source,$target,$ts);
   $ts     = strftime('%Y-%m-%d_%H-%M-%S',localtime);
   $mp     = $configDB{attr}{'dumpPath'};
   $mp   //= AttrVal('global','modpath','.').'/log';
   $target = "$mp/configDB_$ts.dump";

   if (lc($param1) eq 'unzipped') {
      $gzip = '';
   } else {
      $gzip    = '| gzip -c';
      $target .= '.gz';
   }

   if ($dbtype eq 'SQLITE') {
      (undef,$source) = split (/=/, $dbconn);
      my $dumpcmd = "echo '.dump fhem%' | sqlite3 $source $gzip > $target";
      Log 4,"configDB: $dumpcmd";
      $ret        = qx($dumpcmd);
      return $ret if $ret; # return error message if available

   } elsif ($dbtype eq 'MYSQL') {
      ($dbname,$dbhostname,$dbport) = split (/;/,$dbconn);
      $dbport //= '=3306';
      (undef,$dbname)     = split (/=/,$dbname);
      (undef,$dbhostname) = split (/=/,$dbhostname);
      (undef,$dbport)     = split (/=/,$dbport);
      my $dbtables = "fhemversions fhemconfig fhemstate fhemb64filesave";
      my $dumpcmd = "mysqldump --user=$dbuser --password=$dbpass --host=$dbhostname --port=$dbport -Q $dbname $dbtables $gzip > $target";
      Log 4,"configDB: $dumpcmd";
      $ret        = qx($dumpcmd);
      return $ret if $ret;
      $source = $dbname;

   } elsif ($dbtype eq 'POSTGRESQL') {
      ($dbname,$dbhostname,$dbport) = split (/;/,$dbconn);
      $dbport //= '=5432';
      (undef,$dbname)     = split (/=/,$dbname);
      (undef,$dbhostname) = split (/=/,$dbhostname);
      (undef,$dbport)     = split (/=/,$dbport);
      my $dbtables = "-t fhemversions -t fhemconfig -t fhemstate -t fhemb64filesave";
      my $dumpcmd = "PGPASSWORD=$dbpass pg_dump -U $dbuser -h $dbhostname -p $dbport $dbname $dbtables $gzip > $target";
      Log 4,"configDB: $dumpcmd";
      $ret        = qx($dumpcmd);
      return $ret if $ret;
      $source     = $dbname;

   } else {
      return "configdb dump not supported for $dbtype!";
   }

   $size = -s $target;
   $size //= 0;
   $ret  = "configDB dumped $size bytes\nfrom: $source\n  to: $target";
   return $ret;

}

##################################################
# functions used for file handling
# called by 98_configdb.pm
#

# delete file from database
sub _cfgDB_Filedelete($) {
	my ($filename) = @_;
	my $fhem_dbh = _cfgDB_Connect;
	my $ret = $fhem_dbh->do("delete from fhemb64filesave where filename = '$filename'");
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	$ret = ($ret > 0) ? 1 : undef;
	return $ret;
}

# export file from database to filesystem
sub _cfgDB_Fileexport($;$) {
	my ($filename,$raw) = @_;
	my $fhem_dbh = _cfgDB_Connect;
	my $sth      = $fhem_dbh->prepare( "SELECT content FROM fhemb64filesave WHERE filename = '$filename'" );  
	$sth->execute();
	my $blobContent = $sth->fetchrow_array();
    $blobContent = decode_base64($blobContent);
	my $counter = length($blobContent);
	$sth->finish();
	$fhem_dbh->disconnect();
	return "No data found for file $filename" unless $counter;
	return ($blobContent,$counter) if $raw;
	
	open( FILE,">$filename" );
		binmode(FILE);
		print FILE $blobContent;
	close( FILE );
	return "$counter bytes written from database into file $filename";
}

# import file into database
sub _cfgDB_binFileimport($$;$) {
	my ($filename,$filesize,$doDelete) = @_;
	$doDelete = (defined($doDelete)) ? 1 : 0;

	open (inFile,"<$filename") || die $!;
		my $blobContent;
		binmode(inFile);
		my $readBytes = read(inFile, $blobContent, $filesize);
	close(inFile);
	$blobContent = encode_base64($blobContent);
	my $fhem_dbh = _cfgDB_Connect;
	$fhem_dbh->do("delete from fhemb64filesave where filename = '$filename'");
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemb64filesave values (?, ?)');

# add support for postgresql by Matze
    $sth->bind_param( 1, $filename );
    if ($cfgDB_dbtype eq "POSTGRESQL") {
        $sth->bind_param( 2, $blobContent, { pg_type => DBD::Pg::PG_BYTEA() } );
    } else {
        $sth->bind_param( 2, $blobContent );
    }

	$sth->execute($filename, $blobContent);
	$sth->finish();
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();

	unlink($filename) if(($configDB{attr}{deleteimported} || $doDelete) && $readBytes);
	return "$readBytes bytes written from file $filename to database";
}

# list all files stored in database
sub _cfgDB_Filelist(;$) {
	my ($notitle) = @_;
	my $ret =	"Files found in database:\n".
				"------------------------------------------------------------\n";
	$ret = "" if $notitle;
	my $fhem_dbh = _cfgDB_Connect;
	my $sql = "SELECT filename FROM fhemb64filesave group by filename order by filename";  
	my $content = $fhem_dbh->selectall_arrayref($sql);
	foreach my $row (@$content) {
		$ret .= "@$row[0]\n" if(defined(@$row[0]));
	}
	$fhem_dbh->disconnect();
	return $ret;
}

1;

=pod
=item helper
=item summary    configDB backend
=item summary_DE configDB backend
=begin html

<a name="configDB"></a>
<h3>configDB</h3>
	<ul>
	<a href="https://forum.fhem.de/index.php?board=46.0">Link to FHEM forum</a><br/><br/>
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
