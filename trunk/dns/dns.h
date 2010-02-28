// Arduino DNS client for WizNet5100-based Ethernet shield
// (c) Copyright 2009-2010 MCQN Ltd.
// Released under Apache License, version 2.0

#ifndef DNSClient_h
#define DNSClient_h

extern "C" {
    #include "utility/types.h"
}

class DNSClient
{
public:
    // ctor
    void begin(const uint8_t* aDNSServer);

    /** Convert a numeric IP address string into a four-byte IP address.
        @param aIPAddrString IP address to convert
        @param aResult pointer to the four-bytes to store the IP address
        @result 0 if aIPAddrString couldn't be converted to an IP address,
                else success
    */
    int inet_aton(const char *aIPAddrString, uint8_t* aResult);
    int gethostbyname(char* aHostname, uint8_t* aResult);

protected:
    uint16_t BuildRequest(char* aName);
    uint16_t ProcessResponse(int aTimeout, uint8_t* aAddress);

    uint8_t iDNSServer[4];
    uint16_t iRequestId;
    uint8_t iSock;
};

#endif
