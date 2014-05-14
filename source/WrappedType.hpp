#ifndef __WRAPPED_TYPE_H__
#define __WRAPPED_TYPE_H__

#include <unordered_map>

#include "clang/AST/Type.h"

class WrappedType
{
    private:
    const clang::Type * cpp_type;

    protected:
    explicit WrappedType(const clang::Type* t)
        : cpp_type(t)
    { }

    static std::unordered_map<const clang::Type*, WrappedType*> type_map;

    public:
    WrappedType(const WrappedType&) = delete;
    WrappedType(WrappedType&&) = delete;
    WrappedType& operator=(const WrappedType&) = delete;
    WrappedType& operator=(WrappedType&&) = delete;

    static WrappedType * get(const clang::Type* cppType);

    const clang::Type * cppType() const {
        return cpp_type;
    }

    // Returns true when we have done all analyses
    // and collected all information needed to determine
    // how to write the D version of this type.
    virtual bool isTranslationFinal() = 0;

    virtual bool shouldBeEmitted() = 0;
};

#endif // __WRAPPED_TYPE_H__
