#include <iostream>
#include <set>

#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Basic/SourceManager.h"

#include "cpp_type.hpp"
#include "clang_ast_visitor.hpp"

using namespace cpp;

void printPresumedLocation(const clang::NamedDecl* Declaration)
{
    clang::SourceLocation source_loc = Declaration->getLocation();
    clang::PresumedLoc presumed = source_manager->getPresumedLoc(source_loc);

    std::cout << Declaration->getNameAsString() << " at " << presumed.getFilename() << ":" << presumed.getLine() << "\n";
}

TypeVisitor::TypeVisitor()
    : clang::RecursiveASTVisitor<TypeVisitor>(),
    type_to_traverse(nullptr), type_in_progress(nullptr)
{ }

bool TypeVisitor::TraverseType(clang::QualType type)
{
    type_to_traverse = type.getTypePtrOrNull();
    if( !type_to_traverse )
        return false;
    if( Type::type_map.find(type_to_traverse) != Type::type_map.end() )
        return true;

    return Super::TraverseType(type);
}

void TypeVisitor::allocateType(const clang::Type * t, Type::Kind k)
{
    type_in_progress = std::make_shared<Type>(t, k);
    Type::type_map.insert(std::make_pair(t, type_in_progress));
}

#define WALK_UP_METHOD(KIND) \
bool TypeVisitor::WalkUpFrom##KIND##Type( clang::KIND##Type * type) \
{ \
    allocateType(type, Type::KIND); \
    return Super::WalkUpFrom##KIND##Type(type); \
}
WALK_UP_METHOD(Builtin);
WALK_UP_METHOD(Pointer);
bool TypeVisitor::WalkUpFromLValueReferenceType( clang::LValueReferenceType* type)
{
    allocateType(type, Type::Reference);
    return Super::WalkUpFromLValueReferenceType(type);
}

bool TypeVisitor::WalkUpFromRecordType(clang::RecordType* type)
{
    if( type->isStructureType() || type->isClassType() )
    {
        allocateType(type, Type::Record);
    }
    else if( type->isUnionType() )
    {
        allocateType(type, Type::Union);
    }
    return Super::WalkUpFromRecordType(type);
}
WALK_UP_METHOD(Array);
WALK_UP_METHOD(Function);
WALK_UP_METHOD(Typedef);
WALK_UP_METHOD(Vector);
WALK_UP_METHOD(Enum);

bool TypeVisitor::WalkUpFromRValueReferenceType(clang::RValueReferenceType* cppType)
{
    throw SkipRValueRef(cppType);
}

bool TypeVisitor::WalkUpFromMemberPointerType(clang::MemberPointerType* cppType)
{
    throw SkipMemberPointer(cppType);
}

bool TypeVisitor::WalkUpFromType(clang::Type* type)
{
    if( !type_in_progress )
        throw NotWrappableException(type);

    if( type->isInstantiationDependentType() )
        throw SkipTemplate(type);

    return Super::WalkUpFromType(type);
}

bool TypeVisitor::VisitPointerType(clang::PointerType* cppType)
{
    TypeVisitor pointeeVisitor;
    return pointeeVisitor.TraverseType(cppType->getPointeeType());
}

bool TypeVisitor::VisitRecordType(clang::RecordType* cppType)
{
    bool continue_traversal = true;
    const clang::RecordDecl * decl = cppType->getDecl();
    // Recurse down all of the fields of the record
    if( !decl->field_empty() )
    {
        clang::RecordDecl::field_iterator end = decl->field_end();
        TypeVisitor field_visitor;
        for( clang::RecordDecl::field_iterator iter = decl->field_begin();
                iter != end && continue_traversal; ++iter )
        {
            field_visitor.reset();
            continue_traversal = field_visitor.TraverseType(iter->getType());
        }
    }

    return continue_traversal;
}

bool TypeVisitor::VisitArrayType(clang::ArrayType* cppType)
{
    TypeVisitor element_visitor;
    return element_visitor.TraverseType(cppType->getElementType());
}

bool TypeVisitor::VisitFunctionType(clang::FunctionType* cppType)
{
    bool continue_traversal = true;
    TypeVisitor arg_visitor; // Also visits return type
    continue_traversal = arg_visitor.TraverseType(cppType->getResultType());

    // TODO get all the arguments

    return continue_traversal;
}

bool TypeVisitor::VisitLValueReferenceType(clang::LValueReferenceType* cppType)
{
    TypeVisitor target_visitor;
    return target_visitor.TraverseType(cppType->getPointeeType());
}

bool TypeVisitor::VisitTypedefType(clang::TypedefType* cppType)
{
    TypeVisitor real_visitor;
    return real_visitor.TraverseType(cppType->desugar());
}

