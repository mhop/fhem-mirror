#########################################################################################
# $Id$
#
# The file is part of the SIGNALduino project.
# The purpose of this module is universal support for devices.
# 2016 - 1.fhemtester | 2018 - HomeAuto_User & elektron-bbs
#
# - unitec Modul alte Variante bis 20180901 (Typ unitec-Sound) --> keine MU MSG!
# - unitec Funkfernschalterset (Typ uniTEC_48110) ??? EIM-826 Funksteckdosen --> keine MU MSG!
###############################################################################################################################################################################
# - unitec remote door reed switch 47031 (Typ Unitec_47031) [Protocol 30] and [additionally Protocol 83] (sync -30)  (1 = on | 0 = off)
#{    FORUM: https://forum.fhem.de/index.php/topic,43346.msg353144.html#msg353144
#     8 DIP-switches for deviceCode (1-8) | 3 DIP-switches for zone (9-11) | 1 DIP-switch unknown (12) | baugleich FRIEDLAND SU4F zwecks gleichem Platinenlayout + Jumper
#     Kopplung an Unitec 47121 (Zone 1-6) | Unitec 47125 (Zone 1-2) | Friedland (Zone 1)
#     Adresse: 95 - öffnen?               |  get sduino_dummy raw MU;;P0=309;;P1=636;;P2=-690;;P3=-363;;P4=-10027;;D=012031203120402031312031203120312031204020313120312031203120312040203131203120312031203120402031312031203120312031204020313120312031203120312040203131203120312031203120402031312031203120312031204020313120312031203120312040203131203120312030;;CP=0;;O;;
#}    Adresse: 00 - Gehäuse geöffnet?     |  get sduino_dummy raw MU;;P0=684;;P1=-304;;P2=-644;;P3=369;;P4=-9931;;D=010101010101010232323104310101010101010102323231043101010101010101023232310431010101010101010232323104310101010101010102323231043101010101010101023232310431010101010101010232323104310101010101010102323231043101010101010101023232310431010100;;CP=0;;O;;
###############################################################################################################################################################################
# - Westinghouse Deckenventilator (Typ HT12E | remote with 5 buttons without SET | Buttons_five ??? 7787100 ???) [Protocol 29] and [additionally Protocol 30] (sync -35) (1 = off | 0 = on)
#{    FORUM: https://forum.fhem.de/index.php/topic,58397.960.html | https://forum.fhem.de/index.php/topic,53282.30.html
#     Adresse e | 1110 (off|off|off|on): fan_off         |  get sduino_dummy raw MU;;P0=250;;P1=-492;;P2=166;;P3=-255;;P4=491;;P5=-8588;;D=052121212121234121212121234521212121212341212121212345212121212123412121212123452121212121234121212121234;;CP=0;;
#}    Adresse e | 1110 (off|off|off|on): fan low speed   |  get sduino_dummy raw MU;;P0=-32001;;P1=224;;P2=-255;;P3=478;;P4=-508;;P6=152;;P7=-8598;;D=01234141414641414141414123712341414141414141414141237123414141414141414141412371234141414141414141414123712341414141414141414141237123414141414141414141412371234141414141414141414123712341414141414141414141237123414141414141414141412371234141414141414141;;CP=1;;R=108;;O;;
####################################################################################################################################
# - Westinghouse Deckenventilator (Typ [M1EN compatible HT12E] example Delancey | remote RH787T with 9 buttons + SET) [Protocol 83] and [additionally Protocol 30] (sync -36) (1 = off | 0 = on)
#{    Adresse 0 | 0000 (on|on|on|on): I - fan minimum speed  |  get sduino_dummy raw MU;;P0=388;;P1=-112;;P2=267;;P3=-378;;P5=585;;P6=-693;;P7=-11234;;D=0123035353535356262623562626272353535353562626235626262723535353535626262356262627235353535356262623562626272353535353562626235626262723535353535626262356262627235353535356262623562626272353535353562626235626262723535353535626262356262627235353535356262;;CP=2;;R=43;;O;;
#     Adresse 8 | 1000 (off|on|on|on): I - fan minimum speed |  get sduino_dummy raw MU;;P0=-11250;;P1=-200;;P2=263;;P3=-116;;P4=-374;;P5=578;;P6=-697;;D=1232456245454562626245626262024562454545626262456262620245624545456262624562626202456245454562626245626262024562454545626262456262620245624545456262624562626202456245454562626245626262024562454545626262456262620245624545456262624562626202456245454562626;;CP=2;;R=49;;O;;
#     Adresse c | 1100 (off|off|on|on): fan_off              |  get sduino_dummy raw MU;;P0=-720;;P1=235;;P2=-386;;P3=561;;P4=-11254;;D=01230141230101232301010101012301412301012323010101010123014123010123230101010101010141230101232301010101010101412301012323010101010101014123010123230101010101010;;CP=1;;R=242;;
#}    Adresse c | 1100 (off|off|on|on): fan_off              |  get sduino_dummy raw MU;;P0=-11230;;P1=258;;P2=-390;;P3=571;;P4=-699;;D=0123414123234141414141234101234141232341414141412341012341412323414141414123410123414123234141414141234101234141232341414141412341012341412323414141414123410123414123234141414141234101234141232341414141412341012341412323414141414123410123414123234141414;;CP=1;;R=246;;O;;
###############################################################################################################################################################################
# - Remote control SA-434-1 mini 923301 [Protocol 81] and [additionally Protocol 83 + Protocol 86]
#{    one Button, 434 MHz
#     protocol like HT12E
#     10 DIP-switches for address:
#     switch                                hex     bin
#     ------------------------------------------------------------
#     1-10 on                               004     0000 0000 0100
#     1 off, 9-10 on                        804     1000 0000 0100
#     4/8 off, 9-3 5-7 9-10 on              114     0001 0001 0100
#     4/8 off, 9-3 5-7 on, 9 off, 10 on     115     0001 0001 0101
#     4/8 off, 9-3 5-7 on, 9 on, 10 off     11C     0001 0001 1100
#     4/8 off, 9-3 5-7 on, 9-10 off         11D     0001 0001 1101
#     ------------------------------------------------------------
#     pilot 12 bitlength, from that 1/3 bitlength high: -175000, 500   -35, 1
#     one:                                                -1000, 500    -2, 1
#     zero:                                                -500, 1000   -1, 2
#
#     get sduino_dummy raw MU;;P0=-1756;;P1=112;;P2=-11752;;P3=496;;P4=-495;;P5=998;;P6=-988;;P7=-17183;;D=0123454545634545456345634563734545456345454563456345637345454563454545634563456373454545634545456345634563734545456345454563456345637345454563454545634563456373454545634545456345634563734545456345454563456345637345454563454545634563456373454545634545456;;CP=3;;R=0;;
#}    get sduino_dummy raw MU;;P0=-485;;P1=188;;P2=-6784;;P3=508;;P5=1010;;P6=-974;;P7=-17172;;D=0123050505630505056305630563730505056305050563056305637305050563050505630563056373050505630505056305630563730505056305050563056305637305050563050505630563056373050505630505056305630563730505056305050563056305637305050563050505630563056373050505630505056;;CP=3;;R=0;;
###############################################################################################################################################################################
# - QUIGG GT-7000 Funk-Steckdosendimmer | transmitter QUIGG_DMV - receiver DMV-7009AS  [Protocol 34]
#{    https://github.com/RFD-FHEM/RFFHEM/issues/195
#     nibble 0-2 -> Ident | nibble 3-4 -> Tastencode
#     get sduino_dummy raw MU;;P0=-5476;;P1=592;;P2=-665;;P3=1226;;P4=-1309;;D=01232323232323232323232323412323412323414;;CP=3;;R=1;;
#}    Send Adresse FFF funktioniert nicht 100%ig!
###############################################################################################################################################################################
# - Remote Control Novy_840029 for Novy Pureline 6830 kitchen hood [Protocol 86] (Länge je nach Taste 12 oder 18 Bit)
#{    0100				"novy_button"			- nicht geprüft
#     0101				"+_button"				- i.O.
#     0110				"-_button"				- i.O.
#     0111010001	"light_on_off"		- nur 10 Bit, SIGNALduino.pm hängt 2 Nullen an
#     0111010011	"power_button"		- nur 10 Bit, SIGNALduino.pm hängt 2 Nullen an
#    https://github.com/RFD-FHEM/RFFHEM/issues/331
#			nibble 0-1 -> Ident | nibble 2-4 -> Tastencode
#     light on/off button   -	get sduino_dummy raw MU;;P0=710;;P1=353;;P2=-403;;P4=-761;;P6=-16071;;D=20204161204120412041204120414141204120202041612041204120412041204141412041202020416120412041204120412041414120412020204161204120412041204120414141204120202041;;CP=1;;R=40;;
#     + button              -	get sduino_dummy raw MU;;P0=22808;;P1=-24232;;P2=701;;P3=-765;;P4=357;;P5=-15970;;P7=-406;;D=012345472347234723472347234723454723472347234723472347234547234723472347234723472345472347234723472347234723454723472347234723472347234;;CP=4;;R=39;;
#     - button              -	get sduino_dummy raw MU;;P0=-8032;;P1=364;;P2=-398;;P3=700;;P4=-760;;P5=-15980;;D=0123412341234123412341412351234123412341234123414123512341234123412341234141235123412341234123412341412351234123412341234123414123;;CP=1;;R=40;;
#     power button          -	get sduino_dummy raw MU;;P0=-756;;P1=718;;P2=354;;P3=-395;;P4=-16056;;D=01020202310231310202423102310231023102310202023102313102024231023102310231023102020231023131020242310231023102310231020202310231310202;;CP=2;;R=41;;
#}    novy button           - get sduino_dummy raw MU;;P0=706;;P1=-763;;P2=370;;P3=-405;;P4=-15980;;D=0123012301230304230123012301230123012303042;;CP=2;;R=42;;
###############################################################################################################################################################################
# - CAME Drehtor Antrieb - remote CAME_TOP_432EV [Protocol 86] and [additionally Protocol 81]
#{    https://github.com/RFD-FHEM/RFFHEM/issues/151
#     nibble 0-1 -> Ident | nibble 2 -> Tastencode
#}    get sduino_dummy raw MU;;P0=-322;;P1=136;;P2=-15241;;P3=288;;P4=-735;;P6=723;;D=0123434343064343430643434306234343430643434306434343062343434306434343064343430623434343064343430643434306234343430643434306434343062343434306434343064343430623434343064343430643434306234343430643434306434343062343434306434343064343430;;CP=3;;R=27;;
###############################################################################################################################################################################
# - Hoermann HS1-868-BS [Protocol 69]
#{    https://github.com/RFD-FHEM/RFFHEM/issues/344 | https://github.com/RFD-FHEM/RFFHEM/issues/149
#                iiii iiii iiii iiii iiii iiii iiii bbbb
#			0000 0000 1111 0110 0010 1010 1001 1100 0000 0001 1100 (HS1-868-BS)
#}    get sduino_dummy raw MU;;P0=-578;;P1=1033;;P2=506;;P3=-1110;;P4=13632;;D=0101010232323101040101010101010101023232323102323101010231023102310231010232323101010101010101010232323101040101010101010101023232323102323101010231023102310231010232323101010101010101010232323101040101010101010101023232323102323101010231023102310231010;;CP=2;;R=77;;
###############################################################################################################################################################################
# - Hoermann HSM4 [Protocol 69]
#{    https://forum.fhem.de/index.php/topic,71877.msg642879.html (HSM4, Taste 1-4)
#               iiii iiii iiii iiii iiii iiii iiii bbbb
#     0000 0000 1110 0110 1011 1110 1001 0001 0000 0111 1100 (HSM4 Taste A)
#     0000 0000 1110 0110 1011 1110 1001 0001 0000 1011 1100 (HSM4 Taste B)
#     0000 0000 1110 0110 1011 1110 1001 0001 0000 1110 1100 (HSM4 Taste C)
#     0000 0000 1110 0110 1011 1110 1001 0001 0000 1101 1100 (HSM4 Taste D)
#}    get sduino_dummy raw MU;;P0=-3656;;P1=12248;;P2=-519;;P3=1008;;P4=506;;P5=-1033;;D=01232323232323232324545453232454532453245454545453245323245323232453232323245453245454532321232323232323232324545453232454532453245454545453245323245323232453232323245453245454532321232323232323232324545453232454532453245454545453245323245323232453232323;;CP=4;;R=48;;O;;
###############################################################################################################################################################################
# - Transmitter SF01 01319004 433,92 MHz (SF01_01319004) (NEFF kitchen hood) [Protocol 86]
#{    https://github.com/RFD-FHEM/RFFHEM/issues/376 | https://forum.fhem.de/index.php?topic=93545.0
#     Sends 18 bits, converting to hex in SIGNALduino.pm adds 2 bits of 0
#                   iiii iiii iiii ii bbbb aa   hex
#     ------------------------------------------------
#     Plus:         1010 0001 0101 00 1100 00   A15 30
#     Minus:        1010 0001 0101 00 1010 00   A15 28
#     Licht:        1010 0001 0101 00 1110 00   A15 38
#     Nachlüften:   1010 0001 0101 00 1001 00   A15 24
#     Intervall:    1010 0001 0101 00 1101 00   A15 34
#     ------------------------------------------------
#     i - ident, b - button, a - appended
#     get sduino_dummy raw MU;;P0=-707;;P1=332;;P2=-376;;P3=670;;P5=-15243;;D=01012301232323230123012301232301010123510123012323232301230123012323010101235101230123232323012301230123230101012351012301232323230123012301232301010123510123012323232301230123012323010101235101230123232323012301230123230101012351012301232323230123012301;;CP=1;;R=3;;O;;
#     get sduino_dummy raw MU;;P0=-32001;;P1=348;;P2=-704;;P3=-374;;P4=664;;P5=-15255;;D=01213421343434342134213421343421213434512134213434343421342134213434212134345121342134343434213421342134342121343451213421343434342134213421343421213434512134213434343421342134213434212134345121342134343434213421342134342121343451213421343434342134213421;;CP=1;;R=15;;O;;
#     get sduino_dummy raw MU;;P0=-32001;;P1=326;;P2=-721;;P3=-385;;P4=656;;P5=-15267;;D=01213421343434342134213421343421342134512134213434343421342134213434213421345121342134343434213421342134342134213451213421343434342134213421343421342134512134213434343421342134213434213421345121342134343434213421342134342134213451213421343434342134213421;;CP=1;;R=10;;O;;
#     get sduino_dummy raw MU;;P0=-372;;P1=330;;P2=684;;P3=-699;;P4=-14178;;D=010231020202023102310231020231310231413102310202020231023102310202313102314;;CP=1;;R=253;;
#}    get sduino_dummy raw MU;;P0=-710;;P1=329;;P2=-388;;P3=661;;P4=-14766;;D=01232301410123012323232301230123012323012323014;;CP=1;;R=1;;
###
# - Transmitter SF01 01319004 (SF01_01319004_Typ2) 433,92 MHz (BOSCH kitchen) [Protocol 86]
#{                  iiii iiii iiii ii bbbb aa   hex
#     ------------------------------------------------
#     Plus:         0010 0110 0011 10 0100 00		263 90 
#     Minus:        0010 0110 0011 10 0010 00		263 88 
#     Licht:        0010 0110 0011 10 0110 00		263 98 
#     Nachlüften:   0010 0110 0011 10 0001 00		263 84 
#     Intervall:    0010 0110 0011 10 0101 00		263 94 
#     ------------------------------------------------
#     i - ident, b - button, a - appended
#     get sduino_dummy raw MU;;P0=706;;P1=-160;;P2=140;;P3=-335;;P4=-664;;P5=385;;P6=-15226;;P7=248;;D=01210103045303045453030304545453030454530653030453030454530303045454530304747306530304530304545303030454545303045453065303045303045453030304545453030454530653030453030454530303045454530304545306530304530304545303030454545303045453065303045303045453030304;;CP=5;;O;;
#     get sduino_dummy raw MU;;P0=-15222;;P1=379;;P2=-329;;P3=712;;P6=-661;;D=30123236123236161232323616161232361232301232361232361612323236161612323612323012323612323616123232361616123236123230123236123236161232323616161232361232301232361232361612323236161612323612323012323612323616123232361616123236123230123236123236161232323616;;CP=1;;O;;
#     get sduino_dummy raw MU;;P0=705;;P1=-140;;P2=-336;;P3=-667;;P4=377;;P5=-15230;;P6=248;;D=01020342020343420202034343420202020345420203420203434202020343434202020203654202034202034342020203434342020202034542020342020343420202034343420202020345420203420203434202020343434202020203454202034202034342020203434342020202034542020342020343420202034343;;CP=4;;O;;
#     get sduino_dummy raw MU;;P0=704;;P1=-338;;P2=-670;;P3=378;;P4=-15227;;P5=244;;D=01023231010102323231010102310431010231010232310101023232310101025104310102310102323101010232323101010231043101023101023231010102323231010102310431010231010232310101023232310101023104310102310102323101010232323101010231043101023101023231010102323231010102;;CP=3;;O;;
#}    get sduino_dummy raw MU;;P0=-334;;P1=709;;P2=-152;;P3=-663;;P4=379;;P5=-15226;;P6=250;;D=01210134010134340101013434340101340134540101340101343401010134343401013601365401013401013434010101343434010134013454010134010134340101013434340101340134540101340101343401010134343401013401345401013401013434010101343434010134013454010134010134340101013434;;CP=4;;O;;
###############################################################################################################################################################################
# - Berner Garagentorantrieb GA401 | remote TEDSEN SKX1MD 433.92 MHz - 1 button | settings via 9 switch on battery compartment [Protocol 46]
#{    compatible with doors: BERNER SKX1MD, ELKA SKX1MD, TEDSEN SKX1LC, TEDSEN SKX1
#     https://github.com/RFD-FHEM/RFFHEM/issues/91
#}    get sduino_dummy raw MU;;P0=-15829;;P1=-3580;;P2=1962;;P3=-330;;P4=245;;P5=-2051;;D=1234523232345234523232323234523234540023452323234523452323232323452323454023452323234523452323232323452323454023452323234523452323232323452323454023452323234523452323232323452323454023452323234523452323;;CP=2;;
###############################################################################################################################################################################
# - Chilitec Großhandel 22640 - LED Christbaumkerzen mit Fernbedienung
#{ 		Taste -: 		AA802			0010		brightness_minus
# 		Taste Aus: 	AA804			0100		power_off
# 		Taste FL: 	AA806			0110		flickering_fast
# 		Taste Ein: 	AA808			1000		power_on
# 		Taste SL: 	AA80A			1010		flickering_slowly
# 		Taste +: 		AA80C			1100		brightness_plus
#
#}    get sduino_dummy raw MS;;P0=988;;P1=-384;;P2=346;;P3=-1026;;P4=-4923;;D=240123012301230123012323232323232301232323;;CP=2;;SP=4;;R=0;;O;;m=1;;
###############################################################################################################################################################################
# - XM21-0 - LED Christbaumkerzen mit Fernbedienung [Protocol 76]
#{ 		button - ON
# 		MU;P0=-205;P1=113;P3=406;D=010101010101010101010101010101010101010101010101010101010101030303030101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010103030303010101010101010101010100;CP=1;R=69;
# 		MU;P0=-198;P1=115;P4=424;D=0101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010404040401010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101040404040;CP=1;R=60;O;
# 		MU;P0=114;P1=-197;P2=419;D=01212121210101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010121212121010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010
# 		button - OFF
# 		MU;P0=-189;P1=115;P4=422;D=0101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101040404040101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010104040404010101010;CP=1;R=73;O;
# 		MU;P0=-203;P1=412;P2=114;D=01010101020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020101010102020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020200;CP=2;R=74;
# 		MU;P0=-210;P1=106;P3=413;D=0101010101010101010303030301010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101030303030100;CP=1;R=80;
#
# 		    iiiiiiiiiiiiii bb
# 		---------------------
# 		P76#FFFFFFFFFFFFFF FF		- on
#} 		P76#FFFFFFFFFFFFFF C		- off
###############################################################################################################################################################################
# - Krinner LUMIX - LED X-MAS model 572152 [Protocol 92]
#{ 		button - ON
# 		MU;P0=-592;P1=112;P2=-968;P3=413;P4=995;P5=-394;P6=-10161;D=01232323245453245453232323232323232454645324532323232323245453245453232323245453245453232323232323232454645324532323232323245453245453232323245453245453232323232323232454645324532323232323245453245453232323245453245453232323232323232454;CP=3;R=25;
#			MU;P0=24188;P1=-16308;P2=993;P3=-402;P4=416;P5=-967;P6=-10162;D=0123234545454523234523234545454545454545232623452345454545454523234523234545454523234523234545454545454545232623452345454545454523234523234545454523234523234545454545454545232623452345454545454523234523234545454523234523234545454545454545232;CP=4;R=25;
# 		button - OFF
# 		MU;P0=417;P1=-558;P2=975;P3=272;P4=-974;P5=140;P6=-419;P7=-10150;D=01213454040426260426260404040404040404042726042604040404040426260426260404040426260426260404040404040404042726042604040404040426260426260404040426260426260404040404040404042726042604040404040426260426260404040426260426260404040404040404042;CP=0;R=37;
#			MU;P0=11076;P1=-20524;P2=281;P3=-980;P4=982;P5=-411;P6=408;P7=-10156;D=0123232345456345456363636363636363634745634563636363636345456345456363636345456345456363636363636363634745634563636363636345456345456363636345456345456363636363636363634745634563636363636345456345456363636345456345456363636363636363634;CP=6;R=38;
#
# 		    iiiiiii b
# 		----------- -
# 		P92#A06C360 1
#} 		P92#A06C360 0
###############################################################################################################################################################################
# - Atlantic Security / Focus Security China Devices | door/windows switch MD-210R | Vibration Schock Sensor MD-2018R | GasSensor MD-2003R [Protocol 91] & [Protocol 91.1]
#		https://forum.fhem.de/index.php/topic,95346.0.html | https://forum.fhem.de/index.php?topic=95346.msg881810#msg881810 | https://github.com/RFD-FHEM/RFFHEM/issues/477
#		36bit = 24bit DeviceID + 8bit Commando (4 Bit -> Sabo,Contact,Contact extern,keepalive or batterie | 4 bit -> typ) + 4bit Check | all nibbles are XOR = 0
#		i ident | s sabo | c contact intern | e contact extern | k keepalive (battery?) | t typ | C ckecksumme
#
#{	door/windows switch MD_210R
#
#		iiiiiiiiiiiiiiiiiiiiiiiiscekttttCCCC
#		------------------------------------
#		Kontakt auf | Gehäuse auf		get sduino_dummy raw MS;;P1=-410;;P2=807;;P3=-803;;P4=394;;P5=-3994;;D=45412123434123412123434341234123434121234123412121234341234343434123412343;;CP=4;;SP=5;;R=30;;O;;m2;;
#		Kontakt zu | Gehäuse auf		get sduino_dummy raw MS;;P0=-397;;P1=816;;P2=-804;;P3=407;;P4=-4007;;D=34301012323012301012323230123012323010123012301010123010123232323012323232;;CP=3;;SP=4;;R=71;;O;;m2;;
#		Kontakt auf | Gehäuse zu		get sduino_dummy raw MS;;P1=-404;;P2=813;;P3=-794;;P4=409;;P5=-4002;;D=45412123434123412123434341234123434121234123412121212341234343434121212343;;CP=4;;SP=5;;R=65;;m0;;
#		Kontakt zu | Gehäuse zu			get sduino_dummy raw MS;;P0=-800;;P1=402;;P2=-401;;P3=806;;P4=-3983;;D=14123230101230123230101012301230101232301230123232323232301010101232301010;;CP=1;;SP=4;;R=57;;O;;m2;;
#}
#{	Vibration Schock Sensor MD-2018R
#
#		iiiiiiiiiiiiiiiiiiiiiiiisc?kttttCCCC
#		------------------------------------
#		get sduino_dummy raw MS;;P0=-404;;P1=383;;P2=-797;;P3=778;;P4=-3934;;D=14103030321032121032103030303030321210321032103210303030321032103032103212;;CP=1;;SP=4;;R=0;;
#		get sduino_dummy raw MU;;P0=776;;P1=-409;;P2=-802;;P3=379;;P4=-3946;;D=010102310102323231043101010231023231023101010101010232310231023102310102310101023101023232310431010102310232310231010101010102323102310231023101023101010231010232323100;;CP=3;;R=0;;
#}
#{	GasSensor MD-2003R
#
#		iiiiiiiiiiiiiiiiiiiiiiiisc?kttttCCCC
#		------------------------------------
#		get sduino_dummy raw MU;;P0=-164;;P1=378;;P2=-813;;P3=-429;;P4=764;;P5=-3929;;D=0121212134342121343434343421342121212121213434343421212134342134213451212121212121343421213434343434213421212121212134343434212121343421342134512121212121213434212134343434342134212121212121343434342121213434213421345121212121212134342121343434343421342;;CP=1;;R=0;;O;;
#		get sduino_dummy raw MU;;P1=-419;;P2=380;;P3=-810;;P5=767;;P6=-3912;;P7=-32001;;D=262323232323232151532321515151515321532323232323215321515153232151515153232;;CP=2;;R=0;;
#}
###############################################################################################################################################################################
# - Manax | MX-RCS270 , Typ: RCS-10 | MX-RCS250 / mumbi | m-FS300 [Protocol 90] and [additionally Protocol 93] - [ONLY receive !!!]
#{  Manax https://forum.fhem.de/index.php/topic,94327.0.html remote MANAX MX-RCS250
#
#		i ident | b button | ? unknown 
#		iiii iiii iiii iiii ???? bbbb ???? ???? ?????
#		---------------------------------------------
#		Taste A Ein: MS;P1=274;P2=-865;P3=787;P4=-349;P5=-10168;D=15123412121212343434341212341234341212121234343434341234121212123412;CP=1;SP=5;R=46;O;m2;
#		Taste A Aus: MS;P1=285;P2=-858;P3=794;P4=-341;P6=-10162;D=16123412121212343434341212341234341212121234343412341234121212121212;CP=1;SP=6;R=61;O;m2;
#		Taste B Ein: MS;P1=269;P2=-872;P3=795;P4=-338;P6=-10174;D=16123412121212343434341212341234341212121234341234341234121212341212;CP=1;SP=6;R=73;O;m2;
#		Taste B Aus: MS;P1=264;P2=-863;P3=795;P4=-348;P7=-10167;D=17123412121212343434341212341234341212121234341212341234121212343412;CP=1;SP=7;R=73;O;m2;
#		Taste C Ein: MS;P0=-851;P1=283;P2=805;P3=-343;P4=-10146;D=14102310101010232323231010231023231010101023102323231023101023231010;CP=1;SP=4;R=65;O;m2;
#		Taste C Aus: MS;P0=-337;P1=766;P3=273;P4=-862;P5=-10178;D=35341034343434101010103434103410103434343410341034103410343410101034;CP=3;SP=5;R=55;m2;
#		Taste D Ein: MS;P1=261;P2=-872;P3=794;P4=-349;P6=-10168;D=16123412121212343434341212341234341212121212343434341234123434341212;CP=1;SP=6;R=58;O;m2;
#		Taste D Aus: MS;P1=281;P2=-862;P3=790;P4=-342;P6=-10160;D=16123412121212343434341212341234341212121212343412341234123434343412;CP=1;SP=6;R=61;O;m2;
#		Taste Alles Ein: MS;P2=-841;P3=294;P4=812;P6=-325;P7=-10140;D=37324632323232464646463232463246463232323232463232463246324646324632;CP=3;SP=7;R=68;O;m2;
#		Taste Alles Aus: MS;P1=282;P2=-844;P3=816;P4=-330;P6=-10153;D=16123412121212343434341212341234341212121234121212341234121234123412;CP=1;SP=6;R=65;O;m2;
#
#		mumbi m-FS300 https://github.com/RFD-FHEM/RFFHEM/issues/60
#		...
#}
###############################################################################################################################################################################
# !!! ToDo´s !!!
#     - LED lights, counter battery-h reading
#     -
###############################################################################################################################################################################

