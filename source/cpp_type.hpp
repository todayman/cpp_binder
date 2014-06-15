#ifndef __CPP_TYPE_HPP__
#define __CPP_TYPE_HPP__

#include <unordered_map>

#include "clang/AST/Type.h"

class DOutput;

namespace cpp
{
    class Type
    {
        private:
        const clang::Type * cpp_type;
    
        protected:
        explicit Type(const clang::Type* t)
            : cpp_type(t)
        { }
    
        static std::unordered_map<const clang::Type*, Type*> type_map;
    
        public:
        Type(const Type&) = delete;
        Type(Type&&) = delete;
        Type& operator=(const Type&) = delete;
        Type& operator=(Type&&) = delete;
    
        static Type * get(const clang::Type* cppType);
    
        const clang::Type * cppType() const {
            return cpp_type;
        }
    
        // Returns true when we have done all analyses
        // and collected all information needed to determine
        // how to write the D version of this type.
        virtual bool isTranslationFinal() = 0;
    
        // Places the D version of this type into the output.
        // The output is suitable for declaring a variable of this type,
        // not defining this type.
        virtual void translate(DOutput& output) const = 0;
    };
}

#endif // __CPP_TYPE_HPP__
