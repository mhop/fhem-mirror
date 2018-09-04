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
               

    ToDo / Ideas:
        
    
*/ 

/* allow printing of every pin change to Serial */
#define debugPins 1  

/* allow tracking of pulse lengths */
#define pulseHistory 1

/* use a sample config at boot */
// #define debugCfg 1

#include "pins_arduino.h"
#include <EEPROM.h>

const char versionStr[] PROGMEM = "ArduCounter V2.36";
const char compile_date[] PROGMEM = __DATE__ " " __TIME__;
const char errorStr[]   PROGMEM = "Error: ";

#ifdef ARDUINO_BOARD
const char boardName1[] PROGMEM = ARDUINO_BOARD;
#endif

#if defined(__AVR_ATmega328P__) || defined(__AVR_ATmega168__)
const char boardName[] PROGMEM = "UNO";
#elif defined(__AVR_ATmega32U4__) || defined(__AVR_ATmega16U4__)
const char boardName[] PROGMEM = "Leonardo";
#elif defined(__AVR_ATmega1280__) || defined(__AVR_ATmega2560__)
const char boardName[] PROGMEM = "Mega";
#elif defined(ESP8266)
const char boardName[] PROGMEM = "ESP8266";
#else
const char boardName[] PROGMEM = "UNKNOWN";
#endif

#define SERIAL_SPEED 38400
#define MAX_INPUT_NUM 8
#define MAX_HIST 20


#ifdef ESP8266
// varibales / definitions for ESP 8266 based boards
#include <ESP8266WiFi.h>

const char* ssid = "MySSID";
const char* password = "secret";

WiFiServer Server(80);              // For ESP WiFi connection
WiFiClient Client1;                 // active TCP connection
WiFiClient Client2;                 // secound TCP connection to send reject message
boolean Client1Connected;           // remember state of TCP connection
boolean Client2Connected;           // remember state of TCP connection

boolean tcpMode = false;
uint8_t delayedTcpReports = 0;          // how often did we already delay reporting because tcp disconnected
uint32_t lastDelayedTcpReports = 0;     // last time we delayed

#define MAX_APIN 8
#define MAX_PIN 8

/* ESP8266 pins that are typically ok to use 
 * (some might be set to -1 (disallowed) because they are used 
 * as reset, serial, led or other things on most boards) 
 * maps printed pin numbers to sketch internal index numbers */
short allowedPins[MAX_APIN] = 
  { 0,  1,  2,  -1,  
     -1, 5,  6, 7};
/* Wemos / NodeMCU Pins 3,4 and 8 (GPIO 0,2 and 15) define boot mode and therefore
 *  can not be used to connect to signal
 */

/* Map from sketch internal pin index to real chip IO pin number */
short internalPins[MAX_PIN] = 
  { 16,  5,  4,  0,  
     2, 14, 12, 13};
        
#else
// variables / definitions for arduino / 328p based boards
#define MAX_APIN 22
#define MAX_PIN 20

/* arduino pins that are typically ok to use 
 * (some might be set to -1 (disallowed) because they are used 
 * as reset, serial, led or other things on most boards) 
 * maps printed pin numbers to sketch internal index numbers */
short allowedPins[MAX_APIN] = 
  {-1, -1,  0,  1,  
    2,  3,  4,  5,
    6,  7,  8,  9, 
   10, 11, 12, 13,
   14, 15, 16, 17, 
   18, 19 };

/* Map from sketch internal pin index to real chip IO pin number */
short internalPins[MAX_PIN] = 
  { 2,  3,  4,  5,
    6,  7,  8,  9, 
   10, 11, 12, 13, 
   14, 15, 16, 17, 
   18, 19 };
   
/* first and last pin at port PB, PC and PD for arduino uno/nano */
uint8_t firstPin[] = {8, 14, 0};    // aPin -> allowedPins[] -> pinIndex
uint8_t lastPin[]  = {13, 19, 7};

/* Pin change mask for each chip port on the arduino platform */
volatile uint8_t *port_to_pcmask[] = {
  &PCMSK0,
  &PCMSK1,
  &PCMSK2
};

/* last PIN States at io port to detect individual pin changes in arduino ISR */
volatile static uint8_t PCintLast[3];

#endif


Print *Output;                      // Pointer to output device (Serial / TCP connection with ESP8266)
uint32_t bootTime;                  
uint16_t bootWraps;                 // counter for millis wraps at last reset
uint16_t millisWraps;               // counter to track when millis counter wraps 
uint32_t lastMillis;                // milis at last main loop iteration
uint8_t devVerbose;                 // >=10 shows pin changes, >=5 shows pin history

#ifdef debugPins
uint8_t lastState[MAX_PIN];         // for debug output when a pin state changes
#endif

uint32_t intervalMin = 30000;       // default 30 sec - report after this time if nothing else delays it
uint32_t intervalMax = 60000;       // default 60 sec - report after this time if it didin't happen before
uint32_t intervalSml =  2000;       // default 2 secs - continue count if timeDiff is less and intervalMax not over
uint16_t countMin    =     2;       // continue counting if count is less than this and intervalMax not over

uint32_t timeNextReport;
#ifdef ESP8266
uint32_t expectK;
#endif

/* index to the following arrays is the internal pin index number  */

volatile boolean initialized[MAX_PIN];          // did we get first interrupt yet? 
short activePin[MAX_PIN];                       // printed arduino pin number for index if active - otherwise -1
uint16_t pulseWidthMin[MAX_PIN];                // minimal pulse length in millis for filtering
uint8_t pulseLevel[MAX_PIN];                    // start of pulse for measuring length - 0 / 1 as defined for each pin
uint8_t pullup[MAX_PIN];                        // pullup configuration state
 
