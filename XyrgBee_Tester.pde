/* 
===========================================================================================
Project: XyrgBee

Developers: David H Brummel & Barrett Canon

Overview:
  == Modules ==
    Xmitter (3+) - Arduino with Xbee radio plus 1 push button, 2 switches, 1 potentiometer,
                   and 1 RGB LED
                   ** MODIFICATION ** Available switches would not stay in proto boards
                   so switched to using buttons with LEDs to show on/off state
    Receiver (1) - Rainbowduino with 8x8 color LED matrix and Xbee radio

  == Functions ==
    Xmitter: 
      When button is pushed, read switches and potentiometer, encode potentiometer value
      based on switches, update current state array, and transmit state array to Receiver.
    Receiver:
      Receive state array from Xmitter, decode X,Y & RGB values, read current RGB vlaues of 
      matrix at (X,Y), add transmitted RGB (modulo 256), and update matrix at (X,Y).
      
Details:
  == Xmitter ==
    The two switches are mode controls and determine how the potentiometer value is
    interpreted and encoded:
      Switch 1: 0 = X,Y - Potentiometer Range = [0,7]
                1 = RGB - Potentiometer Range = [0,255]
      Switch 2: when Switch 1 = 0: 0 = X  
                                   1 = Y 
                when Switch 1 = 1: 0 = one of {R,G,B}
                                 : 1 = another of {R,G,B}
      NOTE: Each Xmitter can only send 2 of {R,G,B}, so at least 3 Xmitters are needed
            to effectively and evenly cover RGB space.

  == State Array ==

  The State Array consists of 5 values as follows:
    X
    Y
    R
    G
    B

  For R,G,B the missing value will be initialized to 256 so the Reciever can decide to ignore it.

  Each time the Select button is pressed, the State Array will be updated and then transmitted to
  the Receiver.


  == Initial States ==

  When three properly configured Xmitters send their initial states to the Receiver, the LED 
  matrix should light up as shown below:

       0 1 2 3 4 5 6 7
    0  R . . . . . . G
    1  . . . . . . . .
    2  . . . . . . . .
    3  . . . . . . . .
    4  . . . . . . . .
    5  . . . . . . . .
    6  . . . . . . . .
    7  B . . . . . . .


=========================================================================================== 
*/
/* 
===========================================================================================
Module: Tester

Developer: David H Brummel

Description: 

Runs on Arduino + Xbee. Sends canned state array sequences to Receiver to
test command decoding and Rainbowduino LED functionality.

The following changes havebeen made to the state array:
  X =  8 (0x08) = Receiver blanks all LEDs
  X = 15 (0x0F) = Receiver resets (as if arduino reset button pressed)

History:
  2011.02.04 - dhb - Initial Version

=========================================================================================== 
*/

// ====== reconfiguration #defines - change the following to reconfigure software for debugging,
//           RGB selection, and hardware variants
//

// turn debug print on/off
#define dbug 0

// is xbee installed? 1 = yes, 0 = no
#define xbee 0

// is xmit LED monochrome (1) or RGB (3) - controls #defines below
#define xmtLED 1  

// set up #defines for LED on Select button - based on #define xmtLED above
#if xmtLED == 3
  // configure the following pins as pwm outputs
  #define ledStateR 11 // red   leg of rgb led
  #define ledStateG 10 // green leg of rgb led
  #define ledStateB  9 // blue  leg of rgb led
#endif

#if xmtLED == 1
  // configure the following pin as digital output
  #define ledXmit 11 // flashes when state xmitted
#endif

// XBee & serial initialization values
#define bitRate 9600
#define xbPANID "3332"
#define xbDest  "0001"
#define xbMyID  "9990"

// time in seconds to delay while Receiver does its startup routine after a reset
#define rcvrDelay 30

// time (ms) to delay between segments of the test
#define segDelay  1000

// amount to increment R/G/B during corner spectrum test
#define incrSpectrum 15
  
// state array
int state[5] = {0, 0, 0, 0 ,0};

// some canned states
int blankLEDs[5] = {8, 0, 0, 0 ,0};

int resetRCVR[5] = {15, 0, 0, 0, 0};

