#include <stdexcept>

#include "dlang_output.hpp"

DOutput::DOutput(std::ostream& strm)
    : needSpaceBeforeNextItem(false), listStatus(NO_LIST),
      output(strm)
{ }

void DOutput::putItem(const std::string& text)
{
    if( needSpaceBeforeNextItem )
        output << " ";
    output << text;
    needSpaceBeforeNextItem = true;
}

void DOutput::beginList()
{
    if( listStatus != NO_LIST )
        throw std::runtime_error("Nested lists are not supported.");

    output << "(";
    needSpaceBeforeNextItem = true;
    listStatus = LIST_STARTED;
}

void DOutput::endList()
{
    output << ")";
    needSpaceBeforeNextItem = true;
    listStatus = NO_LIST;
}

void DOutput::listItem()
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

void DOutput::newline()
{
    output << "\n";
}

void DOutput::semicolon()
{
    output << ";";
}
