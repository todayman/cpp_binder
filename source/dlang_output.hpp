#ifndef __DOUTPUT_HPP__
#define __DOUTPUT_HPP__

#include <iostream>
#include <string>

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

        void putItem(const std::string& text);

        void beginList();
        void endList();
        void listItem();
        void newline();
        void semicolon();
    };
}

void produceOutputForPackage(dlang::Package& pack);

#endif // __DOUTPUT_HPP__
