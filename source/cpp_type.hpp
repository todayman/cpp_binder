#ifndef __CPP_TYPE_HPP__
#define __CPP_TYPE_HPP__

#include <memory>
#include <unordered_map>

#include "clang/AST/Type.h"
#include "clang/AST/Decl.h"
#include "clang/AST/RecursiveASTVisitor.h"

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
            Invalid,
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

        static std::unordered_map<const clang::Type*, std::shared_ptr<Type>> type_map;

        public:
        explicit Type(const clang::Type* t, Kind k)
            : cpp_type(t), kind(k)
        { }

        Type(const Type&) = delete;
        Type(Type&&) = delete;
        Type& operator=(const Type&) = delete;
        Type& operator=(Type&&) = delete;

        static std::shared_ptr<Type> get(clang::QualType qType);

        const clang::Type * cppType() const {
            return cpp_type;
        }

        void setKind(Kind k) {
            kind = k;
        }

        friend class TypeVisitor;
    };

    class TypeVisitor : public clang::RecursiveASTVisitor<TypeVisitor>
    {
        private:
        // The TypeVisitor does not own this pointer
        const clang::Type * type_to_traverse;
        std::shared_ptr<Type> type_in_progress;

        void allocateType(const clang::Type * t, Type::Kind k);
        public:
        typedef clang::RecursiveASTVisitor<TypeVisitor> Super;

        // Pass in the Type object that this visitor should fill in.
        TypeVisitor();

        std::shared_ptr<Type> getType() {
            return type_in_progress;
        }

        void reset() {
            type_to_traverse = nullptr;
            type_in_progress = nullptr;
        }

        bool TraverseType(clang::QualType type);
        // Game plan here is to allocate the object during
        // the WalkUp phase, since that starts with the most
        // specific type.  Then fill in the object during the
        // Visit phase.
        bool WalkUpFromBuiltinType(clang::BuiltinType * type);
        bool WalkUpFromPointerType(clang::PointerType * type);
        bool WalkUpFromLValueReferenceType(clang::LValueReferenceType * type);
        bool WalkUpFromRecordType(clang::RecordType * type);
        bool WalkUpFromArrayType(clang::ArrayType * type);
        bool WalkUpFromFunctionType(clang::FunctionType * type);
        bool WalkUpFromTypedefType(clang::TypedefType * type);
        bool WalkUpFromVectorType(clang::VectorType * type);
        bool WalkUpFromEnumType(clang::EnumType * type);

        // These are sugar / slight modifications of other types
        // We just pass though them
        bool WalkUpFromElaboratedType(clang::ElaboratedType* cppType);
        bool WalkUpFromDecayedType(clang::DecayedType* cppType);
        bool WalkUpFromParenType(clang::ParenType* cppType);
        bool WalkUpFromDecltypeType(clang::DecltypeType* cppType);
        bool WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type);
        bool WalkUpFromTemplateTypeParmType(clang::TemplateTypeParmType* type);
        bool WalkUpFromSubstTemplateTypeParmType(clang::SubstTemplateTypeParmType* type);

        // These are here for throwing non-fatal errors
        bool WalkUpFromRValueReferenceType(clang::RValueReferenceType*);
        bool WalkUpFromMemberPointerType(clang::MemberPointerType* type);
        bool WalkUpFromDependentNameType(clang::DependentNameType* type);
        bool WalkUpFromPackExpansionType(clang::PackExpansionType* cppType);

        // By the time this method is called, we should know what kind
        // of type it is.  If we don't, then we don't wrap that type.
        // So throw an error.
        bool WalkUpFromType(clang::Type * type);

        bool VisitPointerType(clang::PointerType* cppType);
        bool VisitRecordType(clang::RecordType* cppType);
        bool VisitArrayType(clang::ArrayType * cppType);
        bool VisitFunctionType(clang::FunctionType * cppType);
        bool VisitLValueReferenceType(clang::LValueReferenceType* cppType);
        bool VisitTypedefType(clang::TypedefType* cppType);
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

    class SkipUnwrappableType : public NotWrappableException
    {
        public:
        SkipUnwrappableType(const clang::Type* t)
            : NotWrappableException(t)
        { }
    };

    class SkipRValueRef : public SkipUnwrappableType
    {
        public:
        SkipRValueRef(const clang::RValueReferenceType* t)
            : SkipUnwrappableType(t)
        { }

        virtual const char * what() const noexcept override
        {
            return "Skipping declaration due to rvalue reference.";
        }
    };

    class SkipTemplate : public SkipUnwrappableType
    {
        public:
        SkipTemplate(const clang::Type* t)
            : SkipUnwrappableType(t)
        { }

        virtual const char * what() const noexcept override
        {
            return "Skipping declaration since it is dependent on a template.";
        }
    };

    class SkipMemberPointer : public SkipUnwrappableType
    {
        public:
        SkipMemberPointer(const clang::MemberPointerType* t)
            : SkipUnwrappableType(t)
        { }

        virtual const char * what() const noexcept override
        {
            return "Skipping declaration due to a C++ member pointer.";
        }
    };
}

#endif // __CPP_TYPE_HPP__
