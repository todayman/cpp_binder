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

#ifndef __STRING_HPP__
#define __STRING_HPP__

#include <iostream>
/* A simple non-templated string that I can bind easily */

class string
{
    char * buffer;
    size_t length;

    public:
    string();
    string(const char * str);
    string(const char * start, const char * end);
    string(size_t len);
    string(const string& other);
    string(string&&);
    ~string()
    {
        if( buffer )
        {
            delete []buffer;
        }
    }

    size_t size() const
    {
        return length;
    }

    const char * begin() const
    {
        return buffer;
    }

    const char * end() const
    {
        return buffer + length;
    }
    char * begin()
    {
        return buffer;
    }

    char * end()
    {
        return buffer + length;
    }

    bool operator==(const string& other) const;

    const char * c_str() const
    {
        return buffer;
    }

    string operator+(const string& other) const;
    string& operator=(const string& other);
    string& operator=(string&& other);
};

namespace std {
template<>
struct hash<::string>
{
    size_t operator()(const ::string& str) const
    {
        std::hash<std::string> hasher;
        return hasher(str.c_str());
    }
};
}

std::ostream& operator<<(std::ostream& output, const string& str);

#endif // __STRING_HPP__
