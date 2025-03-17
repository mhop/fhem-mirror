# $Id$

=for comment (License)

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
=cut

=for comment (changelog before 2022)
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
# 2019-01-17 - added     support for device specific uuid (setuuid)
# 2019-01-18 - changed   use GetDefAndAttr()
#
# 2019-02-16 - changed   default field length for table creation
#
# 2020-02-25 - added     support weekprofile in automatic migration
#
# 2020-06-37 - added     support for special strange readings (length check)
#
# 2020-06-29 - added     support for mysqldump parameter by attribute
#
# 2020-07-02 - changed   code cleanup after last changes (remove debug code)
#                        add "configdb attr ?" to show known attributes
#
# 2021-04-17 - bugfix    problem in File.* commands regarding case sensitivity
#
# 2021-08-17 - changed   adopt to Rudi's funny fakelog changes
#
# 2021-10-24 - added     delete old files for large readings
#
=cut

=for comment (changelog starting 2022)
##############################################################################
#
# 2022-02-20 - changed   use createUniqueId() for uuids
#                        remove _cfgDB_Uuid()
#
# 2022-02-20 - added     statefile versioning - begin
# 2022-03-03             statefile versioning - completed
#
# 2022-03-14 - fixed     statefile problems with POSTGRESQL
# 2022-08-06 - added     attribute shortinfo for use with configdb info
# 2022-08-07 - added     log a message if more than 20 versions stored
#
# 2022-12-06 - added     add raw json output in configdb info
#
# 2023-08-07 - fixed     missing uuid in migration process
#
# 2023-08-23 - added     show version counter in save message
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
## no critic
sub AnalyzeCommandChain($$;$);
sub GetDefAndAttr($;$);
sub Log($$);
sub createUniqueId();
## use critic

##################################################
# Forward declarations inside this library
#
sub cfgDB_AttrRead;
sub cfgDB_ReadAll;
sub cfgDB_Init;
sub cfgDB_FileRead;
sub cfgDB_FileUpdate;
sub cfgDB_Fileversion;
sub cfgDB_FileWrite;
sub cfgDB_FW_fileList;
sub cfgDB_Read99;
sub cfgDB_SaveCfg;
sub cfgDB_SaveState;
sub cfgDB_svnId;

sub _cfgDB_binFileimport;
sub _cfgDB_Connect;
sub _cfgDB_DeleteTemp;
sub _cfgDB_Diff;
sub __cfgDB_Diff;
sub _cfgDB_InsertLine;
sub _cfgDB_Execute;
sub _cfgDB_Filedelete;
sub _cfgDB_Fileexport;
sub _cfgDB_Filelist;
sub _cfgDB_Info;
sub _cfgDB_Migrate;
sub _cfgDB_ReadCfg;
sub _cfgDB_ReadState;
sub _cfgDB_Recover;
sub _cfgDB_Reorg;
sub _cfgDB_Rotate;
sub _cfgDB_Search;
sub _cfgDB_table_exists;
sub _cfgDB_dump;
sub _cfgDB_knownAttr;
sub _cfgDB_deleteRF;
sub _cfgDB_deleteStatefiles;
sub _cfgDB_isMysqlType;

##################################################
# Read configuration file for DB connection
#


my ($err,@c) = FileRead({FileName  => 'configDB.conf', 
                           ForceType => "file"}); 
return 0 if ($err);

my @config;

