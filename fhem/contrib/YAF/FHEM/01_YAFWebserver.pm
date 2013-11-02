########################################################################################
#
# 01_YAF.pm
#
# YAF - Yet Another Floorplan
# FHEM Projektgruppe Hochschule Karlsruhe, 2013
# Markus Mangei, Daniel Weisensee, Prof. Dr. Peter A. Henning
#
########################################################################################
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
########################################################################################
package main;

use strict;
use warnings;

# load zlib if possible
my $zlib_active = 1;
eval "require Compress::Zlib;";
if ($@) {
	$zlib_active = 0;
}

########################################################################################
#
# YAFWebserver_Initialize - register YAFWebserver with FHEM
# 
# parameter hash
#
########################################################################################

sub YAFWebserver_Initialize($) {
        my ($hash) = @_;
        $hash->{DefFn} = "YAFWebserver_Define";
        $hash->{UndefFn} = "YAFWebserver_Undefine";
        $hash->{ReadFn} = "YAFWebserver_Read";
}

########################################################################################
#
# YAFWebserver_Define
# 
# parameter hash, def
#
########################################################################################

sub YAFWebserver_Define($@) {
        my ($hash, $def) = @_;
        my ($name, $type, $port) = split("[ \t]+", $def);
        # Starting Listening for Webserver Request
        my $ret = TcpServer_Open($hash, $port, "global");
        return $ret;
}

########################################################################################
#
# YAFWebserver_Undefine
# 
# parameter hash, arg
#
########################################################################################

sub YAFWebserver_Undefine($@) {
        my ($hash, $arg) = @_;
        return TcpServer_Close($hash);
}

########################################################################################
#
# YAFWebserver_Read
# 
# parameter hash
#
########################################################################################

sub YAFWebserver_Read($) {
        my ($hash) = @_;
        my $requested_uri;
        
        # New ServerSocket
        if($hash->{SERVERSOCKET}) {
                TcpServer_Accept($hash, "YAFWebserver");
                return;
        }
        
        my $c = $hash->{CD};
        my $buf;
        
        # Read 1024 Byte of data
        my $ret = sysread($hash->{CD}, $buf, 1024);
        
        # When there is an error in connection return
        if(!defined($ret) || $ret <= 0) {
        	CommandDelete(undef, $hash->{NAME});
       		return;
        }
        
        # New Request
        if (!defined($hash->{HTTPSTATE}) || ($hash->{HTTPSTATE} eq "NewRequest")) {
                # Check if new Request is GET or POST else => break connection
                if (($buf =~ m/\n\n.*/) || ($buf =~ m/\r\n\r\n.*/)) {   
                        my $position_end_of_header = 0;
                        # Search trim position,to cut header from content
                        if ($buf =~ m/\n\n.*/) {
                                $position_end_of_header = index($buf,"\n\n")+2; # +2 for \n\n
                        }
                        else {
                                $position_end_of_header = index($buf, "\r\n\r\n")+4;# +4 for \r\n\r\n
                        }
                        # Hole header is read. Remove header from buffer.
                        $hash->{HTTPHEADER} .= substr($buf, 0, $position_end_of_header);      
                        $buf = substr($buf, $position_end_of_header);
                        # Split header in lines (\r\n)
                        my @header_array = split("[\r\n]", $hash->{HTTPHEADER});
                        # look for requested url
                        my @requested_uri = grep /GET/, @header_array;
                        my @requested_uri_parts = split(" ", $requested_uri[0]);
                        $requested_uri = $requested_uri_parts[1];
                        # Read Content-Length when available
                        my @content_length_array = grep /Content-Length/, @header_array;
                        my $content_length = 0;
                        if (scalar(@content_length_array) > 0) {
                                $content_length = substr($content_length_array[0],16);                              
                        }
                        # set content-length
                        $hash->{HTTPCONTENTLENGTH} = $content_length;
                        # clear HTTPCONTENT
                        $hash->{HTTPCONTENT} = "";
                        $hash->{HTTPSTATE} = "ReadData";                        
                }
                else {
                        $hash->{HTTPHEADER} .= $buf;
                        return;
                }
        }
        
        # Read Data 
        if (defined($hash->{HTTPSTATE}) && ($hash->{HTTPSTATE} eq "ReadData")) {
                $hash->{HTTPCONTENT} .= $buf;
                # Read hole HTTPCONTENT
                if (length($hash->{HTTPCONTENT}) >= $hash->{HTTPCONTENTLENGTH}) {
                        $hash->{HTTPSTATE} = "DoResponse";      
                }
                else {
                        return;
                }
        }
        
        # Answer Request
        if (defined($hash->{HTTPSTATE}) && ($hash->{HTTPSTATE} eq "DoResponse")) {
                my ($contentType, $content) = YAF_Request($requested_uri);
                
                # files over 30000 chars getting compressed
                my $header_compressed = "";  
                if (($zlib_active == 1) && (length($content) > 30000)) {
                	$content = Compress::Zlib::memGzip($content);
    				$header_compressed = "Content-Encoding: gzip\r\n";               	
                }
    
    			# send response to client
                print $c "HTTP/1.1 200 OK\r\n",
                     "Content-Length: ".length($content)."\r\n",
                     $header_compressed,
                     "Content-Type: $contentType\r\n\r\n",
                     $content;
                     
            # Waiting for new Request
            $hash->{HTTPHEADER} = "";
            $hash->{HTTPCONTENT} = "";
            $hash->{HTTPSTATE} = "NewRequest";
            # End of Request 
        }     
        return; 
} 

1;