/*
 * Alertuino
 *
 * Listens on the serial port for a command containing the number
 * of alerts to signal, and then turns on the output for 
 * <number of alerts> * <alert duration>
 *
 * (c) 2008 MCQN Ltd.
 */

int alertPin = 12;              // Pin to use to control the alert output
int alertDuration = 2;          // Duration of an alert in seconds
int alertCount = 0;             // Number of alerts read (

void setup()                    // run once, when the sketch starts
{
  pinMode(alertPin, OUTPUT);    // sets the digital pin as output
  Serial.begin(115200);         // open the serial port to receive commands
}

void loop()                     // run over and over again
{
  digitalWrite(alertPin, HIGH);     // start alerting
  for (int i =0; i < (alertCount*alertDuration); i++)
  {
    delay(1000); // wait for a second
  }
  digitalWrite(alertPin, LOW);      // stop alerting
  delay(1000);  // leave it at least a second before firing off any new alerts
  
  alertCount = 0;   // reset how many alerts there are
  int commandChar;  // temp variable used to read data from the serial port
  // now loop until we receive an ASCII number
  // (basically clear out any rubbish between commands)
  do
  {
    commandChar = Serial.read();
    if (commandChar != -1)
    {
      Serial.print(commandChar);
    }
  } while ( (commandChar < '0') || (commandChar > '9') );
  
  // now we've got the first digit of a "command"
  // loop through reading the rest of it
  do
  {
    // only act on this character if it's valid (and -1 is the we timed out return)
    if (commandChar != -1)
    {
      // move existing count up to next power of 10
      alertCount = alertCount * 10;
      // and add the new digit (with a quick-n-dirty hack to convert from ASCII to integer)
      alertCount = alertCount + (commandChar - '0'); 
    }
    // read the next digit (or "end of command" non-digit) from the serial port
    commandChar = Serial.read();
    if (commandChar != -1)
    {
      Serial.print(commandChar);
    }
  } while ( (commandChar == -1) || ((commandChar >= '0') && (commandChar <= '9')) );
}
