#include <stdexcept>

#include "dlang_output.hpp"

DOutputContext::DOutputContext(std::ostream& strm)
    : needSpaceBeforeNextItem(false), listStatus(NO_LIST),
      output(strm)
{ }

void DOutputContext::putItem(const std::string& text)
{
    if( needSpaceBeforeNextItem )
        output << " ";
    output << text;
    needSpaceBeforeNextItem = true;
}

void DOutputContext::beginList()
{
    if( listStatus != NO_LIST )
        throw std::runtime_error("Nested lists are not supported.");

    output << "(";
    needSpaceBeforeNextItem = true;
    listStatus = LIST_STARTED;
}

void DOutputContext::endList()
{
    output << ")";
    needSpaceBeforeNextItem = true;
    listStatus = NO_LIST;
}

void DOutputContext::listItem()
{
    switch( listStatus )
    {
        case NO_LIST:
            throw std::runtime_error("Entered a list item while there was no list in progress.");
            break;
        case LIST_STARTED:
            break;
        case LONG_LIST:
            output << ",";
            needSpaceBeforeNextItem = true;
            break;
    }
}

void DOutputContext::newline()
{
    output << "\n";
}

void DOutputContext::semicolon()
{
    output << ";";
}
