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

#include <iostream>
#include <fstream>
#include <stdexcept>

#include "boost/filesystem.hpp"

#include "dlang_output.hpp"

dlang::DOutputContext::DOutputContext(std::ostream& strm, int indentLevel)
    : needSpaceBeforeNextItem(false), listStatus(NO_LIST),
      startingLine(true), indentationLevel(indentLevel), output(strm)
{ }

dlang::DOutputContext::DOutputContext(dlang::DOutputContext& ctx, int extraIndent)
    : needSpaceBeforeNextItem(false), listStatus(NO_LIST),
      startingLine(true), indentationLevel(ctx.indentationLevel + extraIndent),
      output(ctx.output)
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
    virtual void visitUnion(const dlang::Union&) override { }
};

class DeclarationWriter : public dlang::DeclarationVisitor
{
    dlang::DOutputContext& output;
    public:
    explicit DeclarationWriter(dlang::DOutputContext& ctx)
        : output(ctx)
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
    virtual void visitInterface(const dlang::Interface& interface) override
    {
        output.putItem("interface");
        output.putItem(interface.name);
        output.newline();

        output.putItem("{");
        output.newline();

        dlang::DOutputContext innerContext(output, 4);
        DeclarationWriter innerWriter(innerContext);
        for( auto method : interface.methods )
        {
            method->visit(innerWriter);
        }

        output.putItem("}");
        output.newline();
    }

    virtual void visitStruct(const dlang::Struct& structure) override
    {
        output.putItem("struct");
        output.putItem(structure.name);
        output.newline();

        output.putItem("{");
        output.newline();

        dlang::DOutputContext innerContext(output, 4);
        DeclarationWriter innerWriter(innerContext);
        for( auto field : structure.getChildren() )
        {
            field->visit(innerWriter);
        }

        output.newline();
        for( auto method : structure.methods )
        {
            method->visit(innerWriter);
        }

        output.putItem("}");
        output.newline();
    }

    virtual void visitClass(const dlang::Class&) override { }
    virtual void visitTypeAlias(const dlang::TypeAlias&) override { }
    virtual void visitEnum(const dlang::Enum&) override { }
    virtual void visitEnumConstant(const dlang::EnumConstant&) override { }

    virtual void visitField(const dlang::Field& field) override
    {
        putVisiblity(field.visibility);
        TypeWriter type(output);
        field.type->visit(type);

        output.putItem(field.name);
        output.semicolon();
        output.newline();
    }

    void visitMethod(const dlang::Method& method, bool displayFinal)
    {
        putVisiblity(method.visibility);

        if( displayFinal && !method.isVirtual )
            output.putItem("final");

        TypeWriter type(output);
        method.return_type->visit(type);

        output.putItem(method.name);
        output.beginList();
        for( auto arg : method.arguments )
        {
            visitArgument(*arg);
        }
        output.endList();
        output.semicolon();
        output.newline();
    }

    virtual void visitMethod(const dlang::Method& method) override
    {
        visitMethod(method, true);
    }

    virtual void visitUnion(const dlang::Union&) override { }

    private:
    void putVisiblity(dlang::Visibility visibility)
    {
        switch( visibility )
        {
            case dlang::PRIVATE:
                output.putItem("private");
                break;
            case dlang::PROTECTED:
                output.putItem("protected");
                break;
            case dlang::PUBLIC:
                output.putItem("public");
                break;
            case dlang::PACKAGE:
                output.putItem("package");
                break;
            case dlang::EXPORT:
                // FIXME I think this is an error for structs
                // I think it only makes sesnse for top-level functions
                output.putItem("export");
                break;
        }
    }
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
            dlang::DOutputContext output(outputFile, 0);
            DeclarationWriter writer(output);
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
