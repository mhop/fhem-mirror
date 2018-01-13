/*
 * Sketch for counting impulses in a defined interval
 * e.g. for power meters with an s0 interface that can be 
 * connected to an input of an arduino board 
 *
 * the sketch uses pin change interrupts which can be anabled 
 * for any of the inputs on e.g. an arduino uno or a jeenode
 *
 * the pin change Interrupt handling used here 
 * is based on the arduino playground example on PCINT:
 * http://playground.arduino.cc/Main/PcInt
 *
 * Refer to avr-gcc header files, arduino source and atmega datasheet.
 */

/* Pin to interrupt map:
 * D0-D7 =           PCINT 16-23 = PCIR2 = PD = PCIE2 = pcmsk2
 * D8-D13 =          PCINT 0-5 =   PCIR0 = PB = PCIE0 = pcmsk0
 * A0-A5 (D14-D19) = PCINT 8-13 =  PCIR1 = PC = PCIE1 = pcmsk1
 */

/* to test pin 4 with interval 10-20 sec do
 *  4,2,1,30a
 *  10,20,2,0i
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
        3.11.16  - more noInterrupt blocks when accessing the non byte volatiles in report
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
        2.1.17 - change message syntax again, report time as well, first and last impulse are reported relative to start of intervall
                  not start of reporting intervall
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
        
        ToDo / Ideas:   
                                
                new index scheme to save memory:
                    define new array to map from pcintPin to new index, limit allowed pins.
                    unused pcintpins point to -1 (or some other unused number < 0) and comment states arduino pin number
                    instead of allowedPins array use new function from aPin to pcintPin
                    and then look up in new array for index or -1
*/ 
 
#include "pins_arduino.h"

const char versionStr[] PROGMEM = "ArduCounter V2.05";
const char errorStr[]   PROGMEM = "Error: ";

#define SERIAL_SPEED 38400
#define MAX_ARDUINO_PIN 24
#define MAX_PCINT_PIN 24
#define MAX_INPUT_NUM 8
#define MAX_HIST 20

/* arduino pins that are typically ok to use 
 * (some are left out because they are used 
 * as reset, serial, led or other things on most boards) */
byte allowedPins[MAX_ARDUINO_PIN] = 
  { 0,  0,  0,  3,  4, 5, 6, 7,
    8,  9, 10, 11, 12, 13,
   14, 15, 16, 17,  0, 0};


/* Pin change mask for each chip port */
volatile uint8_t *port_to_pcmask[] = {
  &PCMSK0,
  &PCMSK1,
  &PCMSK2
};

/* last PIN States to detect individual pin changes in ISR */
volatile static uint8_t PCintLast[3];

unsigned long intervalMin = 30000; // default 30 sec - report after this time if nothing else delays it
unsigned long intervalMax = 60000; // default 60 sec - report after this time if it didin't happen before
unsigned long intervalSml =  2000; // default 2 secs - continue count if timeDiff is less and intervalMax not over
unsigned int  countMin    =     1; // continue counting if count is less than this and intervalMax not over

unsigned long timeNextReport;

/* index to the following arrays is the internal PCINT pin number, not the arduino 
 * pin number because the PCINT pin number corresponds to the physical ports
 * and this saves time for mapping to the arduino numbers
 */

/* did we get first interrupt yet? */
volatile boolean initialized[MAX_PCINT_PIN];
 
/* individual counters for each real pin */
volatile unsigned long counter[MAX_PCINT_PIN];
volatile uint8_t counterIgn[MAX_PCINT_PIN];         // ignored first pulse after init
volatile unsigned int rejectCounter[MAX_PCINT_PIN];

/* millis at last level change (for measuring pulse length) */
volatile unsigned long lastChange[MAX_PCINT_PIN];

/* last valid level */
volatile uint8_t lastLevel[MAX_PCINT_PIN];

/* sum of pulse lengths for average output */
volatile unsigned long pulseWidthSum[MAX_PCINT_PIN];


/* count at last report to get difference */
unsigned long lastCount[MAX_PCINT_PIN];
unsigned int lastRejCount[MAX_PCINT_PIN];

