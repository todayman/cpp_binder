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

    class DeclarationAttributes
    {
        // TODO pack this efficiently
        bool isBoundSet;
        bool bound;
        bool isTargetModuleSet;
        string target_module;
        // Visibility has an unset state
        Visibility visibility;
        // Empty string means no remove prefix
        string remove_prefix;

        public:
        DeclarationAttributes()
            : isBoundSet(false), bound(true), isTargetModuleSet(false),
            target_module(), visibility(UNSET), remove_prefix()
        { }

        static DeclarationAttributes* make();

        void setBound(bool value);
        void setTargetModule(string* value);
        void setVisibility(Visibility value);
        void setRemovePrefix(string* value);

        friend class Declaration;
    };

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
        bool should_emit;
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
            : is_wrappable(true), should_emit(false), target_module(),
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

        virtual bool isWrappable() const
        {
            return is_wrappable;
        }

        virtual void shouldEmit(bool decision)
        {
            should_emit = decision;
        }

        virtual bool shouldEmit() const
        {
            return should_emit;
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

        // This is for the configuration pass, so it can look up decls,
        // then apply attributes to their types
        // TODO split into TypeDeclarations and other declarations?
        virtual Type* getType() const = 0;

        virtual void visit(DeclarationVisitor& visitor) = 0;
        //virtual void visit(ConstDeclarationVisitor& visitor) const = 0;

        virtual void dump() = 0;

        void applyAttributes(const DeclarationAttributes* attribs);
    };

    void applyAttributesToDeclByName(const DeclarationAttributes* attribs, const string* declName);

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

    class DeclarationRange
    {
        public:
        typedef clang::DeclContext::decl_iterator iterator_t;
        typedef clang::DeclContext::decl_range range_t;

        protected:
        iterator_t cpp_iter;
        iterator_t end;

        public:
        explicit DeclarationRange(range_t r)
            : cpp_iter(r.begin()), end(r.end())
        { }
        explicit DeclarationRange(iterator_t i, iterator_t e)
            : cpp_iter(i), end(e)
        { }

        virtual bool empty()
        {
            return cpp_iter == end;
        }

        virtual Declaration* front();

        virtual void popFront()
        {
            cpp_iter++;
        }
    };

    //typedef Iterator<clang::DeclContext::decl_iterator, Declaration> DeclarationRange;