foreach my $line (@c) {
   $line =~ s/^\s+|\s+$//g; # remove whitespaces etc.
   $line =~ s/;$/;;/;       # duplicate ; at end-of-line
   push (@config,$line) if($line !~ m/^#/ && length($line) > 0);
}

use vars qw(%configDB);

my %dbconfig;

my $configs  = join("",@config);
my @configs  = split(/;;/,$configs);
my $count    = @configs;
my $fhemhost = hostname;

## no critic
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
## use critic

my $cfgDB_dbconn    = $dbconfig{connection};
my $cfgDB_dbuser    = $dbconfig{user};
my $cfgDB_dbpass    = $dbconfig{password};
my $cfgDB_dbtype;
my $cfgDB_filename;


if($cfgDB_dbconn =~ m/pg:/i) {
      $cfgDB_dbtype ="POSTGRESQL";
   } elsif ($cfgDB_dbconn =~ m/mysql:/i) {
      $cfgDB_dbtype = "MYSQL";
   } elsif ($cfgDB_dbconn =~ m/mariadb:/i) {
      $cfgDB_dbtype = "MARIADB";
   } elsif ($cfgDB_dbconn =~ m/sqlite:/i) {
      $cfgDB_dbtype = "SQLITE";
      (undef,$cfgDB_filename) = split(/=/,$cfgDB_dbconn);
      $configDB{filename} = $cfgDB_filename;
   } else {
      $cfgDB_dbtype = "unknown";
}

$configDB{type}              = $cfgDB_dbtype;
$configDB{exclude}           = defined($dbconfig{exclude})     ? $dbconfig{exclude}     : '';
$configDB{attr}{nostate}     = defined($dbconfig{nostate})     ? $dbconfig{nostate}     : 0;
$configDB{attr}{rescue}      = defined($dbconfig{rescue})      ? $dbconfig{rescue}      : 0;
$configDB{attr}{loadversion} = defined($dbconfig{loadversion}) ? $dbconfig{loadversion} : 0;

_cfgDB_knownAttr();

%dbconfig = ();
@config   = ();
$configs  = undef;
$count    = undef;

##################################################
# Basic functions needed for DB configuration
# directly called from fhem.pl
#

# initialize database, create tables if necessary
sub cfgDB_Init {
##################################################
# Create non-existing database tables 
# Create default config entries if necessary
#
	my $fhem_dbh = _cfgDB_Connect;

#	create TABLE fhemversions ifnonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemversions(VERSION INT, VERSIONUUID CHAR(50), VERSIONTAG CHAR(50))");

#	create TABLE fhemconfig if nonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemconfig(COMMAND VARCHAR(32), DEVICE VARCHAR(64), P1 VARCHAR(64), P2 TEXT, VERSION INT, VERSIONUUID CHAR(50))");
	
#	create INDEX on fhemconfig if nonexistent (only if SQLITE)
	$fhem_dbh->do("CREATE INDEX IF NOT EXISTS config_idx on 'fhemconfig' (versionuuid,version)") 
	           if($cfgDB_dbtype eq "SQLITE");
		
#	check TABLE fhemconfig already populated
	my $count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemconfig');
	if($count < 1) {
#		insert default entries to get fhem running
		$fhem_dbh->commit();
		my $uuid = createUniqueId();
		$fhem_dbh->do("INSERT INTO fhemversions values (0, '$uuid',NULL)");
		_cfgDB_InsertLine($fhem_dbh, $uuid, '#created by cfgDB_Init',0);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global logdir ./log',1);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global logfile %L/fhem-%Y-%m-%d.log',2);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global modpath .',3);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global userattr devStateIcon devStateStyle icon sortby webCmd',4);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr global verbose 3',5);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define telnetPort telnet 7072 global',6);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define web FHEMWEB 8083 global',7);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'attr web allowfrom .*',8);
		_cfgDB_InsertLine($fhem_dbh, $uuid, 'define Logfile FileLog %L/fhem-%Y-%m-%d.log Logfile',9);
	}

#	create TABLE fhemstate if nonexistent
	$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemstate(stateString TEXT)");

#	create TABLE fhemb64filesave if nonexistent
#	if($cfgDB_dbtype eq "MYSQL") {
	if(_cfgDB_isMysqlType($cfgDB_dbtype)) {
		$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemb64filesave(filename TEXT, content MEDIUMBLOB)");
	} elsif ($cfgDB_dbtype eq "POSTGRESQL") {
		$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemb64filesave(filename TEXT, content bytea)");
	} else {
		$fhem_dbh->do("CREATE TABLE IF NOT EXISTS fhemb64filesave(filename TEXT, content BLOB)");
	}

#   modify table for version tags if needed
    eval {$fhem_dbh->do("SELECT versiontag from fhemversions where version = 0")};
    $fhem_dbh->do("ALTER TABLE fhemversions ADD VERSIONTAG char(50)") if $@;

# close database connection
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();

	return;
}