/* history ring */
volatile uint8_t histIndex;
volatile uint8_t histPin[MAX_HIST];
volatile uint8_t histLevel[MAX_HIST];
volatile unsigned long histTime[MAX_HIST];
volatile unsigned long histLen[MAX_HIST];
volatile char histAct[MAX_HIST];
//volatile uint8_t histI1[MAX_HIST];


/* real arduino pin number for PCINT number if active - otherwise 0 */
uint8_t PCintActivePin[MAX_PCINT_PIN];

/* pin change mode (RISING etc.) as parameter for ISR */
uint8_t PCintMode[MAX_PCINT_PIN];

/* minimal pulse length in millis for filtering */
unsigned int pulseWidthMin[MAX_PCINT_PIN];

/* start of pulse for measuring length */
uint8_t pulseWidthStart[MAX_PCINT_PIN];             // FALLING or RISING as defined for each pin

/* start and end of an interval - typically set by first / last pulse */
volatile unsigned long intervalStart[MAX_PCINT_PIN];
volatile unsigned long intervalEnd[MAX_PCINT_PIN];

/* millis at first interrupt in a reporting cycle */
volatile unsigned long firstPulse[MAX_PCINT_PIN];

/* millis at last report 
 * to find out when maxInterval is over
 * and report has to be done even if
 * no impulses were counted */
unsigned long lastReport[MAX_PCINT_PIN];

/* input data over serial port */
unsigned int commandData[MAX_INPUT_NUM];
uint8_t commandDataPointer = 0;



int digitalPinToPcIntPin(uint8_t aPin) {
  uint8_t pcintPin;                             // PCINT pin number for the pin to be added (index for most arrays)  
  uint8_t portIdx = digitalPinToPort(aPin)-2;   // index of port that this arduno pin belongs to for enabling interrupts
                                                // since the macro maps to defines PB(=2), PC(=3) and PD(=4), we subtract 2
                                                // to use the result as array index in this sketch

  if (portIdx == 1) {                     // now calculate the PCINT pin number that corresponds to the arduino pin number
     pcintPin = aPin - 6;                 // portIdx 1: PC0-PC5 (A0-A5 or D14-D19) is PCINT 8-13 (PC6 is reset)
  } else {                                // arduino numbering continues at D14 since PB6/PB7 are used for other things 
     pcintPin = portIdx*8 + (aPin % 8);   // portIdx 0: PB0-PB5 (D8-D13) is PCINT 0-5 (PB6/PB7 is crystal)
  }                                       // portIdx 2: PD0-PD7 (D0-D7) is PCINT 16-23
  return pcintPin;
}


/* Add a pin to be handled */
byte AddPinChangeInterrupt(uint8_t aPin) {
  volatile uint8_t *pcmask;             // pointer to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
  
  uint8_t bitM = digitalPinToBitMask(aPin);  // mask to bit in PCMSK to enable pin change interrupt for this arduino pin 
  uint8_t port = digitalPinToPort(aPin);     // port that this arduno pin belongs to for enabling interrupts

  if (port == NOT_A_PORT) 
    return 0;
    
  port -= 2;                            // from port (PB, PC, PD) to index in our array
  pcmask = port_to_pcmask[port];        // point to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
  *pcmask |= bitM;                      // set the pin change interrupt mask through a pointer to PCMSK0 or 1 or 2 
  PCICR |= 0x01 << port;                // enable the interrupt
  return 1;
}


/* Remove a pin to be handled */
byte RemovePinChangeInterrupt(uint8_t aPin) {
  volatile uint8_t *pcmask;

  uint8_t bitM = digitalPinToBitMask(aPin);
  uint8_t port = digitalPinToPort(aPin);

  if (port == NOT_A_PORT)
    return 0;

  port -= 2;                            // from port (PB, PC, PD) to index in our array
  pcmask = port_to_pcmask[port];
  *pcmask &= ~bitM;                     // clear the bit in the mask.
  if (*pcmask == 0) {                   // if that's the last one, disable the interrupt.
    PCICR &= ~(0x01 << port);
  }
  return 1;
}



