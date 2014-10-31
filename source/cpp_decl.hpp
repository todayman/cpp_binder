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

namespace cpp
{
    class DeclarationVisitor;
    class ConstDeclarationVisitor;

    bool isCXXRecord(const clang::Decl* decl);

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

        public:
        virtual const clang::Decl* decl() = 0;
        protected:
        string source_name;
        string _name;

        void setSourceName(string name) {
            source_name = name;
        }

        friend class DeclVisitor;

        void markUnwrappable() {
            is_wrappable = false;
        }

        public:
        explicit Declaration()
            : is_wrappable(true), should_bind(false), target_module(""),
              visibility(UNSET), remove_prefix("")
        { }

        const string& getSourceName() const {
            return source_name;
        }
        const string& getTargetName() const {
            if( _name.size() == 0 )
            {
                return source_name;
            }
            else
            {
                return _name;
            }
        }

        bool isWrappable() const noexcept {
            return is_wrappable;
        }

        void shouldBind(bool decision)
        {
            should_bind = decision;
        }

        bool getShouldBind() const
        {
            return should_bind;
        }

        void setTargetModule(string target)
        {
            target_module = target;
        }

        bool isTargetModuleSet() const
        {
            return target_module.size() > 0;
        }
        const string& getTargetModule() const
        {
            return target_module;
        }

        virtual ::Visibility getVisibility() const
        {
            return visibility;
        }
        void setVisibility(Visibility vis)
        {
            visibility = vis;
        }

        void removePrefix(string prefix)
        {
            remove_prefix = prefix;
        }

        virtual Type* getType() const = 0;

        virtual void visit(DeclarationVisitor& visitor) = 0;
        virtual void visit(ConstDeclarationVisitor& visitor) const = 0;
    };

    struct NotTypeDecl : public std::runtime_error
    {
        NotTypeDecl()
            : std::runtime_error("Operation is only valid on Type declarations.")
        { }
    };

    template<typename ClangType, typename TranslatorType>
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
    };

    typedef Iterator<clang::DeclContext::decl_iterator, Declaration> DeclarationIterator;

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

#define DECLARATION_CLASS_TYPE(C, D) \
    class D##Declaration : public Declaration \
    { \
        private: \
        const clang::C##Decl* _decl; \
\
        public: \
        D##Declaration(const clang::C##Decl* d) \
            : _decl(d) \
        { } \
        virtual const clang::Decl* decl() override { \
            return _decl; \
        } \
\
        virtual std::shared_ptr<Type> getType() const override \
        { \
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0)); \
        }\