package main;

use strict;
use warnings;
no warnings 'portable';  # Support for 64-bit ints required
#use SetExtensions;

#$| = 1;		#Puffern abschalten, Hilfreich für PEARL WARNINGS Search

### HASH for all modul models ###
my %models = (
	# keys(model) => values
	"Buttons_five" =>	{ "011111"	=> "1_fan_low_speed",
											"111111" 	=> "2_fan_medium_speed",
											"111101" 	=> "3_fan_high_speed",
											"101111" 	=> "light_on_off",
											"111110"	=> "fan_off",
											hex_lengh	=> "3",
											Protocol 	=> "P29",
											Typ				=> "remote"
										},
	"CAME_TOP_432EV" =>	{	"1110"		=> "left_button",
												"1101"		=> "right_button",
												hex_lengh	=> "3",
												Protocol	=> "P86",
												Typ				=> "remote"
											},
	"Chilitec_22640" =>	{ "0010"    => "brightness_minus",
												"0100"    => "power_off",
												"0110"    => "flickering_fast",
												"1000"    => "power_on",
												"1010"    => "flickering_slowly",
												"1100"    => "brightness_plus",
												hex_lengh	=> "5",
												Protocol  => "P14",
												Typ       => "remote"
											},
	"HS1_868_BS" =>	{ "0"				=> "send",
										hex_lengh	=> "11",
										Protocol	=> "P69",
										Typ				=> "remote"
									},
	"HSM4" =>	{ "0111"		=> "button_1",
							"1011"		=> "button_2",
							"1110"		=> "button_3",
							"1101"		=> "button_4",
							hex_lengh	=> "11",
							Protocol 	=> "P69",
							Typ				=> "remote"
						},
	"Krinner_LUMIX" =>	{	"0000"			=> "off",
												"0001"			=> "on",
												Protocol		=> "P92",
												hex_lengh		=> "8",
												Typ					=> "remote"
											},
	"Novy_840029" => 	{	"0100"        => "novy",
											"0101"        => "speed_plus",
											"0110"        => "speed_minus",
											"0111010001"  => "light_on_off",	# 0111010000
											"0111010011"  => "power_on_off",	# 0111010010
											hex_lengh			=> "3,5",
											Protocol			=> "P86",
											Typ						=> "remote"
										},
	"QUIGG_DMV" =>	{	"11101110"	=> "Ch1_on",
										"11111111"	=> "Ch1_off",
										"01101100" 	=> "Ch2_on",
										"01111101" 	=> "Ch2_off",
										"10101111" 	=> "Ch3_on",
										"10111110" 	=> "Ch3_off",
										"00101101" 	=> "Ch4_on",
										"00111100" 	=> "Ch4_off",
										"00001111" 	=> "Master_on",
										"00011110" 	=> "Master_off",
										"00010100" 	=> "Unknown_on",
										"00000101" 	=> "Unknown_off",
										hex_lengh		=> "5",
										Protocol		=> "P34",
										Typ					=> "remote"
									},
	"RH787T" =>	{	"110111"	=> "1_fan_minimum_speed",
								"110101" 	=> "2_fan_low_speed",
								"101111"	=> "3_fan_medium_low_speed",
								"100111"	=> "4_fan_medium_speed",
								"011101"	=> "5_fan_medium_high_speed",
								"011111"	=> "6_fan_high_speed",
								"111011"	=> "fan_direction",
								"111101"	=> "fan_off",
								"111110"	=> "light_on_off",
								"101101"	=> "set",
								hex_lengh	=> "3",
								Protocol	=> "P83",
								Typ				=> "remote"
							},
	"SA_434_1_mini" =>	{	"0"				=> "send",
												hex_lengh	=> "3",
												Protocol	=> "P81",
												Typ				=> "remote"
											},
	"TEDSEN_SKX1MD" =>	{	"0"				=> "send",
												hex_lengh	=> "5",
												Protocol	=> "P46",
												Typ				=> "remote"
											},
	"Unitec_47031" =>	{ Protocol	=> "P30",
											hex_lengh	=> "3",
											Typ				=> "switch"
										},
	"LED_XM21_0" =>	{	"1100"			=> "off",
										"11111111"	=> "on",
										Protocol		=> "P76",
										hex_lengh		=> "15,16",
										Typ					=> "remote"
									},
	"SF01_01319004" =>	{ "1100"		=> "plus",
												"1010"		=> "minus",
												"1101"		=> "interval",
												"1110"		=> "light_on_off",
												"1001"		=> "delay",
												hex_lengh	=> "5",
												Protocol 	=> "P86",
												Typ				=> "remote"
											},
	"SF01_01319004_Typ2" =>	{	"0100"		=> "plus",
														"0010"		=> "minus",
														"0101"		=> "interval",
														"0110"		=> "light_on_off",
														"0001"		=> "delay",
														hex_lengh	=> "5",
														Protocol 	=> "P86",
														Typ				=> "remote"
													},
	"MD_2003R" =>	{	Protocol	=> "P91", 	#P91.1
									hex_lengh	=> "9",
									Typ				=> "gas"
								},
	"MD_210R" =>	{	Protocol	=> "P91", 	#P91.1
									hex_lengh	=> "9",
									Typ				=> "switch"
								},
	"MD_2018R" =>	{	Protocol	=> "P91", 	#P91.1
									hex_lengh	=> "9",
									Typ				=> "vibration"
								},
	"Manax" =>	{	"1111" => "button_A_on",
								"1110" => "button_A_off",
								"1101" => "button_B_on",
								"1100" => "button_B_off",
								"1011" => "button_C_on",
								"1010" => "button_C_off",
								"0111" => "button_D_on",
								"0110" => "button_D_off",
								"0100" => "button_All_on",
								"1000" => "button_All_off",
								Protocol	=> "P90",
								hex_lengh	=> "9",
								Typ				=> "remote"
							},
	"unknown" =>	{	Protocol	=> "any",
									hex_lengh	=> "",
									Typ				=> "not_exist"
								}
);