void PrintErrorMsg() {
  int len = strlen_P(errorStr);
  char myChar;
  for (unsigned char k = 0; k < len; k++) {
    myChar = pgm_read_byte_near(errorStr + k);
    Serial.print(myChar);
  }
}

void printVersion() {  
  int len = strlen_P(versionStr);
  char myChar;
  for (unsigned char k = 0; k < len; k++) {
    myChar = pgm_read_byte_near(versionStr + k);
    Serial.print(myChar);
  }
}


/* 
   common interrupt handler. "port" is the PCINT port index (0-2), not PB, PC or PD which are mapped to 2-4
   
   do counting and set start / end time of interval.
   reporting is not triggered from here.
   
   only here counter[] is modified
   intervalEnd[] is set here and in report
   intervalStart[] is set in case a pin was not initialized yet and in report
*/
static void PCint(uint8_t port) {
    uint8_t bit;
    uint8_t curr;
    uint8_t delta;
    uint8_t level; 
    uint8_t pulseLevel;
    uint8_t pcintPin;
    unsigned long len;
    unsigned long now = millis();

    // get the pin states for the indicated port.
    curr  = *portInputRegister(port+2);             // current pin states at port (add 2 to get from index to PB, PC or PD)
    delta = curr ^ PCintLast[port];                 // xor gets bits that are different
    PCintLast[port] = curr;                         // store new pin state for next interrupt

    if ((delta &= *port_to_pcmask[port]) == 0)      // delta is pins that have changed. screen out non pcint pins.
        return; /* no handled pin changed */

    for (uint8_t i=0; i < 8; i++) {             // loop over each pin on the given port that changed
        bit = 0x01 << i;                         
        if (delta & bit) {                          // did this pin change?
            pcintPin = port * 8 + i;                // pcint pin numbers follow the bits, only arduino pin nums are special
            level = ((curr & bit) > 0);
            pulseLevel = (pulseWidthStart[pcintPin] == RISING); // RISING means that pulse is at high level
      
            len = now - lastChange[pcintPin];
            histIndex++;
            if (histIndex >= MAX_HIST) histIndex = 0;
            histPin[histIndex]   = pcintPin;
            histTime[histIndex]  = lastChange[pcintPin];
            histLen[histIndex]   = len;
            histLevel[histIndex] = !level;      // before it changed
            histAct[histIndex]   = ' ';
            //histI1[histIndex]    = lastLevel[pcintPin];
            
            // go on if mode is CHANGE, or if RISING and bit is high, or if mode is FALLING and bit is low.
            if (PCintMode[pcintPin] == CHANGE || level == pulseLevel) {

                if (pulseWidthMin[pcintPin]) {              // if minimal pulse length defined then check minimal pulse length and gap
        
                    if (len < pulseWidthMin[pcintPin]) {
                        lastChange[pcintPin] = now;
                        if (level != pulseLevel) {              // if change to gap level
                            rejectCounter[pcintPin]++;          // pulse too short
                            histAct[histIndex] = 'R';
                        } else {
                            histAct[histIndex] = 'X';
                        }
                    } else {

                        if (level == pulseLevel) { // edge does fit defined start, level is now pulse
                            // potential end of a valid gap, now we are at pulse level
                            if (lastLevel[pcintPin] == pulseLevel) {  // last remembered valid level was also pulse
                                // last remembered valid level was pulse, now the gap was confirmed.
                                histAct[histIndex] = 'G';
                            } else {
                                // last remembered valid level was a gap -> now we had another valid gap -> inbetween was only a spike -> ignore
                                histAct[histIndex] = 'G';
                            }
                    
                        } else {    // edge is a change to gap, level is now gap
                            // potential end of a valid pulse, now we are at gap level
                            if (lastLevel[pcintPin] != pulseLevel) {  // last remembered valid level was also gap
                                // last remembered valid level was a gap -> now we had valid new pulse -> count

                                intervalEnd[pcintPin] = now;                    // remember time of in case pulse will be the last in the interval
                                if (!firstPulse[pcintPin]) firstPulse[pcintPin] = now;    // time of first impulse in this reporting interval
                                if (initialized[pcintPin]) {
                                    counter[pcintPin]++;                    // count
                                } else {
                                    counter[pcintPin]++;                    // count
                                    counterIgn[pcintPin]++;                 // count as to be ignored for diff because it defines the start of the interval
                                    intervalStart[pcintPin] = now;              // if this is the very first impulse on this pin -> start interval now
                                    initialized[pcintPin] = true;           // and start counting the next impulse (so far counter is 0)
                                }
                                pulseWidthSum[pcintPin] += len;             // for average calculation
                                histAct[histIndex] = 'C';
                            } else {
                                // last remembered valid level was a pulse -> now we had another valid pulse
                                // inbetween was an invalid drop so pulse is already counted.
                                pulseWidthSum[pcintPin] += len;             // for average calculation
                                histAct[histIndex] = 'P';
                            }
                        }  // change to gap level

                        // remember this valid level as lastLevel
                        lastLevel[pcintPin] = !level;                       // before it changed
                        
                    } // if pulse is not too short
                                    
                } // if pulseWidth checking
            }
            lastChange[pcintPin] = now;
        } // if bit changed
    } // for 
}


