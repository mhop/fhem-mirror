#!/usr/bin/perl -w

##########################################################################
# This file is part of the smarthomatic module for FHEM.
#
# Copyright (c) 2014 Uwe Freese
#
# You can find smarthomatic at www.smarthomatic.org.
# You can find FHEM at www.fhem.de.
#
# This file is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This file is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with smarthomatic. If not, see <http://www.gnu.org/licenses/>.
##########################################################################
# Usage:
#
# Init parser:
# ------------
# my $parser = new SHC_parser();
#
# Receiving packets:
# ------------------
# 1.) Receive string from base station (over UART).
# 2.) Parse received string:
#     $parser->parse("Packet Data: SenderID=22;...");
# 3.) Get MessageGroupName: my $grp = $parser->getMessageGroupName();
# 4.) Get MessageName: my $msg = $parser->getMessageName();
# 5.) Get data fields depending on MessageGroupname and MessageName, e.g.
#     $val = $parser->getField("Temperature");
#
# Sending packets:
# ----------------
# 1.) Init packet:
#     $parser->initPacket("PowerSwitch", "SwitchState", "Set");
# 2.) Set fields:
#     $parser->setField("PowerSwitch", "SwitchState", "TimeoutSec", 8);
# 3.) Get send string: $str = $parser->getSendString($receiverID);
# 4.) Send string to base station (over UART).
##########################################################################
# $Id: 37_SHC_Dev.pm xxxx 2014-xx-xx xx:xx:xx rr2000 $

package SHC_parser;

use strict;
use feature qw(switch);
use XML::LibXML;
use SHC_datafields;

# Hash for data field definitions.
my %dataFields = ();

# Hashes used to translate between names and IDs.
my %messageTypeID2messageTypeName = ();
my %messageTypeName2messageTypeID = ();

my %messageGroupID2messageGroupName = ();
my %messageGroupName2messageGroupID = ();

my %messageID2messageName = ();
my %messageName2messageID = ();

my %messageID2bits = ();

# byte array to store data to send
my @msgData  = ();
my $sendMode = 0;

sub new
{
  my $class = shift;
  init_datafield_positions();
  my $self = {
    _senderID         => 0,
    _packetCounter    => 0,
    _messageTypeID    => 0,
    _messageGroupID   => 0,
    _messageGroupName => "",
    _messageID        => 0,
    _messageName      => "",
    _messageData      => "",
  };
  bless $self, $class;
  return $self;
}

# Read packet layout from XML file and remember the defined MessageGroups,
# Messages and data fields (incl. positions, length).
sub init_datafield_positions()
{
  my $x = XML::LibXML->new() or die "new on XML::LibXML failed";
  my $d = $x->parse_file("FHEM/SHC_packet_layout.xml") or die "parsing XML file failed";

  for my $element ($d->findnodes("/Packet/Header/EnumValue[ID='MessageType']/Element")) {
    my $value = ($element->findnodes("Value"))[0]->textContent;
    my $name  = ($element->findnodes("Name"))[0]->textContent;

    $messageTypeID2messageTypeName{$value} = $name;
    $messageTypeName2messageTypeID{$name}  = $value;
  }

  for my $messageGroup ($d->findnodes("/Packet/MessageGroup")) {
    my $messageGroupName = ($messageGroup->findnodes("Name"))[0]->textContent;
    my $messageGroupID   = ($messageGroup->findnodes("MessageGroupID"))[0]->textContent;

    $messageGroupID2messageGroupName{$messageGroupID}   = $messageGroupName;
    $messageGroupName2messageGroupID{$messageGroupName} = $messageGroupID;

    for my $message ($messageGroup->findnodes("Message")) {
      my $messageName = ($message->findnodes("Name"))[0]->textContent;
      my $messageID   = ($message->findnodes("MessageID"))[0]->textContent;

      $messageID2messageName{$messageGroupID . "-" . $messageID}     = $messageName;
      $messageName2messageID{$messageGroupName . "-" . $messageName} = $messageID;

      my $offset      = 0;
      my $arrayLength = 1;

      for my $field ($message->findnodes("Array|UIntValue|IntValue|BoolValue|EnumValue")) {

        # When an array is detected, remember the array length and change the current field node
        # to the inner node for further processing.
        if ($field->nodeName eq 'Array') {
          $arrayLength = int(($field->findnodes("Length"))[0]->textContent);
          # DEBUG print "Next field is an array with " . $arrayLength . " elements!\n";

          $field = ($field->findnodes("UIntValue|IntValue|BoolValue|EnumValue"))[0];
        }

        given ($field->nodeName) {
          when ('UIntValue') {
            my $id   = ($field->findnodes("ID"))[0]->textContent;
            my $bits = ($field->findnodes("Bits"))[0]->textContent;

            # DEBUG print "Data field " . $id . " starts at " . $offset . " with " . $bits . " bits.\n";

            $dataFields{$messageGroupID . "-" . $messageID . "-" . $id} = new UIntValue($id, $offset, $bits);

            $offset += $bits * $arrayLength;
          }

          when ('IntValue') {
            my $id   = ($field->findnodes("ID"))[0]->textContent;
            my $bits = ($field->findnodes("Bits"))[0]->textContent;

            # DEBUG print "Data field " . $id . " starts at " . $offset . " with " . $bits . " bits.\n";

            $dataFields{$messageGroupID . "-" . $messageID . "-" . $id} = new IntValue($id, $offset, $bits);

            $offset += $bits * $arrayLength;
          }

          when ('BoolValue') {
            my $id   = ($field->findnodes("ID"))[0]->textContent;
            my $bits = 1;

            # DEBUG print "Data field " . $id . " starts at " . $offset . " with " . $bits . " bits.\n";

            $dataFields{$messageGroupID . "-" . $messageID . "-" . $id} = new BoolValue($id, $offset, $arrayLength);

            $offset += $bits * $arrayLength;
          }

          when ('EnumValue') {
            my $id   = ($field->findnodes("ID"))[0]->textContent;
            my $bits = ($field->findnodes("Bits"))[0]->textContent;

            # DEBUG print "Data field " . $id . " starts at " . $offset . " with " . $bits . " bits.\n";

            my $object = new EnumValue($id, $offset, $bits);
            $dataFields{$messageGroupID . "-" . $messageID . "-" . $id} = $object;

            for my $element ($field->findnodes("Element")) {
              my $value = ($element->findnodes("Value"))[0]->textContent;
              my $name  = ($element->findnodes("Name"))[0]->textContent;

              $object->addValue($name, $value);
            }

            $offset += $bits * $arrayLength;
          }
        }
      }

      $messageID2bits{$messageGroupID . "-" . $messageID} = $offset;
    }
  }
}

