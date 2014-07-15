#ifndef __CLANG_AST_VISITOR_HPP__
#define __CLANG_AST_VISITOR_HPP__

#include <iostream>
#include <memory>
#include <set>

#include "clang/AST/RecursiveASTVisitor.h"

#include "cpp_type.hpp"

extern const clang::SourceManager * source_manager;

namespace cpp {

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

    class ASTVisitor : public clang::RecursiveASTVisitor<ASTVisitor>
    {
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
    };
} // namespace cpp

#endif // __CLANG_AST_VISITOR_HPP__
