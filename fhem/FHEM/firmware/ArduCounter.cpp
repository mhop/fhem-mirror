/*
 * Sketch for counting impulses in a defined interval
 * e.g. for power meters with an s0 interface that can be 
 * connected to an input of an arduino or esp8266 board 
 *
 * the sketch uses pin change interrupts which can be anabled 
 * for any of the inputs on e.g. an arduino uno, jeenode, wemos d1 etc.
 *
 * the pin change Interrupt handling for arduinos used here 
 * is based on the arduino playground example on PCINT:
 * http://playground.arduino.cc/Main/PcInt which is outdated.
 *
 * see https://github.com/GreyGnome/EnableInterrupt for a newer library (not used here)
 * and also 
 * https://playground.arduino.cc/Main/PinChangeInterrupt
 * http://www.avrfreaks.net/forum/difference-between-signal-and-isr
 *
 * Refer to avr-gcc header files, arduino source and atmega datasheet.
 */

/* Arduino Uno / Nano Pin to interrupt map:
 * D0-D7 =           PCINT 16-23 = PCIR2 = PD = PCIE2 = pcmsk2
 * D8-D13 =          PCINT 0-5 =   PCIR0 = PB = PCIE0 = pcmsk0
 * A0-A5 (D14-D19) = PCINT 8-13 =  PCIR1 = PC = PCIE1 = pcmsk1
 */

/* test cmds 

    Nano analog
    21,2,0,50,2,98,115  A7=21, falling, no pullup, min 50, ir-out 2, thresholds 98/115

    analog ESP 8266:
    20v               Verbose
    17,3,0,50a        A0, rising, no Pullup, MinLen 50
    15,25t            Level Diff Thresholds
 
    for ESP8266 with D5 falling pullup 30
    5,2,1,30a
    20v
    10,20,1,1i
 
    for ESP32 pin 23
    23,2,1,50a
    10,20,1,1i
 
    for ESP32 with A0 = 36
    36,3,0,50a
    25v
 
    TTGO T-Display has right button at GPIO 35
    35,2,0,50a
    36,3,0,50,27a

*/

/*
    Changes:
        V1.2
        27.10.16 - use noInterrupts in report()
                 - avoid reporting very short timeDiff in case of very slow impulses after a report
                 - now reporting is delayed if impulses happened only within in intervalSml
                 - reporting is also delayed if less than countMin pulses counted
                 - extend command "int" for optional intervalSml and countMin
        29.10.16 - allow interval Min >= Max or Sml > Min 
                   which changes behavior to take fixed calculation interval instead of timeDiff between pulses
                   -> if intervalMin = intervalMax, counting will allways follow the reporting interval
        3.11.16  - more noInterrupt blocks when accessing the non uint8_t volatiles in report
        V1.3    
        4.11.16  - check min pulse width and add more output,
                 - prefix show output with M
        V1.4
        10.11.16 - restructure add Cmd
                 - change syntax for specifying minPulseLengh
             - res (reset) command
        V1.6
        13.12.16 - new startup message logic?, newline before first communication?
        18.12.16 - replace all code containing Strings, new communication syntax and parsing from Jeelink code
        V1.7
        2.1.17 - change message syntax again, report time as well, first and last impulse are reported 
                 relative to start of intervall not start of reporting intervall
        V1.8
        4.1.17 - fixed a missing break in the case statement for pin definition
        5.1.17 - cleanup debug logging
        14.10.17 - fix a bug where last port state was not initialized after interrupt attached but this is necessary there
        23.11.17 - beautify code, add comments, more debugging for users with problematic pulse creation devices
        28.12.17 - better reportung of first pulse (even if only one pulse and countdiff is 0 but realdiff is 1)
        30.12.17 - rewrite PCInt, new handling of min pulse length, pulse history ring
        1.1.18   - check len in add command, allow pin 8 and 13
        2.1.18   - add history per pin to report line, show negative starting times in show history
        3.1.18   - little reporting fix (start pos of history report)
        
        V2.0
        17.1.18  - rewrite many things - use pin number instead of pcIntPinNumber as index, split interrupt handler for easier porting to ESP8266, ...
        V2.23
        10.2.18  - new commands for check alive and quit, send setup message after reboot also over tcp
                    remove reporting time of first pulse (now we hava history)
                    remove pcIntMode (is always change now)
                    pulse min interval is now always checked and defaults to 2 if not set
        march 2018  many changes more to support ESP8266 
        7.3.18  - change pin config output, fix pullup (V2.26), store config in eeprom and read it back after boot
        22.4.18 - many changes, delay report if tcp mode and disconnected, verbose levels, ...
        13.5.18 - V2.36 Keepalive also on Arduino side
        9.12.18 - V3.0 start implementing analog input for old ferraris counters
        6.1.19  - V3.1 printIntervals in hello
        19.1.19 - V3.12 support for ESP with analog
        24.2.19 - V3.13 fix internal pin to GPIO mapping (must match ISR functions) when ESP8266 and analog support       
                - V3.14 added return of devVerbose upon startup
        27.6.19 - V3.20 replace timeNextReport with lastReportCall to avoid problem with data tyoes on ESP
                        fix a bug with analog counting on the ESP 
        20.7.19 -       nicer debug output for analog leves
        21.7.19 - V3.30 replace delay during analog read with millis() logic, optimize waiting times for analog read
        10.8.19 - V3.32 add ICACHE_RAM_ATTR for ISRs and remove remaining long casts (bug) when handling time
        12.8.19 - V3.33 fix handling of keepalive timeouts when millis wraps
                  V3.34 add RSSI output when devVerbose >= 5 in kealive responses
        16.8.19 - V3.35 fix a bug when analog support was disabled and a warning with an unused variable
        19.8.19 - V4.00 start porting to ESP32.
        21.12.19 - V4.10 Support for TTGO Lilygo Board (T-Display) with ST7789V 1,14 Zoll Display (240x135) see https://github.com/Xinyuan-LilyGO/TTGO-T-Display
                        or https://de.aliexpress.com/item/33048962331.html?spm=a2g0o.store_home.hotSpots_212315783.0
        30.12.19 - V4.20 started to make analog support user defineable at runtime
            reconnect when wifi is lost 
        20.1.2020 - rewrite many things ...
        2.2.2020 integrate ESPOTA - see https://raw.githubusercontent.com/esp8266/Arduino/master/tools/espota.py
        30.4.2020 V4.25 - show if compiled with display support, debug tcp disconnects
        12.5.2020 V4.26 - restore fixes after a crash (resetWifi, displayMode 3, change commandData to uint32_t)

    ToDo / Ideas:
        max 10 printData entries, displayMode to cycle through pins to display in different views        
        detect analog Thresholds automatically and adjust over time
        printPinHistory could be called independent of report to avoid of losing history data
*/ 

#include <Arduino.h>

#if defined(TFT_DISPLAY)
#include <TFT_eSPI.h>
#include <SPI.h>
#include <Wire.h>
#include <Button2.h>
#include "esp_adc_cal.h"
/*#include "bmp.h"*/
TFT_eSPI tft = TFT_eSPI();  // Invoke library, pins defined in User_Setup.h or as -D in platformio.ini
uint8_t lineCount;          // initialized in each report call

#define TFT_BUTTON 0
#define displayModeMax 3
Button2 buttonA = Button2(TFT_BUTTON);
uint8_t displayMode = 1;
#endif

#include "pins_arduino.h"
#include <EEPROM.h>

const char versionStr[] PROGMEM = "ArduCounter V4.26";

// even with 38400 one report takes less than 1ms. However printing the report on the tft takes 2ms!
// but if analog interval is set to 10 or less and we output a lot to serial (devVerbose 50) then 
//     background tasks (serial?) eat up 5ms per round...
//     this is much better at 115200! (obviously serial io is done interrupt driven at same core)
// TCP io also creates delays of 15-20ms between loop calls
// show cmd also takes > 10 ms 
// serial output of hello msg takes long because the serial buffer is too small so Serial.print takes longer ...

//#define SERIAL_SPEED 38400
#define SERIAL_SPEED 115200
#define MAX_INPUT_NUM 16

#define pin2GPIO(P) ( pgm_read_byte( digital_pin_to_gpio_PGM + (P) ) )
#define FF 255

#if defined(ESP8266) || defined(ESP32)  // Wifi stuff
#define WifiSupport 1

#if defined(ESP8266)
#include <ESP8266WiFi.h>          
#elif defined(ESP32)
#include <WiFi.h>          
#endif
#include <WiFiUdp.h>
#include <ArduinoOTA.h>

#if defined(STATIC_WIFI)
#include "ArduCounterTestConfig.h"
#else
#include <WiFiManager.h>
WiFiManager wifiManager;
#endif

WiFiServer Server(80);              // For ESP WiFi connection
WiFiClient Client1;                 // active TCP connection
WiFiClient Client2;                 // secound TCP connection to send reject message
boolean serverStarted;              // to show the status once


boolean TCPconnected;               // remember state of TCP connection so loss can be reported
boolean tcpMode = false;            // remember if we had a tcp connection so we can delay report if disconnected
uint8_t delayedTcpReports = 0;      // how often did we already delay reporting because tcp disconnected
uint32_t lastDelayedTcpReports = 0; // last time we delayed

uint16_t keepAliveTimeout = 200;
uint32_t lastKeepAlive;
uint32_t lastReconnectTry;
int reconnects = 0;

#endif


// function declaraions
void clearInput();
void restoreFromEEPROM();
void CmdSaveToEEPROM();
void CmdInterval();
void CmdThreshold();
void CmdAdd ();
void CmdRemove();
void CmdShow();
void CmdHello();
void CmdWait();
void CmdDevVerbose();
void CmdKeepAlive();
void CmdQuit();
void printWifiState(Print *Out);
void handleInput(char c);


/* ESP8266 pins that are typically ok to use 
 * (some might be set to FF (disallowed) because they are used 
 * as reset, serial, led or other things on most boards) 
 * maps printed pin numbers (aPin) to gpio pin numbers (via their macros if available)
 
 * Wemos / NodeMCU Pins 3,4 and 8 (GPIO 0,2 and 15) define boot mode and therefore
 * can not be used to connect to signal */
 
#if defined(ESP8266)                // ESP 8266 variables and definitions
#define MAX_PIN 7                   // max number of pins that can be defined
#define MAX_HIST 20                 // 20 history entries for ESP boards (can be increased)
#define MAX_APIN 18
const uint8_t PROGMEM digital_pin_to_gpio_PGM[] = {
	D0, D1, D2, FF,                 // D0=16, D1=5, D2=4
    FF, D5, D6, D7,                 // D5=14, D6 is my preferred pin for IR out, D7 for LED out
    FF, FF, FF, FF,
    FF, FF, FF, FF,
    FF, A0                          // A0 is gpio pin 17
}; 


/* ESP32 pins that are typically ok to use 
 * (some might be set to -1 (disallowed) because they are used 
 * as reset, serial, led or other things on most boards) 
 * maps printed pin numbers (aPin) to sketch internal index numbers */
 