sub parse
{
  my ($self, $msg) = @_;

  $sendMode = 0;

  if (
    (
      $msg =~
/^Packet Data: SenderID=(\d*);PacketCounter=(\d*);MessageType=(\d*);MessageGroupID=(\d*);MessageID=(\d*);MessageData=([^;]*);.*/
    )
    || ($msg =~
/^Packet Data: SenderID=(\d*);PacketCounter=(\d*);MessageType=(\d*);AckSenderID=\d*;AckPacketCounter=\d*;Error=\d*;MessageGroupID=(\d*);MessageID=(\d*);MessageData=([^;]*);.*/
    )
    )
  {
    $self->{_senderID}       = $1;
    $self->{_packetCounter}  = $2;
    $self->{_messageTypeID}  = $3;
    $self->{_messageGroupID} = $4;
    $self->{_messageID}      = $5;
    $self->{_messageData}    = $6;
  }

  else {
    return undef;
  }
}

sub getSenderID
{
  my ($self) = @_;
  return $self->{_senderID};
}

sub getPacketCounter
{
  my ($self) = @_;
  return $self->{_packetCounter};
}

sub getMessageTypeName
{
  my ($self) = @_;
  return $messageTypeID2messageTypeName{$self->{_messageTypeID}};
}

sub getMessageGroupName
{
  my ($self) = @_;
  return $messageGroupID2messageGroupName{$self->{_messageGroupID}};
}

sub getMessageName
{
  my ($self) = @_;
  return $messageID2messageName{$self->{_messageGroupID} . "-" . $self->{_messageID}};
}

sub getMessageData
{
  my ($self) = @_;

  if ($sendMode) {
    my $res = "";

    foreach (@msgData) {
      $res .= sprintf("%02X", $_);
    }

    return $res;
  } else {
    return $self->{_messageData};
  }
}

sub getField
{
  my ($self, $fieldName, $index) = @_;

  my $obj = $dataFields{$self->{_messageGroupID} . "-" . $self->{_messageID} . "-" . $fieldName};
  my @tmpArray = map hex("0x$_"), $self->{_messageData} =~ /(..)/g;

  return $obj->getValue(\@tmpArray, $index);
}

sub initPacket
{
  my ($self, $messageGroupName, $messageName, $messageTypeName) = @_;

  $self->{_senderID}       = 0;                                                                # base station SenderID
  $self->{_messageTypeID}  = $messageTypeName2messageTypeID{$messageTypeName};
  $self->{_messageGroupID} = $messageGroupName2messageGroupID{$messageGroupName};
  $self->{_messageID}      = $messageName2messageID{$messageGroupName . "-" . $messageName};

  my $lenBytes = $messageID2bits{$self->{_messageGroupID} . "-" . $self->{_messageID}} / 8;

  @msgData = 0 x $lenBytes;

  $sendMode = 1;
}

sub setField
{
  my ($self, $messageGroupName, $messageName, $fieldName, $value) = @_;

  my $gID = $messageGroupName2messageGroupID{$messageGroupName};
  my $mID = $messageName2messageID{$messageGroupName . "-" . $messageName};

  my $obj = $dataFields{$gID . "-" . $mID . "-" . $fieldName};

  $obj->setValue(\@msgData, $value);
}

# sKK01RRRRGGMMDD
# s0001003D3C0164 = SET    Dimmer Switch Brightness 50%
sub getSendString
{
  my ($self, $receiverID, $aesKeyNr) = @_;

  # Right now the only way to set the AES key is by defining in in fhem.cfg
  # "define SHC_Dev_xx SHC_Dev xx aa" where xx = deviceID, aa = AES key
  #
  # TODO: Where to enter the AES key number? This is by device.
  # Add lookup table device -> AES key?
  # Automatically gather used AES key after reception from device?

  my $s = "s"
    . sprintf("%02X", $aesKeyNr)
    . sprintf("%02X", $self->{_messageTypeID})
    . sprintf("%04X", $receiverID)
    . sprintf("%02X", $self->{_messageGroupID})
    . sprintf("%02X", $self->{_messageID})
    . getMessageData();
}

1;