bool TypeVisitor::WalkUpFromElaboratedType(clang::ElaboratedType* type)
{
    return TraverseType(type->getNamedType());
}

bool TypeVisitor::WalkUpFromDecayedType(clang::DecayedType* type)
{
    return TraverseType(type->getDecayedType());
}

bool TypeVisitor::WalkUpFromParenType(clang::ParenType* type)
{
    return TraverseType(type->getInnerType());
}

bool TypeVisitor::WalkUpFromDecltypeType(clang::DecltypeType* type)
{
    return TraverseType(type->getUnderlyingType());
}

bool TypeVisitor::WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type)
{
    throw SkipTemplate(type);
}

bool TypeVisitor::WalkUpFromTemplateTypeParmType(clang::TemplateTypeParmType* type)
{
    throw SkipTemplate(type);
}

bool TypeVisitor::WalkUpFromSubstTemplateTypeParmType(clang::SubstTemplateTypeParmType* type)
{
    throw SkipTemplate(type);
}

ASTVisitor::ASTVisitor()
{ }

bool ASTVisitor::TraverseDecl(clang::Decl * Declaration)
{
    if( !Declaration ) // FIXME sometimes Declaration is null.  I don't know why.
        return true;
    if( Declaration->isTemplateDecl() ) {
       std::cout << "Skipping templated declaration";
        switch (Declaration->getKind()) {
            case clang::Decl::Function:
            case clang::Decl::Record:
            case clang::Decl::CXXRecord:
            case clang::Decl::CXXMethod:
            case clang::Decl::ClassTemplate:
            case clang::Decl::FunctionTemplate:
                // These ones have names, so we can print them out
                std::cout << " " << static_cast<clang::NamedDecl*>(Declaration)->getNameAsString();
                break;
            default:
                break;
        }
        std::cout << ". \n";
    }
    else {
        RecursiveASTVisitor<ASTVisitor>::TraverseDecl(Declaration);
    }

    return true;
}

bool ASTVisitor::TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration)
{
    std::cout << "Skipping partially specialized template declaration " << declaration->getNameAsString() << ".\n";
    return true;
}

bool ASTVisitor::TraverseClassTemplateSpecializationDecl(clang::ClassTemplateSpecializationDecl* declaration)
{
    std::cout << "Skipping specialized template declaration " << declaration->getNameAsString() << ".\n";
    return true;
}

bool ASTVisitor::TraverseCXXMethodDecl(clang::CXXMethodDecl* Declaration)
{
    const clang::CXXRecordDecl * parent_decl = Declaration->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<ASTVisitor>::TraverseCXXMethodDecl(Declaration);
    }

    return true;
}

bool ASTVisitor::TraverseCXXConstructorDecl(clang::CXXConstructorDecl* Declaration)
{
    const clang::CXXRecordDecl * parent_decl = Declaration->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<ASTVisitor>::TraverseCXXConstructorDecl(Declaration);
    }

    return true;
}

void ASTVisitor::maybeInsertType(clang::QualType qType)
{
    // TODO could this really be NULL?
    // under what circumstances is that the case, and do I have to
    // worry about it?
    const clang::Type * cppType = qType.getTypePtr();
    decltype(Type::type_map)::iterator iter = Type::type_map.find(cppType);
    if( iter != Type::type_map.end() ) {
        return;
    }

    TypeVisitor type_visitor;
    type_visitor.TraverseType(qType);
}

bool ASTVisitor::VisitFunctionDecl(clang::FunctionDecl * Declaration)
{
    clang::QualType return_type = Declaration->getResultType();

    std::cout << "Found function ";
    printPresumedLocation(Declaration);
    std::cout << "  with return type " << return_type.getAsString() << "\n";
    try {
        maybeInsertType(return_type);

        std::cout << "  argument types:\n";
        for( clang::ParmVarDecl** iter = Declaration->param_begin();
             iter != Declaration->param_end();
             iter++ )
        {
            clang::QualType arg_type = (*iter)->getType();
            std::cout << "\t" << arg_type.getAsString() << "\n";
            maybeInsertType(arg_type);
        }
        functions.insert(Declaration);
    }
    catch( cpp::SkipUnwrappableDeclaration& e)
    {
        std::cout << "WARNING: " << e.what() << "\n";
    }
    return true;
}

bool ASTVisitor::VisitTypedefDecl(clang::TypedefDecl * decl)
{
    //assert(output_type == nullptr);
    std::cout << "name = " << decl->getNameAsString() << "\n";
    Super::VisitTypedefDecl(decl);


    return true;
}

