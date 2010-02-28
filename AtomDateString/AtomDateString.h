// (c) Copyright 2009 MCQN Ltd.
// Released under Apache License, version 2.0

#ifndef ATOMDATESTRING_H
#define ATOMDATESTRING_H

// This class is used to decode and compare the date/time strings that we receive from the
// Twitter search results.
class AtomDateString
{
  public:
    static uint32_t StringToInt(char* aStr);
    AtomDateString(uint8_t aYear =0, uint8_t aMonth =0, uint8_t aDay =0, uint8_t aHours =0, uint8_t aMinutes =0, uint8_t aSeconds =0);
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
    bool operator>(const AtomDateString& aDS);
  private:
    uint8_t iYear; // Number of years since 1900
    uint8_t iMonth;
    uint8_t iDay;
    uint8_t iHours;
    uint8_t iMinutes;
    uint8_t iSeconds;
};

#endif