#############################
sub SD_UT_Initialize($) {
	my ($hash) = @_;
	$hash->{Match}			= "^P(?:14|29|30|34|46|69|76|81|83|86|90|91|91.1|92)#.*";
	$hash->{DefFn}			= "SD_UT_Define";
	$hash->{UndefFn}		= "SD_UT_Undef";
	$hash->{ParseFn}		= "SD_UT_Parse";
	$hash->{SetFn}			= "SD_UT_Set";
	$hash->{AttrFn}			= "SD_UT_Attr";
	$hash->{AttrList}		= "repeats:1,2,3,4,5,6,7,8,9 IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 model:".join(",", sort keys %models)." $readingFnAttributes ";
	$hash->{AutoCreate} =
	{
		"MD_2003R.*"	 => {ATTR => "model:MD_2003R", FILTER => "%NAME", autocreateThreshold => "3:180", GPLOT => ""},
		"MD_210R.*"	 => {ATTR => "model:MD_210R", FILTER => "%NAME", autocreateThreshold => "3:180", GPLOT => ""},
		"MD_2018R.*"	 => {ATTR => "model:MD_2018R", FILTER => "%NAME", autocreateThreshold => "3:180", GPLOT => ""},
		"unknown_please_select_model"	=> {ATTR => "model:unknown", FILTER => "%NAME", autocreateThreshold => "5:180", GPLOT => ""},
	};
}

