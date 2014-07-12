#ifndef __CPP_TYPE_HPP__
#define __CPP_TYPE_HPP__

#include <unordered_map>

#include "clang/AST/Type.h"

class DOutput;

namespace cpp
{
    // This is a place for all of the different pieces of
    // knowledge we need about each C++ type.  They all
    // get landed here, and we basically use this as the value
    // in a dictionary, where the C++ type is the key.
    class Type
    {
        public:
        enum Kind {
            Builtin,
            Pointer,
            Reference,
            Record,
            Union,
            Array,
            Function,
            Typedef,
            Vector, // MMX, SSE, etc
            Enum,
        };

        private:
        const clang::Type * cpp_type;
        Kind kind;
        // Attributes! from config files or inferred
        // Pointer to D type!

        public:
        explicit Type(const clang::Type* t, Kind k)
            : cpp_type(t), kind(k)
        { }

        protected:
        static std::unordered_map<const clang::Type*, Type*> type_map;
        static Type * makeRecord(const clang::Type * type, const clang::RecordType* cppType);
        static Type * makeUnion(const clang::Type * type, const clang::RecordType* cppType);

        public:
        Type(const Type&) = delete;
        Type(Type&&) = delete;
        Type& operator=(const Type&) = delete;
        Type& operator=(Type&&) = delete;

        static Type * get(const clang::Type* cppType);

        const clang::Type * cppType() const {
            return cpp_type;
        }

    };

    // Same thing as Type, but for declarations of functions,
    // classes, etc.
    class Declaration
    {
        // Attributes!
        // Pointer to D declaration!
    };

    // Catching this type directly is probably programmer error -
    // we didn't match all the types.
    // Catching a "Skip" subclass means that we (temporarily)
    // aren't translating that type, but should continue with the
    // other parts of the translation.
    class NotWrappableException : public std::runtime_error
    {
        private:
        const clang::Type * type;

        // TODO figure out how to print types as strings,
        // so I can make sensible messages
        public:
        NotWrappableException(const clang::Type * t)
            : std::runtime_error("No way to wrap type."), type(t)
        { }

        const clang::Type * getType() const {
            return type;
        }
    };

    class SkipUnwrappableDeclaration : public NotWrappableException
    {
        public:
        SkipUnwrappableDeclaration(const clang::Type* t)
            : NotWrappableException(t)
        { }
    };

    class SkipRValueRef : public SkipUnwrappableDeclaration
    {
        public:
        SkipRValueRef(const clang::RValueReferenceType* t)
            : SkipUnwrappableDeclaration(t)
        { }

        virtual const char * what() const noexcept override
        {
            return "Skipping declaration due to rvalue reference.";
        }
    };

    class SkipTemplate : public SkipUnwrappableDeclaration
    {
        public:
        SkipTemplate(const clang::Type* t)
            : SkipUnwrappableDeclaration(t)
        { }

        virtual const char * what() const noexcept override
        {
            return "Skipping declaration since it is dependent on a template.";
        }
    };

    class SkipMemberPointer : public SkipUnwrappableDeclaration
    {
        public:
        SkipMemberPointer(const clang::MemberPointerType* t)
            : SkipUnwrappableDeclaration(t)
        { }

        virtual const char * what() const noexcept override
        {
            return "Skipping declaration due to a C++ member pointer.";
        }
    };
}

bool hasTemplateParent(const clang::CXXRecordDecl * parent_record);

#endif // __CPP_TYPE_HPP__