#elif defined(ESP32)                // ESP32 variables and definitions
#define MAX_PIN 12
#define MAX_HIST 100                // 100 history entries for ESP boards (can be increased)
#define MAX_APIN 40
#if defined(TFT_DISPLAY)            // TTGO T-Display
const uint8_t PROGMEM digital_pin_to_gpio_PGM[] = {
    FF, FF, FF, FF,                 // pwm at boot, debug, LED, high at boot
    04, FF, FF, FF,                 // 4 is ok, pwm at boot, 
    FF, FF, FF, FF,                 // 6-11 is flash
    FF, FF, FF, FF,                 // 12-15 are used for JTAG
    FF, 17, FF, FF,                 // only 17 is free. 16,18 and 19 for display
    FF, 21, 22, FF,                 // 21-22 avaliable, 23 for display
    FF, 25, 26, 27,                 // 25-26 avaliable, use 27 as irOut
    FF, FF, FF, FF,
    32, 33, 34, 35,                 // 32-35 avaliable (34/35 input only, 35 is right button)
    36, FF, FF, 39};                // 36 is A0, is 39 avaliable but also input only

#else                               // normal ESP32 Devboard
const uint8_t PROGMEM digital_pin_to_gpio_PGM[] = {
    FF, FF, FF, FF,                 // pwm at boot, debug, LED, high at boot
    04, FF, FF, FF,                 // 4 is ok, pwm at boot, 
    FF, FF, FF, FF,                 // 6-11 is flash
    FF, FF, FF, FF,                 // 12 is used at boot, 12-15 for JTAG, otherwise 13 is ok, 14/15 output pwm
    16, 17, 18, 19,
    FF, 21, 22, 23,                 // 21-23 avaliable   
    FF, 25, 26, 27,                 // 25-26 avaliable, use 27 as irOut
    FF, FF, FF, FF,
    32, 33, 34, 35,                 // 32-35 avaliable (34/35 input only)
    36, FF, FF, 39};                // 36 is A0, 39 is avaliable but also input only
#endif


#elif defined(__AVR_ATmega328P__)   // Arduino Nano
#define MAX_HIST 20                 // 20 history entries for arduino boards
#define MAX_PIN 12                  // max 20 counting pins at the same time
#define MAX_APIN 22
const uint8_t PROGMEM digital_pin_to_gpio_PGM[] = {
    FF, FF,  2,  3,                 // 2 is typically ir out for analog,
     4,  5,  6,  7,
     8,  9, 10, 11,
    12, 13, A0, A1,                 // 12 often is led out
    A2, A3, A4, A5,
    A6, A7                          // A7 is typically analog in for ir
};
  
uint8_t pinIndexMap[MAX_APIN];      // map needed by 328p isr to map back from aPin to pinIndex in pinData
uint8_t firstPin[] = {8, 14, 0};    // first and last pin at port PB, PC and PD for arduino uno/nano
uint8_t lastPin[]  = {13, 19, 7};   // not really needed. Instead check bit position (or bit != 0)
volatile uint8_t *port_to_pcmask[] = {&PCMSK0, &PCMSK1, &PCMSK2};    // Pin change mask for each port on arduino
volatile uint8_t PCintLast[3];      // last PIN States at io port to detect pin changes in arduino ISR
#endif                              // end of Nano / Uno specific stuff


Print *Output;                      // Pointer to output device (Serial / TCP connection with ESP8266)
uint32_t bootTime;                  
uint16_t bootWraps;                 // counter for millis wraps at last reset
uint16_t millisWraps;               // counter to track when millis counter wraps 
uint32_t lastMillis;                // milis at last main loop iteration - initialized in setup()
uint32_t lastTimeMillis;            // millis at last show time

uint8_t enableHistory;              // new flag to control collecting and reporting pin history
uint8_t enableSerialEcho;           // echo tcp output on serial
uint8_t enablePinDebug;             // show digital pin changes
uint8_t enableAnalogDebug;          // show analog level sampling
uint8_t enableDevTime;              // show device Time every hour

uint32_t intervalMin = 30000;       // default 30 sec - report after this time if nothing else delays it
uint32_t intervalMax = 60000;       // default 60 sec - report after this time if it didin't happen before
uint32_t intervalSml =  2000;       // default 2 secs - continue if timeDiff is less and intervalMax not over
uint16_t countMin    =     2;       // continue counting if count is less than this and intervalMax not over

uint8_t ledOutPin;                  // todo: not implemented yet

uint32_t lastReportCall;
#if defined(TFT_DISPLAY)
uint32_t lastPrintFlowCall;
#endif


typedef struct pinData {
    // pin configuration data
    uint8_t pinName;                            // printed pin Number for user input / output
                                                
    uint8_t pulseWidthMin;                      // minimal pulse length in millis for filtering
    uint8_t pulseLevel;                         // rising (1)/ falling (0)          // only one bit needed
    uint8_t pullupFlag;                         // 1 for pullup                     // only one bit needed
    uint8_t analogFlag;                         // 1 for analog                     // only one bit needed

    // counting data
    volatile uint32_t counter;                  // counter for pulses
    volatile uint32_t rejectCounter;            // counter for rejected pulses (width too small)
    volatile uint32_t intervalStart;            // time of first impulse in interval
    volatile uint32_t intervalEnd;              // time of last impulse in interval
    volatile uint32_t pulseWidthSum;            // sum of all pulse widthes during interval (for average)
    volatile uint8_t counterIgn;                // counts first pulse that marks begin of the very first interval

    // isr internal states
    volatile uint8_t initialized;               // set if first pulse has ben seen to start interval
    volatile uint32_t lastChange;               // millis at last level change (for measuring pulse length)
    volatile uint8_t lastLevel;                 // level of input at last interrupt     // only one bit needed
    volatile uint8_t lastLongLevel;             // last level that was longer than pulseWidthMin    // only bit

    // reporting data
    uint32_t lastCount;                         // counter at last report (to get the delta count)
    uint16_t lastRejCount;                      // reject counter at last report (to get the delta count)
    uint32_t lastReport;                        // millis at last report to find out when maxInterval is over
    uint8_t reportSequence;                     // sequence number for reports
    uint8_t lastDebugLevel;                          // for debug output when a pin state changes
} pinData_t;

pinData_t pinData[MAX_PIN];
uint8_t maxPinIndex = 0;                        // the next available index (= number of indices used)

typedef struct analogData {
    pinData_t *inPinData;                       // pointer to pinData structure for input pin (to call doCount)
    uint8_t inPinName;                          // printed pin Number for user input / output (optinal here?)
    uint8_t outPinName;                         // printed pin number to use for ir (convert using our macro)
    uint16_t thresholdMin;                      // measurement for 0 level
    uint16_t thresholdMax;                      // measurement for 1 
    uint8_t triggerState;                       // which level was it so far
    uint16_t sumOff = 0;                        // sum of measured values during light off
    uint16_t sumOn  = 0;                        // sum of measured values during light on
    uint16_t avgCnt = 0;                        // counter for average during one level
    uint32_t avgSum = 0;                        // sum for average during one level
} analogData_t;

#define MAX_ANALOG 2
analogData_t analogData[MAX_ANALOG];
uint8_t maxAnalogIndex = 0;                     // the next available index

typedef struct histData {
    volatile uint16_t seq;                      // history sequence number
    volatile uint8_t pin;                       // pin for this entry
    volatile uint8_t level;                     // gap/signal level for this entry 
    volatile uint16_t aLvl;                     // average analog level for this entry
    volatile uint32_t time;                     // time for this entry
    volatile uint32_t len;                      // time that this level was held
    volatile char act;                          // action (count, reject, ...) as one char
} histData_t;

histData_t histData[MAX_HIST];
volatile uint8_t histIndex;                     // pointer to next entry in history ring
volatile uint16_t histNextSeq;                  // next seq number to use
uint16_t histLastOut;                           // seqnuence of last entry already reported

uint32_t commandData[MAX_INPUT_NUM];            // input data over serial port or network
uint8_t  commandDataPointer = 0;                // index pointer to next input value
uint8_t  commandDataSize = 0;                   // number of input values specified in commandData array
char     commandLetter;                         // the actual command letter
uint32_t commandValue = 0;                      // the current value for input function


uint32_t analogReadLast;            // millis() at last analog read
uint32_t analogReadWait;            // millis() during state machine 
uint16_t analogReadInterval = 50;   // interval at which to read analog values (miliseconds)
uint8_t analogReadState = 0;        // to keep track of switching LED on/off, measuring etc.
uint8_t analogReadAmp = 3;          // amplification for display
uint8_t analogReadSamples = 4;      // samples to take with the light off - max 16 so sum can be an int 16
uint8_t analogReadCount = 0;        // counter for sampling

uint32_t analogCallLast = 0;        // last analog read call for debugging delays

#define MAX_UNIT 5                  // 4 characters and a trailing zero
typedef struct printData {
    uint8_t pin;                    // pin number that this unit information is for
    uint32_t pulsesPerUnit;         // number of pulses counted per unit
    uint32_t pulsesPerUnitDiv;      // divisor for ppu
    char unit[MAX_UNIT];            // unit e.g. "l" or "kWh"
    uint32_t flowUnitFactor;        // to get from secounds to minutes or hours as desired
    char flowUnit[MAX_UNIT];        // flow unit e.g. "7/h" or "W"
    uint32_t intervalStart;
    uint32_t lastCount;
} printData_t;
printData_t printData;


void initPinVars(pinData_t *pd, uint32_t now) {
    uint8_t level = 0;
    pd->pinName        = FF;        // inactive
    pd->initialized    = false;     // no pulse seen yet
    pd->pulseWidthMin  = 0;         // min pulse length
    pd->counter        = 0;         // counters to 0
    pd->counterIgn     = 0;    
    pd->lastCount      = 0;
    pd->rejectCounter  = 0;        
    pd->lastRejCount   = 0;
    pd->intervalStart  = now;       // time vars
    pd->intervalEnd    = now;
    pd->lastChange     = now;
    pd->lastReport     = now;
    pd->reportSequence = 0;
    if (!pd->analogFlag)
        level = digitalRead(pin2GPIO(pd->pinName));
    pd->lastLevel = level;
    pd->lastLongLevel = level;
    pd->lastDebugLevel = level;     // for debug output
}


void initHistVars() {
    histIndex = 0;
    histNextSeq = 1;
    for (uint8_t hIdx=0; hIdx < MAX_HIST; hIdx++) {
        histData_t *hd = &histData[hIdx];
        hd->seq = 0;
        hd->pin = FF;
        hd->level = 0;
        hd->time = 0;
        hd->len = 0;
        hd->act = ' ';
    }
}

