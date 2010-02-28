// Simple example to show how the Ethernet WebClient example would change to
// use the DNS library

#include <Ethernet.h>
#include <Dhcp.h>
#include <dns.h>

char* kHostname = "www.google.com";
byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[4]; // = { 10, 0, 0, 177 };
byte server[4]; // = { 64, 233, 187, 99 }; // Google

Client client(server, 80);

void setup()
{
  Serial.begin(9600);
  while (Dhcp.beginWithDHCP(mac) != 1)
  {
    Serial.println("Error getting IP address via DHCP, trying again...");
    delay(15000);
  }    
  delay(1000);
  
  Serial.println("connecting...");
  
  DNSClient dns;
  Dhcp.getDnsServerIp(server);
  dns.begin(server);

  // Resolve the hostname to an IP address
  int err = dns.gethostbyname(kHostname, server);
  if (err == 1)
  {
    Serial.print(kHostname);
    Serial.print(" resolved to ");
    Serial.print((int)server[0]);
    Serial.print(".");
    Serial.print((int)server[1]);
    Serial.print(".");
    Serial.print((int)server[2]);
    Serial.print(".");
    Serial.println((int)server[3]);
    if (client.connect()) {
      Serial.println("connected");
      client.println("GET /search?q=arduino HTTP/1.0");
      client.println();
    } else {
      Serial.println("connection failed");
    }
  }
  else
  {
    Serial.println("DNS lookup failed");
  }
}

void loop()
{
  if (client.available()) {
    char c = client.read();
    Serial.print(c);
  }
  
  if (!client.connected()) {
    Serial.println();
    Serial.println("disconnecting.");
    client.stop();
    for(;;)
      ;
  }
}
