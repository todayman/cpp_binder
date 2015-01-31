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

#ifndef __CPP_DECL_HPP__
#define __CPP_DECL_HPP__

#include <unordered_map>
#include <unordered_set>

#include "llvm/ADT/APSInt.h"

#include "clang/AST/Decl.h"
#include "clang/AST/RecursiveASTVisitor.h"

#include "cpp_type.hpp"
#include "cpp_exception.hpp"
#include "string.hpp"

// TODO These are basically the same as the ones
// in dlang_decls.hpp.  I should have a better model
// for separating out attributes set from configuration files
// and what gets parsed by clang.
enum Visibility
{
    UNSET = 0,
    PRIVATE,
    PACKAGE,
    PROTECTED,
    PUBLIC,
    EXPORT,
};

Visibility accessSpecToVisibility(clang::AccessSpecifier as);

//namespace cpp
//{
    class DeclarationVisitor;
    class ConstDeclarationVisitor;

    bool isCXXRecord(const clang::Decl* decl);
    bool isTemplateTypeParmDecl(const clang::Decl* decl);

    // Same thing as Type, but for declarations of functions,
    // classes, etc.
    class Declaration
    {
        protected:
        // We still want to know about things we can't wrap,
        // like templates, but they'll get skipped later on
        bool is_wrappable;
        // Attributes!
        // Pointer to D declaration!
        bool should_bind;
        string target_module;
        Visibility visibility;
        string remove_prefix;

        protected:
        string source_name;
        string _name;

        virtual void setSourceName(string* name) {
            source_name = *name;
        }

        friend class DeclVisitor;

        virtual void markUnwrappable() {
            is_wrappable = false;
        }

        public:
        Declaration()
            : is_wrappable(true), should_bind(false), target_module(),
              visibility(UNSET), remove_prefix(), source_name(), _name()
        { }

        virtual clang::SourceLocation getSourceLocation() const = 0;

        virtual string* getSourceName() const
        {
            return new string(source_name);
        }
        virtual string* getTargetName() const
        {
            if( _name.size() == 0 )
            {
                return new string(source_name);
            }
            else
            {
                return new string(_name);
            }
        }

        virtual bool isWrappable() const noexcept {
            return is_wrappable;
        }

        virtual void shouldBind(bool decision)
        {
            should_bind = decision;
        }

        virtual bool getShouldBind() const
        {
            return should_bind;
        }

        virtual void setTargetModule(string* target)
        {
            target_module = *target;
        }

        virtual bool isTargetModuleSet() const
        {
            return target_module.size() > 0;
        }
        virtual string* getTargetModule() const
        {
            return new string(target_module);
        }

        virtual ::Visibility getVisibility() const
        {
            return visibility;
        }
        virtual void setVisibility(Visibility vis)
        {
            visibility = vis;
        }

        virtual void removePrefix(string* prefix)
        {
            remove_prefix = *prefix;
        }

        virtual Type* getType() const = 0;

        virtual void visit(DeclarationVisitor& visitor) = 0;
        //virtual void visit(ConstDeclarationVisitor& visitor) const = 0;

        virtual void dump() = 0;
    };

    struct NotTypeDecl : public std::runtime_error
    {
        NotTypeDecl()
            : std::runtime_error("Operation is only valid on Type declarations.")
        { }
    };

    /*template<typename ClangType, typename TranslatorType>
    class Iterator
    {
        private:
        ClangType cpp_iter;

        public:
        explicit Iterator(ClangType i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const Iterator<ClangType, TranslatorType>& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const Iterator<ClangType, TranslatorType>& other) {
            return cpp_iter != other.cpp_iter;
        }

        TranslatorType* operator*();
        TranslatorType* operator->()
        {
            return operator*();
        }
    };*/

    class DeclarationIterator
    {
        private:
        clang::DeclContext::decl_iterator cpp_iter;

        public:
        explicit DeclarationIterator(clang::DeclContext::decl_iterator i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const DeclarationIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const DeclarationIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        Declaration* operator*();
        Declaration* operator->()
        {
            return operator*();
        }

        virtual Declaration* get()
        {
            return operator*();
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(DeclarationIterator* other)
        {
            return (*this) == (*other);
        }
    };

    //typedef Iterator<clang::DeclContext::decl_iterator, Declaration> DeclarationIterator;

#define FORALL_DECLARATIONS(func) \
func(Function)      \
func(Namespace)     \
func(Record)        \
func(Typedef)       \
func(Enum)          \
func(Field)         \
func(EnumConstant)  \
func(Union)         \
func(Method)        \
func(Constructor)   \
func(Destructor)    \
func(Argument)      \
func(Variable)      \
func(TemplateTypeArgument) \
func(Unwrappable)

#define FORWARD_DECL(x) class x##Declaration;
    FORALL_DECLARATIONS(FORWARD_DECL)
#undef FORWARD_DECL

    class DeclarationVisitor
    {
        public:
#define VISITOR_METHOD(X) virtual void visit##X(X##Declaration& node) = 0;
        FORALL_DECLARATIONS(VISITOR_METHOD)
#undef VISITOR_METHOD
    };

    class ConstDeclarationVisitor
    {
        public:
#define VISITOR_METHOD(X) virtual void visit##X(const X##Declaration& node) = 0;
        FORALL_DECLARATIONS(VISITOR_METHOD)
#undef VISITOR_METHOD
    };

#define DECLARATION_CLASS_2(C, D) \
    class D##Declaration : public Declaration \
    { \
        private: \
        const clang::C##Decl* _decl; \
\
        public: \
        D##Declaration(const clang::C##Decl* d) \
            : _decl(d) \
        { } \
\
        virtual clang::SourceLocation getSourceLocation() const override \
        { \
            return _decl->getLocation(); \
        } \
\
        virtual Type* getType() const override \
        { \
            throw NotTypeDecl(); \
        } \
\
        virtual void visit(DeclarationVisitor& visitor) override \
        { \
            visitor.visit##D(*this); \
        } \
\
        virtual void dump() override \
        { \
            _decl->dump(); \
        } \
    }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override \
        { \
            visitor.visit##D(*this); \
        } \*/
#define DECLARATION_CLASS(KIND) DECLARATION_CLASS_2(KIND, KIND)
DECLARATION_CLASS_2(CXXConstructor, Constructor);
DECLARATION_CLASS_2(CXXDestructor, Destructor);

    class VariableDeclaration : public Declaration
    {
        private:
        const clang::VarDecl* _decl;

        public:
        VariableDeclaration(const clang::VarDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            return Type::get(_decl->getType());
        }

        virtual clang::LanguageLinkage getLinkLanguage() const
        {
            return _decl->getLanguageLinkage();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitVariable(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitVariable(*this);
        }*/

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    class ArgumentDeclaration : public Declaration
    {
        private:
        const clang::ParmVarDecl* _decl;

        public:
        ArgumentDeclaration(const clang::ParmVarDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            return Type::get(_decl->getType());
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitArgument(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitArgument(*this);
        }*/

        virtual void dump() override
        {
            _decl->dump();
        }
    };


    class NamespaceDeclaration : public Declaration
    {
        private:
        const clang::NamespaceDecl* _decl;

        public:
        NamespaceDeclaration(const clang::NamespaceDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            throw NotTypeDecl();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitNamespace(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitNamespace(*this);
        }*/

        virtual DeclarationIterator * getChildBegin()
        {
            return new DeclarationIterator(_decl->decls_begin());
        }
        virtual DeclarationIterator * getChildEnd()
        {
            return new DeclarationIterator(_decl->decls_end());
        }

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    class TypedefDeclaration : public Declaration
    {
        private:
        const clang::TypedefDecl* _decl;

        public:
        explicit TypedefDeclaration(const clang::TypedefDecl* d)
            : Declaration()
        {
            _decl = d;
        }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0));
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitTypedef(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitTypedef(*this);
        }*/

        virtual Type* getTargetType() const
        {
            return Type::get(_decl->getUnderlyingType());
        }

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    class EnumDeclaration : public Declaration
    {
        private:
        const clang::EnumDecl* _decl;

        public:
        EnumDeclaration(const clang::EnumDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0));
        }

        virtual Type* getMemberType() const
        {
            return Type::get(_decl->getIntegerType());
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitEnum(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitEnum(*this);
        }*/

        virtual DeclarationIterator * getChildBegin()
        {
            return new DeclarationIterator(_decl->decls_begin());
        }
        virtual DeclarationIterator * getChildEnd()
        {
            return new DeclarationIterator(_decl->decls_end());
        }

        virtual void dump() override
        {
            _decl->dump();
        }
    };
    // TODO change this to a generic constant class
    class EnumConstantDeclaration : public Declaration
    {
        private:
        const clang::EnumConstantDecl* _decl;

        public:
        EnumConstantDeclaration(const clang::EnumConstantDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            return Type::get(_decl->getType());
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitEnumConstant(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitEnumConstant(*this);
        }*/

        /*virtual llvm::APSInt getValue() const
        {
            return _decl->getInitVal();
        }*/

        virtual long long getLLValue() const;

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    class ArgumentIterator
    {
        private:
        clang::FunctionDecl::param_const_iterator cpp_iter;

        public:
        explicit ArgumentIterator(clang::FunctionDecl::param_const_iterator i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const ArgumentIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const ArgumentIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        ArgumentDeclaration* operator*();
        ArgumentDeclaration* operator->()
        {
            return operator*();
        }

        virtual ArgumentDeclaration* get()
        {
            return operator*();
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(ArgumentIterator* other)
        {
            return (*this) == (*other);
        }
    };
    //typedef Iterator<clang::FunctionDecl::param_const_iterator, ArgumentDeclaration> ArgumentIterator;

    class FunctionDeclaration : public Declaration
    {
        private:
        const clang::FunctionDecl* _decl;

        public:
        FunctionDeclaration(const clang::FunctionDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            throw NotTypeDecl();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitFunction(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitFunction(*this);
        }*/

        virtual clang::LanguageLinkage getLinkLanguage() const
        {
            return _decl->getLanguageLinkage();
        }

        virtual Type* getReturnType() const
        {
            return Type::get(_decl->getReturnType());
        }

        virtual ArgumentIterator * getArgumentBegin()
        {
            return new ArgumentIterator(_decl->param_begin());
        }

        virtual ArgumentIterator * getArgumentEnd()
        {
            return new ArgumentIterator(_decl->param_end());
        }

        virtual bool isOverloadedOperator() const
        {
            return _decl->isOverloadedOperator();
        }

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    class FieldDeclaration : public Declaration
    {
        private:
        const clang::FieldDecl* _decl;

        public:
        FieldDeclaration(const clang::FieldDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        // Fields can infer visibility from C++ AST
        virtual ::Visibility getVisibility() const override
        {
            if( visibility == UNSET )
            {
                return accessSpecToVisibility(_decl->getAccess());
            }
            else
            {
                return visibility;
            }
        }

        virtual Type* getType() const override
        {
            return Type::get(_decl->getType());
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitField(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitField(*this);
        }*/

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    class OverriddenMethodIterator
    {
        private:
        clang::CXXMethodDecl::method_iterator cpp_iter;

        public:
        explicit OverriddenMethodIterator(clang::CXXMethodDecl::method_iterator i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const OverriddenMethodIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const OverriddenMethodIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        MethodDeclaration* operator*();
        MethodDeclaration* operator->()
        {
            return operator*();
        }

        virtual MethodDeclaration* get()
        {
            return operator*();
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(OverriddenMethodIterator* other)
        {
            return (*this) == (*other);
        }
    };
    class MethodDeclaration : public Declaration
    {
        private:
        const clang::CXXMethodDecl* _decl;

        public:
        MethodDeclaration(const clang::CXXMethodDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            throw NotTypeDecl();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitMethod(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitMethod(*this);
        }*/

        virtual bool isConst() const
        {
            return _decl->isConst();
        }

        virtual bool isStatic() const
        {
            return _decl->isStatic();
        }
        virtual bool isVirtual() const
        {
            return _decl->isVirtual();
        }

        virtual bool isOverloadedOperator() const
        {
            return _decl->isOverloadedOperator();
        }

        virtual Type* getReturnType() const
        {
            return Type::get(_decl->getReturnType());
        }

        virtual ArgumentIterator * getArgumentBegin()
        {
            return new ArgumentIterator(_decl->param_begin());
        }
        virtual ArgumentIterator * getArgumentEnd()
        {
            return new ArgumentIterator(_decl->param_end());
        }

        virtual void dump() override
        {
            _decl->dump();
        }

        virtual OverriddenMethodIterator * getOverriddenBegin()
        {
            return new OverriddenMethodIterator(_decl->begin_overridden_methods());
        }

        virtual OverriddenMethodIterator * getOverriddenEnd()
        {
            return new OverriddenMethodIterator(_decl->end_overridden_methods());
        }
    };

    class FieldIterator
    {
        private:
        clang::RecordDecl::field_iterator cpp_iter;

        public:
        explicit FieldIterator(clang::RecordDecl::field_iterator i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const FieldIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const FieldIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        FieldDeclaration* operator*();
        FieldDeclaration* operator->()
        {
            return operator*();
        }

        virtual FieldDeclaration* get()
        {
            return operator*();
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(FieldIterator* other)
        {
            return (*this) == (*other);
        }
    };
    //typedef Iterator<clang::RecordDecl::field_iterator, FieldDeclaration> FieldIterator;
    class MethodIterator
    {
        private:
        clang::CXXRecordDecl::method_iterator cpp_iter;

        public:
        explicit MethodIterator(clang::CXXRecordDecl::method_iterator i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const MethodIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const MethodIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        MethodDeclaration* operator*();
        MethodDeclaration* operator->()
        {
            return operator*();
        }

        virtual MethodDeclaration* get()
        {
            return operator*();
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(MethodIterator* other)
        {
            return (*this) == (*other);
        }
    };
    //typedef Iterator<clang::CXXRecordDecl::method_iterator, MethodDeclaration> MethodIterator;

    struct Superclass
    {
        bool isVirtual;
        Visibility visibility;
        Type * base;
    };

    class SuperclassIterator
    {
        private:
        clang::CXXRecordDecl::base_class_const_iterator cpp_iter;

        public:
        explicit SuperclassIterator(clang::CXXRecordDecl::base_class_const_iterator i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const SuperclassIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const SuperclassIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        Superclass* operator*();
        Superclass* operator->()
        {
            return operator*();
        }

        virtual Superclass* get()
        {
            return operator*();
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(SuperclassIterator* other)
        {
            return (*this) == (*other);
        }
    };
    //typedef Iterator<clang::CXXRecordDecl::base_class_const_iterator, Superclass> SuperclassIterator;

    class RecordDeclaration : public Declaration
    {
        protected:
        const clang::RecordDecl* _decl;

        const clang::RecordDecl* definitionOrThis()
        {
            if (hasDefinition())
            {
                return _decl->getDefinition();
            }
            else
            {
                return _decl;
            }
        }

        public:
        RecordDeclaration(const clang::RecordDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0));
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitRecord(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitRecord(*this);
        }*/

        virtual FieldIterator * getFieldBegin()
        {
            return new FieldIterator(definitionOrThis()->field_begin());
        }
        virtual FieldIterator * getFieldEnd()
        {
            return new FieldIterator(definitionOrThis()->field_end());
        }
        virtual DeclarationIterator * getChildBegin()
        {
            return new DeclarationIterator(definitionOrThis()->decls_begin());
        }
        virtual DeclarationIterator * getChildEnd()
        {
            return new DeclarationIterator(definitionOrThis()->decls_end());
        }

        virtual MethodIterator * getMethodBegin()
        {
            if( isCXXRecord() )
            {
                const clang::CXXRecordDecl* record = reinterpret_cast<const clang::CXXRecordDecl*>(definitionOrThis());
                return new MethodIterator(record->method_begin());
            }
            else
            {
                return new MethodIterator(clang::CXXRecordDecl::method_iterator());
            }
        }
        virtual MethodIterator * getMethodEnd()
        {
            if( isCXXRecord() )
            {
                return new MethodIterator(reinterpret_cast<const clang::CXXRecordDecl*>(definitionOrThis())->method_end());
            }
            else
            {
                return new MethodIterator(clang::CXXRecordDecl::method_iterator());
            }
        }

        virtual SuperclassIterator * getSuperclassBegin()
        {
            if( !isCXXRecord() )
            {
                return new SuperclassIterator(clang::CXXRecordDecl::base_class_const_iterator());
            }
            else
            {
                const clang::CXXRecordDecl * record = reinterpret_cast<const clang::CXXRecordDecl*>(definitionOrThis());
                return new SuperclassIterator(record->bases_begin());
            }
        }
        virtual SuperclassIterator * getSuperclassEnd()
        {
            if( !isCXXRecord() )
            {
                return new SuperclassIterator(clang::CXXRecordDecl::base_class_const_iterator());
            }
            else
            {
                const clang::CXXRecordDecl * record = reinterpret_cast<const clang::CXXRecordDecl*>(definitionOrThis());
                return new SuperclassIterator(record->bases_end());
            }
        }

        virtual bool isCXXRecord() const
        {
            return ::isCXXRecord(_decl);
        }

        virtual bool hasDefinition() const
        {
            return (_decl->getDefinition() != nullptr);
        }

        virtual const RecordDeclaration* getDefinition() const;

        virtual bool isDynamicClass() const
        {
            if( !isCXXRecord() ) return false;
            return reinterpret_cast<const clang::CXXRecordDecl*>(_decl)->isDynamicClass();
        }

        virtual void dump() override
        {
            _decl->dump();
        }

        virtual bool isCanonical() const
        {
            return _decl->isCanonicalDecl();
        }

        virtual unsigned getTemplateArgumentCount()
        {
            return 0;
        }
    };

    class UnionDeclaration : public Declaration
    {
        private:
        const clang::RecordDecl* _decl;

        public:
        UnionDeclaration(const clang::RecordDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0));
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitUnion(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) override
        {
            visitor.visitUnion(*this);
        }*/

        virtual FieldIterator * getFieldBegin()
        {
            return new FieldIterator(_decl->field_begin());
        }
        virtual FieldIterator * getFieldEnd()
        {
            return new FieldIterator(_decl->field_end());
        }
        virtual DeclarationIterator * getChildBegin()
        {
            return new DeclarationIterator(_decl->decls_begin());
        }
        virtual DeclarationIterator * getChildEnd()
        {
            return new DeclarationIterator(_decl->decls_end());
        }

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    class TemplateArgumentIterator
    {
        private:
        clang::TemplateParameterList::iterator cpp_iter;

        public:
        explicit TemplateArgumentIterator(clang::TemplateParameterList::iterator i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const TemplateArgumentIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const TemplateArgumentIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        Declaration* operator*();
        Declaration* operator->()
        {
            return operator*();
        }

        virtual Declaration* get()
        {
            return operator*();
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(TemplateArgumentIterator* other)
        {
            return (*this) == (*other);
        }
    };

    class RecordTemplateDeclaration : public RecordDeclaration
    {
        protected:
        const clang::ClassTemplateDecl* outer_decl;

        public:
        RecordTemplateDeclaration(const clang::ClassTemplateDecl* d)
            : RecordDeclaration(d->getTemplatedDecl()), outer_decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return outer_decl->getLocation();
        }

        virtual bool hasDefinition() const override
        {
            // TODO I don't know what forward declared templates look like
            return true;
        }

        virtual const RecordDeclaration* getDefinition() const override
        {
            return this;
        }

        virtual unsigned getTemplateArgumentCount() override
        {
            return outer_decl->getTemplateParameters()->size();
        }
        virtual TemplateArgumentIterator * getTemplateArgumentBegin()
        {
            return new TemplateArgumentIterator(outer_decl->getTemplateParameters()->begin());
        }
        virtual TemplateArgumentIterator * getTemplateArgumentEnd()
        {
            return new TemplateArgumentIterator(outer_decl->getTemplateParameters()->end());
        }

        virtual void dump() override
        {
            outer_decl->dump();
        }
    };

    class TemplateTypeArgumentDeclaration : public Declaration
    {
        private:
        const clang::TemplateTypeParmDecl* _decl;

        public:
        TemplateTypeArgumentDeclaration(const clang::TemplateTypeParmDecl* d)
            : _decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0));
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitTemplateTypeArgument(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
        }*/

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    class UnwrappableDeclaration : public Declaration
    {
        private:
        const clang::Decl* _decl;

        public:
        UnwrappableDeclaration(const clang::Decl* d)
            : _decl(d)
        {
            markUnwrappable();
        }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            throw NotTypeDecl();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitUnwrappable(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) override
        {
            visitor.visitUnwrappable(*this);
        }*/

        virtual void dump() override
        {
            _decl->dump();
        }
    };

    // TODO invalid decl class used to fill in things that are unwrappable,
    // so we know to properly deal with that later (i.e. leaving vtable entries,
    // exposing all of one class except for a non-virtual method, or something)
    class DeclVisitor : public clang::RecursiveASTVisitor<DeclVisitor>
    {
        private:
        template<class SourceType, class TargetType>
        void allocateDeclaration(SourceType * decl) {
            auto search_result = declarations.find(decl->getCanonicalDecl());
            if (search_result == declarations.end())
            {
                decl_in_progress = new TargetType(reinterpret_cast<SourceType*>(decl));
            }
            else
            {
                decl_in_progress = search_result->second;
            }
            //decl_in_progress = reinterpret_cast<TargetType*>(calloc(1, sizeof(TargetType)));
            //new (&decl_in_progress) TargetType(decl);
            declarations.insert(std::make_pair(decl, decl_in_progress));
            bool isCanonical = (decl->getCanonicalDecl() == decl);
            if (!isCanonical)
            {
                declarations.insert(std::make_pair(decl->getCanonicalDecl(), decl_in_progress));
            }
            if (top_level_decls)
            {
                free_declarations.insert(static_cast<Declaration*>(decl_in_progress));
            }
        }

        bool registerDeclaration(clang::Decl* cppDecl, bool top_level = false, clang::TemplateParameterList * tl = nullptr);

        // All declarations ever
        static std::unordered_map<const clang::Decl*, Declaration*> declarations;
        // Root level declarations, i.e. top level functions, namespaces, etc.
        static std::unordered_set<Declaration*> free_declarations;

        bool top_level_decls;
        Declaration* decl_in_progress;
        const clang::PrintingPolicy* print_policy;
        clang::TemplateParameterList * template_list;

        bool TraverseDeclContext(clang::DeclContext * cpp_context, bool top_level = false);
        bool TraverseFieldHelper(clang::CXXRecordDecl* record, bool top_level);
        bool TraverseMethodHelper(clang::CXXRecordDecl* record, bool top_level);
        bool TraverseCtorHelper(clang::CXXRecordDecl* record, bool top_level);
        public:
        typedef clang::RecursiveASTVisitor<DeclVisitor> Super;

        explicit DeclVisitor(const clang::PrintingPolicy* pp);

        bool TraverseType(clang::QualType type)
        {
            Type::get(type, print_policy);
            return true;
        }

        bool shouldVisitImplicitCode() const
        {
            return true;
        }

        bool TraverseDecl(clang::Decl * Declaration);
        bool TraverseTranslationUnitDecl(clang::TranslationUnitDecl* cppDecl);
        bool TraverseNamespaceDecl(clang::NamespaceDecl* cppDecl);
        bool TraverseFunctionDecl(clang::FunctionDecl* cppDecl);
        bool TraverseClassTemplateDecl(clang::ClassTemplateDecl* cppDecl);
        bool TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration);
        bool TraverseClassTemplateSpecializationDecl(clang::ClassTemplateSpecializationDecl* declaration);
        bool TraverseCXXRecordDecl(clang::CXXRecordDecl* cppDecl);
        bool TraverseCXXMethodDecl(clang::CXXMethodDecl* Declaration);
        bool TraverseLinkageSpecDecl(clang::LinkageSpecDecl* cppDecl);
        bool TraverseEnumDecl(clang::EnumDecl* cppDecl);
        //bool TraverseEnumConstantDecl(clang::EnumConstantDecl* cppDecl);
        // TODO handle constexpr
        bool TraverseUsingDirectiveDecl(clang::UsingDirectiveDecl* cppDecl);
        bool TraverseAccessSpecDecl(clang::AccessSpecDecl* cppDecl);
        bool TraverseFriendDecl(clang::FriendDecl* cppDecl);
        bool TraverseStaticAssertDecl(clang::StaticAssertDecl* cppDecl);
        bool TraverseIndirectFieldDecl(clang::IndirectFieldDecl* cppDecl);
        // FIXME I have no idea what this is.
        bool TraverseEmptyDecl(clang::EmptyDecl* cppDecl);
        bool TraverseUsingDecl(clang::UsingDecl* cppDecl);
        bool TraverseUsingShadowDecl(clang::UsingShadowDecl* cppDecl);

        bool WalkUpFromDecl(clang::Decl* cppDecl);
        bool WalkUpFromTranslationUnitDecl(clang::TranslationUnitDecl* cppDecl);
        bool WalkUpFromFunctionDecl(clang::FunctionDecl * Declaration);
        bool WalkUpFromTypedefDecl(clang::TypedefDecl * decl);
        bool WalkUpFromNamespaceDecl(clang::NamespaceDecl * cppDecl);
        bool WalkUpFromCXXMethodDecl(clang::CXXMethodDecl* cppDecl);
        bool WalkUpFromCXXConstructorDecl(clang::CXXConstructorDecl* cppDecl);
        bool WalkUpFromCXXDestructorDecl(clang::CXXDestructorDecl* cppDecl);
        bool WalkUpFromParmVarDecl(clang::ParmVarDecl* cppDecl);
        bool WalkUpFromRecordDecl(clang::RecordDecl* cppDecl);
        bool WalkUpFromEnumDecl(clang::EnumDecl* cppDecl);
        bool WalkUpFromEnumConstantDecl(clang::EnumConstantDecl* cppDecl);
        bool WalkUpFromVarDecl(clang::VarDecl* cppDecl);
        bool WalkUpFromFieldDecl(clang::FieldDecl* cppDecl);
        bool WalkUpFromClassTemplateDecl(clang::ClassTemplateDecl* cppDecl);
        bool WalkUpFromTemplateTypeParmDecl(clang::TemplateTypeParmDecl* cppDecl);
        bool WalkUpFromNonTypeTemplateParmDecl(clang::NonTypeTemplateParmDecl* cppDecl);

        // Template stuff I can't handle yet
        bool TraverseFunctionTemplateDecl(clang::FunctionTemplateDecl* cppDecl);
        bool TraverseTypeAliasTemplateDecl(clang::TypeAliasTemplateDecl* cppDecl);

        bool TraverseTypeAliasDecl(clang::TypeAliasDecl* cppDecl);
        bool TraverseUnresolvedUsingValueDecl(clang::UnresolvedUsingValueDecl* cppDecl);

        bool VisitDecl(clang::Decl* Declaration);
        // Also gets cxx method/ctor/dtor
        bool VisitFunctionDecl(clang::FunctionDecl * Declaration);
        bool VisitTypedefDecl(clang::TypedefDecl * decl);
        bool VisitParmVarDecl(clang::ParmVarDecl* cppDecl);
        bool VisitNamedDecl(clang::NamedDecl* cppDecl);
        bool VisitFieldDecl(clang::FieldDecl* cppDecl);
        bool VisitVarDecl(clang::VarDecl* cppDecl);
        bool VisitTemplateTypeParmDecl(clang::TemplateTypeParmDecl* cppDecl);

        private:
        static void enableDeclarationsInFiles(const std::vector<std::string>& filenames);

        static const std::unordered_map<const clang::Decl*, Declaration*>& getDeclarations()
        {
            return declarations;
        }
        static const std::unordered_set<Declaration*>& getFreeDeclarations()
        {
            return free_declarations;
        }

        friend void enableDeclarationsInFiles(size_t count, char ** filenames);
        friend void arrayOfFreeDeclarations(size_t* count, Declaration*** array);
        friend Declaration * getDeclaration(const clang::Decl* decl);
        friend class RecordDeclaration;
        friend class DeclarationIterator;
        friend class ArgumentIterator;
        friend class FieldIterator;
        friend class MethodIterator;
        friend class OverriddenMethodIterator;
        friend class TemplateArgumentIterator;
    };

namespace clang
{
    class ASTUnit;
}
    void traverseDeclsInAST(clang::ASTUnit* ast);
    void enableDeclarationsInFiles(size_t count, char ** filenames);
    void arrayOfFreeDeclarations(size_t* count, Declaration*** array);
    Declaration * getDeclaration(const clang::Decl* decl);

    class SkipUnwrappableDeclaration : public NotWrappableException
    {
        public:
        SkipUnwrappableDeclaration(clang::Decl*)
        { }
    };

//} // namespace cpp

extern const clang::SourceManager * source_manager;

#endif // __CPP_DECL_HPP__
