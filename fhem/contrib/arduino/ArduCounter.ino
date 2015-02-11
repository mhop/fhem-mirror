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
 * D0-D7 = PCINT 16-23 = PCIR2 = PD = PCIE2 = pcmsk2
 * D8-D13 = PCINT 0-5 = PCIR0 = PB = PCIE0 = pcmsk0
 * A0-A5 (D14-D19) = PCINT 8-13 = PCIR1 = PC = PCIE1 = pcmsk1
 */

#include "pins_arduino.h"

char* version = "ArduCounter V1.0";
char* error = "error ";

/* arduino pins that are typically ok to use 
 * (some are left out because they are used 
 * as reset, serial, led or other things on most boards) */
byte allowedPins[20] = 
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


unsigned long intervalMin =  10000; // default 10 sec
unsigned long intervalMax = 120000; // default 2 min

unsigned long timeNextReport;
unsigned long now;

boolean doReport = false;

/* index to the following arrays is the internal PCINT pin number, not the arduino 
 * pin number because the PCINT pin number corresponds to the physical ports
 * and this saves time for mapping to the arduino numbers
 */

/* pin change mode (RISING etc.) as parameter for ISR */
byte PCintMode[24];

/* pin number for PCINT number if active - otherwise -1 */
char PCintActivePin[24];

/* did we get first interrupt yet? */
volatile boolean initialized[24];
 
/* individual counter for each real pin */
volatile unsigned long counter[24];

/* count at last report to get difference */
unsigned long lastCount[24];

/* millis at first interrupt for current interval
 * (is also last interrupt of old interval) */
volatile unsigned long startTime[24];

/* millis at last interrupt */
volatile unsigned long lastTime[24];

/* millis at last report 
 * to find out when maxInterval is over
 * and report has to be done even if
 * no impulses were counted */
unsigned long lastReport[24];


/* max for SplitLine */
#define MAXLINEPARTS 5

String inputString = "";         // a string to hold incoming data
boolean newCommand = false;      // whether the command string is complete

String linePart[MAXLINEPARTS];
int lineParts = 0;


/* Add a pin to be handled */
int AddPin(uint8_t aPin, int mode) {
  uint8_t pcintPin;                         // PCINT pin number for the pin to be added (this is used as index for most arrays)
  volatile uint8_t *pcmask;                 // pointer to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
  unsigned long now = millis();
  
  uint8_t bit = digitalPinToBitMask(aPin);  // bit in PCMSK to enable pin change interrupt for this pin (arduino pin number!)
  uint8_t port = digitalPinToPort(aPin);    // port that this pin belongs to for enabling interrupts for the whole port (arduino pin number!)

  if (port == NOT_A_PORT) {
    return 1;
  } else {                              // map port to bit in PCIR register
    port -= 2;
    pcmask = port_to_pcmask[port];      // point to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
  }
  if (port == 1) {                      // now calculate the PCINT pin number that corresponds to the arduino pin number
     pcintPin = aPin - 6;                // port 1: PC0-PC5 (A0-A5 or D14-D19) is PCINT 8-13 (PC6 is reset)
  } else {                              // arduino numbering continues at D14 since PB6/PB7 are used for other things 
     pcintPin = port * 8 + (aPin % 8);  // port 0: PB0-PB5 (D8-D13) is PCINT 0-5 (PB6/PB7 is crystal)
  }                                     // port 2: PD0-PD7 (D0-D7) is PCINT 16-23
  
  PCintMode[pcintPin] = mode;           // save mode for ISR which uses the pcintPin as index because this is easy to get in ISR
  PCintActivePin[pcintPin] = aPin;      // save real arduino pin number and flag this pin as active for reporting

  initialized[pcintPin] = false;        // initialize arrays for this pin
  counter[pcintPin]     = 0;            
  lastCount[pcintPin]   = 0;
  startTime[pcintPin]   = now;     
  lastTime[pcintPin]    = now;
  lastReport[pcintPin]  = now;
  
  *pcmask |= bit;          // set the pin change interrupt mask through a pointer to PCMSK0 or 1 or 2 depending on the port corresponding to the pin
  PCICR |= 0x01 << port;   // enable the interrupt
  return 0;
}