\
        virtual void visit(DeclarationVisitor& visitor) override \
        { \
            visitor.visit##D(*this); \
        } \
        virtual void visit(ConstDeclarationVisitor& visitor) const override \
        { \
            visitor.visit##D(*this); \
        } \
    }
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
        virtual const clang::Decl* decl() override { \
            return _decl; \
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
        virtual void visit(ConstDeclarationVisitor& visitor) const override \
        { \
            visitor.visit##D(*this); \
        } \
    }
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            return Type::get(_decl->getType());
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitVariable(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitVariable(*this);
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            return Type::get(_decl->getType());
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitArgument(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitArgument(*this);
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            throw NotTypeDecl();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitNamespace(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitNamespace(*this);
        }

        DeclarationIterator getChildBegin()
        {
            return DeclarationIterator(_decl->decls_begin());
        }
        DeclarationIterator getChildEnd()
        {
            return DeclarationIterator(_decl->decls_end());
        }
    };

    class TypedefDeclaration : public Declaration
    {
        private:
        const clang::TypedefDecl* _decl;

        public:
        TypedefDeclaration(const clang::TypedefDecl* d)
            : _decl(d)
        { }
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0));
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitTypedef(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitTypedef(*this);
        }

        Type* getTargetType() const
        {
            return Type::get(_decl->getUnderlyingType());
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            return Type::get(_decl->getIntegerType());
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitEnum(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitEnum(*this);
        }

        DeclarationIterator getChildBegin()
        {
            return DeclarationIterator(_decl->decls_begin());
        }
        DeclarationIterator getChildEnd()
        {
            return DeclarationIterator(_decl->decls_end());
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            return Type::get(_decl->getType());
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitEnumConstant(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitEnumConstant(*this);
        }

        llvm::APSInt getValue() const
        {
            return _decl->getInitVal();
        }
    };

    typedef Iterator<clang::FunctionDecl::param_const_iterator, ArgumentDeclaration> ArgumentIterator;
    class FunctionDeclaration : public Declaration
    {
        private:
        const clang::FunctionDecl* _decl;

        public:
        FunctionDeclaration(const clang::FunctionDecl* d)
            : _decl(d)
        { }
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            throw NotTypeDecl();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitFunction(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitFunction(*this);
        }

        clang::LanguageLinkage getLinkLanguage() const
        {
            return _decl->getLanguageLinkage();
        }

        virtual Type* getReturnType() const
        {
            return Type::get(_decl->getReturnType());
        }

        virtual ArgumentIterator getArgumentBegin() const
        {
            return ArgumentIterator(_decl->param_begin());
        }

        virtual ArgumentIterator getArgumentEnd() const
        {
            return ArgumentIterator(_decl->param_end());
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        // Fields can infer visibility from C++ AST
        virtual ::Visibility getVisibility() const override
        {
            if( visibility == UNSET )
            {
                switch( _decl->getAccess() )
                {
                    case clang::AS_public:
                        return ::PUBLIC;
                    case clang::AS_private:
                        return ::PRIVATE;
                    case clang::AS_protected:
                        return ::PROTECTED;
                    case clang::AS_none:
                        // This means different things in different contexts,
                        // and I don't know what any of them are.
                        throw 29;
                    default:
                        throw 30;
                }
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
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitField(*this);
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            throw NotTypeDecl();;
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitMethod(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitMethod(*this);
        }

        bool isStatic() const
        {
            return _decl->isStatic();
        }
        bool isVirtual() const
        {
            return _decl->isVirtual();
        }

        virtual Type* getReturnType() const
        {
            return Type::get(_decl->getReturnType());
        }

        virtual ArgumentIterator getArgumentBegin() const
        {
            return ArgumentIterator(_decl->param_begin());
        }
        virtual ArgumentIterator getArgumentEnd() const
        {
            return ArgumentIterator(_decl->param_end());
        }
    };

    typedef Iterator<clang::RecordDecl::field_iterator, FieldDeclaration> FieldIterator;
    typedef Iterator<clang::CXXRecordDecl::method_iterator, MethodDeclaration> MethodIterator;

    class RecordDeclaration : public Declaration
    {
        private:
        const clang::RecordDecl* _decl;

        public:
        RecordDeclaration(const clang::RecordDecl* d)
            : _decl(d)
        { }
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0));
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitRecord(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitRecord(*this);
        }

        FieldIterator getFieldBegin()
        {
            return FieldIterator(_decl->field_begin());
        }
        FieldIterator getFieldEnd()
        {
            return FieldIterator(_decl->field_end());
        }
        DeclarationIterator getChildBegin()
        {
            return DeclarationIterator(_decl->decls_begin());
        }
        DeclarationIterator getChildEnd()
        {
            return DeclarationIterator(_decl->decls_end());
        }

        MethodIterator getMethodBegin()
        {
            if( isCXXRecord(_decl) )
            {
                const clang::CXXRecordDecl* record = reinterpret_cast<const clang::CXXRecordDecl*>(_decl);
                return MethodIterator(record->method_begin());
            }
            else
            {
                return MethodIterator(clang::CXXRecordDecl::method_iterator());
            }
        }
        MethodIterator getMethodEnd()
        {
            if( isCXXRecord(_decl) )
            {
                return MethodIterator(reinterpret_cast<const clang::CXXRecordDecl*>(_decl)->method_end());
            }
            else
            {
                return MethodIterator(clang::CXXRecordDecl::method_iterator());
            }
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            return Type::get(clang::QualType(_decl->getTypeForDecl(), 0));
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitUnion(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitUnion(*this);
        }

        FieldIterator getFieldBegin()
        {
            return FieldIterator(_decl->field_begin());
        }
        FieldIterator getFieldEnd()
        {
            return FieldIterator(_decl->field_end());
        }
        DeclarationIterator getChildBegin()
        {
            return DeclarationIterator(_decl->decls_begin());
        }
        DeclarationIterator getChildEnd()
        {
            return DeclarationIterator(_decl->decls_end());
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
        virtual const clang::Decl* decl() override {
            return _decl;
        }

        virtual Type* getType() const override
        {
            throw NotTypeDecl();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitUnwrappable(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitUnwrappable(*this);
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
            decl_in_progress = new TargetType(decl);
            declarations.insert(std::make_pair(decl, decl_in_progress));
            if( top_level_decls )
            {
                free_declarations.insert(static_cast<Declaration*>(decl_in_progress));
            }
        }

        bool registerDeclaration(clang::Decl* cppDecl, bool top_level = false);

        // All declarations ever
        static std::unordered_map<clang::Decl*, Declaration*> declarations;
        // Root level declarations, i.e. top level functions, namespaces, etc.
        static std::unordered_set<Declaration*> free_declarations;

        bool top_level_decls;
        Declaration* decl_in_progress;
        const clang::PrintingPolicy* print_policy;

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
        bool TraverseFunctionDecl(clang::FunctionDecl* cppDecl);
        bool TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration);
        bool TraverseClassTemplateSpecializationDecl(clang::ClassTemplateSpecializationDecl* declaration);
        bool TraverseCXXRecordDecl(clang::CXXRecordDecl* cppDecl);
        bool TraverseCXXMethodDecl(clang::CXXMethodDecl* Declaration);
        bool TraverseCXXConstructorDecl(clang::CXXConstructorDecl* Declaration);
        bool TraverseCXXDestructorDecl(clang::CXXDestructorDecl* Declaration);
        bool TraverseLinkageSpecDecl(clang::LinkageSpecDecl* cppDecl);
        bool TraverseEnumDecl(clang::EnumDecl* cppDecl);
        //bool TraverseEnumConstantDecl(clang::EnumConstantDecl* cppDecl);
        // TODO handle constexpr
        bool TraverseVarDecl(clang::VarDecl* cppDecl);
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

        bool VisitDecl(clang::Decl* Declaration);
        // Also gets cxx method/ctor/dtor
        bool VisitFunctionDecl(clang::FunctionDecl * Declaration);
        bool VisitTypedefDecl(clang::TypedefDecl * decl);
        bool VisitParmVarDecl(clang::ParmVarDecl* cppDecl);
        bool VisitNamedDecl(clang::NamedDecl* cppDecl);
        bool VisitFieldDecl(clang::FieldDecl* cppDecl);

        static void enableDeclarationsInFiles(const std::vector<std::string>& filenames);

        static const std::unordered_map<clang::Decl*, Declaration*>& getDeclarations()
        {
            return declarations;
        }
        static const std::unordered_set<Declaration*>& getFreeDeclarations()
        {
            return free_declarations;
        }
    };

    class SkipUnwrappableDeclaration : public NotWrappableException
    {
        public:
        SkipUnwrappableDeclaration(clang::Decl*)
        { }
    };

} // namespace cpp

extern const clang::SourceManager * source_manager;

#endif // __CPP_DECL_HPP__
