#include <iostream>
#include <unordered_map>

#include "cpp_decl.hpp"
#include "dlang_decls.hpp"

std::shared_ptr<dlang::Type> translateType(clang::QualType);

std::unordered_map<cpp::Declaration*, std::shared_ptr<dlang::Declaration>> translated;

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

#define CHECK_FOR_DECL(x) \
        auto search = translated.find(static_cast<cpp::Declaration*>(&cppDecl)); \
        if( search != translated.end() ) \
        { \
            return std::dynamic_pointer_cast<dlang::x>(search->second); \
        }
// ^ This cast failing is a huge internal programmer error

// Would kind of like a WhiteHole for these
class TranslatorVisitor : public cpp::DeclarationVisitor
{
    std::string parent_package_name;
    std::shared_ptr<dlang::Declaration> last_result;
    public:

    explicit TranslatorVisitor(std::string parent)
        : parent_package_name(parent), last_result()
    { }

    std::shared_ptr<dlang::Function> translateFunction(cpp::FunctionDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Function)

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
    virtual void visitFunction(cpp::FunctionDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateFunction(cppDecl));
    }

    std::shared_ptr<dlang::Module> translateNamespace(cpp::NamespaceDeclaration& cppDecl)
    {
        // TODO I probably shouldn't even be doing this,
        // just looping over all of the items in the namespace and setting the
        // target_module attribute (if it's not already set),
        // and then visiting those nodes.  Then the modules / packages get
        // created when something goes in them.
        auto search = translated.find(static_cast<cpp::Declaration*>(&cppDecl));
        std::shared_ptr<dlang::Module> module;
        if( search != translated.end() )
        {
            // This cast failing means that we previously translated this
            // namespace as something other than a module, which is a really
            // bad logic error.
            module = std::dynamic_pointer_cast<dlang::Module>(search->second);
            if( !module )
            {
                throw std::logic_error("Translated a namespace to something other than a module.");
            }
        }
        else
        {
            module = std::make_shared<dlang::Module>(cppDecl.getName());
        }

        std::string this_package_name = parent_package_name + "." + module->getName();
        for( cpp::DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             children_iter != children_end;
             ++children_iter )
        {
            if( (*children_iter)->isTargetModuleSet() )
            {
                (*children_iter)->setTargetModule(this_package_name);
            }
        }

        // visit and translate all of the children
        TranslatorVisitor subpackage_visitor(this_package_name);
        for( cpp::DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             children_iter != children_end;
             ++children_iter )
        {
            (*children_iter)->visit(subpackage_visitor);

            // TODO place the result of translation into the correct module
        }

        return module;
    }

    virtual void visitNamespace(cpp::NamespaceDeclaration& cppDecl) override
    {
        translateNamespace(cppDecl);
        last_result = std::shared_ptr<dlang::Declaration>();
    }

    virtual void visitRecord(cpp::RecordDeclaration& cppDecl) override
    {
    }
    std::shared_ptr<dlang::TypeAlias> translateTypedef(cpp::TypedefDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(TypeAlias)

        std::shared_ptr<dlang::TypeAlias> result = std::make_shared<dlang::TypeAlias>();
        result->name = cppDecl.getName();
        result->target_type = translateType(cppDecl.getTargetType());

        return result;
    }
    virtual void visitTypedef(cpp::TypedefDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateTypedef(cppDecl));
    }

    std::shared_ptr<dlang::Enum> translateEnum(cpp::EnumDeclaration& cppDecl)
    {
        std::shared_ptr<dlang::Enum> result = std::make_shared<dlang::Enum>();

        result->type = translateType(cppDecl.getType());

        // visit and translate all of the constants
        for( cpp::DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             children_iter != children_end;
             ++children_iter )
        {
            std::shared_ptr<cpp::EnumConstantDeclaration> constant = std::dynamic_pointer_cast<cpp::EnumConstantDeclaration>(*children_iter);
            if( !constant )
            {
                std::cout << "Error translating enum constant.\n";
                continue;
            }

            result->values.push_back(translateEnumConstant(*constant));
        }

        return result;
    }
    virtual void visitEnum(cpp::EnumDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateEnum(cppDecl));
    }

    std::shared_ptr<dlang::EnumConstant> translateEnumConstant(cpp::EnumConstantDeclaration& cppDecl)
    {
        std::shared_ptr<dlang::EnumConstant> result = std::make_shared<dlang::EnumConstant>();
        result->name = cppDecl.getName(); // TODO remove prefix
        result->value = cppDecl.getValue();

        return result;
    }
    virtual void visitEnumConstant(cpp::EnumConstantDeclaration&) override
    {
        // Getting here means that there is an enum constant declaration
        // outside of an enum declaration, since visitEnum calls
        // translateEnumConstant directly.
        throw 14;
    }
    virtual void visitField(cpp::FieldDeclaration& cppDecl) override
    {
    }
    virtual void visitUnion(cpp::UnionDeclaration& cppDecl) override
    {
    }
    virtual void visitMethod(cpp::MethodDeclaration& cppDecl) override
    {
    }
    virtual void visitConstructor(cpp::ConstructorDeclaration& cppDecl) override
    {
    }
    virtual void visitDestructor(cpp::DestructorDeclaration& cppDecl) override
    {
    }

    std::shared_ptr<dlang::Argument> translateArgument(cpp::ArgumentDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Argument)
        std::shared_ptr<dlang::Argument> arg = std::make_shared<dlang::Argument>();
        arg->name = cppDecl.getName();
        arg->type = translateType(cppDecl.getType());

        return arg;
    }
    virtual void visitArgument(cpp::ArgumentDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateArgument(cppDecl));
    }

    std::shared_ptr<dlang::Variable> translateVariable(cpp::VariableDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Variable)
        std::shared_ptr<dlang::Variable> var = std::make_shared<dlang::Variable>();
        var->name = cppDecl.getName();
        var->type = translateType(cppDecl.getType());

        return var;
    }
    virtual void visitVariable(cpp::VariableDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateVariable(cppDecl));
    }
    virtual void visitUnwrappable(cpp::UnwrappableDeclaration& cppDecl) override
    {
    }
};

void populateDAST()
{
    // May cause problems because root package won't check for empty path.
    TranslatorVisitor visitor("");
    for( auto declaration : cpp::DeclVisitor::getFreeDeclarations() )
    {
        if( !declaration->getShouldBind() || translated.count(declaration.get()) )
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
