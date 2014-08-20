#include <unordered_map>

#include "cpp_decl.hpp"
#include "dlang_decls.hpp"

std::shared_ptr<dlang::Type> translateType(clang::QualType);

std::unordered_map<std::shared_ptr<cpp::Declaration>, std::shared_ptr<dlang::Declaration>> translated;

std::shared_ptr<dlang::Type> translateType(std::shared_ptr<cpp::Type> cppType)
{
    // TODO write
    return std::shared_ptr<dlang::Type>();
}

class TranslateArgument : public cpp::ConstDeclarationVisitor
{
    public:
    virtual void visitFunction(const cpp::FunctionDeclaration&) override { }
    virtual void visitNamespace(const cpp::NamespaceDeclaration&) override { }
    virtual void visitRecord(const cpp::RecordDeclaration&) override { }
    virtual void visitTypedef(const cpp::TypedefDeclaration&) override { }
    virtual void visitEnum(const cpp::EnumDeclaration&) override { }
    virtual void visitField(const cpp::FieldDeclaration&) override { }
    virtual void visitEnumConstant(const cpp::EnumConstantDeclaration&) override { }
    virtual void visitUnion(const cpp::UnionDeclaration&) override { }
    virtual void visitMethod(const cpp::MethodDeclaration&) override { }
    virtual void visitConstructor(const cpp::ConstructorDeclaration&) override { }
    virtual void visitDestructor(const cpp::DestructorDeclaration&) override { }
    virtual void visitVariable(const cpp::VariableDeclaration&) override { }
    virtual void visitUnwrappable(const cpp::UnwrappableDeclaration&) override { }

    virtual void visitArgument(const cpp::ArgumentDeclaration&) override
    {
    }
};

// Would kind of like a WhiteHole for these
class TranslatorVisitor : public cpp::ConstDeclarationVisitor
{
    std::shared_ptr<dlang::Declaration> last_result;
    public:
    std::shared_ptr<dlang::Function> translateFunction(const cpp::FunctionDeclaration& cppDecl)
    {
        std::shared_ptr<dlang::Function> d_decl = std::make_shared<dlang::Function>();
        if( cppDecl.getName().size() )
        {
            d_decl->name = cppDecl.getName();
        }
        else
        {
            throw 12;
        }

        d_decl->return_type = translateType(cppDecl.getReturnType());

        for( auto arg_iter = cppDecl.getArgumentBegin(), arg_end = cppDecl.getArgumentEnd();
             arg_iter != arg_end;
             ++arg_iter )
        {
            // FIXME double dereference? really?
            d_decl->arguments.push_back(translateArgument(**arg_iter));
        }
        return d_decl;
    }
    virtual void visitFunction(const cpp::FunctionDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateFunction(cppDecl));
    }

    virtual void visitNamespace(const cpp::NamespaceDeclaration& cppDecl) override
    {
    }
    virtual void visitRecord(const cpp::RecordDeclaration& cppDecl) override
    {
    }
    virtual void visitTypedef(const cpp::TypedefDeclaration& cppDecl) override
    {
    }
    virtual void visitEnum(const cpp::EnumDeclaration& cppDecl) override
    {
    }
    virtual void visitField(const cpp::FieldDeclaration& cppDecl) override
    {
    }
    virtual void visitEnumConstant(const cpp::EnumConstantDeclaration& cppDecl) override
    {
    }
    virtual void visitUnion(const cpp::UnionDeclaration& cppDecl) override
    {
    }
    virtual void visitMethod(const cpp::MethodDeclaration& cppDecl) override
    {
    }
    virtual void visitConstructor(const cpp::ConstructorDeclaration& cppDecl) override
    {
    }
    virtual void visitDestructor(const cpp::DestructorDeclaration& cppDecl) override
    {
    }

    std::shared_ptr<dlang::Argument> translateArgument(const cpp::ArgumentDeclaration& cppDecl)
    {
        std::shared_ptr<dlang::Argument> arg = std::make_shared<dlang::Argument>();
        arg->name = cppDecl.getName();
        arg->type = translateType(cppDecl.getType());

        return arg;
    }
    virtual void visitArgument(const cpp::ArgumentDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateArgument(cppDecl));
    }

    virtual void visitVariable(const cpp::VariableDeclaration& cppDecl) override
    {
    }
    virtual void visitUnwrappable(const cpp::UnwrappableDeclaration& cppDecl) override
    {
    }
};

void populateDAST()
{
    TranslatorVisitor visitor;
    for( auto declaration : cpp::DeclVisitor::getFreeDeclarations() )
    {
        if( !declaration->getShouldBind() || translated.count(declaration) )
        {
            continue;
        }

        declaration->visit(visitor);
    }
}

// Assigns each declaration to an
void assignDeclarationModules()
{
}
