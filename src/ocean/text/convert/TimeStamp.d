/*******************************************************************************

    Converts between native and text representations of HTTP time
    values. Internally, time is represented as UTC with an epoch
    fixed at Jan 1st 1970. The text representation is formatted in
    accordance with RFC 1123, and the parser will accept one of
    RFC 1123, RFC 850, or asctime formats.

    See http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html for
    further detail.

    Applying the D "import alias" mechanism to this module is highly
    recommended, in order to limit namespace pollution:

    ---
        import TimeStamp = ocean.text.convert.TimeStamp;

        auto t = TimeStamp.parse ("Sun, 06 Nov 1994 08:49:37 GMT");
    ---

    Copyright:
        Copyright (c) 2004 Kris Bell.
        Some parts copyright (c) 2009-2016 dunnhumby Germany GmbH.
        All rights reserved.

    License:
        Tango Dual License: 3-Clause BSD License / Academic Free License v3.0.
        See LICENSE_TANGO.txt for details.

    Version: Initial release: May 2005

    Authors: Kris

*******************************************************************************/

module ocean.text.convert.TimeStamp;

import ocean.core.ExceptionDefinitions;
import ocean.core.Verify;
import ocean.meta.types.Qualifiers;
import ocean.time.Time;
import ocean.text.convert.Formatter;
import ocean.time.chrono.Gregorian;

version (unittest) import ocean.core.Test;

/******************************************************************************

  Parse provided input and return a UTC epoch time. An exception
  is raised where the provided string is not fully parsed.

 ******************************************************************************/

ulong toTime(T) (T[] src)
{
    uint len;

    auto x = parse (src, &len);
    if (len < src.length)
        throw new IllegalArgumentException ("unknown time format: "~src);
    return x;
}

/******************************************************************************

  Template wrapper to make life simpler. Returns a text version
  of the provided value.

  See format() for details

 ******************************************************************************/

char[] toString (Time time)
{
    char[32] tmp = void;

    return format (tmp, time).dup;
}

/******************************************************************************

  RFC1123 formatted time

  Converts to the format "Sun, 06 Nov 1994 08:49:37 GMT", and
  returns a populated slice of the provided buffer. Note that
  RFC1123 format is always in absolute GMT time, and a thirty-
  element buffer is sufficient for the produced output

  Throws an exception where the supplied time is invalid

 ******************************************************************************/

const(T)[] format(T, U=Time) (T[] output, U t)
{return format!(T)(output, cast(Time) t);}

const(T)[] format(T) (T[] output, Time t)
{
    static immutable T[][] Months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    static immutable T[][] Days   = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

    verify(output.length >= 29);
    if (t is t.max)
        throw new IllegalArgumentException("TimeStamp.format :: invalid Time argument");

    // convert time to field values
    const time = t.time;
    const date = Gregorian.generic.toDate(t);

    return snformat(output, "{}, {u2} {} {u4} {u2}:{u2}:{u2} GMT",
                    Days[date.dow], date.day, Months[date.month-1], date.year,
                    time.hours, time.minutes, time.seconds);
}

unittest
{
    static immutable STR_1970 = "Thu, 01 Jan 1970 00:00:00 GMT";
    mstring buf;
    buf.length = 29;
    test(format(buf, Time.epoch1970) == STR_1970);
    char[29] static_buf;
    test(format(static_buf, Time.epoch1970) == STR_1970);
}

/******************************************************************************

  ISO-8601 format :: "2006-01-31T14:49:30Z"

  Throws an exception where the supplied time is invalid

 ******************************************************************************/

const(T)[] format8601(T, U=Time) (T[] output, U t)
{return format!(T)(output, cast(Time) t);}

const(T)[] format8601(T) (T[] output, Time t)
{
    verify(output.length >= 29);
    if (t is t.max)
        throw new IllegalArgumentException("TimeStamp.format :: invalid Time argument");

    // convert time to field values
    const time = t.time;
    const date = Gregorian.generic.toDate(t);

    return snformat(output, "{u4}-{u2}-{u2}T{u2}:{u2}:{u2}Z",
                    date.year, date.month, date.day,
                    time.hours, time.minutes, time.seconds);
}

