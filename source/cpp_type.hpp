/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014-2015 Paul O'Neil <redballoon36@gmail.com>
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

namespace std
{
    template<> struct hash<const clang::QualType>
    {
        public:
        ::std::size_t operator()(const clang::QualType qType) const;
    };
}

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
class TemplateTypeArgumentDeclaration;
class TemplateArgumentInstanceIterator;

//namespace cpp
//{

    class TypeAttributes
    {
        Strategy strategy;
        string target_name;
        string target_module;

        public:
        TypeAttributes()
            : strategy(UNKNOWN), target_name(""), target_module("")
        { }

        static TypeAttributes * make();
        // To force this to an interface.
        // The fact that I'm doing this means that there are bugs
        // in my translator :(
        virtual Strategy getStrategy() const;
        virtual void setStrategy(Strategy s);
        virtual void setTargetName(string* new_target);
        virtual void setTargetModule(string* new_module);

        friend class Type;
    };

    class InvalidType;
    class BuiltinType;
    class PointerType;
    class ReferenceType;
    class NonTemplateRecordType;
    class TemplateRecordType;
    class UnionType;
    class ArrayType;
    class FunctionType;
    class TypedefType;
    class VectorType;
    class EnumType;
    class QualifiedType;
    class TemplateArgumentType;
    class TemplateSpecializationType;
    class DelayedType;
    class TypeVisitor;
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
            Qualified,
            TemplateArgument,
            TemplateSpecialization,
            Delayed
        };

        protected:
        Kind kind;
        // Attributes! from config files or inferred
        // Pointer to D type!
        Strategy strategy;
        string target_name;
        string target_module; // only meaningful for types using the replacement strategy
                              // This is kind of a kludge to deal with builtins.  FIXME?


        static std::unordered_map<const clang::QualType, Type*> type_map;
        static std::unordered_multimap<string, Type*> type_by_name;

        public:
        static void printTypeNames();
        explicit Type(Kind k)
            : kind(k), strategy(UNKNOWN), target_name(""),
              target_module("")
        { }

        Type(const Type&) = delete;
        Type(Type&&) = delete;
        Type& operator=(const Type&) = delete;
        Type& operator=(Type&&) = delete;

        static Type* get(const clang::Type* type, const clang::PrintingPolicy* pp = nullptr);
        static Type* get(const clang::QualType& qType, const clang::PrintingPolicy* pp = nullptr);

        typedef std::unordered_multimap<string, Type*>::iterator iter_t;
        typedef std::pair<iter_t, iter_t> range_t;
        static range_t getByName(const string* name);

        Kind getKind() const;

        friend class ClangTypeVisitor;

        void chooseReplaceStrategy(const string* replacement)
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
            if( kind != Qualified && s == REPLACE ) {
                throw UseReplaceMethod();
            }
            strategy = s;
        }

        Strategy getStrategy() const;
        virtual bool isReferenceType() const
        {
            return false;
        }

        struct WrongStrategy : public std::runtime_error
        {
            WrongStrategy()
                : std::runtime_error("That operation is only valid for types with a different translation strategy.")
            { }
        };
        string* getReplacement() const;
        string* getReplacementModule() const;
        void setReplacementModule(string mod);

        virtual Declaration * getDeclaration() const
        {
            dump();
            assert(0);
        }

        virtual void visit(TypeVisitor& visitor) = 0;
        virtual void dump() const = 0;

        void applyAttributes(const TypeAttributes* attribs);
    };

    class TypeVisitor
    {
        public:
        virtual void visit(InvalidType& type) = 0;
        virtual void visit(BuiltinType& type) = 0;
        virtual void visit(PointerType& type) = 0;
        virtual void visit(ReferenceType& type) = 0;
        virtual void visit(NonTemplateRecordType& type) = 0;
        virtual void visit(TemplateRecordType& type) = 0;
        virtual void visit(UnionType& type) = 0;
        virtual void visit(ArrayType& type) = 0;
        virtual void visit(FunctionType& type) = 0;
        virtual void visit(TypedefType& type) = 0;
        virtual void visit(VectorType& type) = 0;
        virtual void visit(EnumType& type) = 0;
        virtual void visit(QualifiedType& type) = 0;
        virtual void visit(TemplateArgumentType& type) = 0;
        virtual void visit(TemplateSpecializationType& type) = 0;
        virtual void visit(DelayedType& type) = 0;
    };

    class InvalidType : public Type
    {
        protected:
        const clang::QualType type;

        public:
        explicit InvalidType(const clang::QualType t)
            : Type(Type::Invalid), type(t)
        { }

        virtual bool isReferenceType() const override
        {
            throw std::logic_error("Asked if an invalid type has reference semantics.");
        }

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class BuiltinType : public Type
    {
        protected:
        const clang::BuiltinType* type;

        public:
        explicit BuiltinType(const clang::BuiltinType* t)
            : Type(Type::Builtin), type(t)
        { }

        virtual Declaration* getDeclaration() const override
        {
            return nullptr;
        }

        virtual bool isReferenceType() const override
        {
            return false;
        }

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class RecordType : public Type
    {
        public:
        explicit RecordType()
            : Type(Type::Record)
        { }

        virtual bool isReferenceType() const override;
        virtual Declaration* getDeclaration() const override;
        virtual RecordDeclaration * getRecordDeclaration() const = 0;
    };

    class NonTemplateRecordType : public RecordType
    {
        protected:
        const clang::RecordType * type;
        public:
        explicit NonTemplateRecordType(const clang::RecordType* t)
            : RecordType(), type(t)
        { }

        virtual RecordDeclaration * getRecordDeclaration() const override;

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class TemplateRecordType : public RecordType
    {
        protected:
        const clang::InjectedClassNameType * type;
        public:
        explicit TemplateRecordType(const clang::InjectedClassNameType* t)
            : RecordType(), type(t)
        { }

        virtual RecordDeclaration * getRecordDeclaration() const override;

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class PointerOrReferenceType : public Type
    {
        public:
        explicit PointerOrReferenceType(Kind k)
            : Type(k)
        { }

        virtual Declaration* getDeclaration() const override
        {
            return nullptr;
        }
        virtual Type * getPointeeType() const = 0;
    };

    class PointerType : public PointerOrReferenceType
    {
        protected:
        const clang::PointerType* type;
        public:
        explicit PointerType(const clang::PointerType* t)
            : PointerOrReferenceType(Type::Pointer), type(t)
        { }
        virtual Type * getPointeeType() const override;
        virtual bool isReferenceType() const override
        {
            return false;
        }

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };
    class ReferenceType : public PointerOrReferenceType
    {
        protected:
        const clang::LValueReferenceType* type;
        public:
        explicit ReferenceType(const clang::LValueReferenceType* t)
            : PointerOrReferenceType(Type::Reference), type(t)
        { }
        virtual bool isReferenceType() const override;
        virtual Type * getPointeeType() const override;

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class TypedefType : public Type
    {
        protected:
        const clang::TypedefType* type;
        public:
        explicit TypedefType(const clang::TypedefType* t)
            : Type(Type::Typedef), type(t)
        { }

        virtual bool isReferenceType() const override;
        virtual Declaration * getDeclaration() const override;
        TypedefDeclaration * getTypedefDeclaration() const;

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class EnumType : public Type
    {
        protected:
        const clang::EnumType* type;
        public:
        // enums can't be templates, can they?
        explicit EnumType(const clang::EnumType* t)
            : Type(Type::Enum), type(t)
        { }

        virtual bool isReferenceType() const override
        {
            return false;
        }

        virtual Declaration* getDeclaration() const override;
        EnumDeclaration * getEnumDeclaration() const;

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class UnionType : public Type
    {
        protected:
        const clang::RecordType* type;
        public:
        explicit UnionType(const clang::RecordType* t)
            : Type(Type::Union), type(t)
        { }

        virtual bool isReferenceType() const override
        {
            return false;
        }

        virtual Declaration* getDeclaration() const override;
        UnionDeclaration * getUnionDeclaration() const;

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    // Arrays always have fixed size; if they don't, then they're pointers
    class ArrayType : public Type
    {
        public:
        explicit ArrayType()
            : Type(Type::Array)
        { }

        virtual bool isReferenceType() const override
        {
            return false;
        }

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }

        virtual bool isFixedLength() = 0;
        // FIXME should probably not be in the superclass,
        // but it avoids downcasting later
        virtual long long getLength() = 0;
        virtual Type* getElementType() = 0;
    };

    class ConstantArrayType : public ArrayType
    {
        protected:
        const clang::ConstantArrayType* type;

        public:
        explicit ConstantArrayType(const clang::ConstantArrayType* t)
            : ArrayType(), type(t)
        { }

        virtual void dump() const override;

        virtual Type* getElementType() override;

        virtual bool isFixedLength() override;
        virtual long long getLength() override;
    };

    class VariableArrayType : public ArrayType
    {
        protected:
        const clang::IncompleteArrayType* type;

        public:
        explicit VariableArrayType(const clang::IncompleteArrayType* t)
            : ArrayType(), type(t)
        { }

        virtual void dump() const override;

        virtual Type* getElementType() override;

        virtual bool isFixedLength() override;
        virtual long long getLength() override;
    };

    class FunctionType : public Type
    {
        protected:
        const clang::FunctionType* type;

        public:
        explicit FunctionType(const clang::FunctionType* t)
            : Type(Type::Function), type(t)
        { }

        virtual bool isReferenceType() const override
        {
            return false;
        }

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class QualifiedType : public Type
    {
        protected:
        const clang::QualType type;
        public:
        QualifiedType(const clang::QualType t)
            : Type(Type::Qualified), type(t)
        { }

        Type * unqualifiedType();
        const Type * unqualifiedType() const;
        bool isConst() const;

        virtual bool isReferenceType() const override;

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class VectorType : public Type
    {
        protected:
        const clang::VectorType* type;

        public:
        explicit VectorType(const clang::VectorType* t)
            : Type(Type::Vector), type(t)
        { }

        virtual bool isReferenceType() const override
        {
            return false;
        }

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class TemplateArgumentType : public Type
    {
        protected:
        const clang::TemplateTypeParmType* type;
        // The only way I can figure out to do the lookup from
        // TemplateTypeParmType to its decl is using the index into the
        // original list.  Otherwise, if the type is "CanonicalUnqualified",
        // calling getDecl() etc. returns null
        const clang::TemplateParameterList* template_list;

        public:
        explicit TemplateArgumentType(const clang::TemplateTypeParmType* t)
            : Type(Type::TemplateArgument), type(t), template_list(nullptr)
        { }

        virtual Declaration * getDeclaration() const override;
        TemplateTypeArgumentDeclaration * getTemplateTypeArgumentDeclaration() const;
        void setTemplateList(clang::TemplateParameterList* tl)
        {
            template_list = tl;
        }

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class TemplateSpecializationType : public Type
    {
        protected:
        const clang::TemplateSpecializationType* type;

        public:
        explicit TemplateSpecializationType(const clang::TemplateSpecializationType* t)
            : Type(Type::TemplateSpecialization), type(t)
        { }

        Declaration* getTemplateDeclaration() const;

        unsigned getTemplateArgumentCount() const;
        TemplateArgumentInstanceIterator* getTemplateArgumentBegin();
        TemplateArgumentInstanceIterator* getTemplateArgumentEnd();

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;
    };

    class DelayedType : public Type
    {
        protected:
        const clang::DependentNameType * type;

        public:
        explicit DelayedType(const clang::DependentNameType* t)
            : Type(Type::Delayed), type(t)
        { }

        virtual void visit(TypeVisitor& visitor) override
        {
            visitor.visit(*this);
        }
        virtual void dump() const override;

        Type* resolveType() const;
    };

    class TemplateArgumentInstanceIterator
    {
        private:
        const clang::TemplateArgument* cpp_iter;

        public:
        explicit TemplateArgumentInstanceIterator(const clang::TemplateArgument* i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const TemplateArgumentInstanceIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const TemplateArgumentInstanceIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(TemplateArgumentInstanceIterator* other)
        {
            return (*this) == (*other);
        }

        enum Kind
        {
            Type,
            Integer, // TODO Merge with generic expressions?
        };

        virtual Kind getKind();
        virtual class Type* getType();
        virtual long long getInteger();
    };


    class ClangTypeVisitor : public clang::RecursiveASTVisitor<ClangTypeVisitor>
    {
        private:
        // The TypeVisitor does not own this pointer
        const clang::Type * type_to_traverse;
        Type* type_in_progress;
        const clang::PrintingPolicy* printPolicy; // Used for generating names of the type

        template<typename T = Type, typename ClangType>
        void allocateType(const ClangType* t);
        void allocateInvalidType(const clang::QualType& t);
        void allocateQualType(const clang::QualType t);
        public:
        typedef clang::RecursiveASTVisitor<ClangTypeVisitor> Super;

        explicit ClangTypeVisitor(const clang::PrintingPolicy* s);

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
        bool WalkUpFromConstantArrayType(clang::ConstantArrayType * type);
        bool WalkUpFromIncompleteArrayType(clang::IncompleteArrayType * type);
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
        bool WalkUpFromAutoType(clang::AutoType* type);
        bool WalkUpFromTypeOfExprType(clang::TypeOfExprType* type);
        bool WalkUpFromSubstTemplateTypeParmType(clang::SubstTemplateTypeParmType* type);
        bool WalkUpFromDependentNameType(clang::DependentNameType* type);

        // Types we can't handle yet
        bool WalkUpFromTemplateTypeParmType(clang::TemplateTypeParmType* type);
        bool WalkUpFromUnaryTransformType(clang::UnaryTransformType* type);
        bool WalkUpFromDependentTemplateSpecializationType(clang::DependentTemplateSpecializationType* type);
        bool WalkUpFromMemberPointerType(clang::MemberPointerType* type);
        bool WalkUpFromPackExpansionType(clang::PackExpansionType* type);
        bool WalkUpFromRValueReferenceType(clang::RValueReferenceType* type);

        // Template types we can handle
        bool WalkUpFromInjectedClassNameType(clang::InjectedClassNameType* type);
        bool WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type);

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
