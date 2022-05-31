##############################################
# test parsing
##############################################

use strict;
use warnings;
use Test::More;

fhem ("set PHC importChannelList $attr{global}{modpath}/t/FHEM/98_PHC/Kanalliste1.xml");
is(FhemTestUtils_gotLog("Attr called with set PHC module009description EG 230 1"), 1, "description attr from module");
is(FhemTestUtils_gotLog("Attr called with set PHC channelEMD09i00description BWM Wand Arbeiten zum Garten hin"), 1, "description attr from input");
is(FhemTestUtils_gotLog("Attr called with set PHC channelJRM13o06description Zeitmessung Dimmer nach Leinwand"), 1, "description attr from timer");
is(FhemTestUtils_gotLog("Attr called with set PHC channelMFM24o01description Funkausgang - 01"), 1, "description attr from output");

fhem ("set PHC importChannelList $attr{global}{modpath}/t/FHEM/98_PHC/Kanalliste2.xml");
is(FhemTestUtils_gotLog("Attr called with set PHC channelEMD00i01description Wälzpumpe Warmwasser"), 1, "description attr from input");
is(FhemTestUtils_gotLog("Attr called with set PHC module001description Eingangsmodul 24V -01"), 1, "description attr from module");
is(FhemTestUtils_gotLog("Attr called with set PHC channelEMD00o00description LED Ausgang"), 1, "description attr from EMD output");

done_testing;
exit(0);

1;
