// (c) Copyright 2009 MCQN Ltd.
// Released under Apache License, version 2.0

#include <avr/io.h>
#include <string.h>
#include "AtomDateString.h"

// Helper function to convert a string into an integer
uint32_t AtomDateString::StringToInt(char *str) 
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
}


// Basic constructor
AtomDateString::AtomDateString(uint8_t aYear, uint8_t aMonth, uint8_t aDay, uint8_t aHours, uint8_t aMinutes, uint8_t aSeconds)
: iYear(aYear), iMonth(aMonth), iDay(aDay), iHours(aHours), iMinutes(aMinutes), iSeconds(aSeconds) {}

// Method to take a string containing a date, and use it to initialise the data in this DateString
int AtomDateString::Parse(char* aFormat, char* aString)
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
          year = StringToInt(numBuf) - 1900;
          // Move past the year in the string we're parsing
          aString += 4;
          break;
        case 'm':
          // Month
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          month = StringToInt(numBuf);
          break;
        case 'd':
          // Day of the month
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          day = StringToInt(numBuf);
          break;
        case 'H':
          // Hour
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          hours = StringToInt(numBuf);
          break;
        case 'M':
          // Minutes
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          minutes = StringToInt(numBuf);
          break;
        case 'S':
          // Seconds
          numBuf[0] = *aString++;
          numBuf[1] = *aString++;
          numBuf[2] = '\0';
          seconds = StringToInt(numBuf);
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

bool AtomDateString::operator>(const AtomDateString& aDS)
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