#############################
sub SD_UT_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	### checks all ###
	#Log3 $hash->{NAME}, 3, "SD_UT: Define arg0=$a[0] arg1=$a[1] arg2=$a[2]" if($a[0] && $a[1] && $a[2] && !$a[3]);
	#Log3 $hash->{NAME}, 3, "SD_UT: Define arg0=$a[0] arg1=$a[1] arg2=$a[2] arg3=$a[3]" if($a[0] && $a[1] && $a[2] && $a[3] && !$a[4]);
	#Log3 $hash->{NAME}, 3, "SD_UT: Define arg0=$a[0] arg1=$a[1] arg2=$a[2] arg3=$a[3] arg4=$a[4]" if($a[0] && $a[1] && $a[2] && $a[3] && $a[4]);

	# Argument					   0	 1		2		3				4
	return "wrong syntax: define <name> SD_UT <model> <HEX-Value> <optional IODEV>" if(int(@a) < 3 || int(@a) > 5);
	return "wrong <model> $a[2]\n\n(allowed modelvalues: " . join(" | ", sort keys %models).")" if $a[2] && ( !grep { $_ eq $a[2] } %models );
	### checks unknown ###
	return "wrong define: <model> $a[2] need no HEX-Value to define!" if($a[2] eq "unknown" && $a[3] && length($a[3]) >= 1);

	### checks Westinghouse_Delancey RH787T & WestinghouseButtons_five ###
	if ($a[2] eq "RH787T" || $a[2] eq "Buttons_five") {
		if (length($a[3]) > 1) {
			return "wrong HEX-Value! $a[2] have one HEX-Value";
		}
		if (not $a[3] =~ /^[0-9a-fA-F]{1}/s) {
			return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value are not (0-9 | a-f | A-F)";
		}
	}

	### [2] checks CAME_TOP_432EV & Novy_840029 & Unitec_47031 ###
	if (($a[2] eq "CAME_TOP_432EV" || $a[2] eq "Novy_840029" || $a[2] eq "Unitec_47031") && not $a[3] =~ /^[0-9a-fA-F]{2}/s) {
		return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value to short | long or not HEX (0-9 | a-f | A-F){2}";
	}
	### [3] checks SA_434_1_mini & QUIGG_DMV ###
	if (($a[2] eq "SA_434_1_mini" || $a[2] eq "QUIGG_DMV") && not $a[3] =~ /^[0-9a-fA-F]{3}/s) {
		return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value to short | long or not HEX (0-9 | a-f | A-F){3}";
	}
	### [4] checks Neff SF01_01319004 & BOSCH SF01_01319004_Typ2 & Chilitec_22640 & Manax ###
	if (($a[2] eq "SF01_01319004" || $a[2] eq "SF01_01319004_Typ2" || $a[2] eq "Chilitec_22640" || $a[2] eq "Manax") && not $a[3] =~ /^[0-9a-fA-F]{4}/s) {
		return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value to short | long or not HEX (0-9 | a-f | A-F){4}";
	}

	### [5] checks TEDSEN_SKX1MD ###
	return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value to short | long or not HEX (0-9 | a-f | A-F){5}" if ($a[2] eq "TEDSEN_SKX1MD" && not $a[3] =~ /^[0-9a-fA-F]{5}/s);
	### [6] checks MD_2003R | MD_210R | MD_2018R ###
	return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value to short | long or not HEX (0-9 | a-f | A-F){6}" if (($a[2] eq "MD_2003R" || $a[2] eq "MD_210R" || $a[2] eq "MD_2018R") && not $a[3] =~ /^[0-9a-fA-F]{6}/s);
	### [7] checks Hoermann HSM4 | Krinner_LUMIX ###
	return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value to short | long or not HEX (0-9 | a-f | A-F){7}" if (($a[2] eq "HSM4" || $a[2] eq "Krinner_LUMIX") && not $a[3] =~ /^[0-9a-fA-F]{7}/s);
	### [9] checks Hoermann HS1-868-BS ###
	return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value to short | long or not HEX (0-9 | a-f | A-F){9}" if ($a[2] eq "HS1_868_BS" && not $a[3] =~ /^[0-9a-fA-F]{9}/s);
	### [14] checks LED_XM21_0 ###
	return "wrong HEX-Value! ($a[3]) $a[2] HEX-Value to short | long or not HEX (0-9 | a-f | A-F){14}" if ($a[2] eq "LED_XM21_0" && not $a[3] =~ /^[0-9a-fA-F]{14}/s);

	$hash->{lastMSG} =  "no data";
	$hash->{bitMSG} =  "no data";
	$hash->{STATE} =  "Defined";
	my $iodevice = $a[4] if($a[4]);
	my $name = $hash->{NAME};

	$modules{SD_UT}{defptr}{$hash->{DEF}} = $hash;
	my $ioname = $modules{SD_UT}{defptr}{ioname} if (exists $modules{SD_UT}{defptr}{ioname} && not $iodevice);
	$iodevice = $ioname if not $iodevice;

	### Attributes | model set after codesyntax ###
	my $devicetyp = $a[2];
	if ($devicetyp eq "unknown") {
		$attr{$name}{model}	= "unknown"	if( not defined( $attr{$name}{model} ) );
	} else {
		$attr{$name}{model}	= $devicetyp	if( not defined( $attr{$name}{model} ) );
	}
	$attr{$name}{room}	= "SD_UT"	if( not defined( $attr{$name}{room} ) );

	AssignIoPort($hash, $iodevice);
}

