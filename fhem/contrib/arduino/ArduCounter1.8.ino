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
        
        ToDo / Ideas:   
                                
                new index scheme to save memory:
                    array to map from pcintPin to new index, limit allowed pins.
                    unused pcintpins point to -1 and vomment states arduino pin number
                    insread of allowedPins array use new function from aPin to pcintPin
                    and then look up in new array for index or -1
*/ 
 
#include "pins_arduino.h"

const char versionStr[] PROGMEM = "ArduCounter V1.8";
const char errorStr[]   PROGMEM = "Error: ";

#define enablePulseLenChecking 1

#define SERIAL_SPEED 38400
#define MAX_ARDUINO_PIN 24
#define MAX_PCINT_PIN 24
#define MAX_INPUT_NUM 8

/* arduino pins that are typically ok to use 
 * (some are left out because they are used 
 * as reset, serial, led or other things on most boards) */
byte allowedPins[MAX_ARDUINO_PIN] = 
  { 0,  0,  0,  3,  4, 5, 6, 7,
    0,  9, 10, 11, 12, 0,
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

/* pin change mode (RISING etc.) as parameter for ISR */
byte PCintMode[MAX_PCINT_PIN];
/* mode for timing pulse length - derived from PCintMode (RISING etc. */
byte PulseMode[MAX_PCINT_PIN];

/* pin number for PCINT number if active - otherwise -1 */
char PCintActivePin[MAX_PCINT_PIN];

/* did we get first interrupt yet? */
volatile boolean initialized[MAX_PCINT_PIN];
 
/* individual counter for each real pin */
volatile unsigned long counter[MAX_PCINT_PIN];
/* count at last report to get difference */
unsigned long lastCount[MAX_PCINT_PIN];

#ifdef enablePulseLenChecking
/* individual reject counter for each real pin */
volatile unsigned int rejectCounter[MAX_PCINT_PIN];
unsigned int lastRejCount[MAX_PCINT_PIN];

/* millis at last interrupt when signal was rising (for filtering with min pulse length) */
volatile unsigned long lastPulseStart[MAX_PCINT_PIN];

/* millis at last interrupt when signal was falling (for filtering with min pulse length) */
volatile unsigned long lastPulseEnd[MAX_PCINT_PIN];

/* minimal pulse length in millis */
/* specified instead of rising or falling. isr needs to check change anyway */
unsigned int pulseWidthMin[MAX_PCINT_PIN];

/* sum of pulse lengths for average output */
volatile unsigned long pulseWidthSum[MAX_PCINT_PIN];

/* start of pulse for measuring length */
byte pulseWidthStart[MAX_PCINT_PIN];

#endif

/* millis at first interrupt for current calculation
 * (is also last interrupt of old interval) */
volatile unsigned long startTime[MAX_PCINT_PIN];

/* millis at last interrupt */
volatile unsigned long lastTime[MAX_PCINT_PIN];

/* millis at first interrupt in a reporting cycle */
volatile unsigned long startTimeRepInt[MAX_PCINT_PIN];


/* millis at last report 
 * to find out when maxInterval is over
 * and report has to be done even if
 * no impulses were counted */
unsigned long lastReport[MAX_PCINT_PIN];

unsigned int commandData[MAX_INPUT_NUM];
byte commandDataPointer = 0;


int digitalPinToPcIntPin(uint8_t aPin) {
  uint8_t pcintPin;                             // PCINT pin number for the pin to be added (index for most arrays)  
  uint8_t port = digitalPinToPort(aPin) - 2;    // port that this arduno pin belongs to for enabling interrupts

  if (port == 1) {                      // now calculate the PCINT pin number that corresponds to the arduino pin number
     pcintPin = aPin - 6;               // port 1: PC0-PC5 (A0-A5 or D14-D19) is PCINT 8-13 (PC6 is reset)
  } else {                              // arduino numbering continues at D14 since PB6/PB7 are used for other things 
     pcintPin = port * 8 + (aPin % 8);  // port 0: PB0-PB5 (D8-D13) is PCINT 0-5 (PB6/PB7 is crystal)
  }                                     // port 2: PD0-PD7 (D0-D7) is PCINT 16-23
  return pcintPin;
}


/* Add a pin to be handled */
byte AddPinChangeInterrupt(uint8_t aPin) {
  uint8_t pcintPin;                     // PCINT pin number for the pin to be added (used as index for most arrays)
  volatile uint8_t *pcmask;             // pointer to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
  
  uint8_t bit  = digitalPinToBitMask(aPin);  // bit in PCMSK to enable pin change interrupt for this arduino pin 
  uint8_t port = digitalPinToPort(aPin);     // port that this arduno pin belongs to for enabling interrupts

  if (port == NOT_A_PORT) 
    return 0;
    
  port -= 2;
  pcmask = port_to_pcmask[port];        // point to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
  *pcmask |= bit;                       // set the pin change interrupt mask through a pointer to PCMSK0 or 1 or 2 
  PCICR |= 0x01 << port;                // enable the interrupt
  return 1;
}


/* Remove a pin to be handled */
byte RemovePinChangeInterrupt(uint8_t aPin) {
  uint8_t pcintPin;
  volatile uint8_t *pcmask;

  uint8_t bit  = digitalPinToBitMask(aPin);
  uint8_t port = digitalPinToPort(aPin);

  if (port == NOT_A_PORT)
    return 0;

  port -= 2;
  pcmask = port_to_pcmask[port];
  *pcmask &= ~bit;      // disable the mask.
  if (*pcmask == 0) {   // if that's the last one, disable the interrupt.
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
   common interrupt handler. "port" is the PCINT port number (0-2)
   
   do counting and set start / end time of interval.
   reporting is not triggered from here.
   
   only here counter[] is modified
   lastTime[] is set here and in report
   startTime[] is set in case a pin was not initialized yet and in report
*/
static void PCint(uint8_t port) {
  uint8_t bit;
  uint8_t curr;
  uint8_t mask;
  uint8_t pcintPin;
  unsigned long now = millis();
#ifdef enablePulseLenChecking
  unsigned long len, gap;
#endif
  // get the pin states for the indicated port.
  curr = *portInputRegister(port+2);         // current pin states at port
  mask = curr ^ PCintLast[port];             // xor gets bits that are different
  PCintLast[port] = curr;                    // store new pin state for next interrupt

  if ((mask &= *port_to_pcmask[port]) == 0)  // mask is pins that have changed. screen out non pcint pins.
    return; /* no handled pin changed */

  for (uint8_t i=0; i < 8; i++) {
    bit = 0x01 << i;                         // loop over each pin that changed
    if (bit & mask) {                        // did this pin change?
      pcintPin = port * 8 + i;               // pcint pin numbers follow the bits, only arduino pin nums are special

      // count if mode is CHANGE, or if RISING and bit is high, or if mode is FALLING and bit is low.
      if ((PCintMode[pcintPin] == CHANGE
          || ((PCintMode[pcintPin] == RISING)  && (curr & bit))
          || ((PCintMode[pcintPin] == FALLING) && !(curr & bit)))) {
#ifdef enablePulseLenChecking
        if (pulseWidthMin[pcintPin]) {      // check minimal pulse length and gap
           if (  ( (curr & bit) && pulseWidthStart[pcintPin] == RISING) 
              || (!(curr & bit) && pulseWidthStart[pcintPin] == FALLING)) { // edge does fit defined start
            lastPulseStart[pcintPin] = now;
            continue;
          } else {                          // End of defined pulse
            gap = lastPulseStart[pcintPin] - lastPulseEnd[pcintPin];
            len = now - lastPulseStart[pcintPin];
            lastPulseEnd[pcintPin] = now;
            if (len < pulseWidthMin[pcintPin] || gap < pulseWidthMin[pcintPin]) {
                rejectCounter[pcintPin]++;  // pulse too short
                continue;
            }
            pulseWidthSum[pcintPin] += len; // for average calculation
          }
        }
#endif
        lastTime[pcintPin] = now;            // remember time of in case pulse will be the last in the interval
        if (!startTimeRepInt[pcintPin]) startTimeRepInt[pcintPin] = now;    // time of first impulse in this reporting interval
        if (initialized[pcintPin]) {
          counter[pcintPin]++;                      // count
        } else {
          startTime[pcintPin] = lastTime[pcintPin]; // if this is the very first impulse on this pin -> start interval now
          initialized[pcintPin] = true;             // and start counting the next impulse (so far counter is 0)
        }
      }
    }
  }
}


/* 
   report count and time for pins that are between min and max interval 
   
   lastCount[] is only modified here (count at time of last reporting)
   lastTime[]  is modified here and in ISR - disable interrupts in critcal moments to avoid garbage in var
   startTime[] is modified only here (or for very first Interrupt in ISR) -> no problem.
*/
void report() {
  int aPin;
  unsigned long count, countDiff;
  unsigned long timeDiff, now;
  unsigned long startT, endT;
  unsigned long avgLen;
  now = millis();
  for (int pcintPin=0; pcintPin < MAX_PCINT_PIN; pcintPin++) { // go through all observed pins as PCINT pin number
    aPin = PCintActivePin[pcintPin];                        // take saved arduino pin number
    if (aPin < 0) continue;                                 // -1 means pin is not active for reporting
    noInterrupts();
    startT = startTime[pcintPin];
    endT   = lastTime[pcintPin];
    count  = counter[pcintPin];                             // get current counter
    interrupts();
    
    timeDiff  = endT - startT;                              // time between first and last impulse during interval
    countDiff = count - lastCount[pcintPin];                // how many impulses since last report? (works with wrapping)

    if((long)(now - (lastReport[pcintPin] + intervalMax)) >= 0) { // intervalMax is over
      if ((countDiff >= countMin) && (timeDiff > intervalSml) && (intervalMin != intervalMax)) {
        // normal procedure
        lastCount[pcintPin] = count;                      // remember current count for next interval
        noInterrupts();
        startTime[pcintPin] = endT;                       // time of last impulse in this interval becomes also time of first impulse in next
        interrupts();
      } else {
        // nothing counted or counts happened during a fraction of intervalMin only
        noInterrupts();
        lastTime[pcintPin]  = now;                        // don't calculate with last impulse, use now instead
        startTime[pcintPin] = now;                        // start a new interval for next report now
        interrupts();
        lastCount[pcintPin] = count;                      // remember current count for next interval
        timeDiff  = now - startT;                         // special handling - calculation ends now instead of last impulse
      }        
    } else if((long)(now - (lastReport[pcintPin] + intervalMin)) >= 0) {  // minInterval has elapsed
      if ((countDiff >= countMin) && (timeDiff > intervalSml)) {
        // normal procedure
        lastCount[pcintPin] = count;                      // remember current count for next interval
        noInterrupts();
        startTime[pcintPin] = endT;                       // time of last impulse in this interval becomes also time of first impulse in next
        interrupts();
      } else continue;  			// not enough counted - wait                        
    } else continue;    			// intervalMin not over - wait

    Serial.print(F("R"));			// R Report
    Serial.print(aPin);
    Serial.print(F(" C"));			// C - Count
    Serial.print(count);
    Serial.print(F(" D"));			// D - Count Diff
    Serial.print(countDiff);
    Serial.print(F(" T"));			// T - Time
    Serial.print(timeDiff);  
    Serial.print(F(" N"));      // N - now
    Serial.print((long)now);
    
#ifdef enablePulseLenChecking
    // rejected count ausgeben
    // evt auch noch average pulse len und gap len
    if (pulseWidthMin[pcintPin]) { 	// check minimal pulse length and gap
      Serial.print(F(" X"));		// X Reject
      Serial.print(rejectCounter[pcintPin] - lastRejCount[pcintPin]);  
      noInterrupts();
      lastRejCount[pcintPin] = rejectCounter[pcintPin];
      interrupts();
    }
#endif

    if (countDiff) {
      Serial.print(F(" F"));		// F - first impulse after the one that started the interval
      Serial.print((long)startTimeRepInt[pcintPin] - startT);
      Serial.print(F(" L"));		// L - last impulse - marking the end of this interval
      Serial.print((long)endT - startT);
      startTimeRepInt[pcintPin] = 0;
	  
#ifdef enablePulseLenChecking
      if (pulseWidthMin[pcintPin]) {// check minimal pulse length and gap
        noInterrupts();
        avgLen = pulseWidthSum[pcintPin] / countDiff;
        pulseWidthSum[pcintPin] = 0;
        interrupts();
        Serial.print(F(" A"));
        Serial.print(avgLen);
      }
#endif
    }   
    Serial.println();    
    lastReport[pcintPin] = now;		// remember when we reported 
  }
}


/* print status for one pin */
void showPin(byte pcintPin) {
    unsigned long newCount;
    unsigned long countDiff;
    unsigned long timeDiff;
    unsigned long avgLen;

    timeDiff = lastTime[pcintPin] - startTime[pcintPin];
    newCount = counter[pcintPin];
    countDiff = newCount - lastCount[pcintPin];
    if (!timeDiff) 
        timeDiff = millis() - startTime[pcintPin];     

    Serial.print(F("PCInt pin "));
    Serial.print(pcintPin);
      
    Serial.print(F(", iMode "));
    switch (PCintMode[pcintPin]) {
        case RISING: Serial.print(F("rising")); break;
        case FALLING: Serial.print(F("falling")); break;
        case CHANGE: Serial.print(F("change")); break;
    }
#ifdef enablePulseLenChecking
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
#endif
    Serial.print(F(", count "));
    Serial.print(newCount);
    Serial.print(F(" (+"));
    Serial.print(countDiff);
    Serial.print(F(") in "));
    Serial.print(timeDiff);
    Serial.print(F(" ms"));
#ifdef enablePulseLenChecking
    // rejected count ausgeben
    // evt auch noch average pulse len und gap len
    if (pulseWidthMin[pcintPin]) {      // check minimal pulse length and gap
        Serial.print(F(" Rej "));
        Serial.print(rejectCounter[pcintPin] - lastRejCount[pcintPin]);  
    }
#endif
    if (countDiff) {
        Serial.println();
        Serial.print(F("M   first at "));
        Serial.print((long)startTimeRepInt[pcintPin] - lastReport[pcintPin]);
        Serial.print(F(", last at "));
        Serial.print((long)lastTime[pcintPin] - lastReport[pcintPin]);
#ifdef enablePulseLenChecking
        noInterrupts();
        avgLen = pulseWidthSum[pcintPin] / countDiff;
        interrupts();
        Serial.print(F(", avg len "));
        Serial.print(avgLen);
#endif
    }
}


/* give status report in between if requested over serial input */
void showCmd() {
  unsigned long newCount;
  unsigned long countDiff;
  unsigned long timeDiff;
  unsigned long avgLen;
  char myChar;

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
    if (aPin != -1) {
      timeDiff = lastTime[pcintPin] - startTime[pcintPin];
      newCount = counter[pcintPin];
      countDiff = newCount - lastCount[pcintPin];
      if (!timeDiff) 
        timeDiff = millis() - startTime[pcintPin];     
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
}


/*
    handle add command.
*/
void addCmd(unsigned int *values, byte size) {
  uint8_t pcintPin;                         // PCINT pin number for the pin to be added (used as index for most arrays)
  byte mode;
  unsigned int pw;
  unsigned long now = millis();

  //Serial.println(F("M Add called"));
  int aPin = values[0];
  pcintPin = digitalPinToPcIntPin(aPin);
  if (aPin >= MAX_ARDUINO_PIN || aPin < 1 
        || allowedPins[aPin] == 0 || pcintPin > MAX_PCINT_PIN) {
    PrintErrorMsg(); 
    Serial.print(F("Illegal pin specification "));
    Serial.println(aPin);
    return;
  }; 
  
  switch (values[1]) {
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
      Serial.print(F("Illegal pin specification "));
      Serial.println(aPin);
  }
  
  pinMode (aPin, INPUT);
  if (values[2]) {
    digitalWrite (aPin, HIGH);              // enable pullup resistor
  }

#ifdef enablePulseLenChecking 
  PulseMode[pcintPin] = mode;               // specified mode also defines pulse level in this case
  if (values[3] > 0) {
    pw = values[3];
    mode = CHANGE;
  } else {
    pw = 0;
  }  
#endif  
  
  if (!AddPinChangeInterrupt(aPin)) {       // add Pin Change Interrupt
    PrintErrorMsg(); Serial.println(F("AddInt"));
    return;
  }  
  PCintMode[pcintPin] = mode;               // save mode for ISR which uses the pcintPin as index 

#ifdef enablePulseLenChecking
  pulseWidthMin[pcintPin] = pw;             // minimal pulse width in millis, 3 if not specified n add cmd
#endif
  
  if (PCintActivePin[pcintPin] != aPin) {   // in case this pin is already active counting
      PCintActivePin[pcintPin] = aPin;      // save real arduino pin number and flag this pin as active for reporting
      initialized[pcintPin] = false;        // initialize arrays for this pin
      counter[pcintPin]     = 0;            
      lastCount[pcintPin]   = 0;
      startTime[pcintPin]   = now;     
      lastTime[pcintPin]    = now;
      lastReport[pcintPin]  = now;
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
  if (aPin >= MAX_ARDUINO_PIN || aPin < 1 
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
  
  PCintActivePin[pcintPin] = -1;
  initialized[pcintPin]    = false;         // reset for next add
  counter[pcintPin]        = 0;            
  lastCount[pcintPin]      = 0;
#ifdef enablePulseLenChecking
  pulseWidthMin[pcintPin]  = 0;
  lastRejCount[pcintPin]   = 0;
  rejectCounter[pcintPin]  = 0;
#endif

  Serial.print(F("M removed "));
  Serial.println(aPin);
}



void intervalCmd(unsigned int *values, byte size) {
  if (size < 4) {
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
  if (values[2] > 0) {
    intervalSml = (long)values[2] * 1000;
  }
    
  if (values[3]> 0) {
    countMin = values[3];
  }
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
    if (commandDataPointer + 1 < MAX_INPUT_NUM) {
        commandData[commandDataPointer++] = value;
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
      commandDataPointer = 0;
      break;

    case 'd':
      commandData[commandDataPointer] = value;
      removeCmd(commandData, ++commandDataPointer);
      commandDataPointer = 0;
      break;

    case 'i':
      commandData[commandDataPointer] = value;
      intervalCmd(commandData, ++commandDataPointer);
      commandDataPointer = 0;
      break;

    case 'r':
      setup();
      commandDataPointer = 0;
      break;

    case 's':
      showCmd();
      commandDataPointer = 0;
      break;

    case 'h':
      helloCmd();
      commandDataPointer = 0;
      break;

    default:
      commandDataPointer = 0;
      //PrintErrorMsg(); Serial.println();
      break;
    }
    value = 0;
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


void setup() {
  unsigned long now = millis();
  
  for (int pcintPin=0; pcintPin < MAX_PCINT_PIN; pcintPin++) {
    PCintActivePin[pcintPin] = -1;          // set all pins to inactive (-1)
    initialized[pcintPin]    = false;       // initialize arrays for this pin
    counter[pcintPin]        = 0;    
    lastCount[pcintPin]      = 0;
    startTime[pcintPin]      = now;     
    lastTime[pcintPin]       = now;
#ifdef enablePulseLenChecking
    lastPulseStart[pcintPin] = now;
    lastPulseEnd[pcintPin]   = now;
    pulseWidthMin[pcintPin]  = 0;
    rejectCounter[pcintPin]  = 0;        
    lastRejCount[pcintPin]   = 0;
#endif
    lastReport[pcintPin]     = now;
  } 
  
  timeNextReport = millis() + intervalMin;  // time for first output
  Serial.begin(SERIAL_SPEED);               // initialize serial
  delay (500);
  interrupts();
  Serial.println();
  printVersion();
  Serial.println(F("Started"));
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
      if (PCintActivePin[pcintPin] >= 0)
        if((long)(now - (lastReport[pcintPin] + intervalMax)) >= 0)
          doReport = true;                       // active pin has not been reported for langer than intervalMax
  if (doReport) {    
    report();
    timeNextReport = now + intervalMin;          // do it again after intervalMin millis
  }
}