# read attributes
sub cfgDB_AttrRead { 
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
sub cfgDB_FileRead {
	my ($filename,$fhem_dbh) = @_;
    my $internal_call = 1 if $fhem_dbh;

	Log 4, "configDB reading file: $filename";
	my ($err, @ret, $counter);
	$fhem_dbh = _cfgDB_Connect unless $fhem_dbh;
	my $read_cmd  = "SELECT content FROM fhemb64filesave WHERE filename = '$filename'";
	my $sth = $fhem_dbh->prepare( $read_cmd );
	$sth->execute();
	my $blobContent = $sth->fetchrow_array();
	$sth->finish();
	$fhem_dbh->disconnect() unless $internal_call;
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

sub cfgDB_FileWrite {
	my ($filename,@content) = @_;
	Log 4, "configDB writing file: $filename";
	my $fhem_dbh = _cfgDB_Connect;
	$fhem_dbh->do("delete from fhemb64filesave where filename = '$filename'");
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemb64filesave values (?, ?)');
	$sth->execute($filename,encode_base64(join("\n", @content)));
	$sth->finish();
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return;
}

sub cfgDB_FileUpdate {
	my ($filename) = @_;
	my $fhem_dbh = _cfgDB_Connect;
	my $id = $fhem_dbh->selectrow_array("SELECT filename from fhemb64filesave where filename = '$filename'");
	$fhem_dbh->disconnect();
	if($id) {
		my $filesize = -s $filename;
		_cfgDB_binFileimport($filename,$filesize,1) if ($id) ;
		Log 4, "file $filename updated in configDB";
	}
	return;
}

# read and execute fhemconfig and statefile
sub cfgDB_ReadAll {  ## prototype used in fhem.pl
	my ($cl) = @_;
	my ($ret, @dbconfig);

	if ($configDB{attr}{rescue} == 1) {
		Log 0, 'configDB starting in rescue mode!';
		push (@dbconfig, 'attr global modpath .');
		push (@dbconfig, 'attr global verbose 3');
		push (@dbconfig, 'define telnetPort telnet 7072 global');
		push (@dbconfig, 'define web FHEMWEB 8083 global');
		push (@dbconfig, 'attr web allowfrom .*');
		push (@dbconfig, 'define Logfile FileLog ./log/fhem-%Y-%m-%d.log Logfile');
	} else {
		# add Config Rows to commandfile
		@dbconfig = _cfgDB_ReadCfg(@dbconfig);
		# add State Rows to commandfile
		@dbconfig = _cfgDB_ReadState(@dbconfig) unless $configDB{attr}{nostate} == 1;
	}

	# AnalyzeCommandChain for all entries
	$ret = _cfgDB_Execute($cl, @dbconfig);
	return $ret if($ret);
	return;
}

# save running configuration to version 0
sub cfgDB_SaveCfg { ## prototype used in fhem.pl
    Log 4, "configDB save config ".$data{saveID} if(defined($data{saveID}));
	my ($internal) = shift;
	$internal = defined($internal) ? $internal : 0;
	my $c = "configdb";
	my @dontSave = qw(configdb:rescue configdb:nostate configdb:loadversion
	                  configdb:shortinfo 
	                  global:configfile global:statefile global:version);
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

		push (@rowList, GetDefAndAttr($d,1));

	}

		foreach my $a (sort keys %{$configDB{attr}}) {
			my $val = $configDB{attr}{$a};
			next unless $val;
			next if grep {$_ eq "$c:$a";} @dontSave;
			$val =~ s/;/;;/g;
			push @rowList, "attr $c $a $val";
		}

	$t = localtime;
	$out = "#created $t";
	push @rowList, $out;
    Debug "\n".join("\n",@rowList) if defined($data{cfgDB_debug});
    return @rowList if defined($data{cfgDB_rawList});

# Insert @rowList into database table
	my $fhem_dbh = _cfgDB_Connect;
	my ($num,$uuid) = split(/\:/,_cfgDB_Rotate($fhem_dbh,$internal));
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
	return "configDB saved. ($num)";
}

# save statefile
sub cfgDB_SaveState {
	my ($out,$val,$r,$rd,$t,@rowList);

    # don't write statefile in rescue mode
    return if ($configDB{attr}{rescue} == 1);

#    _cfgDB_deleteRF;

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
            $val =~ s/\n/\$xyz\$/g;
			$out = "setstate $d $val";
			Log 5, "configDB: $out";
			push @rowList, $out;
		}
		$r = $defs{$d}{READINGS};
		if($r) {
			foreach my $c (sort keys %{$r}) {
				$rd = $r->{$c};
				if(!defined($rd->{TIME})) {
					Log 5, "WriteStatefile $d $c: Missing TIME, using current time";
					$rd->{TIME} = TimeNow();
				}
				if(!defined($rd->{VAL})) {
					Log 5, "WriteStatefile $d $c: Missing VAL, setting it to 0";
					$rd->{VAL} = 0;
				}
				$val = $rd->{VAL};
				$val =~ s/;/;;/g;
                $val =~ s/\n/\$xyz\$/g;
				$out = "setstate $d $rd->{TIME} $c $val";
				Log 5, "configDB: $out"; 
                push @rowList, $out; 
			}
		}
	}

    my $fileName = defined($data{saveID}) ? $data{saveID} : $configDB{loaded};
       $fileName =~ s/^\s+|\s+$//g; # trim filename
       $fileName .= ".fhem.save";
    Log 4, "configDB save state $fileName with ".$#rowList." entries";
    cfgDB_FileWrite($fileName,@rowList);

	return;
}

