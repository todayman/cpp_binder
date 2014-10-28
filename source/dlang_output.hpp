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

#ifndef __DOUTPUT_HPP__
#define __DOUTPUT_HPP__

#include <iostream>

#include "string.hpp"
#include "dlang_decls.hpp"

namespace dlang
{
    class DOutputContext
    {
        private:
        bool needSpaceBeforeNextItem;

        enum {
            NO_LIST,
            LIST_STARTED,
            LONG_LIST,
        } listStatus;
        bool startingLine;
        int indentationLevel;

        std::ostream& output;

        void indent();

        public:
        DOutputContext(std::ostream& output = std::cout, int indentLevel = 0);
        DOutputContext(DOutputContext& ctx, int extraIndent = 0);

        void putItem(const string& text);

        void beginList(const string& symbol);
        void endList(const string& symbol);
        void listItem(); // FIXME this method is really clunky
        void newline();
        void semicolon();
    };
}

void produceOutputForPackage(dlang::Package& pack);

#endif // __DOUTPUT_HPP__