unittest
{
    static immutable STR_1970 = "1970-01-01T00:00:00Z";
    mstring buf;
    buf.length = 29;
    test(format8601(buf, Time.epoch1970) == STR_1970);
    char[29] static_buf;
    test(format8601(static_buf, Time.epoch1970) == STR_1970);
}

/******************************************************************************

  Parse provided input and return a UTC epoch time. A return value
  of Time.max (or false, respectively) indicated a parse-failure.

  An option is provided to return the count of characters parsed -
  an unchanged value here also indicates invalid input.

 ******************************************************************************/

Time parse(T) (T[] src, uint* ate = null)
{
    size_t len;
    Time   value;

    if ((len = rfc1123 (src, value)) > 0 ||
            (len = rfc850  (src, value)) > 0 ||
            (len = iso8601  (src, value)) > 0 ||
            (len = dostime  (src, value)) > 0 ||
            (len = asctime (src, value)) > 0)
    {
        if (ate)
            *ate = cast(int) len;
        return value;
    }
    return Time.max;
}


/******************************************************************************

  Parse provided input and return a UTC epoch time. A return value
  of Time.max (or false, respectively) indicated a parse-failure.

  An option is provided to return the count of characters parsed -
  an unchanged value here also indicates invalid input.

 ******************************************************************************/

bool parse(T) (T[] src, ref TimeOfDay tod, ref Date date, uint* ate = null)
{
    size_t len;

    if ((len = rfc1123 (src, tod, date)) > 0 ||
            (len = rfc850   (src, tod, date)) > 0 ||
            (len = iso8601  (src, tod, date)) > 0 ||
            (len = dostime  (src, tod, date)) > 0 ||
            (len = asctime (src, tod, date)) > 0)
    {
        if (ate)
            *ate = len;
        return true;
    }
    return false;
}

/******************************************************************************

  RFC 822, updated by RFC 1123 :: "Sun, 06 Nov 1994 08:49:37 GMT"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

 ******************************************************************************/

size_t rfc1123(T) (T[] src, ref Time value)
{
    TimeOfDay tod;
    Date      date;

    auto r = rfc1123!(T)(src, tod, date);
    if (r)
        value = Gregorian.generic.toTime(date, tod);
    return r;
}


/******************************************************************************

  RFC 822, updated by RFC 1123 :: "Sun, 06 Nov 1994 08:49:37 GMT"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

 ******************************************************************************/

size_t rfc1123(T) (T[] src, ref TimeOfDay tod, ref Date date)
{
    T* p = src.ptr;
    T* e = p + src.length;

    bool dt (ref T* p)
    {
        return ((date.day = parseInt(p, e)) > 0  &&
                *p++ == ' '                     &&
                (date.month = parseMonth(p)) > 0 &&
                *p++ == ' '                     &&
                (date.year = parseInt(p, e)) > 0);
    }

    if (parseShortDay(p) >= 0 &&
            *p++ == ','           &&
            *p++ == ' '           &&
            dt (p)                &&
            *p++ == ' '           &&
            time (tod, p, e)      &&
            *p++ == ' '           &&
            p[0..3] == "GMT")
    {
        return cast(size_t) ((p+3) - src.ptr);
    }
    return 0;
}


/******************************************************************************

  RFC 850, obsoleted by RFC 1036 :: "Sunday, 06-Nov-94 08:49:37 GMT"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

 ******************************************************************************/

size_t rfc850(T) (T[] src, ref Time value)
{
    TimeOfDay tod;
    Date      date;

    auto r = rfc850!(T)(src, tod, date);
    if (r)
        value = Gregorian.generic.toTime (date, tod);
    return r;
}

/******************************************************************************

  RFC 850, obsoleted by RFC 1036 :: "Sunday, 06-Nov-94 08:49:37 GMT"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

 ******************************************************************************/

size_t rfc850(T) (T[] src, ref TimeOfDay tod, ref Date date)
{
    T* p = src.ptr;
    T* e = p + src.length;

    bool dt (ref T* p)
    {
        return ((date.day = parseInt(p, e)) > 0  &&
                *p++ == '-'                     &&
                (date.month = parseMonth(p)) > 0 &&
                *p++ == '-'                     &&
                (date.year = parseInt(p, e)) > 0);
    }

    if (parseFullDay(p) >= 0 &&
            *p++ == ','          &&
            *p++ == ' '          &&
            dt (p)               &&
            *p++ == ' '          &&
            time (tod, p, e)     &&
            *p++ == ' '          &&
            p[0..3] == "GMT")
    {
        if (date.year < 70)
            date.year += 2000;
        else
            if (date.year < 100)
                date.year += 1900;

        return cast(size_t) ((p+3) - src.ptr);
    }
    return 0;
}


