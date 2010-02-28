// Class to simplify HTTP fetching on Arduino
// (c) Copyright MCQN Ltd. 2010
// Released under Apache License, version 2.0

#ifndef HttpClient_h
#define HttpClient_h

#include "Ethernet.h"

class HttpClient : public Client
{
public:
    enum
    {
        HttpSuccess = 0,
        // The end of the headers has been reached.  This consumes the '\n'
        // Could not connect to the server
        HttpErrConnectionFailed =-1,
        // This call was made when the HttpClient class wasn't expecting it
        // to be called.  Usually indicates your code is using the class
        // incorrectly
        HttpErrAPI =-2,
        // Spent too long waiting for a reply
        HttpErrTimedOut =-3,
        // The response from the server is invalid, is it definitely an HTTP
        // server?
        HttpErrInvalidResponse =-4,
    };

    static const char* kUserAgent;

    HttpClient(uint8_t* aServerIPAddress, uint16_t aPort);

    /** Connect to the server and start to send the request.
      @param aServerName Name of the server being connected to.  If NULL, the
                         "Host" header line won't be sent
      @param aURLPath	Url to request
      @param aUserAgent User-Agent string to send.  If NULL the default
                        user-agent kUserAgent will be sent
      @param aAcceptList List of MIME types that the client will accept.  If
                         NULL the "Accept" header line won't be sent
      @return 0 if successful, else error
    */
    int startRequest(const char* aServerName,
                     const char* aURLPath,
                     const char* aUserAgent,
                     const char* aAcceptList);

    /** Send an additional header line.  This can only be called in between the
      calls to startRequest and finishRequest.
      @param aHeader Header line to send, in its entirety (but without the
                     trailing CRLF.  E.g. "Authorization: Basic YQDDCAIGES" 
    */
    void sendHeader(const char* aHeader);

    /** Send an additional header line.  This is an alternate form of
      sendHeader() which takes the header name and content as separate strings.
      The call will add the ": " to separate the header, so for example, to
      send a XXXXXX header call sendHeader("XXXXX", "Something")
      @param aHeaderName Type of header being sent
      @param aHeaderValue Value for that header
    */
    void sendHeader(const char* aHeaderName, const char* aHeaderValue);

    /** Send a basic authentication header.  This will encode the given username
      and password, and send them in suitable header line for doing Basic
      Authentication.
      @param aUser Username for the authorization
      @param aPassword Password for the user aUser
    */
    void sendBasicAuth(const char* aUser, const char* aPassword);

    /** Finish sending the HTTP request.  This basically just sends the blank
      line to signify the end of the request
    */
    void finishRequest();

    /** Get the HTTP status code contained in the response.
      For example, 200 for successful request, 404 for file not found, etc.
    */
    int responseStatusCode();

    /** Read the next character of the response headers.
      This functions in the same way as read() but to be used when reading
      through the headers.  Check whether or not the end of the headers has
      been reached by calling endOfHeadersReached(), although after that point
      this will still return data as read() would, but slightly less efficiently
      @return The next character of the response headers
    */
    int readHeader();

    /** Skip any response headers to get to the body.
      Use this if you don't want to do any special processing of the headers
      returned in the response.  You can also use it after you've found all of
      the headers you're interested in, and just want to get on with processing
      the body.
      @return HttpSuccess if successful, else an error code
    */
    int skipResponseHeaders();

    /** Test whether all of the response headers have been consumed.
      @return true if we are now processing the response body, else false
    */
    bool endOfHeadersReached() { return (iState == eReadingBody); };

    int contentLength() { return iContentLength; };
protected:
    // Number of milliseconds that we wait each time there isn't any data
    // available to be read (during status code and header processing)
    static const int kHttpWaitForDataDelay = 1000;
    // Number of milliseconds that we'll wait in total without receiveing any
    // data before returning HttpErrTimedOut (during status code and header
    // processing)
    static const int kHttpResponseTimeout = 30*1000;
    static const char* kContentLengthPrefix;
    typedef enum {
        eIdle,
        eRequestStarted,
        eRequestSent,
        eReadingStatusCode,
        eStatusCodeRead,
        eReadingContentLength,
        eSkipToEndOfHeader,
        eLineStartingCRFound,
        eReadingBody
    } tHttpState;
    // Current state of the finite-state-machine
    tHttpState iState;
    // Stores the status code for the response, once known
    int iStatusCode;
    // Stores the value of the Content-Length header, if present
    int iContentLength;
    // How many bytes of the response body have been read by the user
    int iBodyLengthConsumed;
    // How far through a Content-Length header prefix we are
    const char* iContentLengthPtr;
};

#endif
