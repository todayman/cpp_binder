#include <iostream>
#include <fstream>
#include <stdexcept>

#include "boost/filesystem.hpp"

#include "dlang_output.hpp"

dlang::DOutputContext::DOutputContext(std::ostream& strm, int indentLevel)
    : needSpaceBeforeNextItem(false), listStatus(NO_LIST),
      startingLine(true), indentationLevel(indentLevel), output(strm)
{ }

void dlang::DOutputContext::indent()
{
    for( int i = 0; i < indentationLevel; ++i )
    {
        output << " ";
    }
}

void dlang::DOutputContext::putItem(const std::string& text)
{
    if( startingLine ) indent();
    else if( needSpaceBeforeNextItem ) output << " ";
    output << text;
    needSpaceBeforeNextItem = true;
    startingLine = false;
}

void dlang::DOutputContext::beginList()
{
    if( listStatus != NO_LIST )
        throw std::runtime_error("Nested lists are not supported.");

    if( startingLine ) indent();
    output << "(";
    needSpaceBeforeNextItem = false;
    listStatus = LIST_STARTED;
    startingLine = false;
}

void dlang::DOutputContext::endList()
{
    if( startingLine ) indent();
    output << ")";
    needSpaceBeforeNextItem = true;
    listStatus = NO_LIST;
    startingLine = false;
}

void dlang::DOutputContext::listItem()
{
    if( startingLine ) indent();
    switch( listStatus )
    {
        case NO_LIST:
            throw std::runtime_error("Entered a list item while there was no list in progress.");
            break;
        case LIST_STARTED:
            break;
        case LONG_LIST:
            output << ",";
            needSpaceBeforeNextItem = true;
            break;
    }
    startingLine = false;
}

void dlang::DOutputContext::newline()
{
    output << "\n";
    startingLine = true;
}

void dlang::DOutputContext::semicolon()
{
    if( startingLine ) indent();
    output << ";";
    startingLine = false;
}

class TypeWriter : public dlang::TypeVisitor
{
    dlang::DOutputContext& output;
    public:
    TypeWriter(dlang::DOutputContext& o)
        : output(o)
    { }

    virtual void visitString(const dlang::StringType& strType) override
    {
        output.putItem(strType.name);
    }
    virtual void visitStruct(const dlang::Struct&) override { }
    virtual void visitTypeAlias(const dlang::TypeAlias&) override { }
    virtual void visitEnum(const dlang::Enum&) override { }
    virtual void visitPointer(const dlang::PointerType&) override { }
};

class DeclarationWriter : public dlang::DeclarationVisitor
{
    dlang::DOutputContext output;
    public:
    explicit DeclarationWriter(std::ostream& o, int indentLevel)
        : output(o, indentLevel)
    { }

    virtual void visitFunction(const dlang::Function& function) override
    {
        if( function.linkage.lang == dlang::LANG_C )
        {
            output.putItem("extern(C)");
        }
        else if( function.linkage.lang == dlang::LANG_CPP )
        {
            if( function.linkage.name_space.size() > 0 )
            {
                output.putItem(std::string("extern(C++, ") + function.linkage.name_space + ")");
            }
            else
            {
                output.putItem("extern(C++)");
            }
        }
        else {
            throw 25;
        }
        TypeWriter type(output);
        function.return_type->visit(type);

        output.putItem(function.name);

        output.beginList();
        for( auto arg : function.arguments )
        {
            visitArgument(*arg);
        }
        output.endList();

        output.semicolon();
        output.newline();
        output.newline();
    }

    virtual void visitArgument(const dlang::Argument& argument) override
    {
        TypeWriter type(output);
        argument.type->visit(type);
        if( argument.name.size() > 0 )
        {
            output.putItem(argument.name);
        }
    }
    virtual void visitVariable(const dlang::Variable&) override { }
    virtual void visitInterface(const dlang::Interface&) override { }
    virtual void visitStruct(const dlang::Struct&) override { }
    virtual void visitClass(const dlang::Class&) override { }
    virtual void visitTypeAlias(const dlang::TypeAlias&) override { }
    virtual void visitEnum(const dlang::Enum&) override { }
    virtual void visitEnumConstant(const dlang::EnumConstant&) override { }
};

class PackageWriter : public dlang::PackageVisitor
{
    boost::filesystem::path path_prefix;
    public:
    explicit PackageWriter(boost::filesystem::path prefix)
        : path_prefix(prefix)
    { }

    virtual void visitPackage(const dlang::Package& package) override
    {
        boost::filesystem::path sub_path(path_prefix / package.getName());
        boost::filesystem::create_directory(sub_path);
        for( auto child : package.getChildren() )
        {
            PackageWriter sub_writer(sub_path);
            child.second->visit(sub_writer);
        }
    }

    virtual void visitModule(const dlang::Module& module) override
    {
        boost::filesystem::path module_path(path_prefix / (module.getName() + ".d"));
        std::ofstream outputFile(module_path.c_str(), std::ios::out);
        dlang::DOutputContext output(outputFile, 0);
        output.putItem("module");
        output.putItem(module.getName());
        output.semicolon();
        output.newline();
        output.newline();

        for( std::shared_ptr<dlang::Declaration> decl : module.getChildren() )
        {
            DeclarationWriter writer(outputFile, 0);
            decl->visit(writer);
        }
    }
};

// This is mostly here so that the header doesn't depend on boost
void produceOutputForPackage(dlang::Package& pack)
{
    PackageWriter writer(".");
    pack.visit(writer);
}