volatile uint32_t counter[MAX_PIN];             // real pulse counter
volatile uint8_t counterIgn[MAX_PIN];           // ignored first pulse after init
volatile uint16_t rejectCounter[MAX_PIN];       // counter for rejected pulses that are shorter than pulseWidthMin
uint32_t lastCount[MAX_PIN];                    // counter at last report (to get the delta count)
uint16_t lastRejCount[MAX_PIN];                 // reject counter at last report (to get the delta count)

volatile uint32_t lastChange[MAX_PIN];          // millis at last level change (for measuring pulse length)
volatile uint8_t lastLevel[MAX_PIN];            // level of input at last interrupt
volatile uint8_t lastLongLevel[MAX_PIN];        // last level that was longer than pulseWidthMin

volatile uint32_t pulseWidthSum[MAX_PIN];       // sum of pulse lengths for average calculation
uint8_t reportSequence[MAX_PIN];                // sequence number for reports


#ifdef pulseHistory 
volatile uint8_t histIndex;                     // pointer to next entry in history ring
volatile uint16_t histNextSeq;                  // next seq number to use
volatile uint16_t histSeq[MAX_HIST];            // history sequence number
volatile uint8_t histPin[MAX_HIST];             // pin for this entry
volatile uint8_t histLevel[MAX_HIST];           // level for this entry
volatile uint32_t histTime[MAX_HIST];           // time for this entry
volatile uint32_t histLen[MAX_HIST];            // time that this level was held
volatile char histAct[MAX_HIST];                // action (count, reject, ...) as one char
#endif

volatile uint32_t intervalStart[MAX_PIN];       // start of an interval - typically set by first / last pulse
volatile uint32_t intervalEnd[MAX_PIN];         // end of an interval - typically set by first / last pulse
uint32_t lastReport[MAX_PIN];                   // millis at last report to find out when maxInterval is over

uint16_t commandData[MAX_INPUT_NUM];            // input data over serial port or network
uint8_t  commandDataPointer = 0;                // index pointer to next input value
uint16_t value;                                 // the current value for input function


/*
   do counting and set start / end time of interval.
   reporting is not triggered from here.
   
   only here counter[] is modified
   intervalEnd[] is set here and in report
   intervalStart[] is set in case a pin was not initialized yet and in report
*/
static void inline doCount(uint8_t pinIndex, uint8_t level, uint32_t now) {
    uint32_t len = now - lastChange[pinIndex];
  char     act = ' ';

#ifdef pulseHistory 
    histIndex++;
    if (histIndex >= MAX_HIST) histIndex = 0;
  histSeq[histIndex]   = histNextSeq++;
    histPin[histIndex]   = pinIndex;
    histTime[histIndex]  = lastChange[pinIndex];
    histLen[histIndex]   = len;
    histLevel[histIndex] = lastLevel[pinIndex];
#endif    
    if (len < pulseWidthMin[pinIndex]) {                    // pulse was too short
        lastChange[pinIndex] = now;
        if (lastLevel[pinIndex] == pulseLevel[pinIndex]) {  // if change to gap level
            rejectCounter[pinIndex]++;                      // inc reject counter and set action to R (pulse too short)
            act = 'R';
        } else {
            act = 'X';                              // set action to X (gap too short)
        }
    } else {
        if (lastLevel[pinIndex] != pulseLevel[pinIndex]) {  // edge does fit defined pulse start, level is now pulse, before it was gap
            act = 'G';                              // now the gap is confirmed (even if inbetween was a spike that we ignored)
        } else {                                            // edge is a change to gap, level is now gap
            if (lastLongLevel[pinIndex] != pulseLevel[pinIndex]) { // last remembered valid level was also gap -> now we had valid new pulse -> count
                counter[pinIndex]++;                        // count
                intervalEnd[pinIndex] = now;                // remember time of in case pulse will be the last in the interval
                if (!initialized[pinIndex]) {
                    intervalStart[pinIndex] = now;          // if this is the very first impulse on this pin -> start interval now
                    initialized[pinIndex] = true;           // and start counting the next impulse (so far counter is 0)
                    counterIgn[pinIndex]++;                 // count as to be ignored for diff because it defines the start of the interval
                }
                pulseWidthSum[pinIndex] += len;             // for average calculation
                act = 'C';
            } else {                                        // last remembered valid level was a pulse -> now we had another valid pulse
                pulseWidthSum[pinIndex] += len;             // for average calculation
                act = 'P';                          // pulse was already counted, only short drop inbetween
            }
        }       
        lastLongLevel[pinIndex] = lastLevel[pinIndex];      // remember this valid level as lastLongLevel
    }
#ifdef pulseHistory   
    histAct[histIndex]   = act;
#endif  
    lastChange[pinIndex] = now;
    lastLevel[pinIndex]  = level;
}


/* Interrupt handlers and their installation 
 *  on Arduino and ESP8266 platforms
 */

#ifndef ESP8266 
/* Add a pin to be handled (Arduino code) */
uint8_t AddPinChangeInterrupt(uint8_t rPin) {
    volatile uint8_t *pcmask;                   // pointer to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
    uint8_t bitM = digitalPinToBitMask(rPin);   // mask to bit in PCMSK to enable pin change interrupt for this arduino pin 
    uint8_t port = digitalPinToPort(rPin);      // port that this arduno pin belongs to for enabling interrupts
    if (port == NOT_A_PORT) 
        return 0;
    port -= 2;                                  // from port (PB, PC, PD) to index in our array
    pcmask = port_to_pcmask[port];              // point to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
    *pcmask |= bitM;                            // set the pin change interrupt mask through a pointer to PCMSK0 or 1 or 2 
    PCICR |= 0x01 << port;                      // enable the interrupt
    return 1;
}


