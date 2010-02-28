Who, or What is Bubblino?
=========================

Bubblino is a Twitter-monitoring, bubble-blowing Arduino-bot. For more details
visit http://www.mcqn.com/bubblino


How do I build one?
===================

Find yourself a suitable bubble-blowing kids toy.  Then buy:

- an Arduino
  http://arduino.cc

- an ethernet shield
  http://arduino.cc/en/Main/ArduinoEthernetShield

You'll also need a 1K ohm resistor, a 2N2222 transistor and some wire.

Wire up the circuit as detailed in slide 21 of the presentation at
http://tinyurl.com/6s9fzb.

Make sure you update the Bubblino.pde code so that ALERTPIN matches the pin
you've used to connect the circuit, and modify kSearchPath to use the
correct term you'd like to search for on Twitter.

Then upload the Bubblino.pde code to your Arduino.


Dependencies
============

In order for the code to build, you'll need the DHCP and DNS libraries, the 
AtomDateString library and also the HttpClient library.

These can be found at http://code.google.com/p/mcqn/