/* show pulse history ring */
void showHistory() {
    uint8_t hi;
    Serial.println (F("D pulse history: "));
    unsigned long now = millis();
    unsigned long last;
    uint8_t start = (histIndex + 2) % MAX_HIST;
    for (uint8_t i = 0; i < MAX_HIST; i++) {
        hi = (start + i) % MAX_HIST;
        if (i == 0 || (last <= histTime[hi]+histLen[hi])) {
            Serial.print (F("D pin "));
            Serial.print (PCintActivePin[histPin[hi]]);
            Serial.print (F(" start "));
            Serial.print ((long) (histTime[hi] - now));
            Serial.print (F(" len "));
            Serial.print (histLen[hi]);
            Serial.print (F(" at "));
            Serial.print (histLevel[hi]);
            Serial.print (F(" "));
            Serial.print (histAct[hi]);
            Serial.println();
        }
        last = histTime[hi];
    }    
}


/* 
   report count and time for pins that are between min and max interval 
   
   lastCount[] is only modified here (count at time of last reporting)
   intervalEnd[]  is modified here and in ISR - disable interrupts in critcal moments to avoid garbage in var
   intervalStart[] is modified only here (or for very first Interrupt in ISR) -> no problem.
*/
void report() {
  int aPin;
  unsigned long count, countIgn, countDiff, realDiff;
  unsigned long timeDiff, now;
  unsigned long startT, endT;
  unsigned long avgLen;
  now = millis();
  
  for (int pcintPin=0; pcintPin < MAX_PCINT_PIN; pcintPin++) { // go through all observed pins as PCINT pin number
    aPin = PCintActivePin[pcintPin];                        // take saved arduino pin number
    if (aPin < 1) continue;                                 // 0 means pin is not active for reporting
    noInterrupts();
    startT   = intervalStart[pcintPin];
    endT     = intervalEnd[pcintPin];
    count    = counter[pcintPin];                           // get current counter (counts all pulses
    countIgn = counterIgn[pcintPin];                        // pulses that mark the beginning of an interval and should not be taken into calculation (happens after restart)
    interrupts();
        
    timeDiff  = endT - startT;                              // time between first and last impulse during interval
    countDiff = count - countIgn - lastCount[pcintPin];     // how many pulses during intervall since last report? (ignore forst pulse after device restart) 
    realDiff  = count - lastCount[pcintPin];                        // (works with wrapping)
    if((long)(now - (lastReport[pcintPin] + intervalMax)) >= 0) { // intervalMax is over
      if ((countDiff >= countMin) && (timeDiff > intervalSml) && (intervalMin != intervalMax)) {
        // normal procedure
        lastCount[pcintPin]  = count;                      // remember current count for next interval
        noInterrupts();
        intervalStart[pcintPin]  = endT;                       // time of last impulse in this interval becomes also time of first impulse in next
        counterIgn[pcintPin] = 0;
        interrupts();
      } else {
        // nothing counted or counts happened during a fraction of intervalMin only
        noInterrupts();
        intervalEnd[pcintPin]   = now;                        // don't calculate with last impulse, use now instead
        intervalStart[pcintPin]  = now;                        // start a new interval for next report now
        counterIgn[pcintPin] = 0;
        interrupts();
        lastCount[pcintPin] = count;                      // remember current count for next interval
        timeDiff  = now - startT;                         // special handling - calculation ends now instead of last impulse
      }        
    } else if((long)(now - (lastReport[pcintPin] + intervalMin)) >= 0) {  // minInterval has elapsed      
      if ((countDiff >= countMin) && (timeDiff > intervalSml)) {
        // normal procedure
        lastCount[pcintPin]  = count;                      // remember current count for next interval
        noInterrupts();
        intervalStart[pcintPin]  = endT;                       // time of last impulse in this interval becomes also time of first impulse in next
        counterIgn[pcintPin] = 0;
        interrupts();
      } else continue;              // not enough counted - wait                        
    } else continue;                // intervalMin not over - wait

    Serial.print(F("R"));           // R Report
    Serial.print(aPin);
    Serial.print(F(" C"));          // C - Count
    Serial.print(count);
    Serial.print(F(" D"));          // D - Count Diff (without pulse that marks the begin of an interval)
    Serial.print(countDiff);
    Serial.print(F(" R"));          // R - real Diff for incrementing long counter in Fhem - includes even the first pulse after restart
    Serial.print(realDiff);
    Serial.print(F(" T"));          // T - Time
    Serial.print(timeDiff);  
    Serial.print(F(" N"));          // N - now
    Serial.print((long)now);
    
    // rejected count ausgeben
    // evt auch noch average pulse len und gap len
    if (pulseWidthMin[pcintPin]) {  // check minimal pulse length and gap
      Serial.print(F(" X"));        // X Reject
      Serial.print(rejectCounter[pcintPin] - lastRejCount[pcintPin]);  
      noInterrupts();
      lastRejCount[pcintPin] = rejectCounter[pcintPin];
      interrupts();
    }

    if (realDiff) {
      Serial.print(F(" F"));        // F - first impulse after the one that started the interval
      Serial.print((long)firstPulse[pcintPin] - startT);
      Serial.print(F(" L"));        // L - last impulse - marking the end of this interval
      Serial.print((long)endT - startT);
      firstPulse[pcintPin] = 0;
      
      if (pulseWidthMin[pcintPin]) {// check minimal pulse length and gap
        noInterrupts();
        avgLen = pulseWidthSum[pcintPin] / countDiff;
        pulseWidthSum[pcintPin] = 0;
        interrupts();
        Serial.print(F(" A"));
        Serial.print(avgLen);
      }
    }   
    
    uint8_t hi;
    boolean first = true;
    uint8_t start = (histIndex + 2) % MAX_HIST;
	unsigned long last;
    Serial.print (F(" H"));
    for (uint8_t i = 0; i < MAX_HIST; i++) {
        hi = (start + i) % MAX_HIST;
        if (histPin[hi] == pcintPin) {
	        if (first || (last <= histTime[hi]+histLen[hi])) {
				if (!first) 
					Serial.print (F(", "));
				//Serial.print (F(""));
				Serial.print ((long) (histTime[hi] - now));
				Serial.print (F("/"));
				Serial.print (histLen[hi]);
				Serial.print (F(":"));
				Serial.print (histLevel[hi]);
				//Serial.print (F(" "));
				Serial.print (histAct[hi]);
				first = false;
			}
			last = histTime[hi];
        }
    }    
    
    Serial.println();    
    lastReport[pcintPin] = now;     // remember when we reported 
  }
}


