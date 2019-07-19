################################################################################
# The file is part of the SIGNALduino project
#
 
package lib::SD_Protocols;

our $VERSION = '0.20';
use strict;
use warnings;


#=item new($)   #This functons, will initialize the given Filename containing a valid protocolHash
#=item LoadHash($) #This functons, will load protocol hash from file into a hash
#=item exists() # This functons, will return true if the given id exists otherwise false
#=item getKeys() # This functons, will return all keys from the protocol hash
#=item checkProperty() #This functons, will return a value from the Protocolist and check if the key exists and a value is defined optional you can specify a optional default value that will be returned
#=item getProperty() #This functons, will return a value from the Protocolist without any checks
#=item setDefaults() #This functons, will add common Defaults to the Protocollist

# - - - - - - - - - - - -
#=item new($)
# This functons, will initialize the given Filename containing a valid protocolHash
# First Parameter is for filename (full or relativ path) to be loaded
# Returns string with error value or undef
# =cut
#  $id

sub new
{
	my $ret = LoadHash(@_);
	return $ret->{'error'} if (exists($ret->{'error'})); 
	
	## Do some initialisation needed here
	
	return undef;
}

# - - - - - - - - - - - -
#=item LoadHash($)
# This functons, will load protocol hash from file into a hash.
# First Parameter is for filename (full or relativ path) to be loaded
# Returns a reference to error or the hash
# =cut
#  $id


	
sub LoadHash
{	
	if (! -e $_[0]) {
		return \%{ {"error" => "File $_[0] does not exsits"}};
	}
	delete($INC{$_[0]});
	if(  ! eval { require "$_[0]"; 1 }  ) {
		return 	\%{ {"error" => $@}};
	}
	setDefaults();
	return getProtocolList();
}


# - - - - - - - - - - - -
#=item exists()
# This functons, will return true if the given ID exists otherwise false
# =cut
#  $id
sub exists($)
{
	return exists($lib::SD_ProtocolData::protocols{$_[0]});
}

# - - - - - - - - - - - -
#=item getProtocolList()
# This functons, will return a reference to the protocol hash
# =cut
#  $id, $propertyname,
sub getProtocolList()	{	
	return \%lib::SD_ProtocolData::protocols;	}

# - - - - - - - - - - - -
#=item getKeys()
# This functons, will return all keys from the protocol hash
# 
# returns "" if the var is not defined
# =cut
#  $id, $propertyname,

sub getKeys() {
	return keys %lib::SD_ProtocolData::protocols; }

# - - - - - - - - - - - -
#=item checkProperty()
# This functons, will return a value from the Protocolist and check if the key exists and a value is defined optional you can specify a optional default value that will be returned
# 
# returns "" if the var is not defined
# =cut
#  $id, $propertyname,$default

sub checkProperty($$;$)
{
	return getProperty($_[0],$_[1]) if exists($lib::SD_ProtocolData::protocols{$_[0]}{$_[1]}) && defined($lib::SD_ProtocolData::protocols{$_[0]}{$_[1]});
	return $_[2]; # Will return undef if $default is not provided
}

# - - - - - - - - - - - -
#=item getProperty()
# This functons, will return a value from the Protocolist without any checks
# 
# returns "" if the var is not defined
# =cut
#  $id, $propertyname

sub getProperty($$)
{
	return $lib::SD_ProtocolData::protocols{$_[0]}{$_[1]};
}

# - - - - - - - - - - - -
#=item getProtocolVersion()
# This functons, will return a version value of the Protocolist
# 
# =cut

sub getProtocolVersion
{
	return $lib::SD_ProtocolData::VERSION;
}

# - - - - - - - - - - - -
#=item setDefaults()
# This functon will add common Defaults to the Protocollist
# 
# =cut

sub setDefaults
{
	foreach my $id (getKeys())
	{
		my $format = getProperty($id,"format");
		
		if (defined ($format) && $format eq "manchester")
		{
			# Manchester defaults :
			$lib::SD_ProtocolData::protocols{$id}{method} = \&lib::SD_Protocols::MCRAW if (!defined(checkProperty($id,"method")));
		}
		elsif (getProperty($id,"sync"))
		{
			# Messages with sync defaults :
			
		}
		elsif (getProperty($id,"clockabs"))
		{
			# Messages without sync defaults :
			$lib::SD_ProtocolData::protocols{$id}{length_min} = 8 if (!defined(checkProperty($id,"length_min")));
		}
			
	}
}

# - - - - - - - - - - - -
#=item binStr2hexStr()
# This functon will convert binary string into its hex representation as string
# 
# =cut

sub  binStr2hexStr {
    my $num   = shift;
    my $WIDTH = 4;
    my $index = length($num) - $WIDTH;
    my $hex = '';
    do {
        my $width = $WIDTH;
        if ($index < 0) {
            $width += $index;
            $index = 0;
        }
        my $cut_string = substr($num, $index, $width);
        $hex = sprintf('%X', oct("0b$cut_string")) . $hex;
        $index -= $WIDTH;
    } while ($index > (-1 * $WIDTH));
    return $hex;
}


# - - - - - - - - - - - -
#=item MCRAW()
# This functon is desired to be used as a default output helper for manchester signals. It will check for length_max and return a hex string
# 
# =cut
sub MCRAW
{
	my ($name,$bitData,$id,$mcbitnum) = @_;

	return (-1," message is to long") if ($mcbitnum > checkProperty($id,"length_max",0) );

	return(1,binStr2hexStr($bitData)); 
		
}


1;