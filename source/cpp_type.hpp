/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014 Paul O'Neil <redballoon36@gmail.com>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef __CPP_TYPE_HPP__
#define __CPP_TYPE_HPP__

#include <memory>
#include <unordered_map>

#include "clang/AST/Type.h"
#include "clang/AST/Decl.h"
#include "clang/AST/RecursiveASTVisitor.h"

#include "cpp_exception.hpp"
#include "string.hpp"
using namespace binder;

enum Strategy
{
    UNKNOWN = 0,
    REPLACE,
    STRUCT,
    INTERFACE,
    CLASS,
    OPAQUE_CLASS,
};

class Declaration;
class RecordDeclaration;
class TypedefDeclaration;
class EnumDeclaration;
class UnionDeclaration;

//namespace cpp
//{
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
        Strategy strategy;
        string target_name;

        static std::unordered_map<const clang::Type*, Type*> type_map;
        static std::unordered_map<string, Type*> type_by_name;

        public:
        static void printTypeNames();
        explicit Type(const clang::Type* t, Kind k)
            : cpp_type(t), kind(k), strategy(UNKNOWN), target_name("")
        { }

        Type(const Type&) = delete;
        Type(Type&&) = delete;
        Type& operator=(const Type&) = delete;
        Type& operator=(Type&&) = delete;

        static Type* get(const clang::QualType& qType, const clang::PrintingPolicy* pp = nullptr);
        static Type* getByName(const string* name);

        const clang::Type * cppType() const {
            return cpp_type;
        }

        void setKind(Kind k) {
            kind = k;
        }

        Kind getKind();

        friend class TypeVisitor;

        void chooseReplaceStrategy(string* replacement)
        {
            strategy = REPLACE;
            target_name = *replacement;
        }

        struct DontSetUnknown : public std::runtime_error
        {
            DontSetUnknown()
                : std::runtime_error("Cannot set the strategy to unknown.")
            { }
        };

        struct UseReplaceMethod : public std::runtime_error
        {
            UseReplaceMethod()
                : std::runtime_error("Don't use setStrategy(REPLACE), use setReplaceStrategy(name)")
            { }
        };

        void setStrategy(Strategy s)
        {
            if( s == UNKNOWN )
            {
                throw DontSetUnknown();
            }
            if( s == REPLACE ) {
                throw UseReplaceMethod();
            }
            strategy = s;
        }

        Strategy getStrategy();

        struct WrongStrategy : public std::runtime_error
        {
            WrongStrategy()
                : std::runtime_error("That operation is only valid for types with a different translation strategy.")
            { }
        };
        string* getReplacement();

        RecordDeclaration * getRecordDeclaration();
        Type * getPointeeType();
        TypedefDeclaration * getTypedefDeclaration();
        EnumDeclaration * getEnumDeclaration();
        UnionDeclaration * getUnionDeclaration();
        void dump();
    };

    class TypeVisitor : public clang::RecursiveASTVisitor<TypeVisitor>
    {
        private:
        // The TypeVisitor does not own this pointer
        const clang::Type * type_to_traverse;
        Type* type_in_progress;
        const clang::PrintingPolicy* printPolicy; // Used for generating names of the type

        void allocateType(const clang::Type * t, Type::Kind k);
        public:
        typedef clang::RecursiveASTVisitor<TypeVisitor> Super;

        // Pass in the Type object that this visitor should fill in.
        explicit TypeVisitor(const clang::PrintingPolicy* s);

        Type* getType() {
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

        bool VisitBuiltinType(clang::BuiltinType* cppType);
        bool VisitPointerType(clang::PointerType* cppType);
        bool VisitRecordType(clang::RecordType* cppType);
        bool VisitArrayType(clang::ArrayType * cppType);
        bool VisitFunctionType(clang::FunctionType * cppType);
        bool VisitLValueReferenceType(clang::LValueReferenceType* cppType);
        bool VisitTypedefType(clang::TypedefType* cppType);
    };

    // Catching this type directly is probably programmer error -
    // we didn't match all the types.
    class FatalTypeNotWrappable : public NotWrappableException
    {
        private:
        const clang::Type * type;

        public:
        FatalTypeNotWrappable(const clang::Type* t)
            : NotWrappableException(), type(t)
        { }

        virtual const clang::Type * getType() const {
            return type;
        }
    };

    // Catching a "Skip" subclass means that we (temporarily)
    // aren't translating that type, but should continue with the
    // other parts of the translation.
    class SkipUnwrappableType : public NotWrappableException
    {
        private:
        const clang::Type * type;

        // TODO figure out how to print types as strings,
        // so I can make sensible messages
        public:
        SkipUnwrappableType(const clang::Type* t)
            : NotWrappableException(), type(t)
        { }

        virtual const clang::Type * getType() const {
            return type;
        }
    };

    class SkipRValueRef : public SkipUnwrappableType
    {
        public:
        SkipRValueRef(const clang::RValueReferenceType* t)
            : SkipUnwrappableType(t)
        { }

        virtual const char * what() const noexcept override
        {
            return "Skipping type due to rvalue reference.";
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
            return "Skipping type since it is dependent on a template.";
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
            return "Skipping type due to a C++ member pointer.";
        }
    };
//} namespace cpp

#endif // __CPP_TYPE_HPP__