#define FORALL_DECLARATIONS(func) \
func(Function)                  \
func(Namespace)                 \
func(Record)                    \
func(RecordTemplate)            \
func(Typedef)                   \
func(Enum)                      \
func(Field)                     \
func(EnumConstant)              \
func(Union)                     \
func(SpecializedRecord)         \
func(Method)                    \
func(Constructor)               \
func(Destructor)                \
func(Argument)                  \
func(Variable)                  \
func(TemplateTypeArgument)      \
func(TemplateNonTypeArgument)   \
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
        }\
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

        virtual Type* getType() const
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

        virtual Type* getType() const
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

        virtual DeclarationRange * getChildren();

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

        virtual bool isWrappable() const override;

        TypedefType* getTypedefType() const;
        virtual Type* getType() const override
        {
            return getTypedefType();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitTypedef(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitTypedef(*this);
        }*/

        Type* getTargetType() const;

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

        EnumType* getEnumType() const
        {
            return dynamic_cast<EnumType*>(Type::get(_decl->getTypeForDecl()));
        }
        virtual Type* getType() const override
        {
            return getEnumType();
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

        virtual DeclarationRange * getChildren()
        {
            return new DeclarationRange(_decl->decls());
        }

        virtual void dump() override
        {
            _decl->dump();
        }

        virtual bool isWrappable() const override;
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

        virtual Type* getType() const
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

        virtual bool isWrappable() const override;

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return _decl->getLocation();
        }

        virtual Type* getType() const override
        {
            // TODO in principle, this should probably return a function type
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

        virtual bool isWrappable() const override
        {
            if (isOverloadedOperator())
            {
                return false;
            }
            return Declaration::isWrappable();
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

    class FieldRange
    {
        public:
        typedef clang::RecordDecl::field_iterator iterator_t;
        typedef clang::RecordDecl::field_range range_t;

        private:
        iterator_t cpp_iter;
        iterator_t end;

        public:
        explicit FieldRange(range_t r)
            : cpp_iter(r.begin()), end(r.end())
        { }

        virtual FieldDeclaration* front();

        virtual void popFront()
        {
            cpp_iter++;
        }

        virtual bool empty() const
        {
            return cpp_iter == end;
        }
    };
    //typedef Iterator<clang::RecordDecl::field_iterator, FieldDeclaration> FieldIterator;
    class MethodRange
    {
        public:
        typedef clang::CXXRecordDecl::method_iterator iterator_t;
        typedef clang::CXXRecordDecl::method_range range_t;

        protected:
        iterator_t cpp_iter;
        iterator_t end;

        public:
        MethodRange()
            : cpp_iter(), end()
        { }
        explicit MethodRange(range_t r)
            : cpp_iter(r.begin()), end(r.end())
        { }

        virtual bool empty()
        {
            return cpp_iter == end;
        }

        virtual MethodDeclaration* front();

        virtual void popFront()
        {
            ++cpp_iter;
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

        const clang::RecordDecl* definitionOrThis() const
        {
            const clang::RecordDecl* definition = _decl->getDefinition();
            if (definition)
            {
                return definition;
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

        RecordType* getRecordType() const;
        virtual Type* getType() const override
        {
            return getRecordType();
        }

        virtual bool isWrappable() const override;

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitRecord(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitRecord(*this);
        }*/

        virtual FieldRange * getFieldRange() const
        {
            return new FieldRange(definitionOrThis()->fields());
        }
        virtual DeclarationRange * getChildren() const
        {
            return new DeclarationRange(definitionOrThis()->decls());
        }

        virtual MethodRange * getMethodRange()
        {
            if( isCXXRecord() )
            {
                const clang::CXXRecordDecl* record = reinterpret_cast<const clang::CXXRecordDecl*>(definitionOrThis());
                return new MethodRange(record->methods());
            }
            else
            {
                return new MethodRange();
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

        virtual bool shouldEmit() const override
        {
            if (!hasDefinition())
            {
                return false;
            }
            return Declaration::shouldEmit();
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

        virtual unsigned getTemplateArgumentCount() const
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

        UnionType* getUnionType() const
        {
            return dynamic_cast<UnionType*>(Type::get(_decl->getTypeForDecl()));
        }
        virtual Type* getType() const override
        {
            return getUnionType();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitUnion(*this);
        }
        /*virtual void visit(ConstDeclarationVisitor& visitor) override
        {
            visitor.visitUnion(*this);
        }*/

        virtual FieldRange * getFieldRange()
        {
            return new FieldRange(_decl->fields());
        }
        virtual DeclarationRange * getChildren()
        {
            return new DeclarationRange(_decl->decls());
        }

        virtual void dump() override
        {
            _decl->dump();
        }

        virtual unsigned getTemplateArgumentCount() const
        {
            return 0;
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

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(TemplateArgumentIterator* other)
        {
            return (*this) == (*other);
        }

        enum Kind
        {
            Type,
            NonType,
        };

        virtual Kind getKind();
        virtual bool isPack();

        virtual TemplateTypeArgumentDeclaration* getType();

        virtual TemplateNonTypeArgumentDeclaration* getNonType();
    };

    class TemplateDeclaration /* : virtual public Declaration?*/
    {
        public:
        virtual unsigned getTemplateArgumentCount() const = 0;
        virtual TemplateArgumentIterator * getTemplateArgumentBegin() = 0;
        virtual TemplateArgumentIterator * getTemplateArgumentEnd() = 0;
    };

    class SpecializedRecordDeclaration : public RecordDeclaration//, public SpecializedDeclaration
    {
        protected:
        const clang::ClassTemplateSpecializationDecl* template_decl;
        // FIXME redundant with superclass...
        public:
        SpecializedRecordDeclaration(const clang::ClassTemplateSpecializationDecl* d)
            : RecordDeclaration(d), template_decl(d)
        { }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitSpecializedRecord(*this);
        }

        virtual unsigned getTemplateArgumentCount() const;
        virtual TemplateArgumentInstanceIterator* getTemplateArgumentBegin();
        virtual TemplateArgumentInstanceIterator* getTemplateArgumentEnd();
    };

    class SpecializedRecordIterator
    {
        private:
        clang::ClassTemplateDecl::spec_iterator cpp_iter;

        public:
        explicit SpecializedRecordIterator(clang::ClassTemplateDecl::spec_iterator i)
            : cpp_iter(i)
        { }

        void operator++() {
            cpp_iter++;
        }

        bool operator==(const SpecializedRecordIterator& other) {
            return cpp_iter == other.cpp_iter;
        }

        bool operator!=(const SpecializedRecordIterator& other) {
            return cpp_iter != other.cpp_iter;
        }

        SpecializedRecordDeclaration* operator*();
        SpecializedRecordDeclaration* operator->()
        {
            return operator*();
        }

        virtual SpecializedRecordDeclaration* get()
        {
            return operator*();
        }

        virtual void advance()
        {
            cpp_iter++;
        }

        virtual bool equals(SpecializedRecordIterator* other)
        {
            return (*this) == (*other);
        }
    };

    class RecordTemplateDeclaration : public RecordDeclaration//, public TemplateDeclaration
    {
        protected:
        const clang::ClassTemplateDecl* outer_decl;

        public:
        RecordTemplateDeclaration(const clang::ClassTemplateDecl* d)
            : RecordDeclaration(d->getTemplatedDecl()), outer_decl(d)
        { }

        bool isVariadic() const;

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return outer_decl->getLocation();
        }

        virtual void visit(DeclarationVisitor& visitor)
        {
            visitor.visitRecordTemplate(*this);
        }

        virtual bool hasDefinition() const override
        {
            // TODO I don't know what forward declared templates look like
            return true;
        }

        virtual bool isWrappable() const override;

        virtual const RecordDeclaration* getDefinition() const override
        {
            return this;
        }

        virtual unsigned getTemplateArgumentCount() const override
        {
            return outer_decl->getTemplateParameters()->size();
        }
        virtual TemplateArgumentIterator * getTemplateArgumentBegin() const
        {
            return new TemplateArgumentIterator(outer_decl->getTemplateParameters()->begin());
        }
        virtual TemplateArgumentIterator * getTemplateArgumentEnd() const
        {
            return new TemplateArgumentIterator(outer_decl->getTemplateParameters()->end());
        }

        virtual void dump() override
        {
            outer_decl->dump();
        }

        virtual SpecializedRecordIterator* getSpecializationBegin();
        virtual SpecializedRecordIterator* getSpecializationEnd();
    };

    class UnionTemplateDeclaration : public UnionDeclaration//, public TemplateDeclaration
    {
        protected:
        const clang::ClassTemplateDecl* outer_decl;

        public:
        UnionTemplateDeclaration(const clang::ClassTemplateDecl* d)
            : UnionDeclaration(d->getTemplatedDecl()), outer_decl(d)
        { }

        virtual clang::SourceLocation getSourceLocation() const override
        {
            return outer_decl->getLocation();
        }

        virtual unsigned getTemplateArgumentCount() const override
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

        TemplateArgumentType* getTemplateArgumentType() const
        {
            return dynamic_cast<TemplateArgumentType*>(Type::get(_decl->getTypeForDecl()));
        }
        virtual Type* getType() const override
        {
            return getTemplateArgumentType();
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

    // TODO is basically the same as VariableDeclarataion
    class TemplateNonTypeArgumentDeclaration : public Declaration
    {
        private:
        const clang::NonTypeTemplateParmDecl* _decl;

        public:
        TemplateNonTypeArgumentDeclaration(const clang::NonTypeTemplateParmDecl* d)
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
            visitor.visitTemplateNonTypeArgument(*this);
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
        bool TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration);
        bool TraverseCXXMethodDecl(clang::CXXMethodDecl* Declaration);
        bool TraverseLinkageSpecDecl(clang::LinkageSpecDecl* cppDecl);
        bool TraverseEnumDecl(clang::EnumDecl* cppDecl);
        bool TraverseUsingDirectiveDecl(clang::UsingDirectiveDecl* cppDecl);
        bool TraverseAccessSpecDecl(clang::AccessSpecDecl* cppDecl);
        bool TraverseFriendDecl(clang::FriendDecl* cppDecl);
        bool TraverseStaticAssertDecl(clang::StaticAssertDecl* cppDecl);
        bool TraverseIndirectFieldDecl(clang::IndirectFieldDecl* cppDecl);
        bool TraverseCXXConstructorDecl(clang::CXXConstructorDecl* cppDecl);
        bool TraverseCXXDestructorDecl(clang::CXXDestructorDecl* cppDecl);
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
        bool WalkUpFromParmVarDecl(clang::ParmVarDecl* cppDecl);
        bool WalkUpFromRecordDecl(clang::RecordDecl* cppDecl);
        bool WalkUpFromEnumDecl(clang::EnumDecl* cppDecl);
        bool WalkUpFromEnumConstantDecl(clang::EnumConstantDecl* cppDecl);
        bool WalkUpFromVarDecl(clang::VarDecl* cppDecl);
        bool WalkUpFromFieldDecl(clang::FieldDecl* cppDecl);
        bool WalkUpFromClassTemplateDecl(clang::ClassTemplateDecl* cppDecl);
        bool WalkUpFromTemplateTypeParmDecl(clang::TemplateTypeParmDecl* cppDecl);
        bool WalkUpFromNonTypeTemplateParmDecl(clang::NonTypeTemplateParmDecl* cppDecl);
        bool WalkUpFromClassTemplateSpecializationDecl(clang::ClassTemplateSpecializationDecl* cppDecl);

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
        bool VisitCXXRecordDecl(clang::CXXRecordDecl* cppDecl);
        bool VisitClassTemplateDecl(clang::ClassTemplateDecl* cppDecl);

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
        friend class DeclarationRange;
        friend class ArgumentIterator;
        friend class FieldRange;
        friend class MethodRange;
        friend class OverriddenMethodIterator;
        friend class TemplateArgumentIterator;
        friend class SpecializedRecordIterator;
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
