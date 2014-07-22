#ifndef __CPP_DECL_HPP__
#define __CPP_DECL_HPP__

#include "clang/AST/Decl.h"
#include "clang/AST/RecursiveASTVisitor.h"

#include "cpp_type.hpp"
#include "cpp_exception.hpp"

namespace cpp
{
    // Same thing as Type, but for declarations of functions,
    // classes, etc.
    class Declaration
    {
        // Attributes!
        // Pointer to D declaration!
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
        virtual const clang::Decl* decl() override { \
            return _decl; \
        } \
    }
#define DECLARATION_CLASS(KIND) DECLARATION_CLASS_2(KIND, KIND)
DECLARATION_CLASS(Function);
DECLARATION_CLASS(Namespace);
DECLARATION_CLASS(Record);
DECLARATION_CLASS(Typedef);
DECLARATION_CLASS(Enum);
DECLARATION_CLASS(Field);
DECLARATION_CLASS(EnumConstant); // TODO change this to a generic constant class

DECLARATION_CLASS_2(Record, Union);
DECLARATION_CLASS_2(CXXMethod, Method);
DECLARATION_CLASS_2(CXXConstructor, Constructor);
DECLARATION_CLASS_2(CXXDestructor, Destructor);
DECLARATION_CLASS_2(ParmVar, Argument);
DECLARATION_CLASS_2(Var, Variable);

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
        }

        bool registerDeclaration(clang::Decl* cppDecl);

        static std::unordered_map<clang::Decl*, std::shared_ptr<Declaration>> declarations;

        std::shared_ptr<Declaration> decl_in_progress;

        bool TraverseDeclContext(clang::DeclContext * cpp_context);
        public:
        typedef clang::RecursiveASTVisitor<DeclVisitor> Super;

        DeclVisitor();

        bool TraverseType(clang::QualType type)
        {
            Type::get(type);
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
    };

    class SkipUnwrappableDeclaration : public NotWrappableException
    {
        public:
        SkipUnwrappableDeclaration(clang::Decl*)
        { }
    };

    class SkipDeclarationBecauseType : public SkipUnwrappableDeclaration
    {
        // I'm not actually sure what the rules are here about
        // the lifetime of the cause, but I'm going to try this
        // until I find out it's completely broken. FIXME?
        private:
        const SkipUnwrappableType& cause;

        public:
        SkipDeclarationBecauseType(clang::Decl * cppDecl, SkipUnwrappableType& c)
            : SkipUnwrappableDeclaration(cppDecl), cause(c)
        { }

        const SkipUnwrappableType& getCause() const
        {
            return cause;
        }
    };

} // namespace cpp

extern const clang::SourceManager * source_manager;

#endif // __CPP_DECL_HPP__
