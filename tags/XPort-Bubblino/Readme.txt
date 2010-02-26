Who, or What is Bubblino?
=========================

Bubblino is a Twitter-monitoring, bubble-blowing Arduino-bot. For more details
visit http://www.mcqn.com/bubblino


How do I build one?
===================

Find yourself a suitable bubble-blowing kids toy.  Then buy:

- an Arduino
  http://arduino.cc

- a LadyAda XPort ethernet shield
  http://www.ladyada.net/make/eshield/index.html

You'll also need a 1K ohm resistor, a 2N2222 transistor and some wire.

Wire up the circuit as detailed in slide 21 of the presentation at
http://tinyurl.com/6s9fzb.

Make sure you update the Bubblino.pde code so that ALERTPIN, XPORT_RXPIN,
XPORT_TXPIN, XPORT_RESETPIN, XPORT_DTRPIN, XPORT_CTSPIN, and XPORT_RTSPIN match
the pins you've used to connect the circuit, and modify HTTPPATH to use the
correct term you'd like to search for on Twitter.

Then upload the Bubblino.pde code to your Arduino.


Known Issues
============

Currently this doesn't seem to work with Arduino release 0015 (on Windows XP
at least).  I've only successfully used it with Arduino 0012 on Windows (other
options might work, but I haven't tried them personally).  Hopefully there'll
be an improved version available soon.