//  each corner in Red, Green, Blue, White, and blacK
int state_00R[5] = {0, 0, 255, 0, 0};
int state_00G[5] = {0, 0, 0, 255, 0};
int state_00B[5] = {0, 0, 0, 0, 255};
int state_00W[5] = {0, 0, 255, 255, 255};
int state_00K[5] = {0, 0, 0, 0, 0};

int state_07R[5] = {0, 7, 255, 0, 0};
int state_07G[5] = {0, 7, 0, 255, 0};
int state_07B[5] = {0, 7, 0, 0, 255};
int state_07W[5] = {0, 7, 255, 255, 255};
int state_07K[5] = {0, 7, 0, 0, 0};

int state_70R[5] = {7, 0, 255, 0, 0};
int state_70G[5] = {7, 0, 0, 255, 0};
int state_70B[5] = {7, 0, 0, 0, 255};
int state_70W[5] = {7, 0, 255, 255, 255};
int state_70K[5] = {7, 0, 0, 0, 0};

int state_77R[5] = {7, 7, 255, 0, 0};
int state_77G[5] = {7, 7, 0, 255, 0};
int state_77B[5] = {7, 7, 0, 0, 255};
int state_77W[5] = {7, 7, 255, 255, 255};
int state_77K[5] = {7, 7, 0, 0, 0};

// each corner with colors TBS
int state_00[5]  = {0, 0, 0, 0, 0};
int state_07[5]  = {0, 7, 0, 0, 0};
int state_70[5]  = {7, 0, 0, 0, 0};
int state_77[5]  = {7, 7, 0, 0, 0};

// ===============================
//   SUPPORT ROUTINES
// ===============================

//
// debug - print some dbug text to the serial port
//   args: t1 - text label
//         n1..n3 - integer values to print
//         nl - new line flag - 0 = no new line, 1 = print new line
//
void debug(char *t1, int n1, int n2, int n3, int nl) {
  #if dbug == 1
    Serial.print(t1);
    Serial.print(n1); Serial.print(' ');
    Serial.print(n2); Serial.print(' ');
    Serial.print(n3); Serial.print(' ');
    if (nl == 1) Serial.println(" .");
  #endif
} // end debug()

//
// xmit_state
//
void xmit_state(int *state) {

  // flash it a bit, leaving it on
  for (int i=0; i<10; i++) {
    #if xmtLED == 3
     analogWrite(ledStateR, state[2]);
     analogWrite(ledStateG, state[3]);
     analogWrite(ledStateB, state[4]);
    #endif
    #if xmtLED == 1
     digitalWrite(ledXmit, HIGH);
    #endif
    delay(20);
    #if xmtLED == 3
     analogWrite(ledStateR, LOW);
     analogWrite(ledStateG, LOW);
     analogWrite(ledStateB, LOW);
    #endif
    #if xmtLED == 1
     digitalWrite(ledXmit, LOW);
    #endif
    delay(20);
  }

  // write state values as space separated text to xbee
  for (int i=0; i<5; i++) {
    Serial.print(state[i], BYTE);  //was BYTE
    if (i==4) {
      Serial.print('.');
    } else {
      Serial.print(' ');
    }
  }
  
  // if debug on write again in hex
#if dbug
  for (int i=0; i<5; i++) {
    Serial.print(state[i], HEX);
    if (i==4) {
      Serial.println('.');
    } else {
      Serial.print(' ');
    }
  }
#endif
  
//  Serial.println(' ');
 
  // set LED to new state color
  #if xmtLED == 3
   analogWrite(ledStateR, state[2]);
   analogWrite(ledStateG, state[3]);
   analogWrite(ledStateB, state[4]);
  #endif
  #if xmtLED == 1
   digitalWrite(ledXmit, HIGH);
  #endif

} // end xmit_state

// ===============================
//   MAIN ROUTINES
// ===============================

