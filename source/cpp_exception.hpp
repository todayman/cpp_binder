#ifndef __CPP_EXCEPTION_HPP__
#define __CPP_EXCEPTION_HPP__

#include <stdexcept>

namespace cpp
{
    class NotWrappableException : public std::runtime_error
    {
        public:
        NotWrappableException()
            : std::runtime_error("No way to wrap this thing!")
        { }
    };
} // namespace cpp

#endif // __CPP_EXCEPTION_HPP__