# import existing files during migration 
sub cfgDB_MigrationImport {

	my ($ret, $filename, @files, @def);
	my $modpath = AttrVal("global","modpath",".");

# find eventTypes file
	@def = '';
	@def = _cfgDB_findDef('TYPE=eventTypes');
	foreach my $fn (@def) {
		next unless $fn;
		push @files, $fn;
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
	@def = '';
	@def = _cfgDB_findDef('TYPE=SVG','GPLOTFILE');
	foreach my $fn (@def) {
		next unless $fn;
		push @files, "$modpath/www/gplot/".$fn.".gplot";
	}

# find DbLog configs
	@def = '';
	@def = _cfgDB_findDef('TYPE=DbLog','CONFIGURATION');
	foreach my $fn (@def) {
		next unless $fn;
		push @files, $fn;
	}

# find RSS and Infopanel layouts
	@def = '';
	@def = _cfgDB_findDef('TYPE=(RSS|InfoPanel)','LAYOUTFILE');
	foreach my $fn (@def) {
		next unless $fn;
		push @files, $fn;
	}

# find weekprofile/LightScene/RHASSPY configurations
	@def = '';
	@def = _cfgDB_findDef('TYPE=(weekprofile|LightScene|RHASSPY)','CONFIGFILE');
	foreach my $fn (@def) {
		next unless $fn;
		push @files, $fn;
	}

# find holiday files
	@def = '';
	@def = _cfgDB_findDef('TYPE=holiday','NAME');
	foreach my $fn (@def) {
		next unless $fn;
		if(defined($defs{$fn}{HOLIDAYFILE})) {
           push @files, $defs{$fn}{HOLIDAYFILE};
		} else {
           push @files, "$modpath/FHEM/holiday/".$fn.".holiday";
		}
	}

# import uniqueID file
	$filename = "$modpath/FHEM/FhemUtils/uniqueID";
	push @files,$filename if (-e $filename);   

# do the import
	foreach my $fn (@files) {
		if ( -r $fn ) {
			my $filesize = -s $fn;
			_cfgDB_binFileimport($fn,$filesize);
			$ret .= "importing: $fn\n";
		}
	}

	return $ret;
}

# return SVN Id, called by fhem's CommandVersion
sub cfgDB_svnId { 
	return "# ".'$Id$' 
}

# return filelist depending on directory and regexp
sub cfgDB_FW_fileList {
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
sub cfgDB_Read99 {
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
sub cfgDB_Fileversion {
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
sub _cfgDB_InsertLine {
	my ($fhem_dbh, $uuid, $line, $counter) = @_;
	Log 0, "configDB: $line" if defined($data{cfgDB_debug});
	my ($c,$d,$p1,$p2) = split(/ /, $line, 4);
	my $sth = $fhem_dbh->prepare('INSERT INTO fhemconfig values (?, ?, ?, ?, ?, ?)');
	$sth->execute($c, $d, $p1, $p2, $counter, $uuid);
	return;
}

# pass command table to AnalyzeCommandChain
sub _cfgDB_Execute {
	my ($cl, @dbconfig) = @_;
	my (@ret);

	foreach my $l (@dbconfig) {
		$l =~ s/[\r\n]/\n/g;
		$l =~ s/\\\n/\n/g;
		my $tret = AnalyzeCommandChain($cl, $l);
		push @ret, $tret if(defined($tret));
	}
	return join("\n", @ret) if(@ret);
	return;
}

# read all entries from fhemconfig
# and add them to command table for execution
sub _cfgDB_ReadCfg {
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
	$uuid =~ s/^\s+|\s+$//g;
    $configDB{loaded} = $uuid;
    Log 4, "configDB read config ".$configDB{loaded};
    my @excluded = split(/,/,$configDB{exclude});
    map { s/^\s+|\s+$//g; } @excluded;
	$sth = $fhem_dbh->prepare( "SELECT * FROM fhemconfig WHERE versionuuid = '$uuid' and device <>'configdb' order by version" );  

	$sth->execute();
	while (@line = $sth->fetchrow_array()) {
		$row  = "$line[0] $line[1] $line[2]";
		$row .= " $line[3]" if defined($line[3]);
		if ( grep( /^$line[1]$/, @excluded ) ) {
		  Log 1, "configDB excluding $line[1] ($row)" if $line[0] eq "define";
		} else {
          push @dbconfig, $row;
		}
	}
	$fhem_dbh->disconnect();
	return @dbconfig;
}

# read all entries from fhemstate
# and add them to command table for execution
sub _cfgDB_ReadState {
	my (@dbconfig) = @_;

	my $stateFileName = $configDB{loaded}.".fhem.save";
    my ($err,@state) = cfgDB_FileRead($stateFileName);
    if ($err eq "") {
      Log 4, "configDB read state ".$stateFileName;
      map { my $a = $_; $a =~ s/\$xyz\$/\\n/g; push @dbconfig, $a } @state;
	  my $fhem_dbh = _cfgDB_Connect;
         $fhem_dbh->do("delete from fhemstate");
         $fhem_dbh->commit();
	     $fhem_dbh->disconnect();
    } else {
      Log 4, "configDB read state from table fhemstate";
	  my $fhem_dbh = _cfgDB_Connect;
	  my ($sth, $row,$f);
	  $sth = $fhem_dbh->prepare( "SELECT * FROM fhemstate" );  
	  $sth->execute();
	  while ($row = $sth->fetchrow_array()) {
	    if($row =~ m/(cfgDBkey:)(.{32})/) {
          my $f = $2;
	       my (undef, $content) = cfgDB_FileRead($f,$fhem_dbh);
	       $row =~ s/cfgDB:................................$/$content/;
	       _cfgDB_Filedelete($f,$fhem_dbh);
        }
		push @dbconfig, $row;
	  }
	  $fhem_dbh->disconnect();
    }
	return @dbconfig;
}

# rotate all versions to versionnum + 1
# return uuid for new version 0
sub _cfgDB_Rotate {
	my ($fhem_dbh,$newversion) = @_;
    my $uuid = $data{saveID};
       $uuid =~ s/^\s+|\s+$//g;
    delete $data{saveID}; # no longer needed in memory
	$configDB{loaded} = $uuid;
	my $count = $fhem_dbh->do("UPDATE fhemversions SET VERSION = VERSION+1 where VERSION >= 0") if $newversion == 0;
	$fhem_dbh->do("INSERT INTO fhemversions values ('$newversion', '$uuid', NULL)");
	Log3(undef,1,"configDB: more than 20 versions in database! Please consider setting a limit.") 
	    if ($count > 20 && !defined($configDB{attr}{maxversions}));
	return "$count:$uuid";
}

sub _cfgDB_filesize_str {
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
sub _cfgDB_Migrate {
	my $ret;
	$data{saveID} = createUniqueId();
	$ret = "Starting migration...\n";
	Log 4, 'configDB: Starting migration';
	$ret .= "Processing: database initialization\n";
	Log 4, 'configDB: Processing: cfgDB_Init';
	cfgDB_Init;
	$ret .= "Processing: save config\n";
	Log 4, 'configDB: Processing: cfgDB_SaveCfg';
	cfgDB_SaveCfg;
	$ret .= "Processing: save state\n";
	Log 4, 'configDB: Processing: cfgDB_SaveState';
	cfgDB_SaveState;
	$ret .= "Processing: fileimport\n";
	Log 4, 'configDB: Processing: cfgDB_MigrationImport';
	$ret .= cfgDB_MigrationImport;
	$ret .= "Migration completed\n\n";
	Log 4, 'configDB: Migration completed.';
	$ret .= _cfgDB_Info(undef);
	return $ret;
}

# show database statistics
sub _cfgDB_Info {
	my ($info2,$raw) = @_;
	$info2 //= 'unknown';
	$raw //= 0;
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
	push @r, " loaded:       ".$configDB{loaded};
	my $fhem_dbh = _cfgDB_Connect;
	my ($sql, $sth, @line, $row, $countDef, $countAttr, @raw);

# read versions table statistics

    $configDB{attr}{shortinfo} //= 0;
    if ($configDB{attr}{shortinfo} == 0) {
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
			$line[3]   = "" unless defined $line[3];
			$countDef  = $fhem_dbh->selectrow_array("SELECT COUNT(*) from fhemconfig where COMMAND = 'define' and VERSIONUUID = '$line[5]'");
			$countAttr = $fhem_dbh->selectrow_array("SELECT COUNT(*) from fhemconfig where COMMAND = 'attr' and VERSIONUUID = '$line[5]'");
			$row  = " Ver $line[6] saved: $line[1] $line[2] $line[3] def: $countDef attr: $countAttr";
			$row .= " tag: ".$line[8] if $line[8];
			push @r, $row;
			push @raw, {version => $line[6], saved => "$line[1] $line[2] $line[3]", def => $countDef, attr => $countAttr};
		}
    } else {
    	my $count;
    	$count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemversions');
    	push @r, " versions:     $count";
		$count = $fhem_dbh->selectrow_array('SELECT count(*) FROM fhemconfig');
		push @r, " config:       $count entries";
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

	return toJSON \@raw if $raw;
	return join("\n", @r);
}

sub _cfgDB_Info_Json {
  my $cSVN = shift;
  $cSVN //= 'unknown';
  my %info = ();

# add ./FHEM/98_configdb.pm svn id
  $info{cSVN} = $cSVN;

# add ./configDB.pm svn id
  my $dSVN = cfgDB_svnId;
  $dSVN =~ s/# //;
  $info{dSVN} = $dSVN;

# add configDB database info
	$info{dbconn} = $cfgDB_dbconn;
	$info{dbuser} = $configDB{attr}{private} ? 'private' : $cfgDB_dbuser;
	$info{dbpass} = $configDB{attr}{private} ? 'private' : $cfgDB_dbpass;
	$info{dbtype} = $cfgDB_dbtype;
    $info{dbsize} = _cfgDB_filesize_str(-s $cfgDB_filename) if ($cfgDB_dbtype eq "SQLITE");
    
  return toJSON \%info;
}

# recover former config from database archive
sub _cfgDB_Recover {
	my ($version) = @_;
	my ($cmd, $count, $ret);

	if($version > 0) {
		my $fhem_dbh = _cfgDB_Connect;
		$cmd = "SELECT count(*) FROM fhemconfig WHERE VERSIONUUID in (select versionuuid from fhemversions where version = $version)";
		$count = $fhem_dbh->selectrow_array($cmd);

		if($count > 0) {
			my $fromuuid = $fhem_dbh->selectrow_array("select versionuuid from fhemversions where version = $version");
			my $touuid   = createUniqueId();
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

#           Copy corresponding statefile
            my $filename  = $fromuuid.".fhem.save";
            my ($err,@statefile) = FileRead($filename);
            $filename = $touuid.".fhem.save";
            FileWrite($filename,@statefile);

#			Inform user about restart required
			$ret  = "Version 0 deleted.\n";
			$ret .= "Version $version copied to version 0\n\n";
            $ret .= "FHEM will exit in 3 seconds.";
            InternalTimer(gettimeofday()+3, sub {exit 0}, 0);
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
sub _cfgDB_Reorg {
	my ($lastversion,$quiet) = @_;
	$lastversion = (defined($lastversion)) ? $lastversion : 3;
	Log 4, "configDB reorg started, keeping last $lastversion versions.";
	my $fhem_dbh = _cfgDB_Connect;
	$fhem_dbh->do("delete FROM fhemconfig   where versionuuid in (select versionuuid from fhemversions where version > $lastversion)");
	$fhem_dbh->do("delete from fhemversions where version > $lastversion");
	$fhem_dbh->do("delete FROM fhemconfig   where versionuuid in (select versionuuid from fhemversions where version = -1)");
	$fhem_dbh->do("delete from fhemversions where version = -1");
	my $ts = localtime(time);
	$configDB{attr}{'lastReorg'} = $ts;
	_cfgDB_InsertLine($fhem_dbh,$configDB{loaded},"attr configdb lastReorg $ts",-1); 
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	_cfgDB_deleteStatefiles();
	eval { qx(sqlite3 $cfgDB_filename vacuum) } if($cfgDB_dbtype eq "SQLITE");
	return if(defined($quiet));
	return " Result after database reorg:\n"._cfgDB_Info(undef);
}

# delete temporary version
sub _cfgDB_DeleteTemp {
	Log 4, "configDB: delete temporary Version -1";
	my $fhem_dbh = _cfgDB_Connect;
	$fhem_dbh->do("delete FROM fhemconfig   where versionuuid in (select versionuuid from fhemversions where version = -1)");
	$fhem_dbh->do("delete from fhemversions where version = -1");
	$fhem_dbh->commit();
	$fhem_dbh->disconnect();
	return;
}

# search for device or fulltext in db
sub _cfgDB_Search {
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
	Log 4, "configDB: $sql";
	$sth->execute();
	$text = $dsearch ? " device" : "";
	push @result, "search result for$text: $search in version: $searchversion";
	push @result, "--------------------------------------------------------------------------------";
	while (@line = $sth->fetchrow_array()) {
		$row  = "$line[0] $line[1] $line[2]";
        $row .= " $line[3]" if defined($line[3]);
		Log 4, "configDB: $row";
		push @result, "$row" unless ($line[0] eq 'setuuid');
	}
	$fhem_dbh->disconnect();
	$ret = join("\n", @result);
	return $ret;
}

# called from cfgDB_Diff
sub __cfgDB_Diff {
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
	    $line[3] //= "";
		$ret .= "$line[0] $line[1] $line[2] $line[3]\n";
	}
	return $ret;
}

# compare device configurations from 2 versions
sub _cfgDB_Diff {
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
sub _cfgDB_findDef {
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

sub _cfgDB_type { 
   return $cfgDB_dbtype;
}

sub _cfgDB_dump {
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
      Log 4, "configDB: $dumpcmd";
      $ret        = qx($dumpcmd);
      return $ret if $ret; # return error message if available

#   } elsif ($dbtype eq 'MYSQL') {
   } elsif (_cfgDB_isMysqlType($dbtype)) {
      ($dbname,$dbhostname,$dbport) = split (/;/,$dbconn);
      $dbport //= '=3306';
      (undef,$dbname)     = split (/=/,$dbname);
      (undef,$dbhostname) = split (/=/,$dbhostname);
      (undef,$dbport)     = split (/=/,$dbport);
      my $xparam = defined($configDB{attr}{mysqldump}) ? $configDB{attr}{mysqldump} : '';
      my $dbtables = "fhemversions fhemconfig fhemstate fhemb64filesave";
      my $dumpcmd = "mysqldump $xparam --user=$dbuser --password=$dbpass --host=$dbhostname --port=$dbport -Q $dbname $dbtables $gzip > $target";
      Log 4, "configDB: $dumpcmd";
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
      Log 4, "configDB: $dumpcmd";
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

sub _cfgDB_knownAttr {
  $configDB{knownAttr}{deleteimported} =
    "(0|1) delete file from filesystem after import";
  $configDB{knownAttr}{dumpPath} =
    "(valid path) define path for database dump";
  $configDB{knownAttr}{maxversions}=
    "(number) define maximum number of configurations stored in database";
  $configDB{knownAttr}{mysqldump}=
    "(valid parameter string) define additional parameters used for dump in mysql environment";
  $configDB{knownAttr}{private}=
    "(0|1) show or supress userdata in info output";
  $configDB{knownAttr}{shortinfo}=
    "(0|1) show detailed or short result in info output";
#  $configDB{knownAttr}{loadversion}=
#    "for internal use only";
#  $configDB{knownAttr}{nostate}=
#    "for internal use only";
#  $configDB{knownAttr}{rescue}=
#    "for internal use only";
}

sub _cfgDB_deleteRF {
# Delete old files containing large readings
  my $filename;
   my $fhem_dbh2 = _cfgDB_Connect;
   my $sth = $fhem_dbh2->prepare( "SELECT filename FROM fhemb64filesave" );  
   $sth->execute();
   while ($filename = $sth->fetchrow_array()) {
     if ($filename =~ m/^[0-9A-F]+$/i) {
       Log 4, "configDB delete file: $filename";
       $fhem_dbh2->do("delete from fhemb64filesave where filename = '$filename'");
     }
   }
   $fhem_dbh2->commit();
   $fhem_dbh2->disconnect();
}

sub _cfgDB_deleteStatefiles {
   my $filename;
   my $fhem_dbh = _cfgDB_Connect;
   my $sth = $fhem_dbh->prepare( "SELECT filename FROM fhemb64filesave where filename like '%.fhem.save'" );  
   $sth->execute();
   while ($filename = $sth->fetchrow_array()) {
       Log 5, "configDB: statefile  filename >$filename<";
       if (length($filename) > 42) { # malformed filename from postgresql
         Log 5, "configDB: statefile del1 >$filename<";
         $fhem_dbh->do("delete from fhemb64filesave where filename = '$filename'");
         next;       
       }
       my $uuid  = "";
       $uuid = substr($filename,0,32);
       Log 5, "configDB: statefile uuid:  >$uuid<";
       my $found = $fhem_dbh->selectrow_array("SELECT versionuuid FROM fhemversions WHERE versionuuid = '$uuid'");
       $found //= 'notfound'; # to prevent perl warning
       $found = substr($found,0,32);
       Log 5, "configDB: statefile found: >$found<";
       unless ($uuid eq $found) {
         Log 5, "configDB: statefile del2 >$filename<";
         $fhem_dbh->do("delete from fhemb64filesave where filename = '$filename'");
       }
   }
   $fhem_dbh->commit();
   $fhem_dbh->disconnect();
}

sub _cfgDB_isMysqlType {
   my $type = shift();
   return ($type eq 'MYSQL' || $type eq 'MARIADB');
}
##################################################
# functions used for file handling
# called by 98_configdb.pm
#

# delete file from database
sub _cfgDB_Filedelete {
	my ($filename,$fhem_dbh) = @_;
	my $internal_call = 1 if $fhem_dbh;
	$fhem_dbh = _cfgDB_Connect unless $internal_call;
	my $ret = $fhem_dbh->do("delete from fhemb64filesave where filename = '$filename'");
	$fhem_dbh->commit();
	$fhem_dbh->disconnect() unless $internal_call;
	$ret = ($ret > 0) ? 1 : undef;
	return $ret;
}

# export file from database to filesystem
sub _cfgDB_Fileexport {
	my ($filename,$raw) = @_;
	my $fhem_dbh = _cfgDB_Connect;
	my $sth      = $fhem_dbh->prepare( "SELECT content FROM fhemb64filesave WHERE filename = '$filename'" );  
	$sth->execute();
	my $blobContent = $sth->fetchrow_array();
    $blobContent = decode_base64($blobContent) if($blobContent);
	my $counter = length($blobContent);
	$sth->finish();
	$fhem_dbh->disconnect();
	return "No data found for file $filename" unless $counter;
	return ($blobContent,$counter) if $raw;
	
	open( my $f,">","$filename" );
		binmode($f);
		print $f $blobContent;
	close( $f );
	return "$counter bytes written from database into file $filename";
}

# import file into database
sub _cfgDB_binFileimport {
	my ($filename,$filesize,$doDelete) = @_;
	$doDelete = (defined($doDelete)) ? 1 : 0;

	open (my $inFile,"<","$filename") || die $!;
		my $blobContent;
		binmode($inFile);
		my $readBytes = read($inFile, $blobContent, $filesize);
	close($inFile);
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
sub _cfgDB_Filelist {
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
