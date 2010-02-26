/*
 * Bubblino
 * 
 * A twitter-watching, bubble-blowing Arduino-bot.
 * Searches Twitter for mentions of a specific keyword.  Whenever a new mention
 * is found, the device connected to ALERTPIN on the Arduino will be turned on
 *
 * See http://www.mcqn.com/bubblino for more details
 *
 * (c) Copyright 2009 MCQN Ltd.
 */

#include <avr/io.h>
#include <string.h>
#include "AFSoftSerial.h"
#include "AF_XPort.h"

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
#define HOSTNAME "search.twitter.com"
#define IPADDR "128.121.146.107" // search.twitter.com
#define PORT 80                  // HTTP
#define HTTPPATH "/search.atom?q=bubblino"      // the search we want to monitor
//#define HTTPPATH "/search.atom?q=%23bubblino+OR+%23bcliverpool"      // the search we want to monitor
#define USERAGENT "Bubblino/1.0"

// Number of seconds to wait for some data when reading the response
#define READTIMEOUT 3
// Number of seconds to wait with no response before giving up on this download
#define RESPONSETIMEOUT  30


// This class is used to decode and compare the date/time strings that we receive from the
// Twitter search results.
class DateString
{
  public:
    DateString(uint8_t aYear =0, uint8_t aMonth =0, uint8_t aDay =0, uint8_t aHours =0, uint8_t aMinutes =0, uint8_t aSeconds =0);
    uint8_t Year() { return iYear; };
    uint8_t Month() { return iMonth; };
    uint8_t Day() { return iDay; };
    uint8_t Hours() { return iHours; };
    uint8_t Minutes() { return iMinutes; };
    uint8_t Seconds() { return iSeconds; };
    // Initialise this DateString to the date/time given in aString, using the format defined in aFormat
    //   @param aFormat - string defining the format for the given date string.
    //     %Y - four-digit year
    //     %m - month (01-12)
    //     %d - day of the month (01-31)
    //     %H - hour of the day (00-23)
    //     %M - minutes (00-59)
    //     %S - seconds (00-59)
    //   @param aString - string containing the date to be parsed
    //   @return 0 if successful, else error
    int Parse(char* aFormat, char* aString);
    // Operator overloading to see if this DateString is newer than the one given in aDS
    // This means that if you've got two DateString objects, ds1 and ds2, you can write
    // code like:
    //   if (ds1 > ds2)
    // to compare DateString objects
    bool operator>(const DateString& aDS);
  private:
    uint8_t iYear; // Number of years since 1900
    uint8_t iMonth;
    uint8_t iDay;
    uint8_t iHours;
    uint8_t iMinutes;
    uint8_t iSeconds;
};
// Basic constructor
DateString::DateString(uint8_t aYear, uint8_t aMonth, uint8_t aDay, uint8_t aHours, uint8_t aMinutes, uint8_t aSeconds)
: iYear(aYear), iMonth(aMonth), iDay(aDay), iHours(aHours), iMinutes(aMinutes), iSeconds(aSeconds) {}
// Method to take a string containing a date, and use it to initialise the data in this DateString
int DateString::Parse(char* aFormat, char* aString)
{
  uint8_t year =0, month =0, day =0, hours =0, minutes =0, seconds =0;
  
  if (!aFormat || !aString)
  {
    // Bad arguments
    return -1;
  }
  // Loop through the format string...
  while (*aFormat)
  {
    if (*aFormat == '%')
    {
      // This is a special character, read in the data from the format
      char numBuf[5]; // Enough space for even a four-digit year
      aFormat++; // Skip on to the type of data we need to read next
      switch (*aFormat)
      {
        case 'Y':
          // 4-digit year
          strncpy(numBuf, aString, 4);
          numBuf[4] = '\0';
          year = stringToInt(numBuf) - 1900;
          // Move past the year in the string we're parsing
          aString += 4;
          break;
        case 'm':
          // Month
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          month = stringToInt(numBuf);
          break;
        case 'd':
          // Day of the month
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          day = stringToInt(numBuf);
          break;
        case 'H':
          // Hour
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          hours = stringToInt(numBuf);
          break;
        case 'M':
          // Minutes
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          minutes = stringToInt(numBuf);
          break;
        case 'S':
          // Seconds
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          seconds = stringToInt(numBuf);
          break;
        default:
          // We don't understand any other formatting at present
          return -1;
      };
      aFormat++; // Move onto the next character in the format string
    }
    else if (*aFormat == *aString)
    {
      // Format string still matches date we're parsing, so just skip over this
      aFormat++;
      aString++;
    }
    else
    {
      // The string to be parsed doesn't match what we're expecting
      return -2;
    }
  }
  
  // We've parsed the date.  Update our internal data to match the parsed date
  iYear = year;
  iMonth = month;
  iDay = day;
  iHours = hours;
  iMinutes = minutes;
  iSeconds = seconds;
  return 0;
}
bool DateString::operator>(const DateString& aDS)
{
  if (iYear > aDS.iYear)
  {
    return true;
  }
  else if (iYear == aDS.iYear)
  {
    if (iMonth > aDS.iMonth)
    {
      return true;
    }
    else if (iMonth == aDS.iMonth)
    {
      if (iDay > aDS.iDay)
      {
        return true;
      }
      else if (iDay == aDS.iDay)
      {
        if (iHours > aDS.iHours)
        {
          return true;
        }
        else if (iHours == aDS.iHours)
        {
          if (iMinutes > aDS.iMinutes)
          {
            return true;
          }
          else if (iMinutes == aDS.iMinutes)
          {
            if (iSeconds > aDS.iSeconds)
            {
              return true;
            }
          }
        }
      }
    }
  }
  // If we get here, it's <= us
  return false;
}