/* print status for one pin */
void showPin(byte pcintPin) {
    unsigned long newCount, countIgn, countDiff;
    unsigned long timeDiff;
    unsigned long avgLen;

    timeDiff  = intervalEnd[pcintPin] - intervalStart[pcintPin];
    newCount  = counter[pcintPin];
    countIgn  = counterIgn[pcintPin];
    countDiff = newCount - countIgn - lastCount[pcintPin];
    if (!timeDiff) 
        timeDiff = millis() - intervalStart[pcintPin];     

    Serial.print(F("PCInt pin "));
    Serial.print(pcintPin);
      
    Serial.print(F(", iMode "));
    switch (PCintMode[pcintPin]) {
        case RISING: Serial.print(F("rising")); break;
        case FALLING: Serial.print(F("falling")); break;
        case CHANGE: Serial.print(F("change")); break;
    }
    if (pulseWidthMin[pcintPin] > 0) {
        Serial.print(F(", min len "));
        Serial.print(pulseWidthMin[pcintPin]);
        Serial.print(F(" ms"));
        switch (pulseWidthStart[pcintPin]) {
          case RISING: Serial.print(F(" rising")); break;
          case FALLING: Serial.print(F(" falling")); break;
        }        
    } else {
        Serial.print(F(", no min len"));
    }
    Serial.print(F(", count "));
    Serial.print(newCount);
    Serial.print(F(" (+"));
    Serial.print(countDiff);
    Serial.print(F(") in "));
    Serial.print(timeDiff);
    Serial.print(F(" ms"));

    // rejected count ausgeben
    // evt auch noch average pulse len und gap len
    if (pulseWidthMin[pcintPin]) {      // check minimal pulse length and gap
        Serial.print(F(" Rej "));
        Serial.print(rejectCounter[pcintPin] - lastRejCount[pcintPin]);  
    }
    if (countDiff) {
        Serial.println();
        Serial.print(F("M   first at "));
        Serial.print((long)firstPulse[pcintPin] - lastReport[pcintPin]);
        Serial.print(F(", last at "));
        Serial.print((long)intervalEnd[pcintPin] - lastReport[pcintPin]);
        noInterrupts();
        avgLen = pulseWidthSum[pcintPin] / countDiff;
        interrupts();
        Serial.print(F(", avg len "));
        Serial.print(avgLen);
    }
}