/* Remove a pin to be handled (Arduino code) */
uint8_t RemovePinChangeInterrupt(uint8_t rPin) {
    volatile uint8_t *pcmask;
    uint8_t bitM = digitalPinToBitMask(rPin);
    uint8_t port = digitalPinToPort(rPin);
    if (port == NOT_A_PORT)
        return 0;
    port -= 2;                                  // from port (PB, PC, PD) to index in our array
    pcmask = port_to_pcmask[port];          
    *pcmask &= ~bitM;                           // clear the bit in the mask.
    if (*pcmask == 0) {                     // if that's the last one, disable the interrupt.
        PCICR &= ~(0x01 << port);
    }
    return 1;
}


// now set the arduino interrupt service routines and call the common handler with the port index number
ISR(PCINT0_vect) {
    PCint(0);
}
ISR(PCINT1_vect) {
    PCint(1);
}
ISR(PCINT2_vect) {
    PCint(2);
}

/* 
   common function for arduino pin change interrupt handlers. "port" is the PCINT port index (0-2) as passed from above, not PB, PC or PD which are mapped to 2-4
*/
static void PCint(uint8_t port) {
    uint8_t bit;
    uint8_t curr;
    uint8_t delta;
    short pinIndex;
    uint32_t now = millis();

    // get the pin states for the indicated port.
    curr  = *portInputRegister(port+2);                         // current pin states at port (add 2 to get from index to PB, PC or PD)
    delta = (curr ^ PCintLast[port]) & *port_to_pcmask[port];   // xor gets bits that are different and & screens out non pcint pins
    PCintLast[port] = curr;                                     // store new pin state for next interrupt

    if (delta == 0) return;                                     // no handled pin changed 

    bit = 0x01;                                                 // start mit rightmost (least significant) bit in a port
    for (uint8_t aPin = firstPin[port]; aPin <= lastPin[port]; aPin++) { // loop over each pin on the given port that changed
        if (delta & bit) {                                      // did this pin change?
            pinIndex = allowedPins[aPin];
            if (pinIndex > 0) {                                 // shound not be necessary but test anyway
                doCount (pinIndex, ((curr & bit) > 0), now);    // do the counting, history and so on
            }
        }
        bit = bit << 1;                                         // shift mask to go to next bit
    } 
}


#else
/* Add a pin to be handled (ESP8266 code) */

/* attachInterrupt needs to be given an individual function for each interrrupt .
 *  since we cant pass the pin value into the ISR or we need to use an 
 *  internal function __attachInnterruptArg ... but then we need a fixed reference for the pin numbers ...
*/
uint8_t AddPinChangeInterrupt(uint8_t rPin) {
    switch(rPin) {
    case 4:
        attachInterrupt(digitalPinToInterrupt(rPin), ESPISR4, CHANGE);
        break;
    case 5:
        attachInterrupt(digitalPinToInterrupt(rPin), ESPISR5, CHANGE);
        break;
    case 12:
        attachInterrupt(digitalPinToInterrupt(rPin), ESPISR12, CHANGE);
        break;
    case 13:
        attachInterrupt(digitalPinToInterrupt(rPin), ESPISR13, CHANGE);
        break;
    case 14:
        attachInterrupt(digitalPinToInterrupt(rPin), ESPISR14, CHANGE);
        break;
    case 16:
        attachInterrupt(digitalPinToInterrupt(rPin), ESPISR16, CHANGE);
        break;
    default:
        PrintErrorMsg(); Output->println(F("attachInterrupt"));
    }
    return 1;
}

void ESPISR4() {    // ISR for real pin GPIO 4 / pinIndex 2
    doCount(2, digitalRead(4), millis());
}

void ESPISR5() {    // ISR for real pin GPIO 5 / pinIndex 1
    doCount(1, digitalRead(5), millis());
}

void ESPISR12() {   // ISR for real pin GPIO 12 / pinIndex 6
    doCount(6, digitalRead(12), millis());
}

void ESPISR13() {   // ISR for real pin GPIO 13 / pinIndex 7
    doCount(7, digitalRead(13), millis());
}

void ESPISR14() {// ISR for real pin GPIO 14 / pinIndex 5
    doCount(5, digitalRead(14), millis());
}

void ESPISR16() {   // ISR for real pin GPIO 16 / pinIndex 0
    doCount(0, digitalRead(16), millis());
}
#endif


void PrintErrorMsg() {
    uint8_t len = strlen_P(errorStr);
    char myChar;
    for (unsigned char k = 0; k < len; k++) {
        myChar = pgm_read_byte_near(errorStr + k);
        Output->print(myChar);
    }
}


void printVersionMsg() {  
    uint8_t len = strlen_P(versionStr);
    char myChar;
    for (unsigned char k = 0; k < len; k++) {
        myChar = pgm_read_byte_near(versionStr + k);
        Output->print(myChar);
    }
    Output->print(F(" on "));
    len = strlen_P(boardName);
    for (unsigned char k = 0; k < len; k++) {
        myChar = pgm_read_byte_near(boardName + k);
        Output->print(myChar);
    }

#ifdef ARDUINO_BOARD
    Output->print(F(" "));
    len = strlen_P(boardName1);
    for (unsigned char k = 0; k < len; k++) {
        myChar = pgm_read_byte_near(boardName1 + k);
        Output->print(myChar);
    }
#endif

    Output->print(F(" compiled "));
    len = strlen_P(compile_date);
    for (unsigned char k = 0; k < len; k++) {
        myChar = pgm_read_byte_near(compile_date + k);
        Output->print(myChar);
    }
}


void showIntervals() {
    Output->print(F("I"));
    Output->print(intervalMin / 1000);
    Output->print(F(" "));
    Output->print(intervalMax / 1000);
    Output->print(F(" "));
    Output->print(intervalSml / 1000);
    Output->print(F(" "));
    Output->println(countMin);
}