void initialize() {
    uint32_t now = millis();
    bootTime = now;             // with boot / reset time
    bootWraps = millisWraps;    
    lastReportCall = now;       // time for first output after intervalMin from now
    analogReadLast = now;
    histLastOut = 0;
    lastTimeMillis = now;

    enableHistory = 0;          // pin change history
    enableSerialEcho = 0;       // echo tcp output on serial
    enablePinDebug = 0;         // show digital pin changes
    enableAnalogDebug = 0;      // analog changes
    enableDevTime = 0;          // show device time 


    maxPinIndex = 0;
    maxAnalogIndex = 0;
    analogReadState = 0;
    initHistVars();
    for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++)
        initPinVars(&pinData[pinIndex], now);                   // not necessary but initialize anyway
#if defined TFT_DISPLAY        
    displayMode = 1;
    printData.intervalStart = now;
    printData.lastCount = 0;
    lastPrintFlowCall = now;    
#endif    
#if defined(__AVR_ATmega328P__)        
    for (uint8_t aPin=0; aPin < MAX_APIN; aPin++)
        pinIndexMap[aPin] = FF;
#endif        
#if defined(WifiSupport)
    lastKeepAlive = now;
    serverStarted = false;
    lastReconnectTry = now;
    delayedTcpReports = 0;     
    lastDelayedTcpReports = 0; 
    reconnects = 0;
#endif      
    restoreFromEEPROM();
    clearInput();
}


// search pinData for aPin and return the pinIndex
uint8_t findInPin (uint8_t aPin) {
    for (uint8_t pinIndex = 0; pinIndex < maxPinIndex; pinIndex++) {
        if (pinData[pinIndex].pinName == aPin) return pinIndex;
    }
    return FF;
}

// search analogData for oPin and return the analogIndex
uint8_t findOutPin (uint8_t oPin) {
    for (uint8_t analogIndex = 0; analogIndex < maxAnalogIndex; analogIndex++) {
        if (analogData[analogIndex].outPinName == oPin) return analogIndex;
    }
    return FF;
}

// check if pin is allowed
bool checkPin (uint8_t aPin) {
    if (aPin >= MAX_APIN) return false;                     // pin number too big
    if (pin2GPIO(aPin) == FF) return false;      // pin is not allowed at all
    return true;
}


// find analogData for given pinData
uint8_t findAnalogData(pinData_t *pd) {
    for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++) {
        if (analogData[aIdx].inPinData == pd) 
            return aIdx;
    }
    return FF;
}


void clearInput() {
        commandDataPointer = 0;
        commandDataSize = 0;
        commandValue = 0;
        for (uint8_t i=0; i < MAX_INPUT_NUM; i++)
            commandData[i] = 0;     
}


void PrintErrorMsg() {
    Output->print(F("Error: "));
    Output->print(F("command "));
    Output->print(commandLetter);
    Output->print(F(" "));
}

void PrintPinErrorMsg(uint8_t aPin) {
    PrintErrorMsg(); 
    Output->print(F("Illegal pin specification "));
    Output->println(aPin);
}    


void printVersionMsg() {  
    uint8_t len = strlen_P(versionStr);
    char myChar;
    for (unsigned char k = 0; k < len; k++) {
        myChar = pgm_read_byte_near(versionStr + k);
        Output->print(myChar);
    }
    Output->print(F(" on "));
#if defined(__AVR_ATmega328P__) || defined(__AVR_ATmega168__)
#if defined (ARDUINO_AVR_NANO)
    Output->print(F("NANO"));
#else 
    Output->print(F("UNO"));
#endif
#elif defined(__AVR_ATmega32U4__) || defined(__AVR_ATmega16U4__)
    Output->print(F("Leonardo"));
#elif defined(__AVR_ATmega1280__) || defined(__AVR_ATmega2560__)
    Output->print(F("Mega"));
#elif defined(ESP8266)
    Output->print(F("ESP8266"));
#elif defined(ESP32)
    Output->print(F("ESP32"));
#else
    Output->print(F("UNKNOWN"));
#endif
#if defined (ARDUINO_BOARD)
    Output->print(F(" "));
    Output->print(F(ARDUINO_BOARD));
#endif
#if defined (TFT_DISPLAY)
    Output->print(F(" with display"));
#endif
    Output->print(F(" compiled "));
    Output->print(F(__DATE__ " " __TIME__));
#if defined(ESP8266)
#if defined (ARDUINO_ESP8266_RELEASE)
    Output->print(F(" with core version "));
    Output->print(F(ARDUINO_ESP8266_RELEASE));
#endif
#if defined (ARDUINO_ESP32_RELEASE)
    Output->print(F(" with core version "));
    Output->print(F(ARDUINO_ESP32_RELEASE));
#endif
#endif    
}


void printPinChangeDebug(pinData_t *pd, uint8_t pinState) {
    pd->lastDebugLevel = pinState;
    Output->print(F("M pin "));       Output->print(pd->pinName);
    Output->print(F(" changed to ")); Output->print(pinState);
    Output->print(F(", histIdx "));   Output->print(histIndex);
    Output->print(F(" seq "));        Output->print(histData[histIndex].seq);
    Output->print(F(", count "));     Output->print(pd->counter);
    Output->print(F(", reject "));    Output->print(pd->rejectCounter);
    Output->println();
}


bool checkVal(uint8_t index, uint16_t min, uint16_t max = 0, bool doErr = true) {
    if (index >= commandDataSize) {
        if (doErr) {
            PrintErrorMsg();
            Output->print(F("missing parameter number ")); Output->println(index+1);
        }
        return false;
    }
    if (commandData[index] < min || (max > 0 && commandData[index] > max)) {
        PrintErrorMsg();
        Output->print(F("parameter number ")); Output->print(index+1);
        Output->print(F(" (value "));          Output->print(commandData[index]);
        Output->println(F(") is out of bounds"));
        return false;
    }
    return true;
}


/*
   do counting and set start / end time of interval.
   reporting is not triggered from here.
   
   only here counter[] is modified
   intervalEnd[] is set here and in report
   intervalStart[] is set in case a pin was not initialized yet and in report
*/
static void doCount(pinData_t *pd, uint8_t level, uint16_t analogLevel=0) {
    uint32_t now = millis();
    uint32_t len = now - pd->lastChange;
    char act = ' ';
    if (len < pd->pulseWidthMin) {                      // len is too short
        if (pd->lastLevel == pd->pulseLevel) {          // if change to gap level (we just had a too short pulse)
            act = 'R';                                  // -> reject
            pd->rejectCounter++;                       
        } else {                                        // change to pulse level (we just had a too short gap)
            act = 'X';                                  // -> reject gap / set action to X (gap too short)
        }
    } else {    // len is big enough
        if (pd->lastLevel != pd->pulseLevel) {          // edge fits pulse start, level is pulse, before was gap
            act = 'G';                                  // -> gap (even if betw. was a spike that we ignored)
        } else {                                        // edge is a change to gap, level is now gap
            if (pd->lastLongLevel != pd->pulseLevel) {  // last valid level was gap, now pulse 
                act = 'C';                              // -> count
                pd->counter++;                          
                pd->intervalEnd = now;                  // remember time in case pulse is last in the interval
                if (!pd->initialized) {
                    pd->intervalStart = now;            // if first impulse on this pin -> start interval now
                    printData.intervalStart = now;
                    pd->initialized = true;             // and start counting the next impulse (counter is 0)
                    pd->counterIgn++;                   // count ignored for diff because defines start of intv
                }
                pd->pulseWidthSum += len;               // for average calculation
            } else {                                    // last valid level was pulse -> now another valid pulse
                act = 'P';                              // -> pulse was already counted, only short drop inbetween
                pd->pulseWidthSum += len;               // for average calculation
            }
        }       
        pd->lastLongLevel = pd->lastLevel;              // remember this valid level as lastLongLevel
    }
    if (enableHistory) {
        if (++histIndex >= MAX_HIST) histIndex = 0;
        histData_t *hd = &histData[histIndex];              // write pin history
        hd->seq   = histNextSeq++;                          // fhem side detects wrapping
        hd->pin   = pd->pinName;
        hd->time  = pd->lastChange;
        hd->level = pd->lastLevel;
        hd->aLvl  = analogLevel;
        hd->len   = len;
        hd->act   = act;
    }
    pd->lastChange = now;
    pd->lastLevel  = level;
}


/* Interrupt handlers and their installation  */


#if defined(ESP8266) || defined(ESP32)
void IRAM_ATTR ESPISR(void* arg) {                      // common ISR for all Pins on ESP
    // ESP32 now also defines IRAM_ATTR as ICACHE_RAM_ATTR
    pinData_t *pd = (pinData_t *)arg;
    doCount(pd, digitalRead(pin2GPIO(pd->pinName)));
}
#endif


/* Add a pin to be handled */
uint8_t AddPinChangeInterrupt(uint8_t pinIndex) {
    uint8_t aPin = pinData[pinIndex].pinName;
    uint8_t rPin = pin2GPIO(aPin);
#if defined(ESP8266) || defined(ESP32)
    attachInterruptArg(digitalPinToInterrupt(rPin), ESPISR, &pinData[pinIndex], CHANGE);
#elif defined(__AVR_ATmega328P__)
    volatile uint8_t *pcmask;                       // pointer to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
    uint8_t bitM = digitalPinToBitMask(rPin);       // mask to bit in PCMSK to enable pin change interrupt for this arduino pin 
    uint8_t port = digitalPinToPort(rPin);          // port that this arduno pin belongs to for enabling interrupts
    if (port == NOT_A_PORT) 
        return 0;
    pinIndexMap[aPin] = pinIndex;
    port -= 2;                                      // from port (PB, PC, PD) to index in our array
    PCintLast[port] = *portInputRegister(port+2);   // save current inut state to detect changes in isr
    pcmask = port_to_pcmask[port];                  // point to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
    *pcmask |= bitM;                                // set the pin change interrupt mask through a pointer to PCMSK0 or 1 or 2 
    PCICR |= 0x01 << port;                          // enable the interrupt
#endif    
    return 1;
}


/* Remove a pin to be handled */
uint8_t RemovePinChangeInterrupt(uint8_t pinIndex) {
    uint8_t aPin = pinData[pinIndex].pinName;
    uint8_t rPin = pin2GPIO(aPin);
#if defined(ESP8266) || defined(ESP32)
    detachInterrupt(digitalPinToInterrupt(rPin));
#elif defined(__AVR_ATmega328P__)
    volatile uint8_t *pcmask;
    uint8_t bitM = digitalPinToBitMask(rPin);
    uint8_t port = digitalPinToPort(rPin);
    if (port == NOT_A_PORT)
        return 0;
    pinIndexMap[aPin] = FF;
    port -= 2;                                  // from port (PB, PC, PD) to index in our array
    pcmask = port_to_pcmask[port];          
    *pcmask &= ~bitM;                           // clear the bit in the mask.
    if (*pcmask == 0) {                         // if that's the last one, disable the interrupt.
        PCICR &= ~(0x01 << port);
    }
#endif    
    return 1;
}


