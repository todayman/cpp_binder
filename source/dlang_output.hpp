#ifndef __DOUTPUT_HPP__
#define __DOUTPUT_HPP__

#include <iostream>
#include <string>

class DOutput
{
    private:
    bool needSpaceBeforeNextItem;

    enum {
        NO_LIST,
        LIST_STARTED,
        LONG_LIST,
    } listStatus;

    std::ostream& output;

    public:
    DOutput(std::ostream& output = std::cout);

    void putItem(const std::string& text);

    void beginList();
    void endList();
    void listItem();
    void newline();
    void semicolon();
};

#endif // __DOUTPUT_HPP__
