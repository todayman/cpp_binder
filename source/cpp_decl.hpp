#ifndef __CPP_DECL_HPP__
#define __CPP_DECL_HPP__

#include <unordered_map>
#include <unordered_set>

#include "llvm/ADT/APSInt.h"

#include "clang/AST/Decl.h"
#include "clang/AST/RecursiveASTVisitor.h"

#include "cpp_type.hpp"
#include "cpp_exception.hpp"

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

    // Same thing as Type, but for declarations of functions,
    // classes, etc.
    class Declaration
    {
        // We still want to know about things we can't wrap,
        // like templates, but they'll get skipped later on
        bool is_wrappable;
        // Attributes!
        // Pointer to D declaration!
        bool should_bind;
        std::string target_module;
        Visibility visibility;
        std::string remove_prefix;

        public:
        virtual const clang::Decl* decl() = 0;
        const std::string name() {
            return _name;
        }
        protected:
        std::string _name;

        void setName(std::string name) {
            _name = name;
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

        const std::string& getName() const {
            return _name;
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

        void setTargetModule(std::string target)
        {
            target_module = target;
        }

        bool isTargetModuleSet() const
        {
            return target_module.size() > 0;
        }
        const std::string& getTargetModule() const
        {
            return target_module;
        }

        void setVisibility(Visibility vis)
        {
            visibility = vis;
        }

        void removePrefix(std::string prefix)
        {
            remove_prefix = prefix;
        }

        virtual std::shared_ptr<Type> getType() const = 0;

        virtual void visit(DeclarationVisitor& visitor) = 0;
        virtual void visit(ConstDeclarationVisitor& visitor) const = 0;
    };

    struct NotTypeDecl : public std::runtime_error
    {
        NotTypeDecl()
            : std::runtime_error("Operation is only valid on Type declarations.")
        { }
    };

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

        std::shared_ptr<Declaration> operator*();
        std::shared_ptr<Declaration> operator->()
        {
            return operator*();
        }
    };

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
        virtual std::shared_ptr<Type> getType() const override \
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
DECLARATION_CLASS_TYPE(Record, Record);
DECLARATION_CLASS(Field);

DECLARATION_CLASS_TYPE(Record, Union);
DECLARATION_CLASS_2(CXXMethod, Method);
DECLARATION_CLASS_2(CXXConstructor, Constructor);
DECLARATION_CLASS_2(CXXDestructor, Destructor);
DECLARATION_CLASS_2(Var, Variable);

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

        virtual std::shared_ptr<Type> getType() const override
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

        virtual std::shared_ptr<Type> getType() const override
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

        virtual std::shared_ptr<Type> getReturnType() const
        {
            // TODO changes to getReturnType in clang 3.5
            return Type::get(_decl->getResultType());
        }

        struct arg_iterator
        {
            private:
            clang::FunctionDecl::param_const_iterator cpp_iter;

            public:
            explicit arg_iterator(clang::FunctionDecl::param_const_iterator i)
                : cpp_iter(i)
            { }

            void operator++() {
                cpp_iter++;
            }

            bool operator==(const arg_iterator& other) {
                return cpp_iter == other.cpp_iter;
            }

            bool operator!=(const arg_iterator& other) {
                return cpp_iter != other.cpp_iter;
            }

            std::shared_ptr<ArgumentDeclaration> operator*();
            std::shared_ptr<ArgumentDeclaration> operator->()
            {
                return operator*();
            }
        };

        virtual arg_iterator getArgumentBegin() const
        {
            return arg_iterator(_decl->param_begin());
        }

        virtual arg_iterator getArgumentEnd() const
        {
            return arg_iterator(_decl->param_end());
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

        virtual std::shared_ptr<Type> getType() const override
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

        virtual std::shared_ptr<Type> getType() const override
        {
            throw NotTypeDecl();
        }

        virtual void visit(DeclarationVisitor& visitor) override
        {
            visitor.visitTypedef(*this);
        }
        virtual void visit(ConstDeclarationVisitor& visitor) const override
        {
            visitor.visitTypedef(*this);
        }

        std::shared_ptr<Type> getTargetType() const
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

        virtual std::shared_ptr<Type> getType() const override
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

        virtual std::shared_ptr<Type> getType() const override
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

        virtual std::shared_ptr<Type> getType() const override
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
            decl_in_progress = std::make_shared<TargetType>(decl);
            declarations.insert(std::make_pair(decl, decl_in_progress));
            if( top_level_decls )
            {
                free_declarations.insert(std::static_pointer_cast<Declaration>(decl_in_progress));
            }
        }

        bool registerDeclaration(clang::Decl* cppDecl, bool top_level = false);

        // All declarations ever
        static std::unordered_map<clang::Decl*, std::shared_ptr<Declaration>> declarations;
        // Root level declarations, i.e. top level functions, namespaces, etc.
        static std::unordered_set<std::shared_ptr<Declaration>> free_declarations;

        bool top_level_decls;
        std::shared_ptr<Declaration> decl_in_progress;
        const clang::PrintingPolicy* print_policy;

        bool TraverseDeclContext(clang::DeclContext * cpp_context, bool maintain_top_level = false);
        public:
        typedef clang::RecursiveASTVisitor<DeclVisitor> Super;

        explicit DeclVisitor(const clang::PrintingPolicy* pp);

        bool TraverseType(clang::QualType type)
        {
            Type::get(type, print_policy);
            return true;
        }

        bool TraverseDecl(clang::Decl * Declaration);
        bool TraverseTranslationUnitDecl(clang::TranslationUnitDecl* cppDecl);
        bool TraverseFunctionDecl(clang::FunctionDecl* cppDecl);
        bool TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration);
        bool TraverseCXXMethodDecl(clang::CXXMethodDecl* Declaration);
        bool TraverseCXXConstructorDecl(clang::CXXConstructorDecl* Declaration);
        bool TraverseCXXDestructorDecl(clang::CXXDestructorDecl* Declaration);
        bool TraverseLinkageSpecDecl(clang::LinkageSpecDecl* cppDecl);
        bool TraverseEnumDecl(clang::EnumDecl* cppDecl);
        //bool TraverseEnumConstantDecl(clang::EnumConstantDecl* cppDecl);
        // TODO handle constexpr
        bool TraverseVarDecl(clang::VarDecl* cppDecl);
        bool TraverseUsingDirectiveDecl(clang::UsingDirectiveDecl* cppDecl);
        // FIXME I have no idea what this is.
        bool TraverseEmptyDecl(clang::EmptyDecl* cppDecl);

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

        // Also gets cxx method/ctor/dtor
        bool VisitFunctionDecl(clang::FunctionDecl * Declaration);
        bool VisitTypedefDecl(clang::TypedefDecl * decl);
        bool VisitParmVarDecl(clang::ParmVarDecl* cppDecl);
        bool VisitNamedDecl(clang::NamedDecl* cppDecl);

        static void enableDeclarationsInFiles(const std::vector<std::string>& filenames);

        static const std::unordered_map<clang::Decl*, std::shared_ptr<Declaration>>& getDeclarations()
        {
            return declarations;
        }
        static const std::unordered_set<std::shared_ptr<Declaration>>& getFreeDeclarations()
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
