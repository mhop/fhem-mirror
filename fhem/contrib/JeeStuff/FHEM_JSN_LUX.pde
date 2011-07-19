// -----------------------------------------------------------------------------
// JeeNode for Use with BMP085 and LuxPlug
// reads out a BMP085 sensor connected via I2C
// see http://news.jeelabs.org/2010/06/20/battery-savings-for-the-pressure-plug/
// see http://news.jeelabs.org/2010/06/30/going-for-gold-with-the-bmp085/
//
// Baesd on RoomNode form JeeLabs roomNode.pde
//
// 2010-10-19 <jcw@equi4.com> http://opensource.org/licenses/mit-license.php
// $Id: FHEM_JSN_LUX.pde,v 1.1 2011-07-19 09:31:20 rudolfkoenig Exp $
//
// see http://jeelabs.org/2010/10/20/new-roomnode-code/
// and http://jeelabs.org/2010/10/21/reporting-motion/
// -----------------------------------------------------------------------------
// Includes
#include <Ports.h>
#include <PortsSHT11.h>
#include <RF12.h>
#include <avr/sleep.h>
#include <util/atomic.h>
// -----------------------------------------------------------------------------
// JeeNode RF12-Config
static byte myNodeID = 6;   // node ID used for this unit
static byte myNetGroup = 212; // netGroup used for this unit
unsigned long lux;
// Port Lux-Plug
#define LUX_PORT 4

// Payload aka Data to Send
struct  {
    // RF12LowBat
    byte rf12lowbat_type;
    byte rf12lowbat_data;
    // Lux
    byte lux_type;
    unsigned long lux_data;

} payload;
// -----------------------------------------------------------------------------
// Lux Plug
PortI2C two (LUX_PORT);
LuxPlug lsensor (two, 0x39);
byte highGain;
MilliTimer timer;
// -----------------------------------------------------------------------------
// Config & Vars
#define SERIAL  1   // set to 1 to also report readings on the serial port
#define DEBUG   0   // set to 1 to display each loop()
#define MEASURE_PERIOD  3000 // how often to measure, in tenths of seconds
#define RETRY_PERIOD    10  // how soon to retry if ACK didn't come in
#define RETRY_LIMIT     5   // maximum number of times to retry
#define ACK_TIME        10  // number of milliseconds to wait for an ack
#define REPORT_EVERY    1   // report every N measurement cycles
#define SMOOTH          3   // smoothing factor used for running averages

// set the sync mode to 2 if the fuses are still the Arduino default
// mode 3 (full powerdown) can only be used with 258 CK startup fuses
#define RADIO_SYNC_MODE 2
// -----------------------------------------------------------------------------
// The scheduler makes it easy to perform various tasks at various times:
enum { MEASURE, REPORT, TASK_END };

static word schedbuf[TASK_END];
Scheduler scheduler (schedbuf, TASK_END);

static byte reportCount;    // count up until next report, i.e. packet send

// has to be defined because we're using the watchdog for low-power waiting
ISR(WDT_vect) { Sleepy::watchdogEvent(); }

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
    return 0;
}

// readout all the sensors and other values
static void doMeasure() {
    // RF12lowBat
    payload.rf12lowbat_type = 253;
    payload.rf12lowbat_data = rf12_lowbat();
    // lux_demo.pde
    // need to wait after changing the gain
    //  see http://talk.jeelabs.net/topic/608
    // highGain = ! highGain;
    // lsensor.setGain(highGain);
    // Sleepy::loseSomeTime(1000);
    // Lux Plug
    const word* p = lsensor.getData();
    lux = lsensor.calcLux();
    payload.lux_type = 12;
    payload.lux_data = lux;
    // payload.lux_data = lsensor.calcLux();

  }
// periodic report, i.e. send out a packet and optionally report on serial port
static void doReport() {
    rf12_sleep(-1);
    while (!rf12_canSend())
        rf12_recvDone();
    rf12_sendStart(0, &payload, sizeof payload, RADIO_SYNC_MODE);
    rf12_sleep(0);

    #if SERIAL
        Serial.print("ROOM PAYLOAD: ");
        Serial.print("RF12LowBat: ");
        Serial.print((int) payload.rf12lowbat_data);
        Serial.print(" L: ");
        Serial.print(payload.lux_data);
        Serial.println();
        delay(2); // make sure tx buf is empty before going back to sleep
    #endif
}
// -----------------------------------------------------------------------------
void setup () {
    rf12_initialize(myNodeID, RF12_868MHZ, myNetGroup);
    #if SERIAL
        Serial.begin(57600);
        Serial.print("\n[FHEM-JeeNode.3]");
       // myNodeID = rf12_config();
    #endif

    rf12_sleep(0); // power down
    // Start Lux-Plug
    lsensor.begin();
    Sleepy::loseSomeTime(1000);
    highGain = 1;
    // highGain = ! highGain;
    lsensor.setGain(highGain);
    Sleepy::loseSomeTime(1000);
    reportCount = REPORT_EVERY;     // report right away for easy debugging
    scheduler.timer(MEASURE, 0);    // start the measurement loop going
}
// -----------------------------------------------------------------------------
void loop () {
    #if DEBUG
        Serial.print('.');
        delay(2);
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
