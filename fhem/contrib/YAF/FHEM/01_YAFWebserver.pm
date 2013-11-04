########################################################################################
#
# YAFWebserver.pm
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

use FindBin;
use lib "$FindBin::Bin/FHEM/YAF/libs";
use YAFWebserver;

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
        
        # init new webserver instance
        $hash->{YAFWEBSERVER} = YAFWebserver->new;
        $hash->{HEADER_FIELD_HASHMAP} = ();
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
        # Open new tcp listening on defined port
        my $ret = TcpServer_Open($hash, $port, "");
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
        # Close tcp listening
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
        my $requestedUrl;
        
        # Accept new server sockets
        if($hash->{SERVERSOCKET}) {
                TcpServer_Accept($hash, "YAFWebserver");
                return;
        }
        
        # Received chars stored in $c
        my $c = $hash->{CD};
        
        # Read 1024 byte of data
        my $buf;
        my $ret = sysread($hash->{CD}, $buf, 1024);
        
        # When there is an error in connection return
        if (!defined($ret) || $ret <= 0) {
        	CommandDelete(undef, $hash->{NAME});
        	return;
        }
        
        ########
        # State: new request / read header
        ########
        if (!defined($hash->{HTTPSTATE}) || ($hash->{HTTPSTATE} eq "NewRequest")) {
                # Check if new Request is GET or POST else => break connection
                if (($buf =~ m/\n\n.*/) || ($buf =~ m/\r\n\r\n.*/)) {   
                        my $position = 0;
                        # Search trim position,to cut header from content
                        if ($buf =~ m/\n\n.*/) {
                                $position = index($buf,"\n\n")+2; # +2 for \n\n
                        }
                        else {
                                $position = index($buf, "\r\n\r\n")+4;# +4 for \r\n\r\n
                        }
                        # header is read. Remove header from buffer.
                        $hash->{HTTPHEADER} .= substr($buf, 0, $position);      
                        $buf = substr($buf, $position);
                        # split header in lines in hashmap
                        # example header line: Accept-Encoding: gzip,deflate,sdch
                        # $hash->{HTTPHEADER_VALUEMAP}->{key} => value
                        my @header_field = split("[\r\n][\r\n]", $hash->{HTTPHEADER});
                        my @header_field_line_splitted;
                 		for (my $array_pos = 1; $array_pos < scalar(@header_field); $array_pos++) { 
                 			@header_field_line_splitted = split(":",$header_field[$array_pos]);
                 			$hash->{HTTPHEADER_VALUEMAP}->{"$header_field_line_splitted[0]"} = trim($header_field_line_splitted[1]);
                 		}
                        # look for request line
                        # GET / HTTP/1.1
                        my @header_field_request_splitted = split(" ", $header_field[0]);
                        $hash->{HTTPHEADER_METHOD} = $header_field_request_splitted[0];
                        $hash->{HTTPHEADER_URI} = $header_field_request_splitted[1]; 
                        $hash->{HTTPHEADER_VERSION} = $header_field_request_splitted[2]; 
                        # consume uri
                        # \path\to\file.php ? test = 1 & test = 2
                        # $hash->{GET}->{key} => value                       
                        my @header_field_uri_splitted = split(/\?/, $hash->{HTTPHEADER_URI});
						if (scalar(@header_field_uri_splitted) > 1) {
							my @attributes_array = split("&",$header_field_uri_splitted[1]);
							my @attribute_pair;
							foreach (@attributes_array) {
								@attribute_pair = split("=",$_);
								$hash->{GET}->{"$attribute_pair[0]"} = $attribute_pair[1]; 
							}
						}        
						# cookie 
						if ($hash->{HTTPHEADER_VALUEMAP}->{"Cookie"}) {
							my @cookies_array = split(";", $hash->{HTTPHEADER_VALUEMAP}->{"Cookie"});
							my @cookies_array_pair;
							foreach (@cookies_array) {
								@cookies_array_pair = split("=",$_);
								my $name = trim($cookies_array_pair[0]);
								$hash->{COOKIE}->{"$name"} = $cookies_array_pair[1];
							}
						}
                        # set content-length
                      	if ($hash->{HTTPHEADER_VALUEMAP}->{"Content-Length"}) {
                      		$hash->{HTTPCONTENT_LENGTH} = $hash->{HTTPHEADER_VALUEMAP}->{"Content-Length"};
                      	}
                        else {
                        	$hash->{HTTPCONTENT_LENGTH} = 0;
                        }
                        # clear HTTPCONTENT
                        $hash->{HTTPCONTENT} = "";
                        $hash->{HTTPSTATE} = "ReadData";
                        
                }
                else {
                        $hash->{HTTPHEADER} .= $buf;
                        return;
                }
        }
        
        ########
        # State: consume content
        ########
        if (defined($hash->{HTTPSTATE}) && ($hash->{HTTPSTATE} eq "ReadData")) {
                $hash->{HTTPCONTENT} .= $buf;
                # Read hole HTTPCONTENT
                if (length($hash->{HTTPCONTENT}) >= $hash->{HTTPCONTENT_LENGTH}) {
                        $hash->{HTTPSTATE} = "DoResponse";
                		# content finish
                		# prepare post var
                		if (($hash->{HTTPHEADER_VALUEMAP}->{"Content-Type"}) && ($hash->{HTTPHEADER_VALUEMAP}->{"Content-Type"} eq "application/x-www-form-urlencoded")) {
                			my @attributes_array = split("&",$hash->{HTTPCONTENT});
							my @attribute_pair;
							foreach (@attributes_array) {
								@attribute_pair = split("=",$_);
								$hash->{POST}->{"$attribute_pair[0]"} = $attribute_pair[1];
							}
                		}      
                		elsif (($hash->{HTTPHEADER_VALUEMAP}->{"Content-Type"}) && ($hash->{HTTPHEADER_VALUEMAP}->{"Content-Type"} =~ m/multipart\/form-data; boundary=*/)) {
                			$hash->{POST_DIVISOR} = $hash->{HTTPHEADER_VALUEMAP}->{"Content-Type"};
                			$hash->{POST_DIVISOR} =~ s/multipart\/form-data; boundary=//g;
                			# add prefix
                			$hash->{POST_DIVISOR} = "--".$hash->{POST_DIVISOR};
                			my @post_field_splitted = split($hash->{POST_DIVISOR},$hash->{HTTPCONTENT});
                			# for every post field
                			for (my $array_pos = 1; $array_pos < scalar(@post_field_splitted)-1; $array_pos++) {
                				my @entry_splitted = split("\r\n\r\n",$post_field_splitted[$array_pos]);
                				# remove last return in value
                				$entry_splitted[1] = substr($entry_splitted[1],0,length($entry_splitted[1])-2);
                				# get name
                				$entry_splitted[0] =~ m/.*name="(.*)".*/;
                				$hash->{POST}->{"$1"} = $entry_splitted[1];
                			}
                		}    
                }
                else {
                        return;
                }
        }
        
        ########
        # State: do response
        ########
        if (defined($hash->{HTTPSTATE}) && ($hash->{HTTPSTATE} eq "DoResponse")) {
        	my $header = $hash->{HTTPHEADER};
       		my $content = $hash->{HTTPCONTENT};
       		

       		my $test3 = "no";
         	my $response = "header lines: $hash->{HTTPCONTENT_LENGTH}\r\n####################\r\n$header####################\r\n$content\r\n##################\r\n$test3";
                

                print $c "HTTP/1.1 200 OK\r\n",
                                 "Content-Type: text/plain\r\n",
                                # "Set-Cookie: test=test4\r\n",
                     			"Content-Length: ".length($response)."\r\n\r\n",
                     			$response;
            # Waiting for new Request
            $hash->{HTTPHEADER} = "";
            $hash->{HTTPCONTENT} = "";
            $hash->{HTTPSTATE} = "NewRequest";
                # End of Request 
        }
        
        return; 
}

1;