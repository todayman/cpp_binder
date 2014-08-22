#include <stdexcept>

#include "dlang_output.hpp"

DOutputContext::DOutputContext(std::ostream& strm, int indentLevel)
    : needSpaceBeforeNextItem(false), listStatus(NO_LIST),
      startingLine(true), indentationLevel(indentLevel), output(strm)
{ }

void DOutputContext::indent()
{
    for( int i = 0; i < indentationLevel; ++i )
    {
        output << " ";
    }
}

void DOutputContext::putItem(const std::string& text)
{
    if( startingLine ) indent();
    else if( needSpaceBeforeNextItem ) output << " ";
    output << text;
    needSpaceBeforeNextItem = true;
    startingLine = false;
}

void DOutputContext::beginList()
{
    if( listStatus != NO_LIST )
        throw std::runtime_error("Nested lists are not supported.");

    if( startingLine ) indent();
    output << "(";
    needSpaceBeforeNextItem = true;
    listStatus = LIST_STARTED;
    startingLine = false;
}

void DOutputContext::endList()
{
    if( startingLine ) indent();
    output << ")";
    needSpaceBeforeNextItem = true;
    listStatus = NO_LIST;
    startingLine = false;
}

void DOutputContext::listItem()
{
    if( startingLine ) indent();
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
    startingLine = false;
}

void DOutputContext::newline()
{
    output << "\n";
    startingLine = true;
}

void DOutputContext::semicolon()
{
    if( startingLine ) indent();
    output << ";";
    startingLine = false;
}