/******************************************************************************

  ANSI C's asctime() format :: "Sun Nov 6 08:49:37 1994"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

 ******************************************************************************/

size_t asctime(T) (T[] src, ref Time value)
{
    TimeOfDay tod;
    Date      date;

    auto r = asctime!(T)(src, tod, date);
    if (r)
        value = Gregorian.generic.toTime (date, tod);
    return r;
}

/******************************************************************************

  ANSI C's asctime() format :: "Sun Nov 6 08:49:37 1994"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

 ******************************************************************************/

size_t asctime(T) (T[] src, ref TimeOfDay tod, ref Date date)
{
    T* p = src.ptr;
    T* e = p + src.length;

    bool dt (ref T* p)
    {
        return ((date.month = parseMonth(p)) > 0 &&
                *p++ == ' '                      &&
                ((date.day = parseInt(p, e)) > 0
                 || (*p++ == ' ' && (date.day = parseInt(p, e)) > 0)));
    }

    if (parseShortDay(p) >= 0 &&
        *p++ == ' '           &&
        dt (p)                &&
        *p++ == ' '           &&
        time (tod, p, e)      &&
        *p++ == ' '           &&
        (date.year = parseInt (p, e)) > 0)
    {
        return cast(size_t) (p - src.ptr);
    }
    return 0;
}

/******************************************************************************

  DOS time format :: "12-31-06 08:49AM"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

 ******************************************************************************/

size_t dostime(T) (T[] src, ref Time value)
{
    TimeOfDay tod;
    Date      date;

    auto r = dostime!(T)(src, tod, date);
    if (r)
        value = Gregorian.generic.toTime(date, tod);
    return r;
}


/******************************************************************************

  DOS time format :: "12-31-06 08:49AM"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

 ******************************************************************************/

size_t dostime(T) (T[] src, ref TimeOfDay tod, ref Date date)
{
    T* p = src.ptr;
    T* e = p + src.length;

    bool dt (ref T* p)
    {
        return ((date.month = parseInt(p, e)) > 0 &&
                *p++ == '-'                       &&
                ((date.day = parseInt(p, e)) > 0  &&
                 (*p++ == '-' && (date.year = parseInt(p, e)) > 0)));
    }

    if (dt(p) >= 0                         &&
        *p++ == ' '                        &&
        (tod.hours = parseInt(p, e)) > 0   &&
        *p++ == ':'                        &&
        (tod.minutes = parseInt(p, e)) > 0 &&
        (*p == 'A' || *p == 'P'))
    {
        if (*p is 'P')
            tod.hours += 12;

        if (date.year < 70)
            date.year += 2000;
        else
            if (date.year < 100)
                date.year += 1900;

        return cast(size_t) ((p+2) - src.ptr);
    }
    return 0;
}

/******************************************************************************

  ISO-8601 format :: "2006-01-31 14:49:30,001"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

  Quote from http://en.wikipedia.org/wiki/ISO_8601 (2009-09-01):
  "Decimal fractions may also be added to any of the three time elements.
  A decimal point, either a comma or a dot (without any preference as
  stated most recently in resolution 10 of the 22nd General Conference
  CGPM in 2003), is used as a separator between the time element and
  its fraction."

 ******************************************************************************/

size_t iso8601(T) (T[] src, ref Time value)
{
    TimeOfDay tod;
    Date      date;

    size_t r = iso8601!(T)(src, tod, date);
    if (r)
        value = Gregorian.generic.toTime(date, tod);
    return r;
}

/******************************************************************************

  ISO-8601 format :: "2006-01-31 14:49:30,001"

  Returns the number of elements consumed by the parse; zero if
  the parse failed

  Quote from http://en.wikipedia.org/wiki/ISO_8601 (2009-09-01):
  "Decimal fractions may also be added to any of the three time elements.
  A decimal point, either a comma or a dot (without any preference as
  stated most recently in resolution 10 of the 22nd General Conference
  CGPM in 2003), is used as a separator between the time element and
  its fraction."

 ******************************************************************************/