#define XPORT_RXPIN 5
#define XPORT_TXPIN 6
#define XPORT_RESETPIN 7
#define XPORT_DTRPIN 4
#define XPORT_CTSPIN 3
#define XPORT_RTSPIN 0

char linebuffer[256]; // our large buffer for data

AF_XPort xport = AF_XPort(XPORT_RXPIN, XPORT_TXPIN, XPORT_RESETPIN, XPORT_DTRPIN, XPORT_RTSPIN, XPORT_CTSPIN);

DateString mostRecentUpdate;
DateString currentUpdateDate;

// Helper function to convert a string into an integer
uint32_t stringToInt(char *str) 
{
  uint32_t ret =0;

  // Loop through the string until we hit the end or a non-digit character
  while (*str && (*str >= '0') && (*str <= '9'))
  {
    // move existing count up to next power of 10
    ret = ret * 10;
    // and add the new digit (with a quick-n-dirty hack to convert from ASCII to integer)
    ret = ret + (*str - '0'); 
    // And move to the next character in the string
    str++;
  }
  return ret;
#if 0
  uint32_t num = 0;
  char c;
  
  // grabs a number out of a string
  while (c = str[0]) {
   if ((c < '0') || (c > '9'))
     return num;
   num *= 10;
   num += c - '0';
   str++;
 }
 return num;
#endif
}

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
  DateString newestDateSeen =mostRecentUpdate;
  
  ret = xport.reset();

  switch (ret) 
  {
    case  ERROR_TIMEDOUT: 
    { 
#ifdef LOGGING
      Serial.println("Timed out on reset!"); 
#endif
      return -1;
    }
    case ERROR_BADRESP:  
    { 
#ifdef LOGGING
      Serial.println("Bad response on reset!");
#endif
      return -1;
    }
    case ERROR_NONE: 
    { 
#ifdef LOGGING
      Serial.println("Reset OK!");
#endif
      break;
    }
    default:
    {
#ifdef LOGGING
      Serial.println("Unknown error"); 
#endif
      return -1;
    }
  }
  
  // time to connect...
 
  ret = xport.connect(IPADDR, PORT);
  switch (ret) 
  {
    case  ERROR_TIMEDOUT: 
    { 
#ifdef LOGGING
      Serial.println("Timed out on connect"); 
#endif
      return -1;
    }
    case ERROR_BADRESP:  
    { 
#ifdef LOGGING
      Serial.println("Failed to connect");
#endif
      return -1;
    }
    case ERROR_NONE: 
    { 
#ifdef LOGGING
      Serial.println("Connected..."); break;
#endif
    }
    default:
    {
#ifdef LOGGING
      Serial.println("Unknown error"); 
#endif
      return -1;
    }
  } 
  
  // send the HTTP command, ie "GET /somepath/ HTTP/1.0"
  
  xport.print("GET "); 
  xport.print(HTTPPATH);
  xport.println(" HTTP/1.0"); 
  xport.print("User-Agent: ");
  xport.println(USERAGENT);
  xport.println();  // Blank line shows the end of the header 

  int timeoutCount =0;
  while (timeoutCount < RESPONSETIMEOUT) 
  {
    // read one line from the xport at a time
    ret = xport.readline_timeout(linebuffer, 255, READTIMEOUT*1000);

    if (ret == 0)
    {
      // We timed out
#ifdef LOGGING
      Serial.print("..timed out..");
#endif
      timeoutCount += READTIMEOUT;
    }
    else
    {
      // We got some data, so reset the timeout counter
      timeoutCount = 0;
    }

    // Look for any "<published>...</published" lines, as that's all we're worried about
    // If we get any kind of error response from the server we'll just ignore it as it
    // won't have any matching lines in it
    
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
    if ( ((XPORT_DTRPIN == 0) &&
         (linebuffer[0] == 'D') && (linebuffer[1] == 0)) ||
        xport.disconnected() )
    {
#ifdef LOGGING
      Serial.println("\nDisconnected...");
#endif
      // Remember the date of the latest update
      mostRecentUpdate = newestDateSeen;
      return newMessageCount;
    }
  }

  // If we get here we've timed out without the connection being disconnected
  // Return the number of messages that we've received so far
#ifdef LOGGING
  Serial.println("\nTimed out waiting for response");
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
#endif
  // xport
  xport.begin(9600);
#ifdef LOGGING
  Serial.println("Bubblino is alive...");
#endif
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
