#ifndef __CLANG_AST_VISITOR_HPP__
#define __CLANG_AST_VISITOR_HPP__

#include <iostream>
#include <set>

#include "clang/AST/RecursiveASTVisitor.h"

#include "cpp_type.hpp"

extern const clang::SourceManager * source_manager;

namespace cpp {

    class ASTVisitor : public clang::RecursiveASTVisitor<ASTVisitor>
    {
        private:
        Type * type_in_progress;

        public:
        typedef clang::RecursiveASTVisitor<ASTVisitor> Super;

        ASTVisitor();

        std::set<clang::FunctionDecl*> functions;

        void maybeInsertType(clang::QualType qType);

        bool TraverseDecl(clang::Decl * Declaration);
        bool TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration);
        bool TraverseClassTemplateSpecializationDecl(clang::ClassTemplateSpecializationDecl* declaration);
        bool TraverseCXXMethodDecl(clang::CXXMethodDecl* Declaration);
        bool TraverseCXXConstructorDecl(clang::CXXConstructorDecl* Declaration);
        bool VisitFunctionDecl(clang::FunctionDecl * Declaration);

        bool VisitTypedefDecl(clang::TypedefDecl * decl);
        bool VisitBuiltinType(clang::BuiltinType * type);
    };
} // namespace cpp

#endif // __CLANG_AST_VISITOR_HPP__