/* give status report in between if requested over serial input */
void showCmd() {
  Serial.print(F("M Status: "));
  printVersion();
  Serial.println();
  Serial.print(F("M normal interval "));
  Serial.println(intervalMin);
  Serial.print(F("M max interval "));
  Serial.println(intervalMax);
  Serial.print(F("M min interval "));
  Serial.println(intervalSml);
  Serial.print(F("M min count "));
  Serial.println(countMin);
  
  for (byte pcintPin=0; pcintPin < MAX_PCINT_PIN; pcintPin++) {
    int aPin = PCintActivePin[pcintPin];
    if (aPin > 0) {
      Serial.print(F("M pin "));
      Serial.print(aPin);
      Serial.print(F(" "));
      showPin(pcintPin);      
      Serial.println();
    }
  }
  Serial.print(F("M Next report in "));
  Serial.print(timeNextReport - millis());
  Serial.print(F(" Milliseconds"));
  Serial.println();  
  showHistory();
}



/*
    handle add command.
    todo: check size and clear options not passed
*/
void addCmd(unsigned int *values, byte size) {
  uint8_t pcintPin;                         // PCINT pin number for the pin to be added (used as index for most arrays)
  byte mode = 2;
  uint8_t port;
  unsigned int pw;
  unsigned long now = millis();
  

  //Serial.println(F("M Add called"));
  int aPin = values[0];                     // value 0 is pin number
  pcintPin = digitalPinToPcIntPin(aPin);
  if (aPin >= MAX_ARDUINO_PIN || aPin < 1 
        || allowedPins[aPin] == 0 || pcintPin > MAX_PCINT_PIN) {
    PrintErrorMsg(); 
    Serial.print(F("Illegal pin specification "));
    Serial.println(aPin);
    return;
  }; 
  port = digitalPinToPort(aPin) - 2;
  
  switch (values[1]) {                      // value 1 is rising / falling etc.
    case 2:
      mode = FALLING;
      pulseWidthStart[pcintPin] = FALLING;
      break;
    case 3:
      mode = RISING;       
      pulseWidthStart[pcintPin] = RISING;
      break;
    case 1:
      mode = CHANGE;
      break;
    default:
      PrintErrorMsg(); 
      Serial.print(F("Illegal mode for pin specification "));
      Serial.println(aPin);
  }
  
  pinMode (aPin, INPUT);
  if (size > 2 && values[2]) {              // value 2 is pullup
    digitalWrite (aPin, HIGH);              // enable pullup resistor
  }

  if (size > 3 && values[3] > 0) {          // value 3 is min length (if given)
    pw = values[3];
    mode = CHANGE;
  } else {
    pw = 0;
  }  
  
  if (!AddPinChangeInterrupt(aPin)) {       // add Pin Change Interrupt
    PrintErrorMsg(); Serial.println(F("AddInt"));
    return;
  }  
  PCintMode[pcintPin] = mode;               // save mode for ISR which uses the pcintPin as index 

  pulseWidthMin[pcintPin] = pw;             // minimal pulse width in millis, 0 if not specified in add cmd  todo: needs fixing! values[3] might contain data from last command
  
  if (PCintActivePin[pcintPin] != aPin) {   // in case this pin is not already active counting
      PCintLast[port]          = *portInputRegister(port+2);   // current pin states at port      
      PCintActivePin[pcintPin] = aPin;      // save real arduino pin number and flag this pin as active for reporting
      initialized[pcintPin]    = false;     // initialize arrays for this pin
      counter[pcintPin]        = 0;            
      counterIgn[pcintPin]     = 0;            
      lastCount[pcintPin]      = 0;
      intervalStart[pcintPin]  = now;     
      intervalEnd[pcintPin]    = now;
      lastReport[pcintPin]     = now;       // next reporting cycle is probably earlier than now+intervalMin (already started) so report will be later than next interval     
      lastChange[pcintPin]     = now;
      rejectCounter[pcintPin]  = 0;        
      lastRejCount[pcintPin]   = 0;
  }
  Serial.print(F("M defined pin ")); 
  Serial.print(aPin);
  Serial.print(F(" ")); 
  showPin(pcintPin);    
  Serial.println();
}