void showPinConfig(short pinIndex) {
    Output->print(F("P"));
    Output->print(activePin[pinIndex]);
    switch (pulseLevel[pinIndex]) {
        case 1:  Output->print(F(" rising")); break;
        case 0: Output->print(F(" falling")); break;
        default: Output->print(F(" -")); break;
    }        
    if (pullup[pinIndex]) 
        Output->print(F(" pullup"));
    Output->print(F(" min "));
    Output->print(pulseWidthMin[pinIndex]);
}

#ifdef pulseHistory 
void showPinHistory(short pinIndex, uint32_t now) {
    uint8_t hi;
    uint8_t start = (histIndex + 2) % MAX_HIST;
    uint8_t count = 0;
    uint32_t last;
    boolean first = true;

    for (uint8_t i = 0; i < MAX_HIST; i++) {
        hi = (start + i) % MAX_HIST;
        if (histPin[hi] == pinIndex)
            if (first || (last <= histTime[hi]+histLen[hi])) count++;
    }
    if (!count) return;
    
    Output->print (F("H"));                     // start with H
    Output->print (activePin[pinIndex]);        // printed pin number
    Output->print (F(" "));
    for (uint8_t i = 0; i < MAX_HIST; i++) {
        hi = (start + i) % MAX_HIST;
        if (histPin[hi] == pinIndex) {
            if (first || (last <= histTime[hi]+histLen[hi])) {
                if (!first) Output->print (F(", "));
                        Output->print (histSeq[hi]);                    // sequence
                        Output->print (F("s"));                         
                Output->print ((long) (histTime[hi] - now));    // time when level started
                Output->print (F("/"));                         
                Output->print (histLen[hi]);                    // length 
                Output->print (F("@"));                         
                Output->print (histLevel[hi]);                  // level (0/1)
                Output->print (histAct[hi]);                    // action
                first = false;
            }
            last = histTime[hi];
        }
    }        
    Output->println();    
}
#endif

/*
   lastCount[] is only modified here (count at time of last reporting)
   intervalEnd[]  is modified here and in ISR - disable interrupts in critcal moments to avoid garbage in var
   intervalStart[] is modified only here or for very first Interrupt in ISR
*/
void showPinCounter(short pinIndex, boolean showOnly, uint32_t now) {
    uint32_t count, countDiff, realDiff;
    uint32_t startT, endT, timeDiff, widthSum;
    uint16_t rejCount, rejDiff;
    uint8_t countIgn;
    
    noInterrupts();                                 // copy counters while they cant be changed in isr
    startT   = intervalStart[pinIndex];             // start of interval (typically first pulse)
    endT     = intervalEnd[pinIndex];               // end of interval (last unless not enough)
    count    = counter[pinIndex];                   // get current counter (counts all pulses
    rejCount = rejectCounter[pinIndex];
    countIgn = counterIgn[pinIndex];                // pulses that mark the beginning of an interval
    widthSum = pulseWidthSum[pinIndex];
    interrupts();
        
    timeDiff  = endT - startT;                      // time between first and last impulse
    realDiff  = count - lastCount[pinIndex];        // pulses during intervall
    countDiff = realDiff - countIgn;                // ignore forst pulse after device restart
    rejDiff   = rejCount - lastRejCount[pinIndex];
    
    if (!showOnly) {                                // real reporting sets the interval borders new
        if((long)(now - (lastReport[pinIndex] + intervalMax)) >= 0) { 
            // intervalMax is over
            if ((countDiff >= countMin) && (timeDiff > intervalSml) && (intervalMin != intervalMax)) {
                // normal procedure
                noInterrupts();                     // vars could be modified in ISR as well
                intervalStart[pinIndex] = endT;     // time of last impulse becomes first in next
                interrupts();
            } else {
                // nothing counted or counts happened during a fraction of intervalMin only
                noInterrupts();                     // vars could be modified in ISR as well
                intervalStart[pinIndex] = now;      // start a new interval for next report now
                intervalEnd[pinIndex]   = now;      // no last impulse, use now instead
                interrupts();
                timeDiff  = now - startT;           // special handling - calculation ends now
            }        
        } else if( ((long)(now - (lastReport[pinIndex] + intervalMin)) >= 0)   
            && (countDiff >= countMin) && (timeDiff > intervalSml)) {
            // minInterval has elapsed and other conditions are ok
            noInterrupts();                         // vars could be modified in ISR as well
            intervalStart[pinIndex] = endT;         // time of last also time of first in next
            interrupts();
        } else {
          return;                                   // intervalMin and Max not over - dont report yet
        }
        noInterrupts(); 
        counterIgn[pinIndex]    = 0;
        pulseWidthSum[pinIndex] = 0;
        interrupts();
        lastCount[pinIndex]    = count;             // remember current count for next interval
        lastRejCount[pinIndex] = rejCount;
        lastReport[pinIndex]   = now;               // remember when we reported
#ifdef ESP8266
        delayedTcpReports      = 0;
#endif
        reportSequence[pinIndex]++;
    }   
    Output->print(F("R"));          // R Report
    Output->print(activePin[pinIndex]);
    Output->print(F(" C"));         // C - Count
    Output->print(count);
    Output->print(F(" D"));         // D - Count Diff (without pulse that marks the begin)
    Output->print(countDiff);
    Output->print(F("/"));          // R - real Diff for long counter - includes first after restart
    Output->print(realDiff);
    Output->print(F(" T"));         // T - Time
    Output->print(timeDiff);  
    Output->print(F(" N"));         // N - now
    Output->print((long)now);
    Output->print(F(","));
    Output->print(millisWraps);    
    Output->print(F(" X"));         // X Reject
    Output->print(rejDiff);  
    
    if (!showOnly) {
        Output->print(F(" S"));      // S - Sequence number
        Output->print(reportSequence[pinIndex]);  
    }
    if (countDiff > 0) {
        Output->print(F(" A"));
        Output->print(widthSum / countDiff);
    }
    Output->println();    
#ifdef ESP8266
    if (tcpMode && !showOnly) {
        Serial.print(F("D reported pin "));
        Serial.print(activePin[pinIndex]);
        Serial.print(F(" sequence "));
        Serial.print(reportSequence[pinIndex]);  
        Serial.println(F(" over tcp "));  
    }
#endif  
    
}


