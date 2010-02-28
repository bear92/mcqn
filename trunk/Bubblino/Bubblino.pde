/*
 * Bubblino
 * 
 * A twitter-watching, bubble-blowing Arduino-bot.
 * Searches Twitter for mentions of a specific keyword.  Whenever a new mention
 * is found, the device connected to ALERTPIN on the Arduino will be turned on
 *
 * See http://www.mcqn.com/bubblino for more details
 *
 * (c) Copyright 2009-2010 MCQN Ltd.
 * Released under an Apache License, version 2.0
 *
 *
 * Usage:
 * Connect the switch/LED/whatever is triggered to ALERTPIN pin on the Arduino
 * Set the search terms in kSearchPath
 * To modify how long the Bubblino is triggered for each new tweet, change 
 * the ALERTSPINUP and ALERTDURATION values
 *
 * To monitor an Atom feed rather than Twitter, then change kHostname and kSearchPath
 * to the host and URL path for the Atom feed.
 */

#define USE_DHCP

#include <b64.h>
#include <HttpClient.h>
#include <avr/io.h>
#include <string.h>
#include <AtomDateString.h>
#ifdef USE_DHCP
#include <Dhcp.h>
#include <dns.h>
#endif

// Digital output pin that gets turned on when a new tweet is spotted
#define ALERTPIN  2

// Number of seconds to spin up before showing the new alerts
#define ALERTSPINUP  10

// Number of seconds to run for each alert spotted
#define ALERTDURATION  2

// Define LOGGING to have Bubblino output what's happening to Serial
// Comment out the following line if you don't want output to Serial
#define LOGGING

// HTTP-related constants
char* kHostname = "search.twitter.com";
const char* kSearchPath = "/search.atom?q=bubblino";   // the search we want to monitor
//const char* kSearchPath = "/search.atom?q=%23bubblino+OR+%23bcliverpool";  // the search we want to monitor
const char* kUserAgent = "Bubblino/2.1";

// Number of seconds to wait for some data when reading the response
#define READTIMEOUT 3
// Number of seconds to wait with no response before giving up on this download
#define RESPONSETIMEOUT  30

// Max number of characters we can read in in one go
#define READ_BUF_SIZE  256
char linebuffer[READ_BUF_SIZE]; // our large buffer for data

byte mac[] = { 0xca, 0xff, 0xe0, 0x01, 0x4f, 0x9a };
byte ip[] = { 192, 168, 1, 19 };
byte server[] = { 128, 121, 146, 107 }; // search.twitter.com

AtomDateString mostRecentUpdate;
AtomDateString currentUpdateDate;

#ifdef LOGGING
void printIPAddress(byte* aAddress)
{
  Serial.print((int)aAddress[0]);
  Serial.print(".");
  Serial.print((int)aAddress[1]);
  Serial.print(".");
  Serial.print((int)aAddress[2]);
  Serial.print(".");
  Serial.print((int)aAddress[3]);
}

void printlnIPAddress(byte* aAddress)
{
  printIPAddress(aAddress);
  Serial.println();
}
#endif