#if defined(__AVR_ATmega328P__)
/* 
   common function for arduino pin change interrupt handlers. 
   "port" is the PCINT port index (0-2) as passed from above, 
   not PB, PC or PD which are mapped to 2-4
*/
static void PCint(uint8_t port) {
    uint8_t bit;
    uint8_t curr;
    uint8_t delta;
    short pinIndex;

    // get the pin states for the indicated port.
    curr  = *portInputRegister(port+2);                         // current pin states at port (add 2 to get from index to PB, PC or PD)
    delta = (curr ^ PCintLast[port]) & *port_to_pcmask[port];   // xor gets bits that are different and & screens out non pcint pins
    PCintLast[port] = curr;                                     // store new pin state for next interrupt
    if (delta == 0) return;                                     // no handled pin changed 
    
    // the printed pin numbers for the ports are sequential, starting with 8, 14 and 0 which we keep in an array
    bit = 0x01;                                                 // start mit rightmost (least significant) bit in a port
    for (uint8_t aPin = firstPin[port]; aPin <= lastPin[port]; aPin++) { // loop over each pin on the given port that changed - todo: until bit == 0 ??
        if (delta & bit) {                                      // did this pin change?
            pinIndex = pinIndexMap[aPin];
            if (pinIndex != FF)                                 // shound not be necessary but test anyway
                doCount (&pinData[pinIndex], ((curr & bit) > 0));    // do the counting, history and so on
        }
        bit = bit << 1;                                         // shift mask to go to next bit
    } 
}


ISR(PCINT0_vect) {
    PCint(0);
}
ISR(PCINT1_vect) {
    PCint(1);
}
ISR(PCINT2_vect) {
    PCint(2);
}

#endif


void printAvailablePins() {
    Output->print(F("C"));
    boolean first = true;
    for (uint8_t aPin=0; aPin < MAX_APIN; aPin++)
        if (pin2GPIO(aPin) != FF) {
            if (!first)
                Output->print(F(","));
            first = false;
            Output->print(aPin);            // show available pins
        }
    Output->println();
}


void printTime(uint32_t now) {
    Output->print(F("N")); Output->print(now);
    Output->print(F(",")); Output->print(millisWraps);
    Output->print(F("B")); Output->print(bootTime);
    Output->print(F(",")); Output->print(bootWraps);    
    Output->println();
}
    

void printIntervals() {
    Output->print(F("I"));  Output->print(intervalMin / 1000);
    Output->print(F(","));  Output->print(intervalMax / 1000);
    Output->print(F(","));  Output->print(intervalSml / 1000);
    Output->print(F(","));  Output->print(countMin);
    Output->print(F(","));  Output->print(analogReadInterval);
    Output->print(F(","));  Output->print(analogReadSamples);
    Output->println();
}


void printVerboseFlags() {
    Output->print(F("V")); Output->print(enableHistory);     
    Output->print(F(",")); Output->print(enableSerialEcho);  
    Output->print(F(",")); Output->print(enablePinDebug);
    Output->print(F(",")); Output->print(enableAnalogDebug);
    Output->print(F(",")); Output->print(enableDevTime);
    Output->println();
}
    

#ifdef TFT_DISPLAY
void printUnitConfig() {
    Output->print(F("U")); Output->print(printData.pin);     
    Output->print(F(",")); Output->print(printData.pulsesPerUnit);  
    Output->print(F(",")); Output->print(printData.pulsesPerUnitDiv);  
    Output->print(F(",")); Output->print(printData.unit);
    Output->print(F(",")); Output->print(printData.flowUnitFactor);  
    Output->print(F(",")); Output->print(printData.flowUnit);
    Output->println();
}
#endif


void printPinConfig(pinData_t *pd) {
    Output->print(F("P"));  Output->print(pd->pinName);
    switch (pd->pulseLevel) {
        case 1:  Output->print(F("r")); break;
        case 0: Output->print(F("f")); break;
        default: Output->print(F("-")); break;
    }        
    if (pd->pullupFlag) 
        Output->print(F("p"));
    Output->print(F(" m"));  Output->print(pd->pulseWidthMin);
    if (pd->analogFlag) {
        uint8_t analogIndex = findAnalogData(pd);           // reuse or create analog entry for aPin with oPin
        if (analogIndex != FF) {
            analogData_t *ad = &analogData[analogIndex];
            Output->print(F("out"));  Output->print(ad->outPinName);
            Output->print(F("t"));  Output->print(ad->thresholdMin);
            Output->print(F("/"));  Output->print(ad->thresholdMax);
        }
    }
}


#if defined(TFT_DISPLAY)
void printTFTFlow(uint32_t timeDiff, uint32_t countDiff) {
    char fs[10];
    float flow;
    if (timeDiff != 0 && printData.pulsesPerUnit != 0 && printData.pulsesPerUnitDiv != 0) {
        flow = ((float)countDiff * 1000 * printData.flowUnitFactor) 
                        / (timeDiff * (printData.pulsesPerUnit / printData.pulsesPerUnitDiv));
    } else {
        flow = 0;
    }
    tft.fillRect(0,64,TFT_HEIGHT, TFT_WIDTH-64, TFT_BLACK);
    tft.setCursor(0, 64);
    tft.setTextColor(TFT_GREEN, TFT_BLACK);
    if (flow < 10000 && flow > -1000) {
        sprintf (fs, "%07.2f", flow);
        tft.setTextFont(7);
        tft.setTextSize(1);
        tft.print(fs);
        tft.setTextFont(2);
        tft.setTextSize(1);
        tft.print(printData.flowUnit);
    } else {
        tft.setTextFont(4);
        tft.setTextSize(1);
        tft.print(F("flow too big"));
    }
}
#endif


void printPinHistory(pinData_t *pd, uint32_t now) {
    histData_t *hd;
    uint8_t start = (histIndex + 2) % MAX_HIST;                             // start two after current slot in ring buffer
    uint8_t count = 0;
    uint8_t first = 0;
    uint8_t pinName = pd->pinName;

    for (uint8_t i = 0; i < MAX_HIST; i++) {
        hd = &histData[(start + i) % MAX_HIST];                             // entry relative to start in ring
        if (hd->pin == pinName && ((long int)hd->seq - histLastOut) > 0) {  // are there entries for this pin at all?
            count++;
            first = i;
            break;
        }
    }
    if (!count) { 
      // Output->println (F("M No Pin History"));            
      return;
    }    
    Output->print (F("H"));  Output->print(pinName);                        // printed pin number
    Output->print (F(" "));
    for (uint8_t i = first; i < MAX_HIST; i++) {
        hd = &histData[(start + i) % MAX_HIST];
        if (hd->pin == pinName && ((long int)hd->seq - histLastOut) > 0) {  // include ignored drops / spikes
            if (i != first) Output->print (F(", "));
            Output->print (hd->seq);                                        // sequence
            Output->print (F(","));  Output->print ((long) (hd->time - now)); // time when level started
            Output->print (F(":"));  Output->print (hd->len);               // length 
            Output->print (F("@"));  Output->print (hd->level);             // level (0/1)
            if (pd->analogFlag) {
                Output->print (F("/"));  Output->print (hd->aLvl);          // analog level
            }
            Output->print (hd->act);                                        // action
            histLastOut = hd->seq;
        }
    }        
    Output->println();    
}


/*
   lastCount and lastRejCount are only modified here (counters at time of last reporting)
   intervalEnd is modified here and in ISR - disable interrupts in critcal moments to avoid garbage in var
   intervalStart is modified only here or for very first Interrupt in ISR
*/
void printPinCounter(pinData_t *pd, boolean showOnly, uint32_t now) {
    uint32_t count, countDiff, realDiff;
    uint32_t startT, endT, timeDiff, widthSum;
    uint16_t rejCount, rejDiff;
    uint8_t countIgn;
    
    noInterrupts();                             // copy counters while they cant be changed in isr
    startT   = pd->intervalStart;               // start of interval (typically first pulse)
    endT     = pd->intervalEnd;                 // end of interval (last unless not enough)
    count    = pd->counter;                     // get current counter (counts all pulses
    rejCount = pd->rejectCounter;
    countIgn = pd->counterIgn;                  // pulses that mark the beginning of an interval
    widthSum = pd->pulseWidthSum;
    interrupts();
        
    timeDiff  = endT - startT;                  // time between first and last impulse
    realDiff  = count - pd->lastCount;          // pulses during intervall
    countDiff = realDiff - countIgn;            // ignore forst pulse after device restart
    rejDiff   = rejCount - pd->lastRejCount;
    
    if (!showOnly) {                            // real reporting sets the interval borders new
        if((now - pd->lastReport) > intervalMax) { 
            // intervalMax is over
            if ((countDiff >= countMin) && (timeDiff > intervalSml) && (intervalMin != intervalMax)) {
                // normal procedure
                noInterrupts();                 // vars could be modified in ISR as well
                pd->intervalStart = endT;       // time of last impulse becomes first in next
                interrupts();
            } else {
                // nothing counted or counts happened during a fraction of intervalMin only
                noInterrupts();                 // vars could be modified in ISR as well
                pd->intervalStart = now;        // start a new interval for next report now
                pd->intervalEnd   = now;        // no last impulse, use now instead
                interrupts();
                timeDiff  = now - startT;       // special handling - calculation ends now
            }        
        } else if (((now - pd->lastReport) > intervalMin)   
                    && (countDiff >= countMin) && (timeDiff > intervalSml)) {
            // minInterval has elapsed and other conditions are ok
            noInterrupts();                     // vars could be modified in ISR as well
            pd->intervalStart = endT;           // time of last also time of first in next
            interrupts();
        } else {
          return;                               // intervalMin and Max not over - dont report yet
        }
        noInterrupts(); 
        pd->counterIgn    = 0;
        pd->pulseWidthSum = 0;
        interrupts();
        pd->lastCount    = count;               // remember current count for next interval
        pd->lastRejCount = rejCount;
        pd->lastReport   = now;                 // remember when we reported
#if defined(WifiSupport)
        delayedTcpReports      = 0;
#endif
        pd->reportSequence++;
    } else {
        Output->print(F("D"));                  // prefix with "D" if showOnly so it is not parsed as report line
    }
    Output->print(F("R")); Output->print(pd->pinName);
    Output->print(F("C")); Output->print(count);
    Output->print(F("D")); Output->print(countDiff);
    Output->print(F("/")); Output->print(realDiff);
    Output->print(F("T")); Output->print(timeDiff);  
    
    //Output->print(F("N")); Output->print(now);          // moved to its own line N... dependent on new flag that time should be reported at all
    //Output->print(F(",")); Output->print(millisWraps);    
    
    Output->print(F("X")); Output->print(rejDiff);  
    
    if (!showOnly) {
        Output->print(F("S")); Output->print(pd->reportSequence);  
    }
    if (countDiff > 0) {
        Output->print(F("A")); Output->print(widthSum / countDiff);
    }
    Output->println();    
#if defined(WifiSupport)
    if (enableSerialEcho && tcpMode && !showOnly) {
        Serial.print(F("D reported pin "));  Serial.print(pd->pinName);
        Serial.print(F(" sequence "));       Serial.print(pd->reportSequence);  
        Serial.println(F(" over tcp "));  
    }
#endif  
#if defined(TFT_DISPLAY)
    if (displayMode == 1) {
        if (lineCount < 4) {
            tft.setTextFont(2);
            tft.setTextSize(1);
            tft.setTextColor(TFT_GREEN, TFT_BLACK);
            tft.setCursor(0,48+16*lineCount);               // todo: how can this be separated from report? (timing)
            tft.print(F("R"));  tft.print(pd->pinName);
            tft.print(F(" C")); tft.print(count);
            tft.print(F(" D")); tft.print(countDiff);
            tft.print(F("/"));  tft.print(realDiff);
            tft.print(F(" T")); tft.print(timeDiff);  
            tft.print(F(" X")); tft.print(rejDiff);  
            lineCount++;
        }
    } else if (displayMode == 3) {
        if (pd->pinName == printData.pin) 
            printTFTFlow(timeDiff, countDiff);
    }
#endif  
}