void setup() {

  // assign pins
  #if xmtLED == 3
   pinMode(ledStateR,  OUTPUT);
   pinMode(ledStateG,  OUTPUT);
   pinMode(ledStateB,  OUTPUT);
  #endif
  #if xmtLED == 1
   pinMode(ledXmit, OUTPUT);
  #endif

  // open serial comms
  Serial.begin(9600);

  // configure xbee
#if xbee
  // put the radio in command mode:
  Serial.print("+++");
  // wait for the radio to respond with "OK\r"
  char thisByte = 0;
  while (thisByte != '\r') {
    if (Serial. available() > 0) {
      thisByte = Serial.read();
    }
  }
  // set the destination address with 16-bit addressing. This radio's
  // destination should be the other radio' s MY address and vice versa:
  Serial.print("ATDH0, DL"); Serial.print(xbDest); Serial.print("\r");
  Serial.print("ATMY"); Serial.print(xbMyID); Serial.print("\r");  // set my address (16-bit addressing)
  Serial.print("ATDB3\r");  // set baud rate
  // set the PAN ID. If you're in a place where many people
  // are using XBees, choose a unique PAN ID
  Serial.print("ATID"); Serial.print(xbPANID); Serial.print("\r");
  Serial.print("ATCN\r\r"); // go into data mode:
#endif
  // state array initalized when declared above. if any mods needed, add them here

  // xmit initial state - reset Receiver
  xmit_state(resetRCVR);
  
  // wait for Receiver to finish reset and startup sequence
  for (int i=0; i < rcvrDelay * 2; i++) {
    delay(500);  // 0.5sec
  }
  
  // blank LEDs
  xmit_state(blankLEDs);
  delay(segDelay);
  
  // set corners to red
  xmit_state(state_00R);
  xmit_state(state_07R);
  xmit_state(state_70R);
  xmit_state(state_77R);
  delay(segDelay);

  // set corners to green
  xmit_state(state_00G);
  xmit_state(state_07G);
  xmit_state(state_70G);
  xmit_state(state_77G);
  delay(segDelay);

  // set corners to blue
  xmit_state(state_00B);
  xmit_state(state_07B);
  xmit_state(state_70B);
  xmit_state(state_77B);
  delay(segDelay);

  // set corners to white
  xmit_state(state_00W);
  xmit_state(state_07W);
  xmit_state(state_70W);
  xmit_state(state_77W);
  delay(segDelay);

  // set corners to RGBW
  xmit_state(state_00R);
  xmit_state(state_07G);
  xmit_state(state_70B);
  xmit_state(state_77W);
  delay(segDelay);

  // blank LEDs
  xmit_state(blankLEDs);
  delay(segDelay);
  
  // color all LEDs red then green then blue, by rows
  for (int c = 2; c < 5; c++) {
    state[0] = 0;
    state[1] = 0;
    state[2] = 0;
    state[3] = 0;
    state[4] = 0;
    state[c] = 255;
    for (int x = 0; x < 8; x++) {
      state[0] = x;
      for (int y = 0; y< 8; y++) { 
        state[1] = y;
        xmit_state(state);
      }
    }
  }
  delay(segDelay);
  
  // color all LEDs white, by rows
  state[0] = 0;
  state[1] = 0;
  state[2] = 255;
  state[3] = 255;
  state[4] = 255;
  for (int x = 0; x < 8; x++) {
    state[0] = x;
    for (int y = 0; y< 8; y++) { 
      state[1] = y;
      xmit_state(state);
    }
  }
  delay(segDelay);

  // blank corners
  xmit_state(state_00K);  
  xmit_state(state_07K);  
  xmit_state(state_70K);  
  xmit_state(state_77K);  
  delay(segDelay);
  
  // cycle corners through spectrum
  for (int r = 0; r < 256; r += incrSpectrum) {
    for (int g = 0; g < 256; g += incrSpectrum) {
      for (int b = 0; b < 256; b += incrSpectrum) {
        state_00[2] = r;
        state_00[3] = g;
        state_00[4] = b;
        state_07[2] = r;
        state_07[3] = g;
        state_07[4] = b;
        state_70[2] = r;
        state_70[3] = g;
        state_70[4] = b;
        state_77[2] = r;
        state_77[3] = g;
        state_77[4] = b;
        xmit_state(state_00);
        xmit_state(state_07);
        xmit_state(state_70);
        xmit_state(state_77);
      }
    }
  }
  delay(segDelay);

  // blank LEDs
  xmit_state(blankLEDs);
  
} // end of setup()

void loop() {

} // end of loop()  

