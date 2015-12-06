##############################################
# $Id$
package main;

# Known controller function. 
# Note: Known != implemented, see %sets & %gets for the implemented ones.
use vars qw(%zw_func_id);
use vars qw(%zw_type6);

%zw_func_id= (
  '02'  => 'SERIAL_API_GET_INIT_DATA',
  '03'  => 'SERIAL_API_APPL_NODE_INFORMATION',
  '04'  => 'APPLICATION_COMMAND_HANDLER',
  '05'  => 'ZW_GET_CONTROLLER_CAPABILITIES',
  '06'  => 'SERIAL_API_SET_TIMEOUTS',
  '07'  => 'SERIAL_API_GET_CAPABILITIES',
  '08'  => 'SERIAL_API_SOFT_RESET',
  '10'  => 'ZW_SET_R_F_RECEIVE_MODE',
  '11'  => 'ZW_SET_SLEEP_MODE',
  '12'  => 'ZW_SEND_NODE_INFORMATION',
  '13'  => 'ZW_SEND_DATA',
  '14'  => 'ZW_SEND_DATA_MULTI',
  '15'  => 'ZW_GET_VERSION',
  '16'  => 'ZW_SEND_DATA_ABORT',
  '17'  => 'ZW_R_F_POWER_LEVEL_SET',
  '18'  => 'ZW_SEND_DATA_META',
  '1c'  => 'ZW_GET_RANDOM',
  '20'  => 'MEMORY_GET_ID',
  '21'  => 'MEMORY_GET_BYTE',
  '22'  => 'MEMORY_PUT_BYTE',
  '23'  => 'MEMORY_GET_BUFFER',
  '24'  => 'MEMORY_PUT_BUFFER',
  '27'  => 'FLASH_AUTO_PROG_SET',
  '29'  => 'NVM_GET_ID',
  '2a'  => 'NVM_EXT_READ_LONG_BUFFER',
  '2b'  => 'NVM_EXT_WRITE_LONG_BUFFER',
  '2c'  => 'NVM_EXT_READ_LONG_BYTE',
  '2d'  => 'NVM_EXT_WRITE_LONG_BYTE',
  '30'  => 'CLOCK_SET',
  '31'  => 'CLOCK_GET',
  '32'  => 'CLOCK_COMPARE',
  '33'  => 'RTC_TIMER_CREATE',
  '34'  => 'RTC_TIMER_READ',
  '35'  => 'RTC_TIMER_DELETE',
  '36'  => 'RTC_TIMER_CALL',
  '40'  => 'ZW_SET_LEARN_NODE_STATE',
  '41'  => 'ZW_GET_NODE_PROTOCOL_INFO',
  '42'  => 'ZW_SET_DEFAULT',
  '43'  => 'ZW_NEW_CONTROLLER',
  '44'  => 'ZW_REPLICATION_COMMAND_COMPLETE',
  '45'  => 'ZW_REPLICATION_SEND_DATA',
  '46'  => 'ZW_ASSIGN_RETURN_ROUTE',
  '47'  => 'ZW_DELETE_RETURN_ROUTE',
  '48'  => 'ZW_REQUEST_NODE_NEIGHBOR_UPDATE',
  '49'  => 'ZW_APPLICATION_UPDATE',
  '4a'  => 'ZW_ADD_NODE_TO_NETWORK',
  '4b'  => 'ZW_REMOVE_NODE_FROM_NETWORK',
  '4c'  => 'ZW_CREATE_NEW_PRIMARY',
  '4d'  => 'ZW_CONTROLLER_CHANGE',
  '50'  => 'ZW_SET_LEARN_MODE',
  '51'  => 'ZW_ASSIGN_SUC_RETURN_ROUTE',
  '52'  => 'ZW_ENABLE_SUC',
  '53'  => 'ZW_REQUEST_NETWORK_UPDATE',
  '54'  => 'ZW_SET_SUC_NODE_ID',
  '55'  => 'ZW_DELETE_SUC_RETURN_ROUTE',
  '56'  => 'ZW_GET_SUC_NODE_ID',
  '57'  => 'ZW_SEND_SUC_ID',
  '59'  => 'ZW_REDISCOVERY_NEEDED',
  '5e'  => 'ZW_EXPLORE_REQUEST_INCLUSION',
  '60'  => 'ZW_REQUEST_NODE_INFO',
  '61'  => 'ZW_REMOVE_FAILED_NODE_ID',
  '62'  => 'ZW_IS_FAILED_NODE',
  '63'  => 'ZW_REPLACE_FAILED_NODE',
  '70'  => 'TIMER_START',
  '71'  => 'TIMER_RESTART',
  '72'  => 'TIMER_CANCEL',
  '73'  => 'TIMER_CALL',
  '80'  => 'GET_ROUTING_TABLE_LINE',
  '81'  => 'GET_T_X_COUNTER',
  '82'  => 'RESET_T_X_COUNTER',
  '83'  => 'STORE_NODE_INFO',
  '84'  => 'STORE_HOME_ID',
  '90'  => 'LOCK_ROUTE_RESPONSE',
  '91'  => 'ZW_SEND_DATA_ROUTE_DEMO',
  '95'  => 'SERIAL_API_TEST',
  'a0'  => 'SERIAL_API_SLAVE_NODE_INFO',
  'a1'  => 'APPLICATION_SLAVE_COMMAND_HANDLER',
  'a2'  => 'ZW_SEND_SLAVE_NODE_INFO',
  'a3'  => 'ZW_SEND_SLAVE_DATA',
  'a4'  => 'ZW_SET_SLAVE_LEARN_MODE',
  'a5'  => 'ZW_GET_VIRTUAL_NODES',
  'a6'  => 'ZW_IS_VIRTUAL_NODE',
  'b6'  => 'ZW_WATCHDOG_ENABLE',
  'b7'  => 'ZW_WATCHDOG_DISABLE',
  'b8'  => 'ZW_WATCHDOG_CHECK',
  'b9'  => 'ZW_SET_EXT_INT_LEVEL',
  'ba'  => 'ZW_RF_POWERLEVEL_GET',
  'bb'  => 'ZW_GET_NEIGHBOR_COUNT',
  'bc'  => 'ZW_ARE_NODES_NEIGHBOURS',
  'bd'  => 'ZW_TYPE_LIBRARY',
  'be'  => 'ZW_SEND_TEST_FRAME',
  'bf'  => 'ZW_GET_PROTOCOL_STATUS',
  'd0'  => 'ZW_SET_PROMISCUOUS_MODE',
  'd2'  => 'WATCHDOG_START',
  'd3'  => 'WATCHDOG_STOP',
  'f2'  => 'ZME_FREQ_CHANGE',
  'f4'  => 'ZME_BOOTLOADER_FLASH',
);

