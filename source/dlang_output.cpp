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
#include "cpp_decl.hpp"

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

void dlang::DOutputContext::putItem(const string& text)
{
    if( text.size() == 0 ) return;
    if( startingLine ) indent();
    else if( needSpaceBeforeNextItem ) output << " ";
    output << text;
    needSpaceBeforeNextItem = true;
    startingLine = false;
}

void dlang::DOutputContext::beginList(const string& symbol)
{
    if( listStatus != NO_LIST )
        throw std::runtime_error("Nested lists are not supported.");

    if( symbol.size() )
    {
        if( startingLine ) indent();
        output << symbol;
        needSpaceBeforeNextItem = false;
        startingLine = false;
    }
    listStatus = LIST_STARTED;
}

void dlang::DOutputContext::endList(const string& symbol)
{
    if( symbol.size() )
    {
        if( startingLine ) indent();
        output << symbol;
        needSpaceBeforeNextItem = true;
        startingLine = false;
    }
    listStatus = NO_LIST;
}

void dlang::DOutputContext::listItem()
{
    switch( listStatus )
    {
        case NO_LIST:
            throw std::runtime_error("Entered a list item while there was no list in progress.");
            break;
        case LIST_STARTED:
            listStatus = LONG_LIST;
            break;
        case LONG_LIST:
            if( startingLine ) indent();
            output << ",";
            needSpaceBeforeNextItem = true;
            startingLine = false;
            break;
    }
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

class PackagePathWriter : public dlang::PackageVisitor
{
    public:
    string result;
    PackagePathWriter()
        : result()
    { }

    virtual void visitPackage(const dlang::Package& package) override
    {
        if( package.getParent() )
        {
            package.getParent()->visit(*this);
        }

        if( package.getName().size() > 0 )
        {
            result += package.getName() + ".";
        }
    }

    virtual void visitModule(const dlang::Module& module) override
    {
        if( module.getParent() )
        {
            module.getParent()->visit(*this);
        }

        if( module.getName().size() > 0 )
        {
            result += module.getName() + ".";
        }
    }
};

class TypeWriter : public dlang::TypeVisitor
{
    dlang::DOutputContext& output;
    public:
    TypeWriter(dlang::DOutputContext& o)
        : output(o)
    { }

    virtual string writeModulePath(const dlang::FileDir& fd)
    {
        PackagePathWriter pkgWriter;
        fd.visit(pkgWriter);
        return pkgWriter.result;
    }

    virtual string writeContainingScope(const dlang::Declaration& decl)
    {
        // FIXME!
        dlang::Declaration * parent_decl = dynamic_cast<dlang::Declaration*>(decl.parent);
        string answer;
        if( parent_decl )
        {
            answer = writeContainingScope(*parent_decl);
        }
        else {
            dlang::FileDir * parent_module = dynamic_cast<dlang::FileDir*>(decl.parent);
            if( parent_module )
            {
                answer = writeModulePath(*parent_module);
            }
            else if( !dynamic_cast<const dlang::StringType*>(&decl) )
            {
                std::cerr << "WARNING: Cannot produce scope for decl " << decl.name << " derived from (" << decl.derived_from << "):\n";
                //decl.derived_from->decl()->dump();
            }
        }
        return answer;
    }

    virtual void visitString(const dlang::StringType& strType) override
    {
        output.putItem(strType.name);
    }

    virtual void visitStruct(const dlang::Struct& type) override
    {
        output.putItem(writeContainingScope(type) + type.name);
    }

    virtual void visitTypeAlias(const dlang::TypeAlias& type) override
    {
        output.putItem(writeContainingScope(type) + type.name);
    }
    virtual void visitEnum(const dlang::Enum& type) override
    {
        output.putItem(writeContainingScope(type) + type.name);
    }
    virtual void visitPointer(const dlang::PointerType& type) override
    {
        if( dlang::PointerType::REFERENCE == type.pointer_vs_ref )
        {
            output.putItem("ref");
        }
        type.target->visit(*this);

        if( dlang::PointerType::POINTER == type.pointer_vs_ref )
        {
            output.putItem("*");
        }
    }

    virtual void visitUnion(const dlang::Union& type) override
    {
        output.putItem(writeContainingScope(type) + type.name);
    }

    virtual void visitClass(const dlang::Class& type) override
    {
        output.putItem(writeContainingScope(type) + type.name);
    }

    virtual void visitInterface(const dlang::Interface& type) override
    {
        output.putItem(writeContainingScope(type) + type.name);
    }
};

class DeclarationWriter : public dlang::DeclarationVisitor
{
    dlang::Linkage current_linkage;
    dlang::DOutputContext& output;

    // RAII struct to track linkage
    struct LinkageSegment
    {
        DeclarationWriter& writer;
        dlang::Linkage old_linkage;
        LinkageSegment(DeclarationWriter& w, dlang::Linkage nl)
            : writer(w), old_linkage(writer.current_linkage)
        {
            if( nl.lang == dlang::LANG_C && old_linkage.lang != dlang::LANG_C )
            {
                writer.output.putItem("extern(C)");
            }
            else if( nl.lang == dlang::LANG_CPP && old_linkage.lang != dlang::LANG_CPP )
            {
                if( nl.name_space.size() > 0 && nl.name_space != "::" )
                {
                    if(   nl.name_space.size() > 2
                       && nl.name_space.c_str()[0] == ':'
                       && nl.name_space.c_str()[1] == ':' )
                    {
                        nl.name_space = string(nl.name_space.begin() + 2, nl.name_space.end());
                    }
                    writer.output.putItem(string("extern(C++, ") + nl.name_space + ")");
                }
                else
                {
                    writer.output.putItem("extern(C++)");
                }
            }
            else if( nl.lang == dlang::LANG_D && old_linkage.lang != dlang::LANG_D )
            {
                throw std::logic_error("Moving from non-D linkage to D linkage.  I need to think about this.");
            }
            else {
                throw std::logic_error("Unrecognized linkage language");
            }
        }

        ~LinkageSegment()
        {
            writer.current_linkage = old_linkage;
        }
    };
    public:
    explicit DeclarationWriter(dlang::DOutputContext& ctx)
        : current_linkage({dlang::LANG_D, ""}), output(ctx)
    { }

    virtual void visitFunction(const dlang::Function& function) override
    {
        LinkageSegment ls(*this, function.linkage);
        TypeWriter type(output);
        function.return_type->visit(type);

        output.putItem(function.name);

        output.beginList("(");
        for( auto arg : function.arguments )
        {
            output.listItem();
            visitArgument(*arg);
        }
        output.endList(")");

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

    virtual void visitVariable(const dlang::Variable& variable) override
    {
        LinkageSegment ls(*this, variable.linkage);
        TypeWriter type(output);
        variable.type->visit(type);

        output.putItem(variable.name);

        output.semicolon();
        output.newline();
        output.newline();
    }

    virtual void visitInterface(const dlang::Interface& interface) override
    {
        LinkageSegment ls(*this, interface.linkage);
        output.putItem("interface");
        output.putItem(interface.name);

        TypeWriter type(output);
        if( interface.superclasses.size() > 0 )
        {
            output.putItem(":");
            output.beginList("");
            for( std::shared_ptr<dlang::Interface> super : interface.superclasses )
            {
                output.listItem();
                super->visit(type);
            }
            output.endList("");
        }

        output.newline();

        output.putItem("{");
        output.newline();

        dlang::DOutputContext innerContext(output, 4);
        DeclarationWriter innerWriter(innerContext);
        for( auto method : interface.methods )
        {
            innerWriter.putVisibility(method->visibility);
            method->visit(innerWriter);
        }

        output.putItem("}");
        output.newline();
        output.newline();
    }

    virtual void visitStruct(const dlang::Struct& structure) override
    {
        LinkageSegment ls(*this, structure.linkage);
        output.putItem("struct");
        output.putItem(structure.name);
        output.newline();

        output.putItem("{");
        output.newline();

        dlang::DOutputContext innerContext(output, 4);
        DeclarationWriter innerWriter(innerContext);
        for( auto field : structure.getChildren() )
        {
            innerWriter.putVisibility(field->visibility);
            field->visit(innerWriter);
        }

        output.newline();
        for( auto method : structure.methods )
        {
            innerWriter.putVisibility(method->visibility);
            innerWriter.visitMethod(*method, false);
        }

        output.putItem("}");
        output.newline();
        output.newline();
    }

    virtual void visitClass(const dlang::Class&) override
    {
        throw std::logic_error("TODO: implement DeclarationWriter::visitClass()");
    }

    virtual void visitTypeAlias(const dlang::TypeAlias& aliasDecl) override
    {
        output.putItem("alias");
        output.putItem(aliasDecl.name);

        output.putItem("=");

        TypeWriter type(output);
        aliasDecl.target_type->visit(type);

        output.semicolon();
        output.newline();
    }

    virtual void visitEnum(const dlang::Enum& enumDecl) override
    {
        output.putItem("enum");
        output.putItem(enumDecl.name);
        output.newline();

        output.putItem("{");

        dlang::DOutputContext innerContext(output, 4);
        DeclarationWriter innerWriter(innerContext);

        innerContext.beginList("");
        for( auto field : enumDecl.values )
        {
            innerContext.listItem();
            innerContext.newline();
            field->visit(innerWriter);
        }
        innerContext.endList("");
        output.newline();

        output.putItem("}");
        output.newline();
        output.newline();
    }

    virtual void visitEnumConstant(const dlang::EnumConstant& constant) override
    {
        output.putItem(constant.name);
        output.putItem("=");
        output.putItem(constant.value.toString(10).c_str());
    }

    virtual void visitField(const dlang::Field& field) override
    {
        TypeWriter type(output);
        field.type->visit(type);

        output.putItem(field.name);
        output.semicolon();
        output.newline();
    }

    void visitMethod(const dlang::Method& method, bool displayFinal)
    {
        switch( method.kind )
        {
            case dlang::Method::STATIC:
                output.putItem("static");
                break;
            case dlang::Method::FINAL:
                if( displayFinal )
                {
                    output.putItem("final");
                }
                break;
            case dlang::Method::VIRTUAL:
                break;
        }

        TypeWriter type(output);
        method.return_type->visit(type);

        output.putItem(method.name);
        output.beginList("(");
        for( auto arg : method.arguments )
        {
            output.listItem();
            visitArgument(*arg);
        }
        output.endList(")");
        output.semicolon();
        output.newline();
    }

    virtual void visitMethod(const dlang::Method& method) override
    {
        visitMethod(method, true);
    }

    virtual void visitUnion(const dlang::Union&) override
    {
        throw std::logic_error("TODO: implement DeclarationWriter::visitUnion()");
    }

    private:
    void putVisibility(dlang::Visibility visibility)
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
        boost::filesystem::path sub_path(path_prefix / package.getName().c_str());
        boost::filesystem::create_directory(sub_path);
        for( auto child : package.getChildren() )
        {
            PackageWriter sub_writer(sub_path);
            child.second->visit(sub_writer);
        }
    }

    virtual void visitModule(const dlang::Module& module) override
    {
        boost::filesystem::path module_path(path_prefix / (module.getName() + ".d").c_str());
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
