// New version of the Room Node, derived from rooms.pde
// 2010-10-19 <jcw@equi4.com> http://opensource.org/licenses/mit-license.php
// $Id: FHEM_JSN_RoomNode.pde,v 1.1 2011-07-19 09:31:20 rudolfkoenig Exp $

// see http://jeelabs.org/2010/10/20/new-roomnode-code/
// and http://jeelabs.org/2010/10/21/reporting-motion/

// The complexity in the code below comes from the fact that newly detected PIR
// motion needs to be reported as soon as possible, but only once, while all the
// other sensor values are being collected and averaged in a more regular cycle.

#include <Ports.h>
#include <PortsSHT11.h>
#include <RF12.h>
#include <avr/sleep.h>
#include <util/atomic.h>

#define SERIAL  0   // set to 1 to also report readings on the serial port
#define DEBUG   0   // set to 1 to display each loop() run and PIR trigger

#define SHT11_PORT  4  // defined if SHT11 is connected to a port
#define LDR_PORT    1   // defined if LDR is connected to a port's AIO pin
#define PIR_PORT    1   // defined if PIR is connected to a port's DIO pin

#define MEASURE_PERIOD  600 // how often to measure, in tenths of seconds
#define RETRY_PERIOD    1  // how soon to retry if ACK didn't come in
#define RETRY_LIMIT     1   // maximum number of times to retry
#define ACK_TIME        5  // number of milliseconds to wait for an ack
#define REPORT_EVERY    5   // report every N measurement cycles
#define SMOOTH          3   // smoothing factor used for running averages

// set the sync mode to 2 if the fuses are still the Arduino default
// mode 3 (full powerdown) can only be used with 258 CK startup fuses
#define RADIO_SYNC_MODE 2

// The scheduler makes it easy to perform various tasks at various times:

enum { MEASURE, REPORT, TASK_END };

static word schedbuf[TASK_END];
Scheduler scheduler (schedbuf, TASK_END);

// Other variables used in various places in the code:

static byte reportCount;    // count up until next report, i.e. packet send
static byte myNodeID = 8;   // node ID used for this unit
static byte myNetGroup = 212;

// This defines the structure of the packets which get sent out by wireless:
/*
struct {
    byte light;     // light sensor: 0..255
    byte moved :1;  // motion detector: 0..1
    byte humi  :7;  // humidity: 0..100
    int temp   :10; // temperature: -500..+500 (tenths)
    byte lobat :1;  // supply voltage dropped under 3.1V: 0..1
} payload;
*/
struct {
  byte light_type;
  byte light_data;
  byte moved_type;
  byte moved_data;
  byte humi_type;
  byte humi_data;
  byte temp_type;
  int  temp_data;
  byte rf12lowbat_type;
  byte rf12lowbat_data;
} payload;
// Conditional code, depending on which sensors are connected and how:

#if SHT11_PORT
    SHT11 sht11 (SHT11_PORT);
#endif

#if LDR_PORT
    Port ldr (LDR_PORT);
#endif

#if PIR_PORT
    #define PIR_HOLD_TIME    30 // hold PIR value this many seconds after change
    #define PIR_PULLUP      1   // set to one to pull-up the PIR input pin

    class PIR : public Port {
        volatile byte value, changed;
        volatile uint32_t lastOn;
    public:
        PIR (byte portnum)
            : Port (portnum), value (0), changed (0), lastOn (0) {}

        // this code is called from the pin-change interrupt handler
        void poll() {
            byte pin = digiRead();
            #if SERIAL
            Serial.print("PIR.POLL: ");
            Serial.print(pin,DEC);
            Serial.print(" LastOn: ");
            Serial.println(lastOn);
            #endif
            // if the pin just went on, then set the changed flag to report it
            if (pin) {
                if (!state())
                    changed = 1;
                lastOn = millis();
            }
            value = pin;
        }

        // state is true if curr value is still on or if it was on recently
        byte state() const {
          #if SERIAL
          Serial.print("ATOMIC_RESTORESTATE");
          Serial.print(" LastOn: ");
          Serial.println(lastOn);
          #endif
            byte f = value;
            if (lastOn > 0)
                ATOMIC_BLOCK(ATOMIC_RESTORESTATE) {
                    if (millis() - lastOn < 1000 * PIR_HOLD_TIME)
                        f = 1;
                }
            return f;
        }

        // return true if there is new motion to report
        byte triggered() {
          #if SERIAL
          Serial.print("TRIGGERD");
          Serial.print(" LastOn: ");
          Serial.println(lastOn);
          #endif
            byte f = changed;
            changed = 0;
            return f;
        }
    };

    PIR pir (PIR_PORT);

    // the PIR signal comes in via a pin-change interrupt
    ISR(PCINT2_vect) { pir.poll(); }
#endif

// has to be defined because we're using the watchdog for low-power waiting
ISR(WDT_vect) { Sleepy::watchdogEvent(); }

// utility code to perform simple smoothing as a running average
static int smoothedAverage(int prev, int next, byte firstTime =0) {
    if (firstTime)
        return next;
    return ((SMOOTH - 1) * prev + next + SMOOTH / 2) / SMOOTH;
}

// spend a little time in power down mode while the SHT11 does a measurement
static void shtDelay () {
    Sleepy::loseSomeTime(32); // must wait at least 20 ms
}