#if defined(WifiSupport)
// called from show and new connectinn
void printWifiState(Print *Out) {
    if (WiFi.status() == WL_CONNECTED) {
        Out->print(F("D Connected to "));   Out->print(WiFi.SSID());    
        Out->print(F(" with IP "));         Out->print(WiFi.localIP());    
        Out->print(F(" RSSI "));            Out->print(WiFi.RSSI());
        Out->println();
    } else {
        Out->println(F("D Wifi not connected"));
    }
#if defined(TFT_DISPLAY)
    if (displayMode > 0) {
        //tft.fillRect(0, 0, TFT_HEIGHT, 31, TFT_BLACK);       // oberen Teil löschen
        tft.fillScreen(TFT_BLACK);                              // clear Wifi manager output as well
        tft.setTextFont(2);
        tft.setTextSize(1);
        tft.setTextColor(TFT_GREEN, TFT_BLACK);
        tft.setCursor(0, 0);
        if (WiFi.status() == WL_CONNECTED) {
            tft.print(F("Connected to ")); tft.print(WiFi.SSID());
            tft.setCursor(0, 16);
            tft.print("IP ");       tft.print(WiFi.localIP());
            tft.print(F(" RSSI ")); tft.print(WiFi.RSSI());
        } else {
            tft.print(F("Wifi not Connected"));
            tft.setCursor(0, 16);
            tft.print(F("Retry "));
            tft.print(reconnects);
        }
    }
#endif
}
#endif


/* 
   report count and time for pins that are between min and max interval    
*/

bool reportDue(uint32_t now) {
    if((now - lastReportCall) > intervalMin)            // works fine when millis wraps.
        return true;                                    // intervalMin is over 
    else 
        for (uint8_t pinIndex=0; pinIndex < maxPinIndex; pinIndex++)  
            if((now - pinData[pinIndex].lastReport) > intervalMax)
                return true;                            // active pin has not been reported for langer than intervalMax
    return false;
}


bool delayIfDisconnected(uint32_t now) {
#if defined(WifiSupport)
    if (tcpMode && !TCPconnected && (delayedTcpReports < 3)) {
        if(delayedTcpReports == 0 || ((now - lastDelayedTcpReports) > 30000)) {
            if (enableSerialEcho) {
                Serial.print(F("D report called but tcp is disconnected - delaying ("));
                Serial.print(delayedTcpReports); Serial.print(F(")"));
                Serial.print(F(" now "));  Serial.print(now);
                Serial.print(F(" last ")); Serial.print(lastDelayedTcpReports);
                Serial.print(F(" diff ")); Serial.print(now - lastDelayedTcpReports);
                Serial.println();        
            }
            delayedTcpReports++;
            lastDelayedTcpReports = now;
            return true;        // continue delaying after message
        } else 
            return true;        // another 30 secs not over yet, just continue delaying without message
    }
#endif    
    return false;               // not TCP mode -> no delays anyway
}


#if defined(TFT_DISPLAY)
void handleTFTReport(uint32_t now) {
    lineCount = 0;              // for mode 0 where lines of pin reports are printed
    if (displayMode == 2 && ((now - lastPrintFlowCall) > 5000)) {
        lastPrintFlowCall = now;

        uint8_t pinIndex = findInPin(printData.pin); 
        if (pinIndex == FF)                         // not used so far
            return;
        pinData_t *pd = &pinData[pinIndex];         // pinData entry to work with

        uint32_t countDiff = pd->counter - printData.lastCount - pd->counterIgn;      // ignore first pulse after device restart
        uint32_t timeDiff = pd->intervalEnd - printData.intervalStart;                // time between first and last impulse
        printData.lastCount = pd->counter;
        printData.intervalStart = pd->intervalEnd;
        printTFTFlow(timeDiff, countDiff);
    }
}
#endif


void report() {
    uint32_t now = millis();
#if defined(TFT_DISPLAY)
    handleTFTReport(now);
#endif
    if (!reportDue(now)) return;
    if (delayIfDisconnected(now)) return;
    for (uint8_t pinIndex=0; pinIndex < maxPinIndex; pinIndex++) {  // go through all observed pins as pinIndex
        pinData_t *pd = &pinData[pinIndex];
        printPinCounter (pd, false, now);                           // report pin counters if necessary
        if (enableHistory) 
            printPinHistory(pd, now);                               // show pin history todo: call outside of report
    }
    lastReportCall = now;                                           // check again after intervalMin or if intervalMax is over for a pin
}


void updateEEPROM(int &address, char value) {
    if( EEPROM.read(address) != value){
        EEPROM.write(address, value);
    }
    address++;
}


void save(int &address, uint16_t n, bool komma=true) {
    char b[6];
    sprintf(b, "%u", n);
    uint8_t len = strlen(b);
    if (len < 6)
        for (uint8_t i=0; i<len; i++) 
            updateEEPROM(address, b[i]);
    if(komma)
        updateEEPROM(address, ',');
}

// store a string as sequence of text coded integers
void saveStr(int &address, char *s, uint8_t komma=1) {
    uint8_t cCount = 0;
    uint8_t byteNum = 0;
    uint16_t val;
    bool first = true;
    while (cCount < MAX_UNIT && *(s+cCount) != 0) {
        if (byteNum) {
            val = (*(s+cCount) << 8) + val;         // second char -> add as high byte
            if (!first) updateEEPROM(address, ',');
            save(address, val, false);
            first = false;
            byteNum = 0;
        } else {
            val = *(s+cCount);                      // first char
            byteNum++;
        }
        cCount++;
    }
    if (byteNum) {
        if (!first) updateEEPROM(address, ',');
        save(address, val, false);
        if (!val) {
            updateEEPROM(address, ',');
            save(address, 0, false);
        }
    }
    if (komma)
        updateEEPROM(address, ',');
}


void CmdSaveToEEPROM() {
    int a = 0;
    updateEEPROM(a, 'C');
    updateEEPROM(a, 'f');
    updateEEPROM(a, '2');
    save(a,intervalMin / 1000); save(a,intervalMax / 1000);
    save(a,intervalSml / 1000); save(a,countMin); 
    save(a,analogReadInterval); save(a,analogReadSamples,false); 
    updateEEPROM(a, 'i');
    
    save(a,enableHistory); save(a,enableSerialEcho); 
    save(a,enablePinDebug); save(a,enableAnalogDebug); 
    save(a,enableDevTime,false); 
    updateEEPROM(a, 'v');

#if defined TFT_DISPLAY
    save(a,printData.pin);  
    save(a,printData.pulsesPerUnit); save(a,printData.pulsesPerUnitDiv); 
    saveStr(a,printData.unit);           
    save(a,printData.flowUnitFactor); saveStr(a,printData.flowUnit,false); 
    updateEEPROM(a, 'u');
#endif    

    for (uint8_t pinIndex=0; pinIndex < maxPinIndex; pinIndex++) {
        pinData_t *pd = &pinData[pinIndex];
        uint8_t analogIndex = findAnalogData(pd);       // find analog entry (if exists)                    
        if (pd->analogFlag && analogIndex != FF) {
            analogData_t *ad = &analogData[analogIndex];
            save(a,pd->pinName);    save(a,pd->pulseLevel ? 3:2);
            save(a,pd->pullupFlag); save(a,pd->pulseWidthMin);
            save(a,ad->outPinName); save(a,ad->thresholdMin); save(a,ad->thresholdMax,false);
            updateEEPROM(a, 'a');
        } else {
            save(a,pd->pinName);    save(a,pd->pulseLevel ? 3:2);
            save(a,pd->pullupFlag); save(a,pd->pulseWidthMin,false);
            updateEEPROM(a, 'a');
        }
    }
    updateEEPROM(a, 0);
#if defined(ESP8266) || defined(ESP32)
    EEPROM.commit();               
#endif  
    Output->println(F("D config saved"));
}


void printEEPROM() {
    int address = 0;
    char c; 
    if (EEPROM.read(address) != 'C' || EEPROM.read(address+1) != 'f' || EEPROM.read(address+2) != '2') {
        Output->println(F("D no config in EEPROM"));
        return;
    }
    address = 3;
    Output->print(F("D EEPROM Config: "));
    while (address < 512 && (c = EEPROM.read(address++)) != 0) {
        Output->print(c);        
    }
    Output->println();
}


void restoreFromEEPROM() {
    int address = 0;
    char c;
    if (EEPROM.read(address) != 'C' || EEPROM.read(address+1) != 'f' || EEPROM.read(address+2) != '2') {
        Output->println(F("M no config in EEPROM"));
        return;
    }
    address = 3;
    Output->println(F("M restoring config from EEPROM: "));
    while (address < 512 && (c = EEPROM.read(address++)) != 0) {
        handleInput(c);
        Output->print(c);
    }
    Output->println();
#if defined(TFT_DISPLAY) 
    if (displayMode == 1) {
        tft.setTextFont(2);
        tft.setTextSize(1);
        tft.setTextColor(TFT_GREEN, TFT_BLACK);
        tft.setCursor(0, 32);
        tft.print(F("Pin config loaded"));
    }
#endif
}


void CmdInterval() {
    if (!checkVal(0,1,3600)) return;                    // index 0 is interval min, min 1, max 3600 (1h)
    if (!checkVal(1,1,3600)) return;                    // index 1 is interval max, min 1, max 3600 (1h)
    if (!checkVal(2,0,3600)) return;                    // index 2 is interval small, max 3600 (1h)
    if (!checkVal(3,0,100))  return;                    // index 3 is count min, max 100

    intervalMin = commandData[0] * 1000;      // convert to miliseconds
    intervalMax = commandData[1] * 1000;
    intervalSml = commandData[2] * 1000;
    countMin    = commandData[3];
        
    if (checkVal(4,0,10000,false)) {                          // index 4 is optional analog read interval
        analogReadInterval = (int)commandData[4];
    }
    if (checkVal(5,1,100,false)) {                      // index 5 is optional analog read samples
        analogReadSamples = (uint8_t)commandData[5];
    }
    printIntervals();
}


