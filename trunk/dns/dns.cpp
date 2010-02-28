// Arduino DNS client for WizNet5100-based Ethernet shield
// (c) Copyright 2009-2010 MCQN Ltd.
// Released under Apache License, version 2.0

extern "C" {
    #include "types.h"
    #include "w5100.h"
    #include "sockutil.h"
    #include "socket.h"
    #include "spi.h"
}

#include "dns.h"
#include <string.h>
//#include <stdlib.h>
#include "wiring.h"


#define SOCKET_NONE	255
// Various flags and header field values for a DNS message
#define UDP_HEADER_SIZE	8
#define DNS_HEADER_SIZE	12
#define TTL_SIZE        4
#define QUERY_FLAG               (0)
#define RESPONSE_FLAG            (1<<15)
#define QUERY_RESPONSE_MASK      (1<<15)
#define OPCODE_STANDARD_QUERY    (0)
#define OPCODE_INVERSE_QUERY     (1<<11)
#define OPCODE_STATUS_REQUEST    (2<<11)
#define OPCODE_MASK              (15<<11)
#define AUTHORITATIVE_FLAG       (1<<10)
#define TRUNCATION_FLAG          (1<<9)
#define RECURSION_DESIRED_FLAG   (1<<8)
#define RECURSION_AVAILABLE_FLAG (1<<7)
#define RESP_NO_ERROR            (0)
#define RESP_FORMAT_ERROR        (1)
#define RESP_SERVER_FAILURE      (2)
#define RESP_NAME_ERROR          (3)
#define RESP_NOT_IMPLEMENTED     (4)
#define RESP_REFUSED             (5)
#define RESP_MASK                (15)
#define TYPE_A                   (0x0001)
#define CLASS_IN                 (0x0001)
#define LABEL_COMPRESSION_MASK   (0xC0)
// Port number that DNS servers listen on
#define DNS_PORT        53

// Possible return codes from ProcessResponse
#define SUCCESS          1
#define TIMED_OUT        -1
#define INVALID_SERVER   -2
#define TRUNCATED        -3
#define INVALID_RESPONSE -4

void DNSClient::begin(const uint8_t* aDNSServer)
{
    // Just store the DNS server for whenever we need it
    memcpy(iDNSServer, aDNSServer, sizeof(iDNSServer));
    iRequestId = 0;
    iSock = SOCKET_NONE;
}


int DNSClient::inet_aton(const char* aIPAddrString, uint8_t* aResult)
{
    // See if we've been given a valid IP address
    const char* p =aIPAddrString;
    while (*p &&
           ( (*p == '.') || (*p >= '0') || (*p <= '9') ))
    {
        p++;
    }

    if (*p == '\0')
    {
        // It's looking promising, we haven't found any invalid characters
        p = aIPAddrString;
        int segment =0;
        int segmentValue =0;
        while (*p && (segment < 4))
        {
            if (*p == '.')
            {
                // We've reached the end of a segment
                if (segmentValue > 255)
                {
                    // You can't have IP address segments that don't fit in a byte
                    return 0;
                }
                else
                {
                    aResult[segment] = (byte)segmentValue;
                    segment++;
                    segmentValue = 0;
                }
            }
            else
            {
                // Next digit
                segmentValue = (segmentValue*10)+(*p - '0');
            }
            p++;
        }
        // We've reached the end of address, but there'll still be the last
        // segment to deal with
        if ((segmentValue > 255) || (segment > 3))
        {
            // You can't have IP address segments that don't fit in a byte,
            // or more than four segments
            return 0;
        }
        else
        {
            aResult[segment] = (byte)segmentValue;
            return 1;
        }
    }
    else
    {
        return 0;
    }
}

int DNSClient::gethostbyname(char* aHostname, uint8_t* aResult)
{
    // See if it's a numeric IP address
    if (inet_aton(aHostname, aResult))
    {
        // It is, our work here is done
        return 1;
    }
	
    // Find a socket to use

    if (iSock != SOCKET_NONE)
    {
        return 0;
    }
  
    for (int i = 0; i < MAX_SOCK_NUM; i++)
    {
        uint8_t s = getSn_SR(i);
        if (s == SOCK_CLOSED || s == SOCK_FIN_WAIT)
        {
            iSock = i;
            break;
        }
    }

    if (iSock == SOCKET_NONE)
    {
        // Couldn't find a spare socket
        return 0;
    }

    int ret =0;
    if (socket(iSock, Sn_MR_UDP, 1024+(millis() & 0xF), 0))
    {
        // Try up to three times
        int retries = 0;
//        while ((retries < 3) && (ret <= 0))
        {
            // Send DNS request
            ret = startUDP(iSock, iDNSServer, DNS_PORT);
            if (ret != 0)
            {
                // Now output the request data
                ret = BuildRequest(aHostname);
                if (ret != 0)
                {
                    // And finally send the request
                    ret = sendUDP(iSock);
                    if (ret != 0)
                    {
                        // Now wait for a response
                        int wait_retries = 0;
                        ret = TIMED_OUT;
                        while ((wait_retries < 3) && (ret == TIMED_OUT))
                        {
                            ret = ProcessResponse(5000, aResult);
                            wait_retries++;
                        }
                    }
                }
            }
            retries++;
        }

        // We're done with the socket now
        close(iSock);
        iSock = SOCKET_NONE;
    }

    return ret;
}

