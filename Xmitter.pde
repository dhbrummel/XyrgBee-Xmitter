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
Module: Xmitter

Developer: David H Brummel

History:
  2009.11.01-06 - dhb - Initial Version

=========================================================================================== 
*/

// ====== reconfiguration #defines - change the following to reconfigure software for debugging,
//           RGB selection, and hardware variants
//

// turn debug print on/off
#define dbug 0

// is xbee installed? 1 = yes, 0 = no
#define xbee 1

// is LED on Select button monchrome (1) or RGB (3) - controls #defines below
#define selLED 1  

// *****
// Uncomment one of the following to set which color this Xmitter canNOT control
// *****
//#define missingColor 'R'
#define missingColor 'G'
//#define missingColor 'B'

// ====== end of reconfiguration #defines

// configure the following pins as digital inputs
#define btnSelect 12 // select buttons - capture current state of mode buttons & pot and xmits
#define btnMode1   2 // mode button 1 - 0 = x/y 1 = r/g/b
#define btnMode2   4 // mode button 2 - 0 = x|{r,g,b} 1 = y| {r,g,b}

// configure the following pins as digital outputs
#define ledMode1   3 // shows state of mode button 1 - off = 0, on = 1
#define ledMode2   5 // shows state of mode button 2 - off = 0, on = 1

// set up #defines for LED on Select button - based on #define selLED above
#if selLED == 3
  // configure the following pins as pwm outputs
  #define ledStateR 11 // red   leg of rgb led
  #define ledStateG 10 // green leg of rgb led
  #define ledStateB  9 // blue  leg of rgb led
#endif

#if selLED == 1
  // configure the following pin as digital output
  #define ledSelect 11 // flashes when state xmitted - at power on and when Select pressed
#endif

// configure the following pin as analog input
#define potVal 0

// mode state values
#define modeXY   0
#define modeRGB  1
#define modeX    0
#define modeY    1
#define modeRGB0 0
#define modeRGB1 1

// range values for X,Y and R,G,B - to be used in scaling pot values
#define minX 0
#define minY 0
#define maxX 7 // increase for multiple rainbowduinos connected horizontally
#define maxY 7 // increase for multiple rainbowduinos connected vertically

#define minRGB 0
#define maxRGB 255
#define invRGB 0 // used for RGB that this Xmitter canNOT send (aka invalid for this Xmitter)

// range values for potentiometer - need to determine for each individual pot and change here 
// used by potentiometer scaling routine
#define minPot 0
#define maxPot 1023 

// XBee & serial initialization values
#define bitRate 9600
#define xbPANID "3332"
#define xbDest  "0001"

//  missingColor #define above will select from one of three sets of #defines below, each setting the following:
//
//  #define rgb1   = state index of 1st of {r,g,b} selected by mode 2
//  #define rgb2   = state index of 2nd of {r,g,b} selected by mode 2
//  #define rgbX   = state index of missing color of {r,g,b}
//  #define initX  = X pos of initial LED lit on Receiver's matrix
//  #define initY  = Y pos of initial LED lit on Receiver's matrix
//  #define initR  = R component of color of initial LED lit on Receiver's matrix
//  #define initG  = G component of color of initial LED lit on Receiver's matrix
//  #define initB  = B component of color of initial LED lit on Receiver's matrix
//                   NOTE: the missing color should be initialized to invRGB
//  #define xbMyID = each Xmitter should have a unique ID. IDs here encode the missing color (RGB0).
//                   for more than 3 Xmitters, increment appropriate digit of these IDs

// assign initial state values when missing color is Red - G @ (7,0)
#if missingColor == 'R'
  #define rgb1 3
  #define rgb2 4
  #define rgbX 2
  #define initX 7
  #define initY 0
  #define initR invRGB
  #define initG maxRGB
  #define initB minRGB
  #define xbMyID "1000"
#endif

// assign initial state values when missing color is Green - B @ (0,7)
#if missingColor == 'G'
  #define rgb1 4
  #define rgb2 2
  #define rgbX 3
  #define initX 0
  #define initY 7
  #define initR minRGB
  #define initG invRGB
  #define initB maxRGB
  #define xbMyID "0100"
// the following are workarounds for a bad protoshield (david's green one) *** REMOVE FROM PRODUCTION CODE ***  
//  #define btnMode2   6 // mode button 2 - 0 = x|{r,g,b} 1 = y| {r,g,b}
//  #define ledMode2   8        // shows state of mode button 2 - off = 0, on = 1
#endif

// assign initial state values when missing color is Blue - R @ (0,0)
#if missingColor == 'B'
  #define rgb1 2
  #define rgb2 3
  #define rgbX 4
  #define initX 0
  #define initY 0
  #define initR 82
  #define initG minRGB
  #define initB invRGB
  #define xbMyID "0010"
// the following are workarounds for a bad protoshield (david's blue one) *** REMOVE FROM PRODUCTION CODE ***  
  #define btnMode1   4 // mode button 1 - 0 = x/y 1 = r/g/b
  #define ledMode1   5 // shows state of mode button 1 - off = 0, on = 1
  #define btnMode2   6 // mode button 2 - 0 = x|{r,g,b} 1 = y| {r,g,b}
  #define ledMode2   7 // shows state of mode button 2 - off = 0, on = 1