/*
    handle rem command.
*/
void removeCmd(unsigned int *values, byte size) {
  uint8_t pcintPin;                         // PCINT pin number for the pin to be added (used as index for most arrays) 
  int aPin = values[0];
  pcintPin = digitalPinToPcIntPin(aPin);
  if (size < 1 || aPin >= MAX_ARDUINO_PIN || aPin < 1 
        || allowedPins[aPin] == 0 || pcintPin > MAX_PCINT_PIN) {
    PrintErrorMsg(); 
    Serial.print(F("Illegal pin specification "));
    Serial.println(aPin);
    return;
  };
  
  if (!RemovePinChangeInterrupt(aPin)) {      
    PrintErrorMsg(); Serial.println(F("RemInt"));
    return;
  }
  
  PCintActivePin[pcintPin] = 0;
  initialized[pcintPin]    = false;         // reset for next add
  counter[pcintPin]        = 0;            
  counterIgn[pcintPin]     = 0;            
  lastCount[pcintPin]      = 0;
  pulseWidthMin[pcintPin]  = 0;
  lastRejCount[pcintPin]   = 0;
  rejectCounter[pcintPin]  = 0;

  Serial.print(F("M removed "));
  Serial.println(aPin);
}



void intervalCmd(unsigned int *values, byte size) {
  if (size < 4) {               // i command always gets 4 values: min, max, sml, cntMin
    PrintErrorMsg();
    Serial.print(F("size"));
    Serial.println();
    return;
  }
  if (values[0] < 1 || values[0] > 3600) {
    PrintErrorMsg(); Serial.println(values[0]);
    return;
  }
  intervalMin = (long)values[0] * 1000;
  if (millis() + intervalMin < timeNextReport)
    timeNextReport = millis() + intervalMin;

  if (values[1] < 1 || values[1] > 3600) {
    PrintErrorMsg(); Serial.println(values[1]);
    return;
  }
  intervalMax = (long)values[1]* 1000;
 
  if (values[2] > 3600) {
    PrintErrorMsg(); Serial.println(values[2]);
    return;
  }
  intervalSml = (long)values[2] * 1000;    
  countMin = values[3];

  Serial.print(F("M intervals set to ")); 
  Serial.print(values[0]);
  Serial.print(F(" ")); 
  Serial.print(values[1]);
  Serial.print(F(" ")); 
  Serial.print(values[2]);
  Serial.print(F(" ")); 
  Serial.print(values[3]);
  Serial.println();
}