// for backward compatibility - set thresholds for all analog pins at the same time
void CmdThreshold() {    
    if (!checkVal(0,1,1023)) return;                            // analog threshold min, min 1, max 1023
    if (!checkVal(1,1,1023)) return;                            // analog threshold max, min 1, max 1023
    for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++)
        analogData[aIdx].thresholdMin = commandData[0]; 
    for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++)
        analogData[aIdx].thresholdMax = commandData[1];

    Output->print(F("D analog thresholds set to ")); Output->print(commandData[0]);
    Output->print(F(" ")); Output->println(commandData[1]);
}


/*
    handle add command.
*/
void CmdAdd () {
    uint8_t aPin = commandData[0];              // commandData[0] is pin number
    if ( commandData[0] > 255                   // more than one byte?
         || !checkPin(aPin)                     // is pin allowed?
         || (ledOutPin && aPin == ledOutPin)    // is pin used as led out?
         || findOutPin(aPin) != FF)  {          // is pin used as output so far?
        PrintPinErrorMsg(aPin);
        return;
    }
    uint8_t rPin = pin2GPIO(aPin);              // get gpio pin number for later use
    uint8_t pinIndex = findInPin(aPin);         // is pin already in use counting?
    if (pinIndex == FF) {                       // not used so far
        pinIndex = maxPinIndex;                 // use next available index
        initPinVars(&pinData[pinIndex], millis());
    }
    pinData_t *pd = &pinData[pinIndex];         // pinData entry to work with

    if (!checkVal(1,2,3)) return;               // index 1 is pulse level, min 2, max 3, std error
    pd->pulseLevel = (commandData[1] == 3);     // 2 = falling -> pulseLevel 0, 3 = rising -> pulseLevel 1
    pd->pinName = aPin;                         // save printed pin number for reporting

    if (checkVal(2,0,1, false))                 // index 2 is pullup, optional, no error message if omitted
        pd->pullupFlag = commandData[2];        // as defined
    else pd->pullupFlag = 0;                    // default to no pullup

    if (!checkVal(3,1,1000, false)) 
        commandData[3] = 2;                     // value 3 is min length, optional. Assume default 2 if invalid
    pd->pulseWidthMin = commandData[3];
    
    if (checkVal(4,1,MAX_APIN, false)) {        // 4 - analog out pin number given
        uint8_t oPin = commandData[4];
        if (!checkPin(oPin) || (ledOutPin && oPin == ledOutPin) || findInPin(oPin) != FF)  {          
            PrintPinErrorMsg(oPin);             // pin alreday used as input or ledout (analog out would be ok)
            return;
        }
        uint8_t analogIndex = findAnalogData(pd);           // reuse or create analog entry for aPin with oPin
        if (analogIndex == FF) {
            if (maxAnalogIndex < MAX_ANALOG) {
                analogIndex = maxAnalogIndex++;             // new entry -> initialize, inc used analog pins 
                analogData_t *ad = &analogData[analogIndex];
                ad->thresholdMin = 0;
                ad->thresholdMax = 0;
                ad->inPinData = pd;
            } else {
                PrintErrorMsg();
                Output->println(F("too many analog pins"));
                return;
            }
        }
        pd->analogFlag = 1;                                 // set analog flag
        analogData_t *ad = &analogData[analogIndex];
        ad->inPinName = aPin;
        ad->outPinName = oPin;
        pinMode (rPin, INPUT);
        pinMode (pin2GPIO(oPin), OUTPUT);
        
        if (checkVal(5,1,1023))                             // analog threshold min, min 1, max 1023
            ad->thresholdMin = commandData[5];
        if (checkVal(6,1,1023))                             // analog threshold max, min 1, max 1023
            ad->thresholdMax = commandData[6];
    } else {
        if (pd->pullupFlag) pinMode (rPin, INPUT_PULLUP);
        else pinMode (rPin, INPUT); 
        AddPinChangeInterrupt(pinIndex);
    }
    pd->pinName = aPin;
    if (pinIndex == maxPinIndex) maxPinIndex++;             // increment used entries in pinData
    Output->print(F("D defined ")); printPinConfig(pd); Output->println();
}


/*
    handle remove command.
*/
void CmdRemove() {
    uint8_t aPin = commandData[0];              // commandData[0] is pin number
    uint8_t pinIndex = findInPin(aPin);
    if (commandData[0] > 255                    // too big
         || pinIndex == FF)                     // pin is currently not used as input
         return;                                
    pinData_t *pd = &pinData[pinIndex];         // config entry to work with

    if (!pd->analogFlag) {                      
        RemovePinChangeInterrupt(pinIndex);
    } else {
        // find analog data entry
        uint8_t analogIndex = FF;
        for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++) {
            if (analogData[aIdx].inPinData == pd) {
                analogIndex = aIdx;
                break;
            }
        }
        if (analogIndex != FF) {
            // copy idx +1 and following up and clear the last
            // then dec max
            for (uint8_t rIdx = analogIndex; (rIdx + 1) < maxAnalogIndex; rIdx++)
                analogData[rIdx] = analogData[rIdx + 1];
            analogData_t *lastAd = &analogData[--maxAnalogIndex];
            lastAd->inPinData = 0;
            lastAd->inPinName = 0;
            lastAd->outPinName = 0;
        }
    }
    
    for (uint8_t rIdx = pinIndex; (rIdx + 1) < maxPinIndex; rIdx++) {
        if (!pinData[rIdx].analogFlag) {
            RemovePinChangeInterrupt(rIdx+1);
        }
        pinData[rIdx] = pinData[rIdx + 1];                              // move pinData entries after pinIndex up
        if (!pinData[rIdx].analogFlag) {
            AddPinChangeInterrupt(rIdx);
        }
        
        if (pd->analogFlag) { 
            for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++) {                    
                if (analogData[aIdx].inPinData == &pinData[rIdx + 1]) 
                    analogData[aIdx].inPinData = &pinData[rIdx];
            }
        }
    }
    pinData_t *lastPd = &pinData[--maxPinIndex];                        // clear the last one that is now no longer needed
    initPinVars(lastPd, 0);    
    Output->print(F("D removed ")); Output->println(aPin);
}


void CmdClear () {
    uint8_t aPin = commandData[0];              // commandData[0] is pin number
    uint8_t pinIndex = findInPin(aPin);         // is pin in use?
    if (commandData[0] > 255                    // too big
         || pinIndex == FF) {                   // not found
        PrintPinErrorMsg(aPin);                 // no active pin
        return;
    }
    pinData_t *pd = &pinData[pinIndex];

    uint32_t now = millis();  
    pd->lastReport     = now;
    pd->lastCount      = 0;
    pd->lastRejCount   = 0;
    
    noInterrupts();
    pd->intervalStart  = pd->intervalEnd;       // time of last pulse is now time of first pulse in this new interval
    pd->counter        = 0;                     // counters to 0
    pd->counterIgn     = 0;
    pd->rejectCounter  = 0;        
    pd->pulseWidthSum  = 0;
    interrupts();
    Output->print(F("M cleared ")); Output->println(aPin);
}


/* give status report in between if requested over serial input */
void CmdShow() {
    uint32_t now = millis();  
    Output->println();
    Output->print(F("D Status: ")); printVersionMsg();
    Output->println();
    
#if defined(WifiSupport)
    printWifiState(Output);                            // print line with IP and RSSI
#endif    
    printIntervals();
    printVerboseFlags();
#if defined(TFT_DISPLAY)
    printUnitConfig();
#endif
    
    for (uint8_t pinIndex=0; pinIndex < maxPinIndex; pinIndex++) {
        pinData_t *pd = &pinData[pinIndex];
        printPinConfig(pd);
        Output->print(F(", "));
        printPinCounter(pd, true, now);
    }
    printEEPROM();
    Output->print(F("D Next report in "));              // Fhem side recognizes this as end of show command
    Output->print(lastReportCall + intervalMin - millis());
    Output->println(F(" milliseconds"));
}


void CmdHello() {
    uint32_t now = millis();
    Output->println(); 
    printVersionMsg(); Output->println(F(" Hello"));
    printTime(now);                  // print line with device time,                 e.g. N456,2 B789,3
    printAvailablePins();            // print line with available pins,              e.g. C2,3,4 ...
    printIntervals();                // print line with configured intervals,        e.g. I30,60,2,2 ...
    printVerboseFlags();             // print line with configured verbose flags,    e.g. V0,1,...
    
    for (uint8_t pinIndex=0; pinIndex < maxPinIndex; pinIndex++) { // go through all observed pins as pinIndex
        printPinConfig(&pinData[pinIndex]);
        Output->println();
    }
}


void CmdLED() {
    // set monitor ouput LED and a max of 5 pins to monitor
    // 12,2,3l would set pin 12 as LED and pins 2 and 3 to create LED switches when their level changes
    // dont allow 0, check if already used as led, if not checkPin
    uint8_t aPin = commandData[0];                   // commandData[0] is led pin number
    
    if (commandData[0] > 255 || !aPin || !checkPin(aPin) 
         || findOutPin(aPin) != FF || findInPin(aPin) != FF) {
        PrintPinErrorMsg(aPin);                 // illegal pin or already used for in/other output
        return;
    }
    // save pin and validate other params / pins to monitor
}


uint8_t stuffString(char* str, uint8_t offset) {
    uint8_t sIndex = 0;
    uint8_t byteVal;
    uint8_t cIndex; 
    for (cIndex = offset; (cIndex < MAX_INPUT_NUM) && (sIndex < MAX_UNIT-1); cIndex++) {
        uint16_t value = commandData[cIndex];
        for (uint8_t byteNum = 0; (byteNum < 2) && (sIndex < MAX_UNIT-1); byteNum++) {
            byteVal = value & 0xFF;
            if (!byteVal) break;
            value = value >> 8;
            str[sIndex++] = byteVal;
        }
        if (!byteVal) break;
    }
    str[sIndex] = 0;
    return cIndex + 1;
}


void CmdUnits() {
#if defined(TFT_DISPLAY)
    // set pulses per unit for a pin and a unit for printing consumption per minute / per hour
    uint8_t next = 1;
    uint8_t aPin = commandData[0];                          // commandData[0] is pin number to display
    if (commandData[0] > 255 
         || !aPin || !checkPin(aPin)) {                     // is pin allowed?
        PrintPinErrorMsg(aPin);
        return;
    }
    printData.pin = aPin;

    if (!checkVal(next,1))  return;                         // index 1 is pulsesPerUnit
    printData.pulsesPerUnit = commandData[next++];

    if (!checkVal(next,1))  return;                         // index 2 is pulsesPerUnitDiv
    printData.pulsesPerUnitDiv = commandData[next++];

    next = stuffString(printData.unit, next);               // unit string starting at commandData[3]

    if (!checkVal(next,1))  return;                         // index after first strng is flowUnitFactor
    printData.flowUnitFactor = commandData[next++];

    next = stuffString(printData.flowUnit, next);           // unit string starting at commandData[2]
    printUnitConfig();
#endif    
}