size_t iso8601(T) (T[] src, ref TimeOfDay tod, ref Date date)
{
    T* p = src.ptr;
    T* e = p + src.length;

    bool dt (ref T* p)
    {
        return ((date.year = parseInt(p, e)) > 0   &&
                *p++ == '-'                       &&
                ((date.month = parseInt(p, e)) > 0 &&
                 (*p++ == '-'                       &&
                  (date.day = parseInt(p, e)) > 0)));
    }

    if (dt(p) >= 0       &&
            *p++ == ' '      &&
            time (tod, p, e))
    {
        // Are there chars left? If yes, parse millis. If no, millis = 0.
        if (p - src.ptr) {
            // check fraction separator
            T frac_sep = *p++;
            if (frac_sep is ',' || frac_sep is '.')
                // separator is ok: parse millis
                tod.millis = parseInt (p, e);
            else
                // wrong separator: error
                return 0;
        } else
            tod.millis = 0;

        return cast(size_t) (p - src.ptr);
    }
    return 0;
}


/******************************************************************************

  Parse a time field

 ******************************************************************************/

private bool time(T) (ref TimeOfDay time, ref T* p, T* e)
{
    return ((time.hours = parseInt(p, e)) >= 0   &&
            *p++ == ':'                          &&
            (time.minutes = parseInt(p, e)) >= 0 &&
            *p++ == ':'                          &&
            (time.seconds = parseInt(p, e)) >= 0);
}


/******************************************************************************

  Match a month from the input

 ******************************************************************************/

private int parseMonth(T) (ref T* p)
{
    int month;

    switch (p[0..3])
    {
        case "Jan":
            month = 1;
            break;
        case "Feb":
            month = 2;
            break;
        case "Mar":
            month = 3;
            break;
        case "Apr":
            month = 4;
            break;
        case "May":
            month = 5;
            break;
        case "Jun":
            month = 6;
            break;
        case "Jul":
            month = 7;
            break;
        case "Aug":
            month = 8;
            break;
        case "Sep":
            month = 9;
            break;
        case "Oct":
            month = 10;
            break;
        case "Nov":
            month = 11;
            break;
        case "Dec":
            month = 12;
            break;
        default:
            return month;
    }
    p += 3;
    return month;
}


/******************************************************************************

  Match a day from the input

 ******************************************************************************/

private int parseShortDay(T) (ref T* p)
{
    int day;

    switch (p[0..3])
    {
        case "Sun":
            day = 0;
            break;
        case "Mon":
            day = 1;
            break;
        case "Tue":
            day = 2;
            break;
        case "Wed":
            day = 3;
            break;
        case "Thu":
            day = 4;
            break;
        case "Fri":
            day = 5;
            break;
        case "Sat":
            day = 6;
            break;
        default:
            return -1;
    }
    p += 3;
    return day;
}


/******************************************************************************

  Match a day from the input. Sunday is 0

 ******************************************************************************/

private size_t parseFullDay(T) (ref T* p)
{
    static  T[][] days = [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
    ];

    foreach (size_t i, day; days)
        if (day == p[0..day.length])
        {
            p += day.length;
            return i;
        }
    return -1;
}


/******************************************************************************

  Extract an integer from the input

 ******************************************************************************/

private static int parseInt(T) (ref T* p, T* e)
{
    int value;

    while (p < e && (*p >= '0' && *p <= '9'))
        value = value * 10 + *p++ - '0';
    return value;
}


/******************************************************************************

 ******************************************************************************/

unittest
{
    char[30] tmp;
    const(char)[] s = "Sun, 06 Nov 1994 08:49:37 GMT";

    auto time = parse (s);
    auto text = format (tmp, time);
    test (text == s);

    cstring garbageTest = "Wed Jun 11 17:22:07 20088";
    garbageTest = garbageTest[0..$-1];
    char[128] tmp2;

    time = parse(garbageTest);
    auto text2 = format(tmp2, time);
    test (text2 == "Wed, 11 Jun 2008 17:22:07 GMT");
}