/* 
   report count and time for pins that are between min and max interval    
*/

boolean reportDue() {
    uint32_t now = millis();
    boolean doReport  = false;                          // check if report needs to be called
    if((long)(now - timeNextReport) >= 0)               // works fine when millis wraps.
        doReport = true;                                // intervalMin is over 
    else 
        for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++)  
            if (activePin[pinIndex] > 0)
                if((long)(now - (lastReport[pinIndex] + intervalMax)) >= 0)
                    doReport = true;                    // active pin has not been reported for langer than intervalMax
    return doReport;
}



void report() {
    uint32_t now = millis();    
#ifdef ESP8266
    if (tcpMode && !Client1Connected && (delayedTcpReports < 3)) {
        if(delayedTcpReports == 0 || ((long)(now - (lastDelayedTcpReports + (1 * 30 * 1000))) > 0)) {
            Serial.print(F("D report called but tcp is disconnected - delaying ("));
            Serial.print(delayedTcpReports);
            Serial.print(F(")"));
            Serial.print(F(" now "));
            Serial.print(now);
            Serial.print(F(" last "));
            Serial.print(lastDelayedTcpReports);
            Serial.print(F(" diff "));
            Serial.println(now - lastDelayedTcpReports);
            delayedTcpReports++;
            lastDelayedTcpReports = now;
            return;
        } else return;
    }
#endif
    
    for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++) {  // go through all observed pins as pinIndex
        if (activePin[pinIndex] >= 0) {
            showPinCounter (pinIndex, false, now);              // report pin counters if necessary
#ifdef pulseHistory
            if (devVerbose >= 5) 
                showPinHistory(pinIndex, now);                  // show pin history if verbose >= 5
#endif          
        }
    }
    timeNextReport = now + intervalMin;                         // check again after intervalMin or if intervalMax is over for a pin
}


/* give status report in between if requested over serial input */
void showCmd() {
    uint32_t now = millis();  
    Output->print(F("M Status: "));
    printVersionMsg();
    Output->println();
    showIntervals();
    for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++) {
        if (activePin[pinIndex] > 0) {
            showPinConfig(pinIndex);
            Output->print(F(", "));
            showPinCounter(pinIndex, true, now);
#ifdef pulseHistory             
            showPinHistory(pinIndex, now);
#endif          
        }
    }
    readFromEEPROM();
    Output->print(F("M Next report in "));
    Output->print(timeNextReport - millis());
    Output->print(F(" milliseconds"));
    Output->println();  
    //Output->println(F("M #end#"));
}


void helloCmd() {
    uint32_t now = millis();
    Output->println();
    printVersionMsg();
    Output->print(F(" Hello, pins "));
    boolean first = true;
    for (uint8_t aPin=0; aPin < MAX_APIN; aPin++) {
        if (allowedPins[aPin] >= 0) {
            if (!first) {
                Output->print(F(","));
            } else {
                first = false;
            }
            Output->print(aPin);
        }
    }
    Output->print(F(" available"));
    Output->print(F(" T"));
    Output->print(now);
    Output->print(F(","));
    Output->print(millisWraps);
    Output->print(F(" B"));
    Output->print(bootTime);
    Output->print(F(","));
    Output->print(bootWraps);
    
    Output->println();
    showIntervals();
    for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++) { // go through all observed pins as pinIndex
        if (activePin[pinIndex] >= 0) {
            showPinConfig(pinIndex);
            Output->println();
        }
    }
}



/*
    handle add command.
*/
void addCmd(uint16_t *values, uint8_t size) {
    uint16_t pulseWidth;
    uint32_t now = millis();
  
    uint8_t aPin = values[0];                   // value 0 is pin number
    if (aPin >= MAX_APIN  || allowedPins[aPin] < 0) {
        PrintErrorMsg(); 
        Output->print(F("Illegal pin specification "));
        Output->println(aPin);
        return;
    }; 
    uint8_t pinIndex = allowedPins[aPin];
    uint8_t rPin = internalPins[pinIndex];

    if (activePin[pinIndex] != aPin) {          // in case this pin is not already active counting
      #ifndef ESP8266
        uint8_t port = digitalPinToPort(rPin) - 2;
        PCintLast[port] = *portInputRegister(port+2);
      #endif    
        initPinVars(pinIndex, now);
        activePin[pinIndex] = aPin;             // save arduino pin number and flag this pin as active for reporting
    }

    if (values[1] < 2 || values[1] > 3) {       // value 1 is level (rising / falling -> 0/1
        PrintErrorMsg(); 
        Output->print(F("Illegal pulse level specification for pin "));
        Output->println(aPin);
    }
    pulseLevel[pinIndex] = (values[1] == 3);    // 2 = falling -> pulseLevel 0, 3 = rising -> pulseLevel 1
  
    
    if (size > 2 && values[2]) {                // value 2 is pullup
        pinMode (rPin, INPUT_PULLUP);
        pullup[pinIndex] = 1;
        // digitalWrite (rPin, HIGH);              // old way to enable pullup resistor
    } else {
        pinMode (rPin, INPUT);  
        pullup[pinIndex] = 0;
    }

    if (size > 3 && values[3] > 0) {            // value 3 is min length
        pulseWidth = values[3];
    } else {
        pulseWidth = 2;
    }  
    pulseWidthMin[pinIndex] = pulseWidth;

    if (!AddPinChangeInterrupt(rPin)) {         // add Pin Change Interrupt
        PrintErrorMsg(); 
        Output->println(F("AddInt"));
        return;
    }
         
    Output->print(F("M defined ")); 
    showPinConfig(pinIndex);    
    Output->println();
}


