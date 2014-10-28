/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014 Paul O'Neil <redballoon36@gmail.com>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <string.h>

#include "string.hpp"

string::string()
    : buffer(nullptr), length(0)
{
    buffer = new char[length + 1];
    buffer[length] = 0;
}

string::string(const char * str)
    : buffer(nullptr), length(strlen(str))
{
    buffer = new char[length + 1];
    strncpy(buffer, str, length);
    buffer[length] = 0;
}

string::string(const char * start, const char * end)
    : buffer(nullptr), length(end - start)
{
    buffer = new char[length + 1];
    strncpy(buffer, start, length);
    buffer[length] = 0;
}

string::string(const string& other)
    : buffer(nullptr), length(other.length)
{
    buffer = new char[length + 1];
    strncpy(buffer, other.buffer, length);
    buffer[length] = 0;
}
string::string(string&& other)
    : buffer(other.buffer), length(other.length)
{
    other.buffer = nullptr;
}

string::string(size_t len)
    : buffer(nullptr), length(len)
{
    buffer = new char[length + 1];
    memset(buffer, 0, length + 1);
}

bool string::operator==(const string& other) const
{
    if( length == other.length )
    {
        return strncmp(buffer, other.buffer, length) == 0;
    }
    return true;
}

string string::operator+(const string& other) const
{
    string result(length + other.length);
    strncpy(result.buffer, buffer, length);
    strncpy(result.buffer + length, other.buffer, other.length);
    return result;
}

string& string::operator=(const string& other)
{
    if( length != other.length )
    {
        if( buffer )
            delete []buffer;
        length = other.length;
        buffer = new char[length + 1];
    }
    strncpy(buffer, other.buffer, length);
    buffer[length] = 0;
    return *this;
}
string& string::operator=(string&& other)
{
    if( buffer )
        delete []buffer;
    buffer = other.buffer;
    other.buffer = nullptr;
    length = other.length;
    return *this;
}

std::ostream& operator<<(std::ostream& output, const string& str)
{
    return output << str.c_str();
}