#endif


// global variables
int mode1_btn_state = 0;  // "*_btn_state"s used in toggle_button logic
int mode2_btn_state = 0;
int mode1_led_state = 0;  // "*_led_state"s reflect state of each mode
int mode2_led_state = 0;

// state array
int state[5] = {initX, initY, initR, initG, initB};

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
// signal_error - toggle mode LEDs until reset
//
void signal_error() {

  digitalWrite(ledMode1, LOW);
  digitalWrite(ledMode2, LOW);

  while (1) {
    digitalWrite(ledMode1, HIGH);
    digitalWrite(ledMode2, LOW);
    delay(10);
    digitalWrite(ledMode1, LOW);
    digitalWrite(ledMode2, HIGH);
    delay(10);
  }

} // end signal_error

//
// toggle_button - toggle button 
//
void toggle_button(int btn, int led, int *btnstate, int *ledstate) {

  
  int val = 0;      // val will be used to store the state
                  // of the input pin 


  val = digitalRead(btn); // read input value and store it 
                             // yum, fresh 

  // check if there was a transition 
  if ((val == HIGH) && (*btnstate == LOW)){ 
    *ledstate = 1 - *ledstate;
    debug("btn: ", btn, *ledstate, -1, 1);
    delay(10);
  } 

  *btnstate = val; // val is now old, let's store it 

  if (*ledstate == 1) {      
    digitalWrite(led, HIGH); // turn LED ON 
  } else { 
    digitalWrite(led, LOW); 
  } 

} // end toggle_button

//
// xmit_state
//
void xmit_state(int *state) {

  // flash it a bit, leaving it on
  for (int i=0; i<10; i++) {
    #if selLED == 3
     analogWrite(ledStateR, state[2]);
     analogWrite(ledStateG, state[3]);
     analogWrite(ledStateB, state[4]);
    #endif
    #if selLED == 1
     digitalWrite(ledSelect, HIGH);
    #endif
    delay(20);
    #if selLED == 3
     analogWrite(ledStateR, LOW);
     analogWrite(ledStateG, LOW);
     analogWrite(ledStateB, LOW);
    #endif
    #if selLED == 1
     digitalWrite(ledSelect, LOW);
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
//#if dbug
  for (int i=0; i<5; i++) {
    Serial.print(state[i], HEX);
    if (i==4) {
      Serial.println('.');
    } else {
      Serial.print(' ');
    }
  }
//#endif
  
//  Serial.println(' ');
 
  // set LED to new state color
  #if selLED == 3
   analogWrite(ledStateR, state[2]);
   analogWrite(ledStateG, state[3]);
   analogWrite(ledStateB, state[4]);
  #endif
  #if selLED == 1
   digitalWrite(ledSelect, HIGH);
  #endif

} // end xmit_state

// ===============================
//   MAIN ROUTINES
// ===============================

void setup() {

  // assign pins
  pinMode(btnSelect, INPUT);
  pinMode(btnMode1,  INPUT);
  pinMode(btnMode2,  INPUT);

  pinMode(ledMode1,  OUTPUT);
  pinMode(ledMode2,  OUTPUT);

  #if selLED == 3
   pinMode(ledStateR,  OUTPUT);
   pinMode(ledStateG,  OUTPUT);
   pinMode(ledStateB,  OUTPUT);
  #endif
  #if selLED == 1
   pinMode(ledSelect, OUTPUT);
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

  // xmit initial state
  xmit_state(state);

} // end of setup()

void loop() {
  
  int pot_val;
  int val_temp;

  // handle mode button presses
  toggle_button(btnMode1, ledMode1, &mode1_btn_state, &mode1_led_state);
  toggle_button(btnMode2, ledMode2, &mode2_btn_state, &mode2_led_state);
  
  // if select button pressed, read pot, update state, and xmit new state
  if (digitalRead(btnSelect) == HIGH) {

    // read the pot
    pot_val = analogRead(potVal);
    debug("raw pv: ", pot_val, -1, -1, 1);

    switch (mode1_led_state) {
      case modeXY:
        switch (mode2_led_state) {
          case modeX:
            val_temp = map(pot_val, minPot, maxPot, minX, maxX);
            state[0] = val_temp;
            debug("m00: ", pot_val, val_temp, -1, 1);
            break;
          case modeY:
            val_temp = map(pot_val, minPot, maxPot, minY, maxY);
            state[1] = val_temp;
            debug("m01: ", pot_val, val_temp, -1, 1);
            break;
          default:
            signal_error();
        } // end mode2_led_state
        break;

      case modeRGB:
        switch (mode2_led_state) {
          case modeRGB0:
            val_temp = map(pot_val, minPot, maxPot, minRGB, maxRGB);
            state[rgb1] = val_temp;
            debug("m10: ", pot_val, val_temp, -1, 1);
            break;
          case modeRGB1:
            val_temp = map(pot_val, minPot, maxPot, minRGB, maxRGB);
            state[rgb2] = val_temp;
            debug("m11: ", pot_val, val_temp, -1, 1);
            break;
          default:
            signal_error();
        } // end mode2_led_state
        break;

      default:
        signal_error();
    } // end mode1_btn_state

    // send state to receiver
    xmit_state(state);

  } // end if select button pressed

} // end of loop()