// CheckTwitter - connect to Twitter and pull down the latest search results.
//   Then parse the results and work out how many new messages have arrived since we last checked
//   @return -1 if there was an error, otherwise the number of new messages
int CheckTwitter(void) 
{
  int ret =0;
  int newMessageCount =0; // Assume we got no new messages to start
  char* found =NULL;
  char* start =NULL;
  char* end =NULL;
  AtomDateString newestDateSeen =mostRecentUpdate;
  DNSClient dns;
  
  // Resolve the hostname to an IP address
  Dhcp.getDnsServerIp(server);
#ifdef LOGGING
  Serial.print("Using DNS server: ");
  printlnIPAddress(server);
#endif
  dns.begin(server);
  ret = dns.gethostbyname(kHostname, server);
  if (ret == 1)
  {
    // Resolved the host okay
#ifdef LOGGING
    Serial.print("Resolved ");
    Serial.print(kHostname);
    Serial.print(" to ");
    printlnIPAddress(server);
#endif

    HttpClient http(server, 80);
  
    ret = http.startRequest(kHostname, kSearchPath, kUserAgent, "application/xml");
    if (ret == 0)
    {
#ifdef LOGGING
      Serial.println("startedRequest ok");
#endif

      http.finishRequest();
    
      ret = http.responseStatusCode();
      if (ret >= 0)
      {
#ifdef LOGGING
        Serial.print("Got status code: ");
        Serial.println(ret);
#endif
        ret = http.skipResponseHeaders();
        if (ret >= 0)
        {
          unsigned long timeoutStart = millis();
          int bodyLen = http.contentLength();
#ifdef LOGGING
          Serial.print("Content length is: ");
          Serial.println(bodyLen);
#endif
        
          // Now we've got to the body, so we can start looking for tweets
          while ( (bodyLen > 0) && (millis() - timeoutStart) < (RESPONSETIMEOUT*1000) ) 
          {
            // read one line from the server at a time
            char c = '\0';
            char* current = linebuffer;
            while ((c != '\n') 
                   && (bodyLen > 0)
                   && ( (millis() - timeoutStart) < (RESPONSETIMEOUT*1000) ) 
                   && ( (current-linebuffer) < (READ_BUF_SIZE-1) ))
            {
              if (http.available())
              {
                // We've got some data to read
                c = http.read();
                // Store it in the linebuffer
                *current++ = c;
                // And reset the timeout counter
                timeoutStart = millis();
              }
              else
              {
                // We haven't got any data, so lets pause to allow some to arrive
                delay(1000);
              }
            }

#ifdef LOGGING
            if (current-linebuffer >= (READ_BUF_SIZE-1))
            {
              Serial.println("### BUFFER OVERFLOW ###");
            }
#endif
    
            if ( (bodyLen == 0) || (c == '\n') || (current-linebuffer == (READ_BUF_SIZE-1)) )
            {
              // We've found a full line, or filled our linebuffer (but we'll process what
              // we've got so far anyway)
              // NUL terminate the linebuffer string
              *current = '\0';
      
              // And now 
              // Look for any "<published>...</published" lines, as that's all we're worried
              // about.  If we get any kind of error response from the server we'll just
              // ignore it as it won't have any matching lines in it
    
              found = strstr(linebuffer, "<published>");
              if (((int)found) != 0) 
              {
                start = strstr(found, ">") + 1; // The date will start just after the published tag ends
                end = strstr(start, "</published>"); // and end when we hit the end-published tag
                if ((start != 0) && (end != 0)) 
                {
                  //Serial.println("\n******Found first entry!*******");
                  // As we don't care about anything other than the published dates, we can overwrite part
                  // of the data to NUL-terminate the date string for easier processing
                  end[0] = 0;
#ifdef LOGGING
                  Serial.print(start);
#endif
                  // See if this update was published after the most recent one we'd seen last time
                  if (currentUpdateDate.Parse("%Y-%m-%dT%H:%M:%SZ", start) == 0)
                  {
#ifdef LOGGING
                    Serial.println(" parsed");
#endif
                    if (currentUpdateDate > mostRecentUpdate)
                    {
                      // This message was posted after the last time we checked
                      newMessageCount++;
#ifdef LOGGING
                      Serial.print("It's newer than ");
                      Serial.print((int)mostRecentUpdate.Year()+1900);
                      Serial.print("-");
                      Serial.print((int)mostRecentUpdate.Month());
                      Serial.print("-");
                      Serial.print((int)mostRecentUpdate.Day());
                      Serial.print(" ");
                      Serial.print((int)mostRecentUpdate.Hours());
                      Serial.print(":");
                      Serial.print((int)mostRecentUpdate.Minutes());
                      Serial.print(":");
                      Serial.println((int)mostRecentUpdate.Seconds());
#endif
                      if (currentUpdateDate > newestDateSeen)
                      {
                        // And it's the newest we've spotted this time too
                        newestDateSeen = currentUpdateDate;
                      }
                    }
                  }
                  else
                  {
#ifdef LOGGING
                    Serial.print("Failed to parse date: ");
                    Serial.println(start);
#endif
                  }
                }
              }
      
              // See if we've reached the end of the page
              if (!http.connected() || (bodyLen == 0))
              {
#ifdef LOGGING
                Serial.println("\nDisconnected...");
#endif
                http.stop();
                // Remember the date of the latest update
                mostRecentUpdate = newestDateSeen;
                return newMessageCount;
              }
            }
            // else we timed out, the main loop will catch that for us
          }

          // If we get here we've timed out without the connection being disconnected
          // Return the number of messages that we've received so far
#ifdef LOGGING
          Serial.println("\nTimed out waiting for response");
          Serial.print("  timeoutStart: ");
          Serial.println(timeoutStart);
          Serial.print("  millis(): ");
          Serial.println(millis());
#endif
          http.stop();
          // Remember the date of the latest update
          mostRecentUpdate = newestDateSeen;
        }
#ifdef LOGGING
        else
        {
          Serial.print("Error getting response: ");
          Serial.println(ret);
        }
#endif
      }
#ifdef LOGGING
      else
      {
        Serial.print("Didn't get a 200 OK response from the server, got: ");
        Serial.println(ret);
      }
#endif
    }
#ifdef LOGGING
    else
    {
      Serial.print("Error sending request: ");
      Serial.println(ret);
    }
#endif
  }
#ifdef LOGGING
  else
  {
    Serial.print("DNS lookup failed: ");
    Serial.println(ret);
  }
#endif
  
  // Remember the date of the latest update
  mostRecentUpdate = newestDateSeen;
  return newMessageCount;
}


void setup()
{
  pinMode(ALERTPIN, OUTPUT);
  
#ifdef LOGGING
  Serial.begin(9600);
  delay(1000);

  Serial.println("Bubblino is alive...");
#endif
  while (Dhcp.beginWithDHCP(mac) != 1)
  {
#ifdef LOGGING
    Serial.println("Error getting IP address via DHCP, trying again...");
#endif
    delay(15000);
  }  
}


// Main execution loop
void loop()
{
  int newMessageCount;
    
#ifdef LOGGING
  Serial.println("Checking twitter for updates...");
#endif
  // Find out if there are any new tweets
  newMessageCount = CheckTwitter();
#ifdef LOGGING
  Serial.println("Done.");
#endif
  if (newMessageCount < 0) 
  {
    // Something went wrong
#ifdef LOGGING
    Serial.println("Error getting data from twitter");
#endif
  }
  else if (newMessageCount > 0)
  {
    // There were some new tweets
#ifdef LOGGING
    Serial.print("We've found ");
    Serial.print(newMessageCount);
    Serial.println(" new tweets");
#endif
    // Turn on Bubblino
    // Give him time to spin up, and then stay on for ALERTDURATION seconds
    // for each new tweet
    digitalWrite(ALERTPIN, HIGH);
    for (int i =0; i < ALERTSPINUP+(newMessageCount*ALERTDURATION); i++)
    {
      delay(1000); // Wait for a second
    }
    digitalWrite(ALERTPIN, LOW);
  }
  // else we didn't get any new messages so don't do anything

  delay(10000); // wait ten seconds before checking for new tweets
}