/*
    handle rem command.
*/
void removeCmd(uint16_t *values, uint8_t size) {
    uint8_t aPin = values[0];
    if (size < 1 || aPin >= MAX_APIN || allowedPins[aPin] < 0) {
        PrintErrorMsg(); 
        Output->print(F("Illegal pin specification "));
        Output->println(aPin);
        return;
    };
    uint8_t pinIndex = allowedPins[aPin];

#ifdef ESP8266
    detachInterrupt(digitalPinToInterrupt(internalPins[pinIndex]));
#else   
    if (!RemovePinChangeInterrupt(internalPins[pinIndex])) {      
        PrintErrorMsg(); Output->println(F("RemInt"));
        return;
    }
#endif
    initPinVars(pinIndex, 0);
    Output->print(F("M removed "));
    Output->println(aPin);
}



void intervalCmd(uint16_t *values, uint8_t size) {
    /*Serial.print(F("D int ptr is "));
    Serial.println(size);*/
    if (size < 4) {               // i command always gets 4 values: min, max, sml, cntMin
        PrintErrorMsg();
        Output->print(F("size"));
        Output->println();
        return;
    }
    if (values[0] < 1 || values[0] > 3600) {
        PrintErrorMsg(); Output->println(values[0]);
        return;
    }
    intervalMin = (long)values[0] * 1000;
    if (millis() + intervalMin < timeNextReport)
    timeNextReport = millis() + intervalMin;

    if (values[1] < 1 || values[1] > 3600) {
        PrintErrorMsg(); Output->println(values[1]);
        return;
    }
    intervalMax = (long)values[1]* 1000;

    if (values[2] > 3600) {
        PrintErrorMsg(); Output->println(values[2]);
        return;
    }
    intervalSml = (long)values[2] * 1000;

    if (values[3] > 100) {
        PrintErrorMsg(); Output->println(values[3]);
        return;
    }
    countMin = values[3];

    Output->print(F("M intervals set to ")); 
    Output->print(values[0]);
    Output->print(F(" ")); 
    Output->print(values[1]);
    Output->print(F(" ")); 
    Output->print(values[2]);
    Output->print(F(" ")); 
    Output->print(values[3]);
    Output->println();
}


void keepAliveCmd(uint16_t *values, uint8_t size) {
    Output->println(F("alive"));
#ifdef ESP8266
    if (values[0] == 1 && size > 0 && size < 3 && Client1.connected()) {
        tcpMode = true;
        if (size == 2) {
            expectK = millis() + values[1] * 2500;
        } else {
            expectK = millis() + 600000;    // 10 Minutes if nothing sent (should not happen)
        }
    }  
#endif
}


#ifdef ESP8266
void quitCmd() {
    if (Client1.connected()) {
        Client1.println(F("closing connection"));
        Client1.stop();
        tcpMode =  false;
        Serial.println(F("M TCP connection closed"));
    } else {
        Serial.println(F("M TCP not connected"));
    }
}
#endif


    
void updateEEPROM(int &address, byte value) {
    if( EEPROM.read(address) != value){
        EEPROM.write(address, value);
    }
    address++;
}
    
    
void updateEEPROMSlot(int &address, char cmd, int v1, int v2, int v3, int v4) {
    updateEEPROM(address, cmd);         // I / A
    updateEEPROM(address, v1 & 0xff);       
    updateEEPROM(address, v1 >> 8);    
    updateEEPROM(address, v2 & 0xff);
    updateEEPROM(address, v2 >> 8);
    updateEEPROM(address, v3 & 0xff);
    updateEEPROM(address, v3 >> 8);
    updateEEPROM(address, v4 & 0xff);
    updateEEPROM(address, v4 >> 8);
}


void saveToEEPROMCmd() {
    int address   = 0;
    uint8_t slots = 1;
    updateEEPROM(address, 'C');
    updateEEPROM(address, 'f');
    updateEEPROM(address, 'g');
    for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++)
        if (activePin[pinIndex] > 0) slots ++;
    updateEEPROM(address, slots);                   // number of defined pins + intervall definition
    updateEEPROMSlot(address, 'I', (uint16_t)(intervalMin / 1000), (uint16_t)(intervalMax / 1000), 
                                  (uint16_t)(intervalSml / 1000), (uint16_t)countMin);
    for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++) 
        if (activePin[pinIndex] > 0)
            updateEEPROMSlot(address, 'A', (uint16_t)activePin[pinIndex], (uint16_t)(pulseLevel[pinIndex] ? 3:2), 
                                                    (uint16_t)pullup[pinIndex], (uint16_t)pulseWidthMin[pinIndex]);
#ifdef ESP8266                   
    EEPROM.commit();               
#endif  
    Serial.print(F("config saved, "));
    Serial.print(slots);
    Serial.print(F(", "));
    Serial.println(address);
}


void readFromEEPROM() {
    int address = 0;
    Output->println();
    Output->print(F("M EEPROM Config: "));
    Output->print((char) EEPROM.read(0));
    Output->print((char) EEPROM.read(1));
    Output->print((char) EEPROM.read(2));
    Output->print(F(" Slots: "));
    Output->print((int) EEPROM.read(3));
    Output->println();
    if (EEPROM.read(address) != 'C' || EEPROM.read(address+1) != 'f' || EEPROM.read(address+2) != 'g') {
        Output->println(F("M no config in EEPROM"));
        return;
    }
    address = 3;
    uint8_t slots = EEPROM.read(address++);
    if (slots > MAX_PIN + 1) {
        Output->println(F("M illegal config in EEPROM"));
        return;
    }
    uint16_t v1, v2, v3, v4;
    char cmd;
    for (uint8_t slot=0; slot < slots; slot++) {
        cmd = EEPROM.read(address);
        v1 = EEPROM.read(address+1) + (((uint16_t)EEPROM.read(address+2)) << 8);
        v2 = EEPROM.read(address+3) + (((uint16_t)EEPROM.read(address+4)) << 8);
        v3 = EEPROM.read(address+5) + (((uint16_t)EEPROM.read(address+6)) << 8);
        v4 = EEPROM.read(address+7) + (((uint16_t)EEPROM.read(address+8)) << 8);
    address = address + 9;
    Output->print(F("M Slot: "));
        Output->print(cmd);
        Output->print(F(" "));
        Output->print(v1);
        Output->print(F(","));
        Output->print(v2);
        Output->print(F(","));
        Output->print(v3);
        Output->print(F(","));
        Output->print(v4);
        Output->println();
    }  
}