###################################
sub SD_UT_Set($$$@) {
	my ( $hash, $name, @a ) = @_;
	my $cmd = $a[0];
	my $ioname = $hash->{IODev}{NAME};
	my $model = AttrVal($name, "model", "unknown");
	my $ret = undef;
	my $msg = undef;
	my $msgEnd = undef;
	my $value = "";		# value from models cmd
	my $save = "";		# bits from models cmd
	my $repeats = AttrVal($name,'repeats', '5');

	Log3 $name, 4, "$ioname: SD_UT_Set attr_model=$model name=$name (before check)" if($cmd ne "?");
	return $ret if ($defs{$name}->{DEF} eq "unknown");		# no setlist

	############ Westinghouse_Delancey RH787T ############
	if ($model eq "RH787T" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%04b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 4 digits
		$msg = $models{$model}{Protocol} . "#0" . $adr ."1";
		$msgEnd = "#R" . $repeats;
	############ Westinghouse Buttons_five ############
	} elsif ($model eq "Buttons_five" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%04b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 4 digits
		$msg = $models{$model}{Protocol} . "#";
		$msgEnd .= "11".$adr."#R" . $repeats;
	############ SA_434_1_mini ############
	} elsif ($model eq "SA_434_1_mini" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																		# split adress from def
		my $bitData = sprintf( "%012b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 12 digits
		$msg = $models{$model}{Protocol} . "#" . $bitData . "#R" . $repeats;
	############ TEDSEN_SKX1MD ############
	} elsif ($model eq "TEDSEN_SKX1MD" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																		# split adress from def
		my $bitData = sprintf( "%020b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 20 digits
		$msg = $models{$model}{Protocol} . "#" . $bitData . "#R" . $repeats;
	############ QUIGG_DMV ############
	} elsif ($model eq "QUIGG_DMV" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%012b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 12 digits
		$msg = $models{$model}{Protocol} . "#" . $adr;
		$msgEnd = "P#R" . $repeats;
	############ Novy_840029 ############
	} elsif ($model eq "Novy_840029" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%08b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 8 digits
		$msg = $models{$model}{Protocol} . "#" . $adr;
		$msgEnd = "#R" . $repeats;
	############ CAME_TOP_432EV ############
	} elsif ($model eq "CAME_TOP_432EV" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%08b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 8 digits
		$msg = $models{$model}{Protocol} . "#" . $adr;
		$msgEnd = "#R" . $repeats;
	############ NEFF SF01_01319004 || BOSCH SF01_01319004_Typ2 ############
	} elsif (($model eq "SF01_01319004" || $model eq "SF01_01319004_Typ2") && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%016b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 16 digits
		$msg = $models{$model}{Protocol} . "#" . substr($adr,0,14);
		$msgEnd = "#R" . $repeats;
	############ Hoermann HS1-868-BS ############
	} elsif ($model eq "HS1_868_BS" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																	# split adress from def
		my $bitData = "00000000";
		$bitData .= sprintf( "%036b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 36 digits
		$msg = $models{$model}{Protocol} . "#" . $bitData . "#R" . $repeats;
	############ Hoermann HSM4 ############
	} elsif ($model eq "HSM4" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%028b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 28 digits
		$msg = $models{$model}{Protocol} . "#00000000" . $adr;
		$msgEnd .= "1100#R" . $repeats;
	############ Chilitec 22640 ############
	} elsif ($model eq "Chilitec_22640" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%016b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 16 digits
		$msg = $models{$model}{Protocol} . "#" . $adr;
		$msgEnd .= "#R" . $repeats;
	############ LED_XM21_0 22640 ############
	} elsif ($model eq "LED_XM21_0" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%014b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 14 digits
		$msg = $models{$model}{Protocol} . "#" . $adr;
		$msgEnd .= "#R" . $repeats;
	############ Krinner_LUMIX ############
	} elsif ($model eq "Krinner_LUMIX" && $cmd ne "?") {
		my @definition = split(" ", $hash->{DEF});																# split adress from def
		my $adr = sprintf( "%028b", hex($definition[1])) if ($name ne "unknown");	# argument 1 - adress to binary with 14 digits
		$msg = $models{$model}{Protocol} . "#" . $adr;
		$msgEnd .= "#R" . $repeats;
	############ Manax ############
	} elsif ($model eq "Manax" && $cmd ne "?") {
		return "ERROR: the send command is currently not supported";
	}

	Log3 $name, 4, "$ioname: SD_UT_Set attr_model=$model msg=$msg msgEnd=$msgEnd" if(defined $msgEnd);

	if ($cmd eq "?") {
		### create setlist ###
		foreach my $keys (sort keys %{ $models{$model}}) {	
			if ( $keys =~ /^[0-1]{1,}/s ) {
				$ret.= $models{$model}{$keys}.":noArg ";
			}
		}
	} else {
		if (defined $msgEnd) {
			### if cmd, set bits ###
			foreach my $keys (sort keys %{ $models{$model}}) {
				if ( $keys =~ /^[0-1]{1,}/s ) {
					$save = $keys;
					$value = $models{$model}{$keys};
					last if ($value eq $cmd);
				}
			}
			$msg .= $save.$msgEnd;
			Log3 $name, 5, "$ioname: SD_UT_Set attr_model=$model msg=$msg cmd=$cmd value=$value (cmd loop)";
		}

		readingsSingleUpdate($hash, "LastAction", "send", 0) if ($models{$model}{Typ} eq "remote");
		readingsSingleUpdate($hash, "state" , $cmd, 1);

		IOWrite($hash, 'sendMsg', $msg);
		Log3 $name, 3, "$ioname: $name set $cmd";

		## for hex output ##

		my @split = split("#", $msg);
		my $hexvalue = $split[1];
		$hexvalue =~ s/P+//g;															# if P parameter, replace P with nothing
		$hexvalue = sprintf("%X", oct( "0b$hexvalue" ) );
		###################
		Log3 $name, 4, "$ioname: $name SD_UT_Set sendMsg $msg, rawData $hexvalue";
	}
	return $ret;
}

#####################################
sub SD_UT_Undef($$) {
	my ($hash, $name) = @_;
	delete($modules{SD_UT}{defptr}{$hash->{DEF}})
		if(defined($hash->{DEF}) && defined($modules{SD_UT}{defptr}{$hash->{DEF}}));
	return undef;
}


###################################
sub SD_UT_Parse($$) {
	my ($iohash, $msg) = @_;
	my $ioname = $iohash->{NAME};
	my ($protocol,$rawData) = split("#",$msg);
	$protocol=~ s/^[u|U|P](\d+)/$1/; # extract protocol
	my $hlen = length($rawData);
	my $blen = $hlen * 4;
	my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
	my $model = "unknown";
	my $name = "unknown_please_select_model";
	my $SensorTyp;
	Log3 $iohash, 4, "$ioname: SD_UT protocol $protocol, bitData $bitData, hlen $hlen";

	my $def;
	my $deviceCode = "";
	my $devicedef;
	my $zone;							# Unitec_47031 - bits for zone
	my $zoneRead;					# Unitec_47031 - text for user of zone
	my $usersystem;				# Unitec_47031 - text for user of system
	my $deviceTyp;				# hash -> typ
	my $contact;					# MD_210R
	my $keepalive;				# MD_210R
	my $sabotage;					# MD_210R
	my $batteryState;
	my $state = "unknown";

	my $deletecache = $modules{SD_UT}{defptr}{deletecache};
	Log3 $iohash, 5, "$ioname: SD_UT device in delete cache = $deletecache" if($deletecache && $deletecache ne "-");

	if ($deletecache && $deletecache ne "-") {
		CommandDelete( undef, "$deletecache" );						# delete device
		CommandDelete( undef, "FileLog_$deletecache" );		# delete filelog_device
		Log3 $iohash, 3, "SD_UT_Parse device $deletecache deleted" if($deletecache);
		$modules{SD_UT}{defptr}{deletecache} = "-";
		return "";
	}

	if ($hlen == 3) {
		### Westinghouse Buttons_five [P29] ###
		if(!$def && ($protocol == 29 || $protocol == 30)) {
			$deviceCode = substr($rawData,2,1);
			$devicedef = "Buttons_five " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
		### Unitec_47031 [P30] ###		
		if (!$def && ($protocol == 30 || $protocol == 83)) {
			$deviceCode = substr($rawData,0,2);
			$devicedef = "Unitec_47031 " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
		### Remote control SA_434_1_mini 923301 [P81] ###
		if (!$def && ($protocol == 81 || $protocol == 83 || $protocol == 86)) {
			$deviceCode = $rawData;
			$devicedef = "SA_434_1_mini " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
		### Westinghouse_Delancey RH787T [P83] ### no define
		if (!$def && ($protocol == 83 || $protocol == 30)) {
			$deviceCode = substr($bitData,1,4);
			$deviceCode = sprintf("%X", oct( "0b$deviceCode" ) );
			$devicedef = "RH787T " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
		### CAME_TOP_432EV [P86] ###  no define
		if (!$def && ($protocol == 86 || $protocol == 81)) {
			$deviceCode = substr($rawData,0,2);
			$devicedef = "CAME_TOP_432EV " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
	}

	if($hlen == 3 || $hlen == 5) {
		### Novy_840029 [P86] ###
		if (!$def && ($protocol == 86 || $protocol == 81)) {
			$deviceCode = substr($rawData,0,2);
			$devicedef = "Novy_840029 " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
	}

	if ($hlen == 5) {
		### Chilitec_22640 [P14] ###
		if (!$def && $protocol == 14) {
			$deviceCode = substr($rawData,0,4);
			$devicedef = "Chilitec_22640 " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
		### QUIGG_DMV [P34] ###
		if (!$def && $protocol == 34) {
			$deviceCode = substr($rawData,0,3);
			$devicedef = "QUIGG_DMV " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
		### Remote control TEDSEN_SKX1MD [P46] ###
		if (!$def && $protocol == 46) {
			$deviceCode = $rawData;
			$devicedef = "TEDSEN_SKX1MD " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
		### NEFF SF01_01319004 || BOSCH SF01_01319004_Typ2 [P86] ###
		if (!$def && $protocol == 86) {
			$deviceCode = substr($bitData,0,14) . "00";
			$deviceCode = sprintf("%X", oct( "0b$deviceCode" ) );
			$devicedef = "SF01_01319004 " . $deviceCode if (!$def);
			$def = $modules{SD_UT}{defptr}{$devicedef} if (!$def);
			$devicedef = "SF01_01319004_Typ2 " . $deviceCode if (!$def);
			$def = $modules{SD_UT}{defptr}{$devicedef} if (!$def);
		} 
	}

	if ($hlen == 8 && !$def && $protocol == 92) {
		### Remote control Krinner_LUMIX [P92] ###
		$deviceCode = substr($rawData,0,7);
		$devicedef = "Krinner_LUMIX " . $deviceCode;
		$def = $modules{SD_UT}{defptr}{$devicedef};
	}

	if ($hlen == 9) {
		if (!$def && ($protocol == 91 || $protocol == 91.1)) {
			### Atlantic Security with all models [P91] or [P91.1 ] with CHECK ###
			Log3 $iohash, 4, "$ioname: SD_UT device MD_210R check length & Protocol OK";
		my @array_rawData = split("",$rawData);
		my $xor_check = hex($array_rawData[0]);
		foreach my $nibble (1...8) {
			$xor_check = $xor_check ^ hex($array_rawData[$nibble]);
		}
		if ($xor_check != 0) {
			Log3 $iohash, 4, "$ioname: SD_UT device from Atlantic Security - check XOR ($xor_check) FAILED! rawData=$rawData";
			return "";
		} else {
			Log3 $iohash, 4, "$ioname: SD_UT device from Atlantic Security - check XOR OK";
		}

		$model = substr($rawData,7,1);
		if ($model eq "E") {
			$model = "MD_210R";
		} elsif ($model eq "4") {
			$model = "MD_2018R";
		} elsif ($model eq "C") {
			$model = "MD_2003R";
		} else {
			Log3 $iohash, 1, "SD_UT Please report maintainer. Your model from Atlantic Security are unknown! rawData=$rawData";
			return "";
		}
		
		$deviceTyp = $models{$model}{Typ};
		$model = "$model";
		$deviceCode = substr($rawData,0,6);
		$devicedef = "$model " . $deviceCode if (!$def);
		$def = $modules{SD_UT}{defptr}{$devicedef} if (!$def);
		$name = $model."_" . $deviceCode;

		Log3 $iohash, 4, "$ioname: SD_UT device $model from category $deviceTyp with code $deviceCode are ready to decode";
	}
		
		### Manax MX-RCS250 [P90] ###
		if (!$def && $protocol == 90) {
			$deviceCode = substr($rawData,0,4);
			$devicedef = "Manax " . $deviceCode;
			$def = $modules{SD_UT}{defptr}{$devicedef};
		}
	}
	
	if ($hlen == 11 && $protocol == 69) {
		### Remote control Hoermann HS1-868-BS [P69] ###
		$deviceCode = substr($rawData,2,9);
		$devicedef = "HS1_868_BS " . $deviceCode if (!$def);
		$def = $modules{SD_UT}{defptr}{$devicedef} if (!$def);
		### Remote control Hoermann HSM4 [P69] ###
		$deviceCode = substr($rawData,2,7);
		$devicedef = "HSM4 " . $deviceCode if (!$def);
		$def = $modules{SD_UT}{defptr}{$devicedef} if (!$def);
	}

	if (($hlen == 15 || $hlen == 16) &&  !$def && $protocol == 76) {
		### Remote LED_XM21_0 [P76] ###
		$deviceCode = substr($rawData,0,14);
		$devicedef = "LED_XM21_0 " . $deviceCode;
		$def = $modules{SD_UT}{defptr}{$devicedef};
	}
	
	### unknown ###
	$devicedef = "unknown" if(!$def);
	$def = $modules{SD_UT}{defptr}{$devicedef} if(!$def);
	$modules{SD_UT}{defptr}{ioname} = $ioname;

	Log3 $iohash, 4, "$ioname: SD_UT device $devicedef found (delete cache = $deletecache)" if($def && $deletecache && $deletecache ne "-");

	if(!$def) {
		Log3 $iohash, 1, "$ioname: SD_UT_Parse UNDEFINED sensor $model detected, protocol $protocol, data $rawData, code $deviceCode";
		return "UNDEFINED $name SD_UT $model" if ($model eq "unknown");																		# model set user manual
		return "UNDEFINED $name SD_UT $model $deviceCode" if ($model ne "unknown_please_select_model");		# model set automatically
	}

	my $hash = $def;
	$name = $hash->{NAME};
	$hash->{lastMSG} = $rawData;
	$hash->{bitMSG} = $bitData;
	$deviceCode = undef;				# reset

	$model = AttrVal($name, "model", "unknown");
	Log3 $name, 5, "$ioname: SD_UT_Parse devicedef=$devicedef attr_model=$model protocol=$protocol state= (before check)";

	############ Westinghouse_Delancey RH787T ############ Protocol 83 or 30 ############
  if ($model eq "RH787T" && ($protocol == 83 || $protocol == 30)) {
		$state = substr($bitData,6,6);
		$deviceCode = substr($bitData,1,4);

		## Check fixed bits
		my $unknown1 = substr($bitData,0,1);	# every 0
		my $unknown2 = substr($bitData,5,1);	# every 1
		if ($unknown1 ne "0" | $unknown2 ne "1") {
			Log3 $name, 3, "$ioname: $model fixed bits wrong! always bit0=0 ($unknown1) and bit5=1 ($unknown2)";
			return "";
		}

		## deviceCode conversion for User in ON or OFF ##
		my $deviceCodeUser = $deviceCode;
		$deviceCodeUser =~ s/1/off|/g;
		$deviceCodeUser =~ s/0/on|/g;
		$deviceCodeUser = substr($deviceCodeUser, 0 , length($deviceCodeUser)-1);
		$deviceCode = $deviceCode." ($deviceCodeUser)";

	############ Westinghouse Buttons_five ############ Protocol 29 or 30 ############
	} elsif ($model eq "Buttons_five" && ($protocol == 29 || $protocol == 30)) {
		$state = substr($bitData,0,6);
		$deviceCode = substr($bitData,8,4);

		## Check fixed bits
		my $unknown1 = substr($bitData,6,1);	# every 1
		my $unknown2 = substr($bitData,7,1);	# every 1
		if ($unknown1 ne "1" | $unknown2 ne "1") {
			Log3 $name, 3, "$ioname: $model fixed bits wrong! always bit6=1 ($unknown1) and bit7=1 ($unknown2)";
			return "";
		}

		## deviceCode conversion for User in ON or OFF ##
		my $deviceCodeUser = $deviceCode;
		$deviceCodeUser =~ s/1/off|/g;
		$deviceCodeUser =~ s/0/on|/g;
		$deviceCodeUser = substr($deviceCodeUser, 0 , length($deviceCodeUser)-1);
		$deviceCode = $deviceCode." ($deviceCodeUser)";
	############ Unitec_47031 ############ Protocol 30 or 83 ############
	} elsif ($model eq "Unitec_47031" && ($protocol == 30 || $protocol == 83)) {
		$state = substr($bitData,11,1);		# muss noch 100% verifiziert werden !!!

		## deviceCode conversion for User in ON or OFF ##
		$deviceCode = substr($bitData,0,8);		
		my $deviceCodeUser = $deviceCode;
		$deviceCodeUser =~ s/1/on|/g;
		$deviceCodeUser =~ s/0/off|/g;
		$deviceCodeUser = substr($deviceCodeUser, 0 , length($deviceCodeUser)-1);
		$deviceCode = $deviceCode." ($deviceCodeUser)";

		## zone conversion for User in ON or OFF ##
		$zone = substr($bitData,8,3);
		my $zoneUser = $zone;
		$zoneUser =~ s/1/on|/g;
		$zoneUser =~ s/0/off|/g;
		$zoneUser = substr($zoneUser, 0 , length($zoneUser)-1);
		$zoneRead = $zone." ($zoneUser) - Zone ";

		# Anmeldung an Profi-Alarmanzentrale 47121
		if (oct("0b".$zone) < 6 ) {
			$zoneRead.= (oct("0b".$zone)+1);
			$usersystem = "Unitec 47121";
		# other variants
		} else {
			$zoneRead.= (oct("0b".$zone)-5);
			# Anmeldung an Basis-Alarmanzentrale 47125 | Sirenen-System (z.B. ein System ohne separate Funk-Zentrale)
			$usersystem = "Unitec 47125 or Friedland" if (oct("0b".$zone) == 6);
			# Anmeldung an Basis-Alarmanzentrale 47125
			$usersystem = "Unitec 47125" if (oct("0b".$zone) == 7);
		}
		Log3 $name, 5, "$ioname: SD_UT_Parse devicedef=$devicedef attr_model=$model protocol=$protocol deviceCode=$deviceCode state=$state Zone=$zone";
	############ TEDSEN_SKX1MD ############ Protocol 46 ############
	} elsif ($model eq "TEDSEN_SKX1MD" && $protocol == 46) {
		$state = "receive";
	############ SA_434_1_mini ############ Protocol 81 ############
	} elsif ($model eq "SA_434_1_mini" && ($protocol == 81 || $protocol == 83 || $protocol == 86)) {
		$state = "receive";
	############ QUIGG_DMV ############ Protocol 34 ############
	} elsif ($model eq "QUIGG_DMV" && $protocol == 34) {
		$state = substr($bitData,12,8);
		$deviceCode = substr($bitData,0,12);
	############ Novy_840029 ############ Protocol 86 ############
	} elsif ($model eq "Novy_840029" && ($protocol == 86 || $protocol == 81)) {
		if ($hlen == 3) {		# 12 Bit [3]
			$state = substr($bitData,8);			# 4 Bit
		} else {						# 20 Bit [5]
			$state = substr($bitData,8,10);		# 10 Bit (letzte 2 Bit entfernen)
		}
		$deviceCode = substr($bitData,0,8);
	############ CAME_TOP_432EV ############ Protocol 86 ############
	} elsif ($model eq "CAME_TOP_432EV" && ($protocol == 86 || $protocol == 81)) {
		$state = substr($bitData,8);
		$deviceCode = substr($bitData,0,8);
	############ NEFF SF01_01319004 || BOSCH SF01_01319004_Typ2 ############ Protocol 86 ############
	} elsif (($model eq "SF01_01319004" || $model eq "SF01_01319004_Typ2") && $protocol == 86) {
		$state = substr($bitData,14,4);
		$deviceCode = substr($bitData,0,14) . "00" if ($blen >= 14);
		$deviceCode = sprintf("%X", oct( "0b$deviceCode" ) );
	############ Hoermann HS1-868-BS ############ Protocol 69 ############
	} elsif ($model eq "HS1_868_BS" && $protocol == 69) {
		$state = "receive";
		$deviceCode = substr($bitData,8,28);
	############ Hoermann HSM4 ############ Protocol 69 ############
	} elsif ($model eq "HSM4" && $protocol == 69) {
		$state = substr($bitData,36,4);
		$deviceCode = substr($bitData,8,28);
	############ Chilitec_22640 ############ Protocol 14 ############
	} elsif ($model eq "Chilitec_22640" && $protocol == 14) {
		$state = substr($bitData,16,4);
		$deviceCode = substr($bitData,0,16);
	############ LED_XM21_0 ############ Protocol 76 ############
	} elsif ($model eq "LED_XM21_0" && $protocol == 76) {
		$deviceCode = substr($bitData,0,56);
		$state = substr($bitData,56,8);
	############ Krinner_LUMIX ############ Protocol 92 ############
	} elsif ($model eq "Krinner_LUMIX" && $protocol == 92) {
		$deviceCode = substr($bitData,0,28);
		$state = substr($bitData,28,4);
	############ Atlantic Security ############ Protocol 91 or 91.1 ############
	} elsif ($protocol == 91 || $protocol == 91.1) {
		############ MD_210R ############ switch ############
		$sabotage = substr($bitData,24,1);
		$contact = substr($bitData,25,1);
		$batteryState = substr($bitData,26,1);		# muss noch 100% verifiziert werden  bei all typs !!!
		$keepalive = substr($bitData,27,1);				# muss noch 100% verifiziert werden  bei all typs !!!
		
		($batteryState) = @_ = ('ok', 'warning')[$batteryState];
		($keepalive) = @_ = ('event', 'periodically')[$keepalive];
		($sabotage) = @_ = ('closed', 'open')[$sabotage];
		
		if ($model eq "MD_210R") {
			($contact) = @_ = ('closed', 'open')[$contact];
			if ($sabotage eq "closed" && $contact eq "closed") {
				$state = "normal";
			} else {
				$state = "warning";
			}
		############ MD_2018R ############ vibration ############ | ############ MD_2003R ############ gas ############
		} elsif ($model eq "MD_2018R" || $model eq "MD_2003R") {
			($contact) = @_ = ('no Alarm', 'Alarm')[$contact];
			$sabotage = undef;

			if ($contact eq "no Alarm") {
				$state = "normal";
			} else {
				$state = "warning";
			}
		}
	} elsif ($model eq "Manax" && $protocol == 90) {
	############ Manax  ############ Protocol 90 ############
		## Check fixed bits
		my $unknown1 = substr($bitData,16,4);		# ?
		my $unknown2 = substr($bitData,24,12);	# ?
		
		$state = substr($bitData,20,4);
		$deviceCode = substr($bitData,0,16);
	############ unknown ############
	} else {
		readingsSingleUpdate($hash, "state", "???", 0);
		readingsSingleUpdate($hash, "unknownMSG", $bitData."  (protocol: ".$protocol.")", 1);
		Log3 $name, 3, "$ioname: SD_UT Please define your model of Device $name in Attributes!" if (AttrVal($name, "model", "unknown") eq "unknown");
		Log3 $name, 5, "$ioname: SD_UT_Parse devicedef=$devicedef attr_model=$model protocol=$protocol rawData=$rawData, bitData=$bitData";
	}

	Log3 $name, 5, "$ioname: SD_UT_Parse devicedef=$devicedef attr_model=$model protocol=$protocol devicecode=$deviceCode state=$state" if($model ne "unknown" && defined($deviceCode));
	Log3 $name, 5, "$ioname: SD_UT_Parse devicedef=$devicedef attr_model=$model typ=".$models{$model}{Typ}." (after check)";

	if ($models{$model}{Typ} eq "remote" && ($model ne "SA_434_1_mini" || $model ne "HS1_868_BS")) {
		### identify state bits to value from hash ###
		foreach my $keys (sort keys %{ $models{$model}}) {	
			if ($keys eq $state) {
				$state = $models{$model}{$keys};
				Log3 $name, 5, "$ioname: SD_UT_Parse devicedef=$devicedef attr_model=$model typ=".$models{$model}{Typ}." key=".$models{$model}{$keys}." (state loop)";
				last;
			}
		}
	}

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "deviceCode", $deviceCode, 0) if (defined($deviceCode) && $models{$model}{Typ} eq "remote");
	readingsBulkUpdate($hash, "contact", $contact) if (defined($contact) && ($model eq "MD_210R" || $model eq "MD_2018R" || $model eq "MD_2003R"));
	readingsBulkUpdate($hash, "batteryState", $batteryState) if (defined($batteryState));
	readingsBulkUpdate($hash, "deviceTyp", $deviceTyp,0) if (defined($deviceTyp) && ($model eq "MD_210R" || $model eq "MD_2018R" || $model eq "MD_2003R"));
	readingsBulkUpdate($hash, "keepalive", $keepalive) if (defined($keepalive) && ($model eq "MD_210R" || $model eq "MD_2018R" || $model eq "MD_2003R"));
	readingsBulkUpdate($hash, "sabotage", $sabotage) if (defined($sabotage) && ($model eq "MD_210R" || $model eq "MD_2018R" || $model eq "MD_2003R"));
	readingsBulkUpdate($hash, "System-Housecode", $deviceCode, 0) if (defined($deviceCode) && $model eq "Unitec_47031");
	readingsBulkUpdate($hash, "Zone", $zoneRead, 0) if (defined($zoneRead) && $model eq "Unitec_47031");
	readingsBulkUpdate($hash, "Usersystem", $usersystem, 0) if (defined($zoneRead) && $model eq "Unitec_47031");
	readingsBulkUpdate($hash, "LastAction", "receive", 0) if (defined($state) && $models{$model}{Typ} eq "remote" && ($model ne "SA_434_1_mini" || $model ne "HS1_868_BS"));
	readingsBulkUpdate($hash, "state", $state)  if (defined($state) && $state ne "unknown");
	readingsEndUpdate($hash, 1); 		# Notify is done by Dispatch

	return $name;
}

###################################
sub SD_UT_Attr(@) {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	my $typ = $hash->{TYPE};
	my $devicemodel;
	my $deviceCode;
	my $devicename;
	my $ioDev = InternalVal($name, "LASTInputDev", undef);
	my $state;
	my $oldmodel = AttrVal($name, "model", "unknown");
	my $bitData;
	my $hex_lengh = length(InternalVal($name, "lastMSG", "0"));

	############ chance device models ############
	if ($cmd eq "set" && $attrName eq "model" && $attrValue ne $oldmodel) {

		if (InternalVal($name, "bitMSG", "no data") ne "no data") {
			my $devicemodel;

			### ERROR for Users
			my $allowed_models;
			foreach my $keys (sort keys %models) {	# read allowed_models with the same hex_lengh
				$allowed_models.= $keys.", " if ($models{$keys}{hex_lengh} eq $hex_lengh);
			}

			Log3 $name, 4, "SD_UT_Attr Check for the change, $oldmodel hex_lengh=$hex_lengh, attrValue=$attrValue needed hex_lengh=".$models{$attrValue}{hex_lengh};
			return "ERROR! You want to choose the $oldmodel model to $attrValue.\nPlease check your selection.\nThe length of RAWMSG must be the same!\n\nAllowed models are: $allowed_models" if ($models{$attrValue}{hex_lengh} ne $hex_lengh && $oldmodel ne "unknown");	# variants one
			return "ERROR! You want to choose the unknown model to $attrValue.\nPlease check your selection.\nRAWMSG length is wrong!\n\nAllowed models are: $allowed_models" if (not ($models{$attrValue}{hex_lengh} =~ /($hex_lengh)/ ) && $oldmodel eq "unknown");				# variants two/three
			### #### #### ###

			if ($attrName eq "model" && $attrValue eq "unknown") {
				readingsSingleUpdate($hash, "state", " Please define your model with attributes! ", 0);
			}

			foreach my $keys (sort keys %models) {	
				if($keys eq $attrValue) {
					$attr{$name}{model}	= $attrValue;				# set new model
					$bitData = InternalVal($name, "bitMSG", "-");
					$devicemodel = $keys;
					$state = "Defined";
					last;
				}
			}

			############ Westinghouse_Delancey RH787T ############
			if ($attrName eq "model" && $attrValue eq "RH787T") {
				$deviceCode = substr($bitData,1,4);
				$deviceCode = sprintf("%X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ Westinghouse Buttons_five ############
			} elsif ($attrName eq "model" && $attrValue eq "Buttons_five") {
				$deviceCode = substr($bitData,8,4);
				$deviceCode = sprintf("%X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ SA_434_1_mini	############
			} elsif ($attrName eq "model" && $attrValue eq "SA_434_1_mini") {
				$deviceCode = sprintf("%03X", oct( "0b$bitData" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ TEDSEN_SKX1MD	############
			} elsif ($attrName eq "model" && $attrValue eq "TEDSEN_SKX1MD") {
				$deviceCode = sprintf("%05X", oct( "0b$bitData" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ Unitec_47031	############
			} elsif ($attrName eq "model" && $attrValue eq "Unitec_47031") {
				$deviceCode = substr($bitData,0,8);																# unklar derzeit! 10Dil auf Bild
				$deviceCode = sprintf("%02X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ QUIGG_DMV ############
			} elsif ($attrName eq "model" && $attrValue eq "QUIGG_DMV") {
				$deviceCode = substr($bitData,0,12);
				$deviceCode = sprintf("%03X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ Novy_840029 ############
			} elsif ($attrName eq "model" && $attrValue eq "Novy_840029") {
				$deviceCode = substr($bitData,0,8);
				$deviceCode = sprintf("%02X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ CAME_TOP_432EV ############
			} elsif ($attrName eq "model" && $attrValue eq "CAME_TOP_432EV") {
				$deviceCode = substr($bitData,0,8);
				$deviceCode = sprintf("%X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ NEFF SF01_01319004 || BOSCH SF01_01319004_Typ2 ############
			} elsif ($attrName eq "model" && ($attrValue eq "SF01_01319004" || $attrValue eq "SF01_01319004_Typ2")) {
				$deviceCode = substr($bitData,0,14) . "00";
				$deviceCode = sprintf("%04X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ Hoermann HS1-868-BS	############
			} elsif ($attrName eq "model" && $attrValue eq "HS1_868_BS") {
				$deviceCode = sprintf("%09X", oct( "0b$bitData" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ Hoermann HSM4	############
			} elsif ($attrName eq "model" && $attrValue eq "HSM4") {
				$deviceCode = substr($bitData,8,28);
				$deviceCode = sprintf("%07X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ Chilitec_22640	############
			} elsif ($attrName eq "model" && $attrValue eq "Chilitec_22640") {
				$deviceCode = substr($bitData,0,16);
				$deviceCode = sprintf("%04X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ LED_XM21_0	############
			} elsif ($attrName eq "model" && $attrValue eq "LED_XM21_0") {
				$deviceCode = substr($bitData,0,56);
				$deviceCode = sprintf("%14X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ Krinner_LUMIX	############
			} elsif ($attrName eq "model" && $attrValue eq "Krinner_LUMIX") {
				$deviceCode = substr($bitData,0,28);
				$deviceCode = sprintf("%07X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ Manax ############
			} elsif ($attrName eq "model" && $attrValue eq "Manax") {
				$deviceCode = substr($bitData,0,16);
				$deviceCode = sprintf("%04X", oct( "0b$deviceCode" ) );
				$devicename = $devicemodel."_".$deviceCode;
			############ unknown ############
			} else {
				$devicename = "unknown_please_select_model";
				Log3 $name, 3, "SD_UT_Attr UNDEFINED sensor $attrValue (model=unknown)";
			}

			Log3 $name, 3, "SD_UT_Attr UNDEFINED sensor $attrValue detected, code $deviceCode (DoTrigger)" if ($devicemodel ne "unknown");

			$modules{SD_UT}{defptr}{deletecache} = $name if ($hash->{DEF} eq "unknown");
			Log3 $name, 5, "SD_UT: Attr cmd=$cmd devicename=$name attrName=$attrName attrValue=$attrValue oldmodel=$oldmodel";

			readingsSingleUpdate($hash, "state", $state, 0);

			DoTrigger ("global","UNDEFINED unknown_please_select_model SD_UT unknown") if ($devicename eq "unknown_please_select_model");			# if user push attr return to unknown
			DoTrigger ("global","UNDEFINED $devicename SD_UT $devicemodel $deviceCode") if ($devicename ne "unknown_please_select_model");		# create new device

			#CommandAttr( undef, "$devicename model $attrValue" ) if ($devicename ne "unknown_please_select_model");	# set model | Function not reliable !!!
			$attr{$devicename}{model}	= "$attrValue" if ($devicename ne "unknown_please_select_model");				# set model

		} else {
			readingsSingleUpdate($hash, "state", "Please press button again!", 0);
			return "Please press button again or receive more messages!\nOnly with another message can the model be defined.\nWe need bitMSG from message.";
		}
	}

	if ($cmd eq "del" && $attrName eq "model") {			### delete readings

		for my $readingname (qw/Button deviceCode LastAction state unknownMSG/)
		{
			readingsDelete($hash,$readingname);
		}
	}

	## return if fhem init
	if ($init_done) {
		Log3 $name, 3, "SD_UT_Attr set $attrName to $attrValue" if ($cmd eq "set");
		return "Note: Your unknown_please_select_model device are deleted with the next receive.\nPlease use your new defined model device and do not forget to push -Save config-" if ($defs{$name}->{DEF} eq "unknown" && $oldmodel eq "unknown" && $attrValue ne "$oldmodel");
	}
	return undef;
}

###################################

1;

=pod
=item summary    ...
=item summary_DE ...
=begin html

<a name="SD_UT"></a>
<h3>SD_UT</h3>
<ul>The module SD_UT is a universal module of SIGNALduino for devices or sensors.<br>
	After the first creation of the device <code><b>unknown_please_select_model</b></code>, the user must define the device himself via the <code>model</code> attribute.<br>
	If the device is not supported yet, bit data can be collected with the unknown_please_select_model device.<br><br>
	<i><u><b>Note:</b></u></i> As soon as the attribute model of a defined device is changed or deleted, the module re-creates a device of the selected type, and when a new message is run, the current device is deleted. 
	Devices of <u>the same or different type with the same deviceCode will result in errors</u>. PLEASE use different <code>deviceCode</code>.<br><br>
	 <u>The following devices are supported:</u><br>
	 <ul> - Atlantic Security sensors&nbsp;&nbsp;&nbsp;<small>(module model: MD-2003R, MD-2018R,MD-210R | Protokoll 91|91.1)</small></ul>
	 <ul> - BOSCH ceiling fan&nbsp;&nbsp;&nbsp;<small>(module model: SF01_01319004_Typ2 | protocol 86)</small></ul>
	 <ul> - CAME swing gate drive&nbsp;&nbsp;&nbsp;<small>(module model: CAME_TOP_432EV | protocol 86)</small></ul>
	 <ul> - ChiliTec LED X-Mas light&nbsp;&nbsp;&nbsp;<small>(module model: Chilitec_22640 | protocol 14)</small></ul>
	 <ul> - Hoermann HS1-868-BS&nbsp;&nbsp;&nbsp;<small>(module model: HS1_868_BS | protocol 69)</small></ul>
	 <ul> - Hoermann HSM4&nbsp;&nbsp;&nbsp;<small>(module model: HSM4 | protocol 69)</small></ul>
	 <ul> - Krinner LUMIX X-Mas light string&nbsp;&nbsp;&nbsp;<small>(module model: Krinner_LUMIX | protocol 92)</small></ul>
	 <ul> - LED_XM21_0 X-Mas light string&nbsp;&nbsp;&nbsp;<small>(module model: LED_XM21_0 | protocol 76)</small></ul>
	 <ul> - Manax RCS250 <b>ONLY RECEIVE!</b>&nbsp;&nbsp;&nbsp;<small>(module model: Manax | protocol 90)</small></ul>
	 <ul> - NEFF kitchen hood&nbsp;&nbsp;&nbsp;<small>(module model: SF01_01319004 | protocol 86)</small></ul>
	 <ul> - Novy Pureline 6830 kitchen hood&nbsp;&nbsp;&nbsp;<small>(module model: Novy_840029 | protocol 86)</small></ul>
	 <ul> - QUIGG DMV-7000&nbsp;&nbsp;&nbsp;<small>(module model: QUIGG_DMV | protocol 34)</small></ul>
	 <ul> - Remote control SA-434-1 mini 923301&nbsp;&nbsp;&nbsp;<small>(module model: SA_434_1_mini | protocol 81)</small></ul>
	 <ul> - Remote control TEDSEN SKX1MD&nbsp;&nbsp;&nbsp;<small>(module model: TEDSEN_SKX1MD | protocol 46)</small></ul>
	 <ul> - unitec remote door reed switch 47031 (Unitec 47121 | Unitec 47125 | Friedland)&nbsp;&nbsp;&nbsp;<small>(module model: Unitec_47031 | protocol 30)</small></ul>
	 <ul> - Westinghouse Delancey ceiling fan (remote, 5 buttons without SET)&nbsp;&nbsp;&nbsp;<small>(module model: Buttons_five | protocol 29)</small></ul>
	 <ul> - Westinghouse Delancey ceiling fan (remote, 9 buttons with SET)&nbsp;&nbsp;&nbsp;<small>(module model: RH787T | protocol 83)</small></ul>
	 <br><br>
	<b>Define</b><br>
	<ul><code>define &lt;NAME&gt; SD_UT &lt;model&gt; &lt;Hex-address&gt;</code><br><br>
	<u>examples:</u>
		<ul>
		define &lt;NAME&gt; SD_UT RH787T A<br>
		define &lt;NAME&gt; SD_UT SA_434_1_mini ffd<br>
		define &lt;NAME&gt; SD_UT unknown<br>
		</ul>	</ul><br><br>
	<b>Set</b><br>
	<ul>Different transmission commands are available.</ul><br>
		<ul><u>BOSCH (SF01_01319004_Typ2) | NEFF (SF01_01319004)</u></ul>
	<ul><a name="delay"></a>
		<li>delay<br>
		button one on the remote</li>
	</ul>
	<ul><a name="interval"></a>
		<li>interval<br>
		button two on the remote</li>
	</ul>
	<ul><a name="light_on_off"></a>
		<li>light_on_off<br>
		button three on the remote</li>
	</ul>
	<ul><a name="minus"></a>
		<li>minus<br>
		button four on the remote</li>
	</ul>
	<ul><a name="plus"></a>
		<li>plus<br>
		button five on the remote</li>
	</ul><br>

	<ul><u>ChiliTec LED X-Mas light</u></ul>
	<ul><a name="power_on"></a>
		<li>power_on<br>
		button ON on the remote</li>
	</ul>
	<ul><a name="power_off"></a>
		<li>power_off<br>
		button OFF on the remote</li>
	</ul>
	<ul><a name="flickering_slowly"></a>
		<li>flickering_slowly<br>
		button SL on the remote</li>
	</ul>
	<ul><a name="flickering_fast"></a>
		<li>flickering_fast<br>
		button SF on the remote</li>
	</ul>
	<ul><a name="brightness_minus"></a>
		<li>brightness_minus<br>
		button - on the remote</li>
	</ul>
	<ul><a name="brightness_plus"></a>
		<li>brightness_plus<br>
		button + on the remote</li>
	</ul><br>
	
	<ul><u>LED_XM21_0 light string</u></ul>
	<ul><a name="on"></a>
		<li>on<br>
		button I on the remote</li>
	</ul>
	<ul><a name="off"></a>
		<li>off<br>
		button O on the remote</li>
	</ul><br>

	<ul><u>Remote control SA-434-1 mini 923301&nbsp;&nbsp;|&nbsp;&nbsp;Hoermann HS1-868-BS&nbsp;&nbsp;|&nbsp;&nbsp;TEDSEN_SKX1MD</u></ul>
	<ul>
		<li>send<br>
		button <small>(Always send the same, even if the user sends another set command via console.)</small></li>
	</ul><br>

	<ul><u>Hoermann HSM4 (remote with 4 buttons)</u></ul>
	<ul><a name="button_1"></a>
		<li>button_1<br>
		Button one on the remote</li>
	</ul>
	<ul><a name="button_2"></a>
		<li>button_2<br>
		Button two on the remote</li>
	</ul>
	<ul><a name="button_3"></a>
		<li>button_3<br>
		Button three on the remote</li>
	</ul>
	<ul><a name="button_4"></a>
		<li>button_4<br>
		Button four on the remote</li>
	</ul><br>

	<ul><u>Westinghouse Deckenventilator (remote with 5 buttons and without SET)</u></ul>
	<ul><a name="1_fan_low_speed"></a>
		<li>1_fan_low_speed<br>
		Button LOW on the remote</li>
	</ul>
	<ul><a name="2_fan_medium_speed"></a>
		<li>2_fan_medium_speed<br>
		Button MED on the remote</li>
	</ul>
	<ul><a name="3_fan_high_speed"></a>
		<li>3_fan_high_speed<br>
		Button HI on the remote</li>
	</ul>
	<ul><a name="light_on_off"></a>
		<li>light_on_off<br>
		switch light on or off</li>
	</ul>
	<ul><a name="fan_off"></a>
		<li>fan_off<br>
		turns off the fan</li>
	</ul><br><a name=" "></a>

	<ul><u>Westinghouse Delancey ceiling fan (remote RH787T with 9 buttons and SET)</u></ul>
	<ul><a name="1_fan_minimum_speed"></a>
		<li>1_fan_minimum_speed<br>
		Button I on the remote</li>
	</ul>
	<ul><a name="2_fan_low_speed"></a>
		<li>2_fan_low_speed<br>
		Button II on the remote</li>
	</ul>
	<ul><a name="3_fan_medium_low_speed"></a>
		<li>3_fan_medium_low_speed<br>
		Button III on the remote</li>
	</ul>
	<ul><a name="4_fan_medium_speed"></a>
		<li>4_fan_medium_speed<br>
		Button IV on the remote</li>
	</ul>
	<ul><a name="5_fan_medium_high_speed"></a>
		<li>5_fan_medium_high_speed<br>
		Button V on the remote</li>
	</ul>
	<ul><a name="6_fan_high_speed"></a>
		<li>6_fan_high_speed<br>
		Button VI on the remote</li>
	</ul>
	<ul><a name="fan_off"></a>
		<li>fan_off<br>
		turns off the fan</li>
	</ul>
	<ul><a name="fan_direction"></a>
		<li>fan_direction<br>
		Defining the direction of rotation</li>
	</ul>
	<ul><a name="light_on_off"></a>
		<li>light_on_off<br>
		switch light on or off</li>
	</ul>
	<ul><a name="set"></a>
		<li>set<br>
		Button SET in the remote</li><a name=" "></a>
	</ul>
	<br><br>

	<b>Get</b><br>
	<ul>N/A</ul><br><br>

	<b>Attribute</b><br>
	<ul><li><a href="#do_not_notify">do_not_notify</a></li></ul><br>
	<ul><li><a href="#ignore">ignore</a></li></ul><br>
	<ul><li><a href="#IODev">IODev</a></li></ul><br>
	<ul><a name="model"></a>
		<li>model<br>
		The attribute indicates the model type of your device.<br>
		(unknown, Buttons_five, CAME_TOP_432EV, Chilitec_22640, HS1-868-BS, HSM4, QUIGG_DMV, LED_XM21_0, Manax, Novy_840029, RH787T, SA_434_1_mini, SF01_01319004, TEDSEN_SKX1MD, Unitec_47031)</li>
	</ul><br>
	<ul><li><a name="repeats">repeats</a><br>
	This attribute can be used to adjust how many repetitions are sent. Default is 5.</li></ul><br>

	<b><i>Generated readings of the models</i></b><br>
	<ul><u>Buttons_five | CAME_TOP_432EV | Chilitec_22640 | HSM4 | LED_XM21_0 | Manax | Novy_840029 | QUIGG_DMV | SF01_01319004 | SF01_01319004_Typ2 | RH787T</u><br>
	<li>deviceCode<br>
	Device code of the system</li>
	<li>LastAction<br>
	Last executed action of the device. <code>receive</code> for command received | <code>send</code> for command send</li>
	<li>state<br>
	Last executed keystroke of the remote control</li></ul><br>

	<ul><u>MD_2003R (gas)&nbsp;&nbsp;|&nbsp;&nbsp;MD_2018R (vibration)&nbsp;&nbsp;|&nbsp;&nbsp;MD_210R (door/windows switch)</u><br>
	<li>contact<br>
	Status of the internal alarm contact</li>
	<li>deviceTyp<br>
	Model type of your sensor</li>
	<li>sabotage<br>
	State of sabotage contact</li>
	<li>state<br>
	State of the device</li></ul><br>

	<ul><u>HS1-868-BS&nbsp;&nbsp;|&nbsp;&nbsp;SA_434_1_mini&nbsp;&nbsp;|&nbsp;&nbsp;TEDSEN_SKX1MD</u><br>
	<li>LastAction<br>
	Last executed action of FHEM. <code>send</code> for command send.</li>
	<li>state<br>
	Last executed action of the device. <code>receive</code> for command received | <code>send</code> for command send</li></ul><br>

	<ul><u>Unitec_47031</u><br>
	<li>System-Housecode<br>
	System or house code of the device</li>
	<li>state<br>
	Condition of contact (prepared, unconfirmed)</li>
	<li>Zone<br>
	Zone of the device</li>
	<li>Usersystem<br>
	Group of the system</li>
	</ul><br>

</ul>
=end html
=begin html_DE

<a name="SD_UT"></a>
<h3>SD_UT</h3>
<ul>Das Modul SD_UT ist ein Universalmodul vom SIGNALduino f&uuml;r Ger&auml;te oder Sensoren.<br>
	Nach dem ersten anlegen des Ger&auml;tes <code><b>unknown_please_select_model</b></code> muss der User das Ger&auml;t selber definieren via dem Attribut <code>model</code>.<br>
	Bei noch nicht unterst&uuml;tzen Ger&auml;ten k&ouml;nnen mit dem <code><b>unknown_please_select_model</b></code> Ger&auml;t Bitdaten gesammelt werden.<br><br>
	<i><u><b>Hinweis:</b></u></i> Sobald das Attribut model eines definieren Ger&auml;tes verstellt oder gel&ouml;scht wird, so legt das Modul ein Ger&auml;t des gew&auml;hlten Typs neu an und mit Durchlauf einer neuen Nachricht wird das aktuelle Ger&auml;t gel&ouml;scht. 
	Das betreiben von Ger&auml;ten des <u>gleichen oder unterschiedliches Typs mit gleichem <code>deviceCode</code> f&uuml;hrt zu Fehlern</u>. BITTE achte stets auf einen unterschiedlichen <code>deviceCode</code>.<br><br>
	 <u>Es werden bisher folgende Ger&auml;te unterst&uuml;tzt:</u><br>
	 <ul> - Atlantic Security Sensoren&nbsp;&nbsp;&nbsp;<small>(Modulmodel: MD-2003R, MD-2018R,MD-210R | Protokoll 91|91.1)</small></ul>
	 <ul> - BOSCH Deckenl&uuml;fter&nbsp;&nbsp;&nbsp;<small>(Modulmodel: SF01_01319004_Typ2 | Protokoll 86)</small></ul>
	 <ul> - CAME Drehtor Antrieb&nbsp;&nbsp;&nbsp;<small>(Modulmodel: CAME_TOP_432EV | Protokoll 86)</small></ul>
	 <ul> - ChiliTec LED Christbaumkerzen&nbsp;&nbsp;&nbsp;<small>(Modulmodel: Chilitec_22640 | Protokoll 14)</small></ul>
	 <ul> - Hoermann HS1-868-BS&nbsp;&nbsp;&nbsp;<small>(Modulmodel: HS1_868_BS | Protokoll 69)</small></ul>
	 <ul> - Hoermann HSM4&nbsp;&nbsp;&nbsp;<small>(Modulmodel: HSM4 | Protokoll 69)</small></ul>
	 <ul> - Krinner LUMIX Christbaumkerzen&nbsp;&nbsp;&nbsp;<small>(Modulmodel: Krinner_LUMIX | Protokol 92)</small></ul>
	 <ul> - LED_XM21_0 Christbaumkerzen&nbsp;&nbsp;&nbsp;<small>(Modulmodel: LED_XM21_0 | Protokol 76)</small></ul>
	 <ul> - Manax RCS250 <b>NUR EMPFANG!</b>&nbsp;&nbsp;&nbsp;<small>(Modulmodel: Manax | Protokoll 90)</small></ul>
	 <ul> - NEFF Dunstabzugshaube&nbsp;&nbsp;&nbsp;<small>(Modulmodel: SF01_01319004 | Protokoll 86)</small></ul>
	 <ul> - Novy Pureline 6830 Dunstabzugshaube&nbsp;&nbsp;&nbsp;<small>(Modulmodel: Novy_840029 | Protokoll 86)</small></ul>
	 <ul> - QUIGG DMV-7000&nbsp;&nbsp;&nbsp;<small>(Modulmodel: QUIGG_DMV | Protokoll 34)</small></ul>
	 <ul> - Remote control SA-434-1 mini 923301&nbsp;&nbsp;&nbsp;<small>(Modulmodel: SA_434_1_mini | Protokoll 81)</small></ul>
	 <ul> - Remote control TEDSEN_SKX1MD&nbsp;&nbsp;&nbsp;<small>(Modulmodel: TEDSEN_SKX1MD | Protokoll 46)</small></ul>
	 <ul> - unitec remote door reed switch 47031 (Unitec 47121 | Unitec 47125 | Friedland)&nbsp;&nbsp;&nbsp;<small>(Modulmodel: Unitec_47031 | Protokoll 30)</small></ul>
	 <ul> - Westinghouse Deckenventilator (Fernbedienung, 5 Tasten ohne SET)&nbsp;&nbsp;&nbsp;<small>(Modulmodel: Buttons_five | Protokoll 29)</small></ul>
	 <ul> - Westinghouse Delancey Deckenventilator (Fernbedienung, 9 Tasten mit SET)&nbsp;&nbsp;&nbsp;<small>(Modulmodel: RH787T | Protokoll 83)</small></ul>
	 <br><br>

	<b>Define</b><br>
	<ul><code>define &lt;NAME&gt; SD_UT &lt;model&gt; &lt;Hex-Adresse&gt;</code><br><br>
	<u>Beispiele:</u>
		<ul>
		define &lt;NAME&gt; SD_UT RH787T A<br>
		define &lt;NAME&gt; SD_UT SA_434_1_mini ffd<br>
		define &lt;NAME&gt; SD_UT unknown<br>
		</ul></ul><br><br>

	<b>Set</b><br>
	<ul>Je nach Ger&auml;t sind unterschiedliche Sendebefehle verf&uuml;gbar.</ul><br>
	<ul><u>BOSCH (SF01_01319004_Typ2) | NEFF (SF01_01319004)</u></ul>
	<ul><a name="delay"></a>
		<li>delay<br>
		Taste 1 auf der Fernbedienung</li>
	</ul>
	<ul><a name="interval"></a>
		<li>interval<br>
		Taste 2 auf der Fernbedienung</li>
	</ul>
	<ul><a name="light_on_off"></a>
		<li>light_on_off<br>
		Taste 3 auf der Fernbedienung</li>
	</ul>
	<ul><a name="minus"></a>
		<li>minus<br>
		Taste 4 auf der Fernbedienung</li>
	</ul>
	<ul><a name="plus"></a>
		<li>plus<br>
		Taste 5 auf der Fernbedienung</li>
	</ul><br>

	<ul><u>ChiliTec LED Christbaumkerzen</u></ul>
	<ul><a name="power_on"></a>
		<li>power_on<br>
		Taste ON auf der Fernbedienung</li>
	</ul>
	<ul><a name="power_off"></a>
		<li>power_off<br>
		Taste OFF auf der Fernbedienung</li>
	</ul>
	<ul><a name="flickering_slowly"></a>
		<li>flickering_slowly<br>
		Taste SL auf der Fernbedienung</li>
	</ul>
	<ul><a name="flickering_fast"></a>
		<li>flickering_fast<br>
		Taste SF auf der Fernbedienung</li>
	</ul>
	<ul><a name="brightness_minus"></a>
		<li>brightness_minus<br>
		Taste - auf der Fernbedienung</li>
	</ul>
	<ul><a name="brightness_plus"></a>
		<li>brightness_plus<br>
		Taste + auf der Fernbedienung</li>
	</ul><br>
	
	<ul><u>LED_XM21_0 Christbaumkerzen</u></ul>
	<ul><a name="on"></a>
		<li>on<br>
		Taste I auf der Fernbedienung</li>
	</ul>
	<ul><a name="off"></a>
		<li>off<br>
		Taste O auf der Fernbedienung</li>
	</ul><br>

	<ul><u>Remote control SA-434-1 mini 923301&nbsp;&nbsp;|&nbsp;&nbsp;Hoermann HS1-868-BS&nbsp;&nbsp;|&nbsp;&nbsp;TEDSEN_SKX1MD</u></ul>
	<ul>
		<li>send<br>
		Knopfdruck <small>(Sendet immer das selbe, auch wenn der Benutzer einen anderen Set-Befehl via Konsole sendet.)</small></li>
	</ul><br>

	<ul><u>Hoermann HSM4 (Fernbedienung mit 4 Tasten)</u></ul>
	<ul><a name="button_1"></a>
		<li>button_1<br>
		Taste 1 auf der Fernbedienung</li>
	</ul>
	<ul><a name="button_2"></a>
		<li>button_2<br>
		Taste 2 auf der Fernbedienung</li>
	</ul>
	<ul><a name="button_3"></a>
		<li>button_3<br>
		Taste 3 auf der Fernbedienung</li>
	</ul>
	<ul><a name="button_4"></a>
		<li>button_4<br>
		Taste 4 auf der Fernbedienung</li>
	</ul><br>

	<ul><u>Westinghouse Deckenventilator (Fernbedienung mit 5 Tasten)</u></ul>
	<ul><a name="1_fan_low_speed"></a>
		<li>1_fan_low_speed<br>
		Taste LOW auf der Fernbedienung</li>
	</ul>
	<ul><a name="2_fan_medium_speed"></a>
		<li>2_fan_medium_speed<br>
		Taste MED auf der Fernbedienung</li>
	</ul>
	<ul><a name="3_fan_high_speed"></a>
		<li>3_fan_high_speed<br>
		Taste HI auf der Fernbedienung</li>
	</ul>
	<ul><a name="light_on_off"></a>
		<li>light_on_off<br>
		Licht ein-/ausschalten</li>
	</ul>
	<ul><a name="fan_off"></a>
		<li>fan_off<br>
		Ventilator ausschalten</li>
	</ul><br>

	<ul><a name=" "></a><u>Westinghouse Delancey Deckenventilator (Fernbedienung RH787T mit 9 Tasten + SET)</u></ul>
	<ul><a name="1_fan_minimum_speed"></a>
		<li>1_fan_minimum_speed<br>
		Taste I auf der Fernbedienung</li>
	</ul>
	<ul><a name="2_fan_low_speed"></a>
		<li>2_fan_low_speed<br>
		Taste II auf der Fernbedienung</li>
	</ul>

	<ul><a name="3_fan_medium_low_speed"></a>
		<li>3_fan_medium_low_speed<br>
		Taste III auf der Fernbedienung</li>
	</ul>
	<ul><a name="4_fan_medium_speed"></a>
		<li>4_fan_medium_speed<br>
		Taste IV auf der Fernbedienung</li>
	</ul>
	<ul><a name="5_fan_medium_high_speed"></a>
		<li>5_fan_medium_high_speed<br>
		Taste V auf der Fernbedienung</li>
	</ul>
	<ul><a name="6_fan_high_speed"></a>
		<li>6_fan_high_speed<br>
		Taste VI auf der Fernbedienung</li>
	</ul>
	<ul><a name="fan_off"></a>
		<li>fan_off<br>
		Ventilator ausschalten</li></ul>
	<ul><a name="fan_direction"></a>
		<li>fan_direction<br>
		Drehrichtung festlegen</li>
	</ul>
	<ul><a name="light_on_off"></a>
		<li>light_on_off<br>
		Licht ein-/ausschalten</li>
	</ul>
	<ul><a name="set"></a>
		<li>set<br>
		Taste SET in der Fernbedienung</li><a name=" "></a>
	</ul>
	<br><br>

	<b>Get</b><br>
	<ul>N/A</ul><br><br>

	<b>Attribute</b><br>
	<ul><li><a href="#do_not_notify">do_not_notify</a></li></ul><br>
	<ul><li><a href="#ignore">ignore</a></li></ul><br>
	<ul><li><a href="#IODev">IODev</a></li></ul><br>
	<ul><li><a name="model">model</a><br>
		Das Attribut bezeichnet den Modelltyp Ihres Ger&auml;tes.<br>
		(unknown, Buttons_five, CAME_TOP_432EV, Chilitec_22640, HS1-868-BS, HSM4, QUIGG_DMV, RH787T, LED_XM21_0, Manax, Novy_840029, SA_434_1_mini, SF01_01319004, TEDSEN_SKX1MD, Unitec_47031)</li><a name=" "></a>
	</ul><br>
	<ul><li><a name="repeats">repeats</a><br>
	Mit diesem Attribut kann angepasst werden, wie viele Wiederholungen sendet werden. Standard ist 5.</li></ul><br>

	<b><i>Generierte Readings der Modelle</i></b><br>
	<ul><u>Buttons_five | CAME_TOP_432EV | Chilitec_22640 | HSM4 | LED_XM21_0 | Manax | Novy_840029 | QUIGG_DMV | SF01_01319004 | SF01_01319004_Typ2 | RH787T</u><br>
	<li>deviceCode<br>
	Ger&auml;teCode des Systemes</li>
	<li>LastAction<br>
	Zuletzt ausgef&uuml;hrte Aktion des Ger&auml;tes. <code>receive</code> f&uuml;r Kommando empfangen | <code>send</code> f&uuml;r Kommando gesendet</li>
	<li>state<br>
	Zuletzt ausgef&uuml;hrter Tastendruck der Fernbedienung</li></ul><br>

	<ul><u>MD_2003R (gas)&nbsp;&nbsp;|&nbsp;&nbsp;MD_2018R (vibration)&nbsp;&nbsp;|&nbsp;&nbsp;MD_210R (door/windows switch)</u><br>
	<li>contact<br>
	Zustand des internen Alarmkontaktes.</li>
	<li>deviceTyp<br>
	Modeltyp Ihres Sensors.</li>
	<li>sabotage<br>
	Zustand des Sabotagekontaktes.</li>
	<li>state<br>
	Zustand des Ger&auml;tes.</li></ul><br>

	<ul><u>HS1-868-BS&nbsp;&nbsp;|&nbsp;&nbsp;SA_434_1_mini&nbsp;&nbsp;|&nbsp;&nbsp;TEDSEN_SKX1MD</u><br>
	<li>LastAction<br>
	Zuletzt ausgef&uuml;hrte Aktion aus FHEM. <code>send</code> f&uuml;r Kommando gesendet.</li>
	<li>state<br>
	Zuletzt ausgef&uuml;hrte Aktion des Ger&auml;tes. <code>receive</code> f&uuml;r Kommando empfangen.</li></ul><br>

	<ul><u>Unitec_47031</u><br>
	<li>System-Housecode<br>
	Eingestellter System bzw. Hauscode des Ger&auml;tes</li>
	<li>state<br>
	Zustand des Kontaktes (vorbereitet, unbest&auml;tigt)</li>
	<li>Zone<br>
	Eingestellte Zone des Ger&auml;tes</li>
	<li>Usersystem<br>
	Bezeichnung Systemes</li>
	</ul><br>

</ul>
=end html_DE
=cut