uint16_t DNSClient::BuildRequest(char* aName)
{
    // Build header
    //                                    1  1  1  1  1  1
    //      0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                      ID                       |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |QR|   Opcode  |AA|TC|RD|RA|   Z    |   RCODE   |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                    QDCOUNT                    |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                    ANCOUNT                    |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                    NSCOUNT                    |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                    ARCOUNT                    |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    // As we only support one request at a time at present, we can simplify
    // some of this header
    iRequestId = millis(); // generate a random ID
    uint16_t twoByteBuffer;
    uint16_t ret;

    // FIXME This should all be possible with the calls to bufferData, which are commented
    // FIXME out at present, but the data doesn't seem to be written out correctly if we try
    // FIXME that.
    // FIXME We should also check that there's enough space available to write to, rather
    // FIXME than assume there's enough space (as the code does at present)
    uint16_t ptr = IINCHIP_READ(Sn_TX_WR0(0));
    ptr = ((ptr & 0x00ff) << 8) + IINCHIP_READ(Sn_TX_WR0(0) + 1);

    write_data(iSock, (uint8 *)&iRequestId, (uint8_t*)ptr, 2);
    ptr += 2;
//    ret = bufferData(iSock, (uint8_t*)&iRequestId, sizeof(iRequestId));
//    if (ret == sizeof(iRequestId))
    {
        twoByteBuffer = htons(QUERY_FLAG | OPCODE_STANDARD_QUERY | RECURSION_DESIRED_FLAG);
        write_data(iSock, (uint8_t*)&twoByteBuffer, (uint8_t *)ptr, 2);
        ptr += 2;
//        ret = bufferData(iSock, (uint8_t*)&another, sizeof(twoByteBuffer));
//        if (ret == sizeof(twoByteBuffer))
        {
            twoByteBuffer = htons(1);  // One question record
            write_data(iSock, (uint8_t*)&twoByteBuffer, (uint8_t *)ptr, 2);
            ptr += 2;
//            ret = bufferData(iSock, (uint8_t*)&one, sizeof(twoByteBuffer));
//            if (ret == sizeof(twoByteBuffer))
            {
                twoByteBuffer = 0;  // Zero answer records
                write_data(iSock, (uint8_t*)&twoByteBuffer, (uint8_t *)ptr, 2);
                ptr += 2;
//                ret = bufferData(iSock, (uint8_t*)&twoByteBuffer, sizeof(twoByteBuffer));
//                if (ret == sizeof(twoByteBuffer))
                {
                    // Zero authority records
                    write_data(iSock, (uint8_t*)&twoByteBuffer, (uint8_t *)ptr, 2);
                    ptr += 2;
//                    ret = bufferData(iSock, (uint8_t*)&twoByteBuffer, sizeof(twoByteBuffer));
//                    if (ret == sizeof(twoByteBuffer))
                    {
                        // and zero additional records
                        write_data(iSock, (uint8_t*)&twoByteBuffer, (uint8_t *)ptr, 2);
                        ptr += 2;
//                        ret = bufferData(iSock, (uint8_t*)&twoByteBuffer, sizeof(twoByteBuffer));
//                        if (ret == sizeof(twoByteBuffer))
                        {
                            // Build question
                            char* start =aName;
                            char* end =start;
                            uint8_t len;
                            // Run through the name being requested
                            while (*end)
                            {
                                // Find out how long this section of the name is
                                end = start;
                                while (*end && (*end != '.') )
                                {
                                    end++;
                                }

                                if (end-start > 0)
                                {
                                    // Write out the size of this section
                                    len = end-start;
                                    write_data(iSock, (uint8_t*)&len, (uint8_t *)ptr, 1);
                                    ptr += 1;
//                                    ret = bufferData(iSock, &len, sizeof(len));
//                                    if (ret != sizeof(len))
//                                    {
//                                        // We didn't manage to write things out
//                                        return 0;
//                                    }
                                    // And then write out the section
                                    write_data(iSock, (uint8_t*)start, (uint8_t *)ptr, len);
                                    ptr += len;
//                                    ret = bufferData(iSock, (uint8_t*)start, end-start);
//                                    if (ret != (end-start))
//                                    {
//                                        // There was a problem writing out this chunk of data
//                                        return 0;
//                                    }
                                }
                                start = end+1;
                            }

                            // We've got to the end of the question name, so
                            // terminate it with a zero-length section
                            len = 0;
                            write_data(iSock, (uint8_t*)&len, (uint8_t *)ptr, 1);
                            ptr += 1;
//                            ret = bufferData(iSock, &len, sizeof(len));
//                            if (ret == sizeof(len))
                            {
                                // Finally the type and class of question
                                twoByteBuffer = htons(TYPE_A);
                                write_data(iSock, (uint8_t*)&twoByteBuffer, (uint8_t *)ptr, 2);
                                ptr += 2;
//                                ret = bufferData(iSock, (uint8_t*)&twoByteBuffer, sizeof(twoByteBuffer));
//                                if (ret == sizeof(twoByteBuffer))
                                {
                                    twoByteBuffer = htons(CLASS_IN);  // Internet class of question
                                    write_data(iSock, (uint8_t*)&twoByteBuffer, (uint8_t *)ptr, 2);
                                    ptr += 2;
//                                    ret = bufferData(iSock, (uint8_t*)&twoByteBuffer, sizeof(twoByteBuffer));
//                                    if (ret == sizeof(twoByteBuffer))
                                    {
										// FIXME And for now update the buffer size here
                                        IINCHIP_WRITE(Sn_TX_WR0(iSock),(uint8)((ptr & 0xff00) >> 8));
                                        IINCHIP_WRITE((Sn_TX_WR0(iSock) + 1),(uint8)(ptr & 0x00ff));
                                        // Success!  Everything buffered okay
                                        return 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // If we get here, one of the many bufferData calls failed to write out
    // all its data
    return 0;
}


uint16_t DNSClient::ProcessResponse(int aTimeout, uint8_t* aAddress)
{
    uint32_t startTime = millis();

    // Wait for a response packet
    while((IINCHIP_READ(Sn_RX_RSR0(iSock)) == 0x0000) && (IINCHIP_READ(Sn_RX_RSR0(iSock) + 1) == 0x0000))
    {
        if((millis() - startTime) > aTimeout)
            return TIMED_OUT;
    }

    // We've had a reply!
    uint16_t ptr = IINCHIP_READ(Sn_RX_RD0(iSock));
    ptr = ((ptr & 0x00ff) << 8) + IINCHIP_READ(Sn_RX_RD0(iSock) + 1);

    // Read the UDP header
    uint8_t header[DNS_HEADER_SIZE]; // Enough space to reuse for the DNS header
    read_data(iSock, (uint8_t*)ptr, header, UDP_HEADER_SIZE);
    ptr += UDP_HEADER_SIZE;
    // Check that it's a response from the right server and the right port
    if ( (memcmp(iDNSServer, header, 4) != 0) || 
        ( *((uint16_t*)&header[4]) != htons(DNS_PORT) ) )
    {
        // It's not from who we expected
        return INVALID_SERVER;
    }

    // Read through the rest of the response
    uint16_t data_len = htons(*((uint16_t*)&header[6]));
    uint16_t end_ptr = ptr + data_len;
    if (data_len < DNS_HEADER_SIZE)
    {
        return TRUNCATED;
    }
    read_data(iSock, (uint8_t*)ptr, header, DNS_HEADER_SIZE);
    ptr += DNS_HEADER_SIZE;

    uint16_t header_flags = htons(*((uint16_t*)&header[2]));
    // Check that it's a response to this request
    if ( ( iRequestId != (*((uint16_t*)&header[0])) ) ||
        (header_flags & QUERY_RESPONSE_MASK != RESPONSE_FLAG) )
    {
        // Mark the entire packet as read
        IINCHIP_WRITE(Sn_RX_RD0(iSock),(uint8)((end_ptr & 0xff00) >> 8));
        IINCHIP_WRITE((Sn_RX_RD0(iSock) + 1),(uint8)(end_ptr & 0x00ff));
        return INVALID_RESPONSE;
    }
    // Check for any errors in the response (or in our request)
    // although we don't do anything to get round these
    if ( (header_flags & TRUNCATION_FLAG) || (header_flags & RESP_MASK) )
    {
        // Mark the entire packet as read
        IINCHIP_WRITE(Sn_RX_RD0(iSock),(uint8)((end_ptr & 0xff00) >> 8));
        IINCHIP_WRITE((Sn_RX_RD0(iSock) + 1),(uint8)(end_ptr & 0x00ff));
        return -5; //INVALID_RESPONSE;
    }

    // And make sure we've got (at least) one answer
    uint16_t answerCount = htons(*((uint16_t*)&header[6]));
    if (answerCount == 0 )
    {
        // Mark the entire packet as read
        IINCHIP_WRITE(Sn_RX_RD0(iSock),(uint8)((end_ptr & 0xff00) >> 8));
        IINCHIP_WRITE((Sn_RX_RD0(iSock) + 1),(uint8)(end_ptr & 0x00ff));
        return -6; //INVALID_RESPONSE;
    }

    // Skip over any questions
    for (int i =0; i < htons(*((uint16_t*)&header[4])); i++)
    {
        // Skip over the name
        uint8_t len;
        do
        {
            read_data(iSock, (uint8_t*)ptr, &len, sizeof(len));
            // Don't need to actually read the data out for the string, just
            // advance ptr to beyond it
            ptr += sizeof(len) + len;
        } while (len != 0);
        // Now jump over the type and class
        ptr += 4;
    }

    // Now we're up to the bit we're interested in, the answer
    // There might be more than one answer (although we'll just use the first
    // type A answer) and some authority and additional resource records but
    // we're going to ignore all of them.

    for (int i =0; i < answerCount; i++)
    {
        // Skip the name
        uint8_t len;
        do
        {
            read_data(iSock, (uint8_t*)ptr, &len, sizeof(len));
            if ((len & LABEL_COMPRESSION_MASK) == 0)
            {
                // It's just a normal label
                // Don't need to actually read the data out for the string, just
                // advance ptr to beyond it
                ptr += sizeof(len) + len;
            }
            else
            {
                // This is a pointer to a somewhere else in the message for the
                // rest of the name.  We don't care about the name, and RFC1035
                // says that a name is either a sequence of labels ended with a
                // 0 length octet or a pointer or a sequence of labels ending in
                // a pointer.  Either way, when we get here we're at the end of
                // the name
                // Skip over the pointer
                ptr += 2;
                // And set len so that we drop out of the name loop
                len = 0;
            }
        } while (len != 0);

        // Check the type and class
        uint16_t answerType;
        uint16_t answerClass;
        read_data(iSock, (uint8_t*)ptr, (uint8_t*)&answerType, sizeof(answerType));
        ptr += sizeof(answerType);

        read_data(iSock, (uint8_t*)ptr, (uint8_t*)&answerClass, sizeof(answerClass));
        ptr += sizeof(answerClass);

        // Ignore the Time-To-Live as we don't do any caching
        ptr += TTL_SIZE;

        // And read out the length of this answer
        // Don't need header_flags anymore, so we can reuse it here
        read_data(iSock, (uint8_t*)ptr, (uint8_t*)&header_flags, sizeof(header_flags));
        ptr += sizeof(header_flags);

        if ( (htons(answerType) == TYPE_A) && (htons(answerClass) == CLASS_IN) )
        {
            if (htons(header_flags) != 4)
            {
                // It's a weird size
                // Mark the entire packet as read
                IINCHIP_WRITE(Sn_RX_RD0(iSock),(uint8)((end_ptr & 0xff00) >> 8));
                IINCHIP_WRITE((Sn_RX_RD0(iSock) + 1),(uint8)(end_ptr & 0x00ff));
                return -9;//INVALID_RESPONSE;
            }
            read_data(iSock, (uint8_t*)ptr, aAddress, 4);
            return SUCCESS;
        }
        else
        {
            // This isn't an answer type we're after, move onto the next one
            ptr += htons(header_flags);
        }
    }

    // Mark the entire packet as read
    IINCHIP_WRITE(Sn_RX_RD0(iSock),(uint8)((end_ptr & 0xff00) >> 8));
    IINCHIP_WRITE((Sn_RX_RD0(iSock) + 1),(uint8)(end_ptr & 0x00ff));

    IINCHIP_WRITE(Sn_CR(0),Sn_CR_RECV);

    while( IINCHIP_READ(Sn_CR(0)) );

    // If we get here then we haven't found an answer
    return -10;//INVALID_RESPONSE;
}