void restoreFromEEPROM() {
    int address = 0;  
    if (EEPROM.read(address) != 'C' || EEPROM.read(address+1) != 'f' || EEPROM.read(address+2) != 'g') {
        Serial.println(F("M no config in EEPROM"));
        return;
    }
    address = 3;
    uint8_t slots = EEPROM.read(address++);
    if (slots > MAX_PIN + 1 || slots < 1) {
        Serial.println(F("M illegal config in EEPROM"));
        return;
    }
    Serial.println(F("M restoring config from EEPROM"));
    char cmd;
    for (uint8_t slot=0; slot < slots; slot++) {
        cmd = EEPROM.read(address);
        commandData[0] = EEPROM.read(address+1) + (((uint16_t)EEPROM.read(address+2)) << 8);
        commandData[1] = EEPROM.read(address+3) + (((uint16_t)EEPROM.read(address+4)) << 8);
        commandData[2] = EEPROM.read(address+5) + (((uint16_t)EEPROM.read(address+6)) << 8);
        commandData[3] = EEPROM.read(address+7) + (((uint16_t)EEPROM.read(address+8)) << 8);
        address = address + 9;
        commandDataPointer = 4;
        if (cmd == 'I') intervalCmd(commandData, commandDataPointer);
        if (cmd == 'A') addCmd(commandData, commandDataPointer);
    }
    commandDataPointer = 0;
    value = 0;
    for (uint8_t i=0; i < MAX_INPUT_NUM; i++)
        commandData[i] = 0;     
  
}


void handleInput(char c) {
    if (c == ',') {                       // Komma input, last value is finished
        if (commandDataPointer < (MAX_INPUT_NUM - 1)) {
            commandData[commandDataPointer++] = value;
            value = 0;
        }
    }
    else if ('0' <= c && c <= '9') {      // digit input
        value = 10 * value + c - '0';
    }
    else if ('a' <= c && c <= 'z') {      // letter input is command
    
        if (devVerbose > 0) {
            Serial.print(F("D got "));
            for (short v = 0; v <= commandDataPointer; v++) {          
                if (v > 0) Serial.print(F(","));
                Serial.print(commandData[v]);
            }
            Serial.print(c);
            Serial.print(F(" size "));
            Serial.print(commandDataPointer+1);
            Serial.println();
        }

        switch (c) {
        case 'a':
            commandData[commandDataPointer] = value;
            addCmd(commandData, commandDataPointer+1);
            break;
        case 'd':
            commandData[commandDataPointer] = value;
            removeCmd(commandData, commandDataPointer+1);
            break;
        case 'i':
            commandData[commandDataPointer] = value;
            intervalCmd(commandData, commandDataPointer+1);
            break;
        case 'r':
            initialize();
            break;
        case 's':
            showCmd();
            break;
        case 'v':
            if (value < 255) {
                devVerbose = value;
                Output->print(F("M devVerbose set to ")); 
                Output->println(value); 
            } else {
                Output->println(F("M illegal value passed for devVerbose")); 
            }
            break;
        case 'h':
            helloCmd();
            break;
        case 'e':
            saveToEEPROMCmd();
            break; 
        case 'f':
            // OTA flash from HTTP Server
            break; 
#ifdef ESP8266      
        case 'q':
            quitCmd();
            break; 
#endif
        case 'k':
            commandData[commandDataPointer] = value;
            keepAliveCmd(commandData, commandDataPointer+1);
            break;   
        default:
            break;
        }
        commandDataPointer = 0;
        value = 0;
        for (uint8_t i=0; i < MAX_INPUT_NUM; i++)
            commandData[i] = 0;     
        //Serial.println(F("D End of command"));
    }
}

#ifdef debugCfg
/* do sample config so we don't need to configure pins after each reboot */
void debugSetup() {
    commandData[0] = 10;
    commandData[1] = 20;
    commandData[2] = 3;
    commandData[3] = 0;
    commandDataPointer = 4;
    intervalCmd(commandData, commandDataPointer);

    commandData[0] = 1;   // pin 1
    commandData[1] = 2;   // falling
    commandData[2] = 1;   // pullup
    commandData[3] = 30;  // min Length
    commandDataPointer = 4;
    addCmd(commandData, commandDataPointer);

    commandData[0] = 2;   // pin 2
    addCmd(commandData, commandDataPointer);

/*  
    commandData[0] = 5;   // pin 5
    addCmd(commandData, commandDataPointer);

    commandData[0] = 6;   // pin 6
    addCmd(commandData, commandDataPointer);
*/
}
#endif


#ifdef debugPins
void debugPinChanges() {
    for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++) {
        short aPin = activePin[pinIndex];
        if (aPin > 0) {
            uint8_t rPin = internalPins[pinIndex];
            uint8_t pinState = digitalRead(rPin);
                       
            if (pinState != lastState[pinIndex]) {
                lastState[pinIndex] = pinState;
                Output->print(F("M pin "));
                Output->print(aPin);
                Output->print(F(" ( internal "));
                Output->print(rPin);
                Output->print(F(" ) "));
                Output->print(F(" to "));
                Output->print(pinState);
#ifdef pulseHistory                     
                Output->print(F("  histIdx "));
                Output->print(histIndex);
#endif                  
                Output->print(F("  count "));
                Output->print(counter[pinIndex]);
                Output->print(F("  reject "));
                Output->print(rejectCounter[pinIndex]);
                Output->println();
            }
        }
    }
}
#endif