// wait a few milliseconds for proper ACK to me, return true if indeed received
static byte waitForAck() {
    MilliTimer ackTimer;
    while (!ackTimer.poll(ACK_TIME)) {
        if (rf12_recvDone() && rf12_crc == 0 &&
                rf12_hdr == (RF12_HDR_DST | RF12_HDR_ACK | myNodeID))
            return 1;
        set_sleep_mode(SLEEP_MODE_IDLE);
        sleep_mode();
    }
    return 1;
}

// readout all the sensors and other values
static void doMeasure() {
  #if SERIAL
  Serial.println("doMeasure");
  #endif
    byte firstTime = payload.humi_data == 0; // special case to init running avg

    // RF12lowBat
    payload.rf12lowbat_type = 253;
    payload.rf12lowbat_data = rf12_lowbat();

    #if SHT11_PORT
#ifndef __AVR_ATtiny84__
        sht11.measure(SHT11::HUMI, shtDelay);
        sht11.measure(SHT11::TEMP, shtDelay);
        float h, t;
        sht11.calculate(h, t);
        int humi = h + 0.5, temp = 10 * t + 0.5;
#else
        //XXX TINY!
        int humi = 50, temp = 25;
#endif

        payload.humi_type = 16;
        payload.humi_data = smoothedAverage(payload.humi_data, humi, firstTime);
        payload.temp_type = 11;
        payload.temp_data = smoothedAverage(payload.temp_data, temp, firstTime);
    #endif
    #if LDR_PORT
        ldr.digiWrite2(1);  // enable AIO pull-up
        byte light = ~ ldr.anaRead() >> 2;
        ldr.digiWrite2(0);  // disable pull-up to reduce current draw

        payload.light_type = 17;
        payload.light_data = smoothedAverage(payload.light_data, light, firstTime);
    #endif
    #if PIR_PORT
        payload.moved_type = 18;
        payload.moved_data = pir.state();
    #endif
}

// periodic report, i.e. send out a packet and optionally report on serial port
static void doReport() {
  Serial.println("REPORT");
    rf12_sleep(-1);
    while (!rf12_canSend())
        rf12_recvDone();
    rf12_sendStart(0, &payload, sizeof payload, RADIO_SYNC_MODE);
    rf12_sleep(0);

    #if SERIAL
        Serial.print("ROOM L:");
        Serial.print((int) payload.light_data);
        Serial.print(" M:");
        Serial.print((int) payload.moved_data);
        Serial.print(" H:");
        Serial.print((int) payload.humi_data);
        Serial.print(" T:");
        Serial.print((int) payload.temp_data);
        Serial.print(" LB:");
        Serial.print((int) payload.rf12lowbat_data);
        Serial.println();
        delay(2); // make sure tx buf is empty before going back to sleep
    #endif
}

// send packet and wait for ack when there is a motion trigger
static void doTrigger() {
    #if DEBUG
        Serial.print("doTrigger PIR ");
        Serial.print((int) payload.moved_data);
        delay(2);
    #endif

    for (byte i = 0; i < RETRY_LIMIT; ++i) {
        rf12_sleep(-1);
        while (!rf12_canSend())
            rf12_recvDone();
        rf12_sendStart(RF12_HDR_ACK, &payload, sizeof payload, RADIO_SYNC_MODE);
        byte acked = waitForAck();
        rf12_sleep(0);

        if (acked) {
            #if DEBUG
                Serial.print(" ack ");
                Serial.println((int) i);
                delay(2);
            #endif
            // reset scheduling to start a fresh measurement cycle
            scheduler.timer(MEASURE, MEASURE_PERIOD);
            return;
        }

        Sleepy::loseSomeTime(RETRY_PERIOD * 100);
    }
    scheduler.timer(MEASURE, MEASURE_PERIOD);
    #if DEBUG
        Serial.println(" no ack!");
        delay(2);
    #endif
}

void setup () {
    #if SERIAL || DEBUG
        Serial.begin(57600);
        Serial.print("\n[roomNode.3]");
        // myNodeID = rf12_config();
        rf12_initialize(myNodeID, RF12_868MHZ, myNetGroup);
    #else
        rf12_initialize(myNodeID, RF12_868MHZ, myNetGroup);
    #endif

    rf12_sleep(0); // power down

    #if PIR_PORT
        pir.digiWrite(PIR_PULLUP);
#ifdef PCMSK2
        bitSet(PCMSK2, PIR_PORT + 3);
        bitSet(PCICR, PCIE2);
#else
        //XXX TINY!
#endif
    #endif

    reportCount = REPORT_EVERY;     // report right away for easy debugging
    scheduler.timer(MEASURE, 0);    // start the measurement loop going
}

void loop () {
    #if DEBUG
        Serial.println('Loop..................................................');
        delay(2);
    #endif

    #if PIR_PORT
        if (pir.triggered()) {
            payload.moved_data = pir.state();
            doTrigger();
        }
    #endif

    switch (scheduler.pollWaiting()) {

        case MEASURE:
            // reschedule these measurements periodically
            scheduler.timer(MEASURE, MEASURE_PERIOD);

            doMeasure();

            // every so often, a report needs to be sent out
            if (++reportCount >= REPORT_EVERY) {
                reportCount = 0;
                scheduler.timer(REPORT, 0);
            }
            break;

        case REPORT:
            doReport();
            break;
    }
}