void CmdDevVerbose() {    
    if (!checkVal(0,0,1))  return;                  // index 0 is enableHistory
    if (!checkVal(1,0,10)) return;                  // index 1 is enableSerialEcho
    if (!checkVal(2,0,1))  return;                  // index 2 is enablePinDebug
    if (!checkVal(3,0,10)) return;                  // index 3 is enableAnalogDebug
    if (!checkVal(4,0,1))  return;                  // index 3 is enableDevTime

    enableHistory     = (uint8_t)commandData[0];
    enableSerialEcho  = (uint8_t)commandData[1];
    enablePinDebug    = (uint8_t)commandData[2];
    enableAnalogDebug = (uint8_t)commandData[3];
    enableDevTime     = (uint8_t)commandData[4];
    printVerboseFlags();
}
            
            
void CmdKeepAlive() {
    if (commandData[0] == 1 && commandDataSize > 0) {
        Output->print(F("A"));
#if defined(WifiSupport)
        uint32_t now = millis();
        Output->print(F("R")); Output->print(WiFi.RSSI());
        if (commandData[0] == 1 && commandDataSize > 0 && commandDataSize < 3 && Client1.connected()) {
            tcpMode = true;
            if (commandDataSize == 2) {
                keepAliveTimeout = commandData[1];  // timeout in seconds (on ESP side we use it times 3)
            } else {
                keepAliveTimeout = 200;             // *3 gives 10 minutes if nothing sent (should not happen)
            }
        }  
        lastKeepAlive = now;
#endif
        Output->println();
    }
}

 
void CmdQuit() {
#if defined(WifiSupport)
    if (Client1.connected()) {
        Client1.println(F("closing connection"));
        Client1.stop();
        tcpMode =  false;
        if (enableSerialEcho) 
            Serial.println(F("D TCP connection closed after Q command"));
        return;
    } 
#endif
    Serial.println(F("D TCP not connected"));
}


void CmdRestart() {
#if defined(ESP8266) || defined(ESP32)
    ESP.restart();
#endif
    // beim uno / nano ohne wlan einfach nur die Variablen zurücksetzen.
    initialize();
}


void CmdWifiReset() {
#if defined(WifiSupport)
    wifiManager.resetSettings();
#endif
}


/* theoretical issue: when connected via Wifi and serial at the same time, input might overlap */
void handleInput(char c) {
    if (c == ',') {                       // Komma input, last value is finished
        if (commandDataPointer < (MAX_INPUT_NUM - 1)) {
            commandData[commandDataPointer++] = commandValue;
            commandValue = 0;
        }
    }
    else if ('0' <= c && c <= '9') {      // digit input
        commandValue = 10 * commandValue + c - '0';
        commandDataSize = commandDataPointer + 1;
    }
    else if ('a' <= c && c <= 'z') {      // letter input is command
        commandLetter = c;
        if (commandDataPointer < (MAX_INPUT_NUM - 1)) {
            commandData[commandDataPointer] = commandValue;    
        }
    
        if (enableSerialEcho > 1) {
            Serial.print(F("D got "));
            for (short v = 0; v <= commandDataPointer; v++) {          
                if (v > 0) Serial.print(F(","));
                Serial.print(commandData[v]);
            }
            Serial.print(c);
            Serial.print(F(" size ")); Serial.println(commandDataSize);
        }

        switch (c) {
        case 'a':                       // add a pin
            CmdAdd(); break;
        case 'c':
            CmdClear(); break;          // clear a counter for pin specifid
        case 'd':                       // delete a pin
            CmdRemove(); break;
        case 'e':                       // save to EEPROM
            CmdSaveToEEPROM(); break; 

        case 'h':                       // hello
            CmdHello(); break;
        case 'i':                       // interval
            CmdInterval(); break;
        case 'k':                       // keep alive
            CmdKeepAlive(); break;   
        case 'l'    :                   // led feedback
            CmdLED(); break;   

        case 'q':                       // quit
            CmdQuit(); break; 
        case 'r':                       // reset / restart
            CmdRestart(); break;
        case 's':                       // show
            CmdShow(); break;
        case 't':                       // thresholds for analog pins (legacy - moved to a)
            CmdThreshold(); break;
        case 'u':                       // pulses per unit for local output
            CmdUnits(); break;
        case 'v':                       // dev verbose
            CmdDevVerbose(); break;
        case 'w':                       // reset wifi settings
            CmdWifiReset(); break;

        default:
            break;
        }
        clearInput();
        //Serial.println(F("D End of command"));
    }
}


void debugDigitalPinChanges() {
    for (uint8_t pinIndex=0; pinIndex < maxPinIndex; pinIndex++) {
        pinData_t *pd = &pinData[pinIndex];        
        if (!pd->analogFlag) {
            uint8_t pinState = digitalRead(pin2GPIO(pd->pinName));
            if (pinState != pd->lastDebugLevel)
                printPinChangeDebug(pd, pinState);
        }   
    }
}


#if defined(WifiSupport)   
void printWifiStatus() {
    Serial.print(F("D Wifi Status is "));
    switch (WiFi.status()) {
        case WL_CONNECT_FAILED: 
        Serial.println(F("Connect Failed")); break;
        case WL_CONNECTION_LOST: 
        Serial.println(F("Connection Lost")); break;
        case WL_DISCONNECTED: 
        Serial.println(F("Disconnected")); break;
        case WL_CONNECTED: 
        Serial.println(F("Connected")); break;
        default:
        Serial.println(WiFi.status());
    }
}


#if !defined(STATIC_WIFI)
void configModeCallback (WiFiManager *myWiFiManager) {
    Serial.println("Entered config mode");
    Serial.println(WiFi.softAPIP());
    //if you used auto generated SSID, print it
    Serial.println(myWiFiManager->getConfigPortalSSID());
#if defined(TFT_DISPLAY)
    tft.fillScreen(TFT_BLUE);
    tft.setTextFont(4);
    tft.setTextSize(1);
    tft.setTextColor(TFT_YELLOW , TFT_BLUE);
    tft.setCursor(0,32);    // x, y,   TFT_HEIGHT=240, TFT_WIDTH=135

    tft.print(F("Entered config mode      "));
    tft.setCursor(0, 100);
    tft.print(myWiFiManager->getConfigPortalSSID());
#endif
}
#endif


void initWifi() {
    TCPconnected = false;
    WiFi.mode(WIFI_STA);
    WiFi.setAutoConnect(true);
    WiFi.setAutoReconnect(true);
    delay (1000);    
    if (WiFi.status() != WL_CONNECTED) {
#if defined(STATIC_WIFI)
#if defined(TFT_DISPLAY) 
        tft.setTextFont(2);
        tft.setTextSize(1);
        tft.setTextColor(TFT_GREEN, TFT_BLACK);
        tft.setCursor(0,0);
        tft.print(F("Conecting WiFi to ")); tft.print(ssid);
#endif
        uint8_t counter = 0;
        Serial.print(F("D Connecting WiFi to ")); Serial.println(ssid);
        WiFi.begin(ssid, password);                 // connect with compiled strings
        while (WiFi.status() != WL_CONNECTED) {
            printWifiStatus();
            delay(1000);
            counter++;
            if (counter > 2) {
#if defined(TFT_DISPLAY)    
                tft.setCursor(0,0);
                tft.print(F("Retry conecting WiFi to")); tft.print(ssid);
#endif
                Serial.println(F("D Retry connecting WiFi"));
                WiFi.begin(ssid, password);         // restart connecting
                delay (1000);
                counter = 0;                        // do forever until connected with retries
            }
        }    
#else                                               // connect using WifiManager if auto reconnect not successful
#if defined(TFT_DISPLAY) 
        tft.setCursor(0,0);
        tft.print(F("try reconecting WiFi"));
#endif
        Serial.println(F("D Try reconnecting WiFi"));
        WiFi.begin();             
        delay(1000);
        printWifiStatus();
        if (WiFi.status() != WL_CONNECTED) {
#if defined(TFT_DISPLAY)    
            tft.setCursor(0,0);
            tft.print(F("Retry reconecting WiFi"));
#endif
            Serial.println(F("D Retry reconnecting WiFi"));
            WiFi.begin();         
            delay (1000);
        }            
        wifiManager.setConfigPortalBlocking(false);
        wifiManager.setAPCallback(configModeCallback);  //set callback that gets called when connecting to previous WiFi fails, and enters Access Point mode
        wifiManager.autoConnect();
#endif
    }
}


void handleConnections() { 
    IPAddress remote;   
    uint32_t now = millis();
    
    if (WiFi.status() == WL_CONNECTED && !serverStarted) {      // first call after connected
        printWifiState (&Serial);
        Server.begin();                                         // Start the TCP server
        Serial.println(F("D TCP Server started"));
        serverStarted = true;                                   // remember we did this already
    } 
    if (WiFi.status() != WL_CONNECTED) {                        // WiFi lost
        if (serverStarted) {                                    // first time we notice ...
            printWifiState (&Serial);                          // show that we lost Wifi
            Server.close();                                     // Stop  the TCP server
            serverStarted = false;                              // so printWifiState will be called after reconnect
            Serial.println(F("D Wifi lost - TCP Server stopped"));
            lastReconnectTry = now;                             // don't try to manually reconnect right now - Framework should do it
        }
        if ((now - lastReconnectTry) > 5000) {
            printWifiState (&Serial);                          // show that we lost Wifi
            Serial.println(F("D Try reconnecting WiFi"));
            WiFi.begin();                                       // try to force reconnect (framework seems to not do it sometimes...)
            lastReconnectTry = now;
            reconnects++;
        }
    }

    if (Client1.connected()) {
        if (Client1.available()) {
            handleInput(Client1.read());                        // input from TCP
            //Serial.println(F("D new Input over TCP"));
        }
        now = millis();                                         // get millis again to avoid keepalive timeout directly after first k command
        if((now - lastKeepAlive) > (keepAliveTimeout*3000)) {   // check keepAlive timout (* 3 secs)
            Serial.println(F("D no keepalive - close"));
            Output->println(F("D no keepalive - close"));   
            //Output->print(F("D timeout was "));
            //Output->print(keepAliveTimeout);
            //Output->print(F(" last at "));
            //Output->print(lastKeepAlive);
            //Output->print(F(" now "));
            //Output->print(now);
            Output->println();
            Client1.stop();                                     // close connection due to keepalive timeout 
        }
        Client2 = Server.available();                           // refuse further connect attempts
        if (Client2) {
            remote = Client2.remoteIP();
            Client2.println(F("conn busy"));
            Client2.stop();
            if (enableSerialEcho) {
                Serial.print(F("D 2nd conn from ")); Serial.print(remote);
                Serial.println(F(" rejected"));
            }
        }
    } else {    // no client connected right now
        if (TCPconnected) {                                 // client used to be connected, now disconnected
            TCPconnected = false;
            Output = &Serial;
            if (enableSerialEcho)
                Serial.println(F("D conn lost"));           // report disconnect via serial
        }
        Client1 = Server.available();
        if (Client1) {                                      // accepting new connection
            remote = Client1.remoteIP();
            if (enableSerialEcho) {
                Serial.print(F("D new conn from ")); Serial.print(remote);
                Serial.println(F(" accepted"));
            }
            TCPconnected = true;                            // remember connection in case we loose it
            Output = &Client1;
            lastKeepAlive = now;
            CmdHello();                                     // say hello to client
        }
    }
} 
#endif