void helloCmd() {
  Serial.println();
  printVersion();
  Serial.println(F("Hello"));
}


static void HandleSerialPort(char c) {
  static unsigned int value;

  if (c == ',') {
    if (commandDataPointer < (MAX_INPUT_NUM - 1)) {
        commandData[commandDataPointer] = value;
        commandDataPointer++;
        value = 0;
    }
  }
  else if ('0' <= c && c <= '9') {
    value = 10 * value + c - '0';
  }
  else if ('a' <= c && c <= 'z') {
    switch (c) {
    case 'a':
      commandData[commandDataPointer] = value;
      addCmd(commandData, ++commandDataPointer);
      break;
    case 'd':
      commandData[commandDataPointer] = value;
      removeCmd(commandData, ++commandDataPointer);
      break;
    case 'i':
      commandData[commandDataPointer] = value;
      intervalCmd(commandData, ++commandDataPointer);
      break;
    case 'r':
      initialize();
      break;
    case 's':
      showCmd();
      break;
    case 'h':
      helloCmd();
      break;
    default:
      //PrintErrorMsg(); Serial.println();
      break;
    }
    commandDataPointer = 0;
    value = 0;
    for (byte i=0; i < MAX_INPUT_NUM; i++)
        commandData[i] = 0;     
  }
}



SIGNAL(PCINT0_vect) {
  PCint(0);
}
SIGNAL(PCINT1_vect) {
  PCint(1);
}
SIGNAL(PCINT2_vect) {
  PCint(2);
}



void initialize() {
  unsigned long now = millis();

  Serial.println();
  printVersion();
  Serial.println(F(" Started"));
  
  for (int pcintPin=0; pcintPin < MAX_PCINT_PIN; pcintPin++) {
    PCintActivePin[pcintPin] = 0;           // set all pins to inactive (0)
    initialized[pcintPin]    = false;       // initialize arrays for this pin
    counter[pcintPin]        = 0;    
    counterIgn[pcintPin]     = 0;    
    lastCount[pcintPin]      = 0;
    intervalStart[pcintPin]  = now;     
    intervalEnd[pcintPin]    = now;
    lastChange[pcintPin]     = now;
    pulseWidthMin[pcintPin]  = 0;
    rejectCounter[pcintPin]  = 0;        
    lastRejCount[pcintPin]   = 0;
    lastReport[pcintPin]     = now;
  }   

  for (unsigned int port=0; port <= 2; port++) {
    PCintLast[port] = *portInputRegister(port+2); // current pin states at port
  }
  
  timeNextReport = millis() + intervalMin;      // time for first output
}


void setup() {
    Serial.begin(SERIAL_SPEED);                 // initialize serial
    delay (500);
    interrupts();
    initialize();  
}


/*
   Main Loop  
   checks if report should be called because timeNextReport is reached
      or lastReport for one pin is older than intervalMax   
   timeNextReport is only set here (and when interval is changed / at setup)
*/
void loop() {
  unsigned long now = millis();
  
  if (Serial.available()) {
    HandleSerialPort(Serial.read());
  }
  boolean doReport  = false;                     // check if report nedds to be called
  if((long)(now - timeNextReport) >= 0)          // works fine when millis wraps.
    doReport = true;                             // intervalMin is over 
  else 
    for (byte pcintPin=0; pcintPin < MAX_PCINT_PIN; pcintPin++)  
      if (PCintActivePin[pcintPin] > 0)
        if((long)(now - (lastReport[pcintPin] + intervalMax)) >= 0)
          doReport = true;                       // active pin has not been reported for langer than intervalMax

  if (doReport) {    
    report();
    timeNextReport = now + intervalMin;          // do it again after intervalMin millis
  }
}

