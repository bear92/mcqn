// PachubeFetch
// Simple sketch to download a CSV feed from Pachube
// (c) Copyright 2010 MCQN Ltd.
// Released under Apache License, version 2.0
//
// Usage:
// Enter your Pachube username and password in kPachubeUser and kPachubePassword
// and the feed you want to monitor in kPachubeFeed.  Then choose which of the
// feed values to monitor with kPachubeFeedIndex

#include <HttpClient.h>

#include <b64.h>
#include <Ethernet.h>
#include <Dhcp.h>
#include <dns.h>
#include <Client.h>
#include <Server.h>
#include <ctype.h>

byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 10, 0, 0, 177 };
byte server[] = { 209, 40, 205, 190 }; // pachube.com

// Pachube user login details
const char* kPachubeUser = "insert usernamme here";
const char* kPachubePassword = "insert password here";

// Name of the server we want to connect to
char* kHostname = "www.pachube.com";
// Path to the CSV file we want to monitor
const char* kPachubeFeed = "/api/feeds/3147.csv";
// Index into the feed to select the value we want to monitor (0 for the first one)
const int kPachubeFeedIndex = 1;
// These limits set the max and min values that the gauge will display
const int kLowerLimit = 0;
const int kHigherLimit = 39;

// Pin that the gauge is connected to on the Arduino
const int gaugePin = 6;
// Number of milliseconds to wait without receiving any data before we give up
const int kNetworkTimeout = 30*1000;
// Number of milliseconds to wait if no data is available before trying again
const int kNetworkDelay = 1000;
// Number of milliseconds to wait between requests
const int kPollingInterval = 5000;

void setup() {
  // initialize serial communications at 9600 bps:
  Serial.begin(9600); 

  while (Dhcp.beginWithDHCP(mac) != 1)
  {
#ifdef LOGGING
    Serial.println("Error getting IP address via DHCP, trying again...");
#endif
    delay(15000);
  }  
}

void loop() {
  int err =0;
  DNSClient dns;
  
  // Resolve the hostname to an IP address
  Dhcp.getDnsServerIp(server);
  Serial.print("Using DNS server: ");
  for (int b =0; b < 4; b++)
  {
    Serial.print((int)server[b]);
    Serial.print(".");
  }
  Serial.println();
  dns.begin(server);
  err = dns.gethostbyname(kHostname, server);
  if (err == 1)
  {
    // Resolved the host okay

    HttpClient http(server, 80);
  
    err = http.startRequest(kHostname, kPachubeFeed, "Dialbox/1.0", NULL);
    if (err == 0)
    {
      Serial.println("startedRequest ok");

      http.sendBasicAuth(kPachubeUser, kPachubePassword);
    
      http.finishRequest();
    
      err = http.responseStatusCode();
      if (err >= 0)
      {
        Serial.print("Got status code: ");
        Serial.println(err);
        err = http.skipResponseHeaders();
        if (err >= 0)
        {
          int bodyLen = http.contentLength();
          Serial.print("Content length is: ");
          Serial.println(bodyLen);
        
          // Now we've got to the body, so we can extract a feed value
          unsigned long timeoutStart = millis();
          char c ='\0';
          int val = 0;
          int idx = 0;

          // Whilst we haven't timed out & haven't reached the end of the body
          while ((bodyLen > 0) &&
                 ( (millis() - timeoutStart) < kNetworkTimeout ))
          {
              if (http.available())
              {
                  c = http.read();
                  bodyLen--;
                
                  if (idx == kPachubeFeedIndex)
                  {
                    // We're reading in the feed we're interested in
                    if (isdigit(c))
                    {
                      val = val*10 + (c - '0');
                    }
                    else
                    {
                      // We've reached a non-digit character in this value.  It's possible
                      // it's a decimal point, but we don't support that right now anyway
                      // and skip over any subsequent info in this value (e.g. decimal part)
                      idx++;
                    }
                  }
                  else
                  {
                    if (c == ',')
                    {
                      // We've reached the next value
                      idx++;
                    }
                  }

                  // We read something, reset the timeout counter
                  timeoutStart = millis();
              }
              else
              {
                  // We haven't got any data, so let's pause to allow some to
                  // arrive
                  delay(kNetworkDelay);
              }
          }
        
          if (bodyLen == 0)
          {
            Serial.print("Setting value to: ");
            Serial.println(val);
            // We've finished reading the page okay, so we should be able to display the value
            analogWrite(gaugePin, map(val, kLowerLimit, kHigherLimit, 0, 255));
          }
        }
        else
        {
          Serial.print("Failed to skip response headers: ");
          Serial.println(err);
        }
      }
      else
      {    
        Serial.print("Getting response failed: ");
        Serial.println(err);
      }
    }
    else
    {
      Serial.print("Connect failed: ");
      Serial.println(err);
    }
    http.stop();
  }
  else
  {
    Serial.print("Failed to resolve hostname, error: ");
    Serial.println(err);
  }

  // Pause 10 seconds between updates
  delay(10000);
}