/* Remove a pin to be handled */
int RemovePin(uint8_t aPin) {
  uint8_t pcintPin;
  volatile uint8_t *pcmask;
  uint8_t bit = digitalPinToBitMask(aPin);
  uint8_t port = digitalPinToPort(aPin);

  if (port == NOT_A_PORT) {
    return 1;
  } else {
    port -= 2;
    pcmask = port_to_pcmask[port];
  }
  if (port == 1) {                       // see comments at AddPin above
     pcintPin = port * 8 + (aPin - 14);
  } else {
     pcintPin = port * 8 + (aPin % 8);
  }
  PCintActivePin[pcintPin] = -1;

  *pcmask &= ~bit;      // disable the mask.
  if (*pcmask == 0) {   // if that's the last one, disable the interrupt.
    PCICR &= ~(0x01 << port);
  }
  return 0;
}


// common interrupt handler. "port" is the PCINT port number (0-2)
static void PCint(uint8_t port) {
  uint8_t bit;
  uint8_t curr;
  uint8_t mask;
  uint8_t pcintPin;

  // get the pin states for the indicated port.
  curr = *portInputRegister(port+2);         // current pin states at port
  mask = curr ^ PCintLast[port];             // xor gets bits that are different
  PCintLast[port] = curr;                    // store new pin state for next interrupt

  if ((mask &= *port_to_pcmask[port]) == 0) {  // mask is pins that have changed. screen out non pcint pins.
    return; /* no handled pin changed */
  }

  for (uint8_t i=0; i < 8; i++) {
    bit = 0x01 << i;                         // loop over each pin that changed
    if (bit & mask) {                        // is pin change interrupt enabled for this pin?
      pcintPin = port * 8 + i;               // pcint pin numbers directly follow the bit numbers, only arduino pin numbers are special

      // count if mode is CHANGE, or if mode is RISING and
      // the bit is currently high, or if mode is FALLING and bit is low.
      if ((PCintMode[pcintPin] == CHANGE
          || ((PCintMode[pcintPin] == RISING) && (curr & bit))
          || ((PCintMode[pcintPin] == FALLING) && !(curr & bit)))) {
        lastTime[pcintPin] = millis();       // remember time of this impulse in case it will be the last in the interval
        if (initialized[pcintPin]) {
          counter[pcintPin]++;               // count
        } else {
          startTime[pcintPin] = lastTime[pcintPin]; // if this is the first impulse on this pin, remember time as first impulse in interval
          initialized[pcintPin] = true;             // and start counting the next impulse
        }
      }
    }
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


/* split a line read from serial into individual words 
 * and store them in the array lineParts[] */
void SplitLine () {
  int index = 0;
  int sepPos = 0;
  lineParts = 0;
  while (sepPos > -1 && index < inputString.length()) {      // as long as a blank was found an not at end of line ...
    while (inputString.charAt(index) == ' '                  // if next char is another blank
            && lineParts < MAXLINEPARTS
            && index < inputString.length()) index++;        // skip more blanks
    if (index < inputString.length()) { 
      sepPos = inputString.indexOf(' ', index+1);            // find next blank after the word?
      if (sepPos == -1)                             
        linePart[lineParts] = inputString.substring(index);  // no more blanks -> take rest of string
      else 
        linePart[lineParts] = inputString.substring(index, sepPos); // more blanks -> take word nefore next blank and go on
      index = sepPos + 1;                                    // continue looking after last blank
      lineParts ++;
    }
  }
  for (int i=lineParts; i<MAXLINEPARTS; i++)                 // clear the rest of the array
    linePart[i] = "";
}



void report() {
  int aPin;
  unsigned long newCount, countDiff;
  unsigned long timeDiff, now;
  now = millis();
  for (int pcintPin=0; pcintPin<24; pcintPin++) {             // go through all observed pins as PCINT pin number
    aPin = PCintActivePin[pcintPin];                          // take saved arduino pin number
    if (aPin >= 0) {                                          // -1 means pin is not active for reporting
      newCount  = counter[pcintPin];                          // get current counter
      countDiff = newCount - lastCount[pcintPin];             // how many impulses since last report?
      if (countDiff == 0 && 
         (now - lastReport[pcintPin] < intervalMax))          // if nothing to report, take next pin
        continue;                                 
      if (countDiff > 0) {                                    // if there was an impulse, report
        timeDiff  = lastTime[pcintPin] - startTime[pcintPin]; // time between first and last impulse during interval
        lastCount[pcintPin] = newCount;                       // remember current count for next interval
        startTime[pcintPin] = lastTime[pcintPin];             // time of last impulse in this interval becomes also time of first impulse in next interval
      } else {                                    
        timeDiff  = now - startTime[pcintPin];                // there was no impulse, but maxInterval is over: show from last impulse to now
        startTime[pcintPin] = now;                            // start a new interval for next report - last one will be reported as 0 imulses ... 
        lastTime[pcintPin] = now;                             // also time of first impulse in next interval
      }
      Serial.println((String) "R" + aPin +                    // report on serial out
                              " C" + newCount + 
                              " D" + countDiff + 
                              " T" + timeDiff);             
      lastReport[pcintPin] = now;                             // remember when we reported 
    }
  }
}


/* give status report in between if requested over serial input */
void showCmd() {
  unsigned long newCount;
  unsigned long countDiff;
  unsigned long timeDiff;
  char* pName;

  Serial.println((String) version); 
  Serial.println((String) "Min " + intervalMin);
  Serial.println((String) "Max " + intervalMax);
  
  for (int i=0; i<24; i++) {
    int aPin = PCintActivePin[i];
    if (aPin != -1) {
      timeDiff = lastTime[i] - startTime[i];
      newCount = counter[i];
      countDiff = newCount - lastCount[i];
      if (!timeDiff)
        timeDiff = millis() - startTime[i];
      Serial.println((String) "PCInt " + i + " aPin " + aPin
                            + " Cnt " + newCount + " (+" + countDiff 
                            + " ) in " + timeDiff + " Millis");
    }
  }
  Serial.println((String) "Next in " + (timeNextReport - millis()));
}


void addCmd() {
  String pinArg = linePart[1];              // given arduino pin number or name as string
  String modeArg = linePart[2];             // mode falling, rising or change
  String pullArg = linePart[3];             // optional pullup
  int aPin = -1;                             
  int mode = RISING; // default

  if (pinArg.charAt(0) == 'D' || pinArg.charAt(0) == 'd') 
    aPin = pinArg.substring(1).toInt();      // arduino pin name starting with a "d"?
  if (aPin == -1) {
    aPin = pinArg.toInt();                   // interpret string as pin number
    if (aPin >= 20 || aPin < 1) {
      Serial.print(error); Serial.println(aPin);
      return;
    } 
  }  
  if (allowedPins[aPin] == 0) {
    Serial.print(error); Serial.println(aPin);
    return;
  };
  if (lineParts > 2) {
    if (modeArg.equalsIgnoreCase("f"))
      mode = FALLING;
    else if (modeArg.equalsIgnoreCase("c"))
      mode = CHANGE;
    else if (modeArg.equalsIgnoreCase("r"))
      mode = RISING;
    else {
      Serial.print(error); Serial.println(modeArg);
      return;
    }
  }
  pinMode (aPin, INPUT);
  if (lineParts > 3) {
    if (pullArg.equalsIgnoreCase("p"))
      digitalWrite (aPin, HIGH);             // enable pullup resistor
    else {
      Serial.print(error); Serial.println(pullArg);
      return;
    }
  }
  
  if (AddPin(aPin, mode) == 0) {             // call AddPin with arduino pin number
    Serial.print("added "); Serial.println(aPin);
  } else {
    Serial.print(error); Serial.println(pinArg);
  }
}


void removeCmd() {
  String pinArg = linePart[1];              // given arduino pin number or name as string in first part
  int aPin = -1;
  if (pinArg.charAt(0) == 'D' || pinArg.charAt(0) == 'd') 
    aPin = pinArg.substring(1).toInt();      // arduino pin name starting with a "d"?
  if (aPin == -1) {
    aPin = pinArg.toInt();                  // interpret string as pin number
    if (aPin >= 20 || aPin < 1) {
      Serial.print(error); Serial.println(aPin);
      return;
    } 
  }  
  if (allowedPins[aPin] == 0) {
    Serial.print(error); Serial.println(aPin);
    return;
  };
  if (RemovePin(aPin) == 0) {               // call RemovePin with arduino pin number
    Serial.println((String)"removed " + aPin);
  } else {
    Serial.print(error); Serial.println(pinArg);
  }
}


void intervalCmd() {
  String timeArgMin = linePart[1];
  String timeArgMax = linePart[2];
  int timeMin = timeArgMin.toInt();
  if (timeMin < 1 || timeMin > 3600) {
    Serial.print(error); Serial.println(timeArgMin);
    return;
  }
  int timeMax = timeArgMax.toInt();
  if (timeMax < 1 || timeMax > 3600 || timeMax < timeMin) {
    Serial.print(error); Serial.println(timeArgMax);
    return;
  }
  intervalMin = (long)timeMin * 1000;
  intervalMax = (long)timeMax * 1000;
  if (millis() + intervalMin < timeNextReport)
    timeNextReport = millis() + intervalMin;
}


void doCommand() {
  SplitLine();
  if (linePart[0].equals("show")) {
    showCmd();
  } else if (linePart[0].equals("add")) {
    addCmd();
  } else if (linePart[0].equals("rem")) {
    removeCmd();
  } else if (linePart[0].equals("int")) {
    intervalCmd();
  } else {
    Serial.print(error); Serial.println(linePart[0]);
  }
}


void setup() {
  unsigned long now = millis();
  for (int pcintPin=0; pcintPin < 24; pcintPin++) {
    PCintActivePin[pcintPin] = -1;          // set all pins to inactive (-1)
  } 
  timeNextReport = millis() + intervalMin;  // time for first output
  Serial.begin(9600);                       // initialize serial
  inputString.reserve(200);                 // reserve 200 bytes for the inputString
  interrupts();
  Serial.println((String) version + " Setup done."); 
}



void loop() {
  now = millis();
  doReport = false;                              // check if report nedds to be called
  if((long)(now - timeNextReport) >= 0)
    doReport = true;                             // intervalMin is over 
  else 
    for (byte pcintPin=0; pcintPin<24; pcintPin++)  
      if (PCintActivePin[pcintPin] >= 0)
        if((long)(now - (lastReport[pcintPin] + intervalMax)) >= 0)
          doReport = true;                       // active pin has not been reported for langer than maxInterval
  if (doReport) {    
    report();
    timeNextReport = now + intervalMin;          // do it again after interval millis
  }
  if (newCommand) {
    doCommand();
    inputString = "";
    newCommand = false;
  }
}


/*
 SerialEvent occurs whenever a new data comes in the
 hardware serial RX.  This routine is run between each
 time loop() runs, so using delay inside loop can delay
 response.  Multiple bytes of data may be available.
 */
void serialEvent() {
  while (Serial.available()) {
    char inChar = (char)Serial.read(); 
    if (inChar == '\n' or inChar == '\r') {
      if (inputString.length() > 0)
        newCommand = true;
    }  else {
      inputString += inChar;
    }
  }
}