#ifdef ESP8266    
void connectWiFi() {
    Client1Connected = false;
    Client2Connected = false;

    // Connect to WiFi network
    WiFi.mode(WIFI_STA);
    delay (1000);    
    if (WiFi.status() != WL_CONNECTED) {
        Serial.print(F("M Connecting WiFi to "));
        Serial.println(ssid);
        WiFi.begin(ssid, password);                 // authenticate 
        while (WiFi.status() != WL_CONNECTED) {
            Serial.print(F("M Status is "));
            switch (WiFi.status()) {
              case WL_CONNECT_FAILED: 
                Serial.println(F("Connect Failed"));
                break;
              case WL_CONNECTION_LOST: 
                Serial.println(F("Connection Lost"));
                break;
              case WL_DISCONNECTED: 
                Serial.println(F("Disconnected"));
                break;
              case WL_CONNECTED: 
                Serial.println(F("Connected"));
                break;
              default:
                Serial.println(WiFi.status());
            }
            delay(1000);
        }    
        Serial.println();
        Serial.print(F("M WiFi connected to "));
        Serial.println(WiFi.SSID());
    } else {
        Serial.print(F("M WiFi already connected to "));
        Serial.println(WiFi.SSID());
    }

    // Start the server
    Server.begin();
    Serial.println(F("M Server started"));

    // Print the IP address
    Serial.print(F("M Use this IP: "));
    Serial.println(WiFi.localIP());
}


void handleConnections() { 
    IPAddress remote;   
    uint32_t now = millis();
    
    if (Client1Connected) {
        if((long)(now - expectK) >= 0) {
            Serial.println(F("M no keepalive from Client - disconnecting"));
            Client1.stop();
        }
    }    
    if (Client1.available()) {
        handleInput(Client1.read());
        //Serial.println(F("M new Input over TCP"));
    }
    if (Client1.connected()) {
        Client2 = Server.available();
        if (Client2) {
            Client2.println(F("connection already busy"));
            remote = Client2.remoteIP();
            Client2.stop();
            Serial.print(F("M second connection from "));
            Serial.print(remote);
            Serial.println(F(" rejected"));
        }
    } else {
        if (Client1Connected) {                                 // client used to be connected, now disconnected
            Client1Connected = false;
            Output = &Serial;
            Serial.println(F("M connection to client lost"));
        }
        Client1 = Server.available();
        if (Client1) {                                          // accepting new connection
            remote = Client1.remoteIP();
            Serial.print(F("M new connection from "));
            Serial.print(remote);
            Serial.println(F(" accepted"));
            Client1Connected = true;
            Output = &Client1;
            expectK = now + 600000;   // max 10 Minutes (to be checked on Fhem module side as well
            helloCmd();                                         // say hello to client
        }
    }
} 
#endif


void handleTime() {
    uint32_t now = millis();
    if (now < lastMillis) millisWraps++;
    lastMillis = now;
}


void initPinVars(short pinIndex, uint32_t now) {
    activePin[pinIndex]      = -1;          // inactive (-1)
    initialized[pinIndex]    = false;       // no pulse seen yet
    pulseWidthMin[pinIndex]  = 0;           // min pulse length
    counter[pinIndex]        = 0;           // counter to 0
    counterIgn[pinIndex]     = 0;    
    lastCount[pinIndex]      = 0;
    rejectCounter[pinIndex]  = 0;        
    lastRejCount[pinIndex]   = 0;
    intervalStart[pinIndex]  = now;         // time vars
    intervalEnd[pinIndex]    = now;
    lastChange[pinIndex]     = now;
    lastReport[pinIndex]     = now;
    reportSequence[pinIndex] = 0;
    uint8_t level = digitalRead(internalPins[pinIndex]);
    lastLevel[pinIndex]      = level;
#ifdef debugPins      
    lastState[pinIndex]      = level;      // for debug output
#endif
}


void initialize() {
    uint32_t now = millis();
    for (uint8_t pinIndex=0; pinIndex < MAX_PIN; pinIndex++) {
        initPinVars(pinIndex, now);
    }   
    timeNextReport = now + intervalMin;      // time for first output
    devVerbose = 0;
#ifndef ESP8266
    for (uint8_t port=0; port <= 2; port++) {
        PCintLast[port] = *portInputRegister(port+2); // current pin states at port for PCInt handler
    }
#endif
#ifdef debugCfg
    debugSetup();
#endif
    restoreFromEEPROM();
    bootTime  = millis();       // with boot / reset time
    bootWraps = millisWraps;
#ifdef ESP8266  
    expectK   = now + 600000;   // max 10 Minutes (to be checked on Fhem module side as well
#endif  
}


void setup() {
    Serial.begin(SERIAL_SPEED);             // initialize serial
#ifdef ESP8266    
    EEPROM.begin(100);
#endif    
    delay (500);
    interrupts();    
    Serial.println();        
    Output = &Serial;    
    millisWraps = 0;
    lastMillis = millis();
    initialize();     
    helloCmd();                             // started message to serial
#ifdef ESP8266
    connectWiFi();
#endif
}


/*
   Main Loop  
   checks if report should be called because timeNextReport is reached
   or lastReport for one pin is older than intervalMax   
   timeNextReport is only set here (and when interval is changed / at setup)
*/
void loop() {
    handleTime();
    if (Serial.available()) {
        handleInput(Serial.read());
    }
#ifdef ESP8266    
    handleConnections();
#endif

#ifdef debugPins
    if (devVerbose >= 10) {
        debugPinChanges();
    }
#endif

    if (reportDue()) {    
        report();
    }
}