void handleTime() {
    uint32_t now = millis();
    if (now < lastMillis) millisWraps++;
    lastMillis = now;

    if (enableDevTime) 
        if ((long int)now - lastTimeMillis > (int32_t)60 * 60 * 1000) {     // every 60 minutes
            printTime(now);
            lastTimeMillis = now;
        }
}


void detectTrigger(analogData_t *ad, unsigned int val) {
    uint32_t average;
    uint8_t nextState = ad->triggerState;           // initialize next trigger level to be the same as the old one 
    if (val > ad->thresholdMax) {
        nextState = 1;                              // if above upper threshold then change to 1
    } else if (val < ad->thresholdMin) {
        nextState = 0;                              // if below lower threshold then change to 0
    }
    if (ad->avgCnt <= 65000) {
        ad->avgSum += val;
        ad->avgCnt++;
    }
    if (nextState != ad->triggerState) {            // if level has changed
        average = ad->avgSum / ad->avgCnt;
        if (average > 4000) average = 4000;
        doCount (ad->inPinData, nextState, (uint16_t) average);
        ad->avgSum = 0;
        ad->avgCnt = 0;
        if (enablePinDebug)
            printPinChangeDebug(ad->inPinData, nextState);
    }
    ad->triggerState = nextState;                   // save new level
}


void readAnalog() {
    uint32_t now = millis();
    char line[26];
    uint16_t waitForOff = 0; 
    uint16_t waitForOn = 1;

    //if (analogCallLast && (now - analogCallLast) > 5) {
    //    Output->print(F("D readAnalog call delay "));
    //    Output->println(now - analogCallLast);
    //}
    analogCallLast = now;

    if ((now - analogReadLast) > analogReadInterval) {      // time for next analog read?
        switch (analogReadState) {
            case 0:                                                 // initial state
                for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++) {                    
                    analogData_t *ad = &analogData[aIdx];
                    digitalWrite(pin2GPIO(ad->outPinName) , LOW);   // make sure IR LED is off for first read
                    analogReadCount = 0;                            // initialize sums and counter
                    ad->sumOff = 0; ad->sumOn = 0;
                }
                analogReadState = 1;
                analogReadWait = millis();
                break;
            case 1:                                                 // wait before measuring
                if ((now - analogReadWait) < waitForOff)            // todo: wait in microseconds with micros() function, make witForOff configurable
                    return;
                analogReadState = 2;
                break;
            case 2:
                for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++) {
                    analogData_t *ad = &analogData[aIdx];
                    uint16_t sample = analogRead(pin2GPIO(ad->inPinName));   // read the analog in value (off)
                    ad->sumOff += sample;

                    if (enableAnalogDebug > 2) {
                        Output->print(F("M "));
                        Output->print(millis());
                        Output->print(F(", 0, "));
                        Output->print(sample);
                        Output->print(F(", "));
                        Output->print(analogReadCount);
                        Output->println();
                    }
                }
                if (++analogReadCount < analogReadSamples)
                    break;
                for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++) {
                    analogData_t *ad = &analogData[aIdx];
                    digitalWrite(pin2GPIO(ad->outPinName), HIGH);      // turn IR LED on
                }
                analogReadCount = 0;
                analogReadState = 4;
                analogReadWait = millis();
                break;
            case 4:                                                 // wait again before measuring
                if ((now - analogReadWait) < waitForOn)
                    return;
                analogReadState = 5;
                break;
            case 5:
                int sensorDiff;
                for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++) {
                    analogData_t *ad = &analogData[aIdx];
                    uint16_t sample = analogRead(pin2GPIO(ad->inPinName));   // read the analog in value (on)
                    ad->sumOn += sample;
                    if (enableAnalogDebug > 2) {
                        Output->print(F("M "));
                        Output->print(millis());
                        Output->print(F(", 1, "));
                        Output->print(sample);
                        Output->print(F(", "));
                        Output->print(analogReadCount);
                        Output->println();
                    }

                }
                if (++analogReadCount < analogReadSamples) 
                    break;
                for (uint8_t aIdx = 0; aIdx < maxAnalogIndex; aIdx++) {
                    analogData_t *ad = &analogData[aIdx];
                    digitalWrite(pin2GPIO(ad->outPinName) , LOW);       // turn IR LED off again
                
                    sensorDiff = (ad->sumOn / analogReadSamples) - (ad->sumOff / analogReadSamples);
                    if (sensorDiff < 0) sensorDiff = 0;
                    if (sensorDiff > 4096) sensorDiff = 4096;
                    detectTrigger (ad, sensorDiff);                    // calculate level with triggers
                    if (enableAnalogDebug > 1) {
                        sprintf(line, "L%2d: %4d, %4d -> % 4d", ad->inPinName, 
                            ad->sumOn / analogReadSamples, ad->sumOff / analogReadSamples, sensorDiff);
                        Output->println(line);
                    } else if (enableAnalogDebug) {
                        sprintf(line, "L%2d: % 4d", ad->inPinName, sensorDiff);
                        Output->println(line);
                    }                    
#if defined(TFT_DISPLAY)
                    if (displayMode == 1) {                    
                        int len = sensorDiff * analogReadAmp * TFT_HEIGHT / 4096;
                        tft.fillRect(0,TFT_WIDTH-10-(10*aIdx),len,10, TFT_YELLOW);
                        tft.fillRect(len,TFT_WIDTH-10-(10*aIdx),TFT_HEIGHT-len,10, TFT_BLACK);
                    }
#endif
                }
                analogReadState = 0;
                analogReadLast = now;
                break;
            default:
                analogReadState = 0;
                Output->println(F("Error: wrong analog read state"));
                break;
        }
    }
}

#if defined (TFT_DISPLAY)
/*
void ButtonHandlerChanged(Button2& btn) {
    Serial.println("changed");
}
*/


void ButtonHandlerTap(Button2& btn) {
    displayMode++;
    if (displayMode > displayModeMax) displayMode = 0;
    tft.setTextFont(2);
    tft.setTextSize(1);
    tft.setTextColor(TFT_GREEN, TFT_BLACK);
    tft.fillRect(0, 32, TFT_HEIGHT, TFT_WIDTH-32, TFT_BLACK);       // unteren Teil löschen
    //tft.fillScreen(TFT_BLUE);
    // test             240 (lange Seite) 135 (kurze)
    //tft.fillRect(0, 32, TFT_HEIGHT-1, TFT_WIDTH-32-1, TFT_BLACK);  // lässt einen 1-Pixel blauen Rand
    tft.setCursor(TFT_HEIGHT-20, TFT_WIDTH-25);    // x, y,   TFT_HEIGHT=240, TFT_WIDTH=135
    tft.print(displayMode);
    /*
    Serial.print(F("D displayMode "));
    Serial.println(displayMode);
    */
    if (displayMode == 2) {
        tft.setCursor(0, 32);
        tft.setTextFont(4);
        tft.setTextSize(1);
        tft.setTextColor(TFT_RED, TFT_BLACK);
        tft.print(F("consumption 5s"));
    } else if (displayMode == 3) {
        tft.setCursor(0, 32);
        tft.setTextFont(4);
        tft.setTextSize(1);
        tft.setTextColor(TFT_RED, TFT_BLACK);
        tft.print(F("consumption dyn"));
    }
}
#endif


void setup() {
#if defined (TFT_DISPLAY)
    tft.init();
    tft.fillScreen(TFT_BLACK);
    tft.setRotation(1);             // 1=Querformat (0 wäre Hochformat, TFT_Width / TFT_Height beziehen sich offenbar auf Hochformat)
    tft.setTextFont(2);
    tft.setTextSize(1);
    tft.setTextColor(TFT_GREEN, TFT_BLACK);

    //buttonA.setChangedHandler(ButtonHandlerChanged);
    //buttonA.setPressedHandler(pressed);
    //buttonA.setReleasedHandler(released);

    // captures any type of click, longpress or shortpress
    buttonA.setTapHandler(ButtonHandlerTap);
    //buttonA.setClickHandler(click);
    //buttonA.setLongClickHandler(longClick);
    //buttonA.setDoubleClickHandler(doubleClick);
    //buttonA.setTripleClickHandler(tripleClick);

#endif    

    Serial.begin(SERIAL_SPEED);             // initialize serial
#if defined(ESP8266) || defined (ESP32)
    EEPROM.begin(100);
#endif    
    delay (500);
    interrupts();    
    Serial.println();        
    Output = &Serial;    
    millisWraps = 0;
    lastMillis = millis();
    initialize();     
    CmdHello();                             // started message to serial
#if defined(WifiSupport)
    initWifi();

    ArduinoOTA
    .onStart([]() {
        String type;
        if (ArduinoOTA.getCommand() == U_FLASH)
            type = "sketch";
        else // U_SPIFFS
            type = "filesystem";
        // NOTE: if updating SPIFFS this would be the place to unmount SPIFFS using SPIFFS.end()
        Serial.println("Start updating " + type);
    });
    ArduinoOTA.onEnd([]() {
        Serial.println("\nEnd");
    });
    ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
        Serial.printf("Progress: %u%%\r", (progress / (total / 100)));
    });
    ArduinoOTA.onError([](ota_error_t error) {
        Serial.printf("Error[%u]: ", error);
        if (error == OTA_AUTH_ERROR) Serial.println("Auth Failed");
        else if (error == OTA_BEGIN_ERROR) Serial.println("Begin Failed");
        else if (error == OTA_CONNECT_ERROR) Serial.println("Connect Failed");
        else if (error == OTA_RECEIVE_ERROR) Serial.println("Receive Failed");
        else if (error == OTA_END_ERROR) Serial.println("End Failed");
    });
    ArduinoOTA.begin();
#endif
}


/*   Main Loop  */
void loop() {
#if defined(WifiSupport)
#if !defined(STATIC_WIFI)
    wifiManager.process();                          // process config portal
#endif
    ArduinoOTA.handle();
    handleConnections();                            // new TCP connection or input over TCP
#endif
#if defined (TFT_DISPLAY)
    buttonA.loop();                                 // check for button events
#endif
    handleTime();                                   // check if millis() wrapped (for reporting)
    if (Serial.available()) handleInput(Serial.read()); // input over serial 
    readAnalog();                                   // analog measurements
    if (enablePinDebug) debugDigitalPinChanges();
    report();                                       // report counts if due
}
