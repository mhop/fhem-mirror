# More complex test, with external program and delayed log/event checking
# Note: exit(0) must be called in the delayed code.
use strict;
use warnings;
use Test::More;

my $usage = `mosquitto_pub 2>&1`;
if(!$usage) { # mosquitto not installed
  ok(1);
  done_testing;
  exit(0);
}

fhem('"mosquitto_pub -i test -t hallo -m world"');
InternalTimer(time()+1, sub() {
  is(FhemTestUtils_gotLog(
        "autocreate: define MQTT2_test MQTT2_DEVICE test m2s"), 1,
        "autocreate log");
  is(FhemTestUtils_gotEvent("MQTT2_test:hallo: world"), 1,
        "autocreate event");
  done_testing;
  exit(0);
}, 0);

1;
