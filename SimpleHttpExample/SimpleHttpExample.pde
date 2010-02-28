// (c) Copyright 2010 MCQN Ltd.
// Released under Apache License, version 2.0
//
// Simple example to show how to use the HttpClient library
// Get's the web page given at http://<kHostname><kPath> and
// outputs the content to the serial port

#include <HttpClient.h>
#include <b64.h>
#include <Ethernet.h>
#include <Dhcp.h>
#include <dns.h>
#include <Client.h>
#include <Server.h>

// This example downloads the URL "http://arduino.cc/"

// Name of the server we want to connect to
char* kHostname = "arduino.cc";
// Path to download (this is the bit after the hostname in the URL
// that you want to download
const char* kPath = "/";

byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 10, 0, 0, 177 };
byte server[] = { 209, 40, 205, 190 }; // pachube.com

// Number of milliseconds to wait without receiving any data before we give up
const int kNetworkTimeout = 30*1000;
// Number of milliseconds to wait if no data is available before trying again
const int kNetworkDelay = 1000;

void setup()
{
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

void loop()
{
  int err =0;
  DNSClient dns;
  
  // Get the DNS server address that we were given by DHCP
  Dhcp.getDnsServerIp(server);
  Serial.print("Using DNS server: ");
  for (int b =0; b < 4; b++)
  {
    Serial.print((int)server[b]);
    Serial.print(".");
  }
  Serial.println();
  dns.begin(server);

  // Resolve the hostname to an IP address
  err = dns.gethostbyname(kHostname, server);
  if (err == 1)
  {
    // Resolved the host okay

    HttpClient http(server, 80);
  
    err = http.startRequest(kHostname, kPath, NULL, NULL);
    if (err == 0)
    {
      Serial.println("startedRequest ok");

      http.finishRequest();
    
      err = http.responseStatusCode();
      if (err >= 0)
      {
        Serial.print("Got status code: ");
        Serial.println(err);

        // Usually you'd check that the response code is 200 or a
        // similar "success" code (200-299) before carrying on,
        // but we'll print out whatever response we get

        err = http.skipResponseHeaders();
        if (err >= 0)
        {
          int bodyLen = http.contentLength();
          Serial.print("Content length is: ");
          Serial.println(bodyLen);
          Serial.println();
          Serial.println("Body returned follows:");
        
          // Now we've got to the body, so we can print it out
          unsigned long timeoutStart = millis();
          char c;
          // Whilst we haven't timed out & haven't reached the end of the body
          while (http.connected() &&
                 ( (millis() - timeoutStart) < kNetworkTimeout ))
          {
              if (http.available())
              {
                  c = http.read();
                  // Print out this character
                  Serial.print(c);
                  
                  bodyLen--;
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

  // And just stop, now that we've tried a download
  while(1);
}