%zw_type6 = (
  '01' => 'GENERIC_CONTROLLER',    '12' => 'SWITCH_REMOTE',
  '02' => 'STATIC_CONTROLLER',     '13' => 'SWITCH_TOGGLE',
  '03' => 'AV_CONTROL_POINT',      '20' => 'SENSOR_BINARY',
  '06' => 'DISPLAY',               '21' => 'SENSOR_MULTILEVEL',
  '07' => 'GARAGE_DOOR',           '22' => 'WATER_CONTROL',
  '08' => 'THERMOSTAT',            '30' => 'METER_PULSE',
  '09' => 'WINDOW_COVERING',       '40' => 'ENTRY_CONTROL',
  '0F' => 'REPEATER_SLAVE',        '50' => 'SEMI_INTEROPERABLE',
  '10' => 'SWITCH_BINARY',         'ff' => 'NON_INTEROPERABLE',
  '11' => 'SWITCH_MULTILEVEL',
);

sub
zwlib_parseNeighborList($$)
{
  my ($iodev, $data) = @_;
  my $homeId = $iodev->{homeId};
  my $ioName = $iodev->{NAME};
  my @r = map { ord($_) } split("", pack('H*', $data));
  return "Bogus neightborList $data" if(int(@r) != 29);

  my @list;
  my $ioId = ReadingsVal($ioName, "homeId", "");
  $ioId = $1 if($ioId =~ m/CtrlNodeId:(..)/);
  for my $byte (0..28) {
    my $bits = $r[$byte];
    for my $bit (0..7) {
      if($bits & (1<<$bit)) {
        my $dec = $byte*8+$bit+1;
        my $hex = sprintf("%02x", $dec);
        my $h = $modules{ZWave}{defptr}{"$homeId $hex"};
        push @list, ($hex eq $ioId ? $ioName :
                    ($h ? $h->{NAME} : "UNKNOWN_$dec"));
      }
    }
  }
  return @list ? join(" ", @list) : "empty";
}

#####################################
sub
zwlib_checkSum($)
{
  my ($data) = @_;
  my $cs = 0xff;
  map { $cs ^= ord($_) } split("", pack('H*', $data));
  return sprintf("%02x", $cs);
}


1;
