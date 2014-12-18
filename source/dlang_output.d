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
module dlang_output;

import std.file : exists, isDir, mkdir;
import std.stdio;

import dlang_decls;

class DOutputContext
{
    private:
    bool needSpaceBeforeNextItem;

    enum ListStatus {
        NO_LIST,
        LIST_STARTED,
        LONG_LIST,
    }
    ListStatus listStatus;
    bool startingLine;
    int indentationLevel;

    File output;

    void indent()
    {
        foreach (i; 0 .. indentationLevel)
        {
            output.write(" ");
        }
    }

    public:
    this(File strm, int indentLevel = 0)
    {
        needSpaceBeforeNextItem = false;
        listStatus = ListStatus.NO_LIST;
        startingLine = true;
        indentationLevel = 0;
        output = strm;
    }
    this(ref DOutputContext ctx, int extraIndent = 0)
    {
        needSpaceBeforeNextItem = false;
        listStatus = ListStatus.NO_LIST;
        startingLine = true;
        indentationLevel = ctx.indentationLevel + extraIndent;
        output = ctx.output;
    }

    void putItem(string text)
    {
        if (text.length == 0) return;
        if (startingLine) indent();
        else if (needSpaceBeforeNextItem) output.write(" ");
        output.write(text);
        needSpaceBeforeNextItem = true;
        startingLine = false;
    }

    void beginList(string symbol)
    {
        if (listStatus != ListStatus.NO_LIST)
            throw new Exception("Nested lists are not supported.");

        if (symbol.length > 0)
        {
            if (startingLine) indent();
            output.write(symbol);
            needSpaceBeforeNextItem = false;
            startingLine = false;
        }
        listStatus = ListStatus.LIST_STARTED;
    }

    void endList(string symbol)
    {
        if (symbol.length > 0)
        {
            if (startingLine) indent();
            output.write(symbol);
            needSpaceBeforeNextItem = true;
            startingLine = false;
        }
        listStatus = ListStatus.NO_LIST;
    }

    void listItem() // FIXME this method is really clunky
    {
        final switch (listStatus)
        {
            case ListStatus.NO_LIST:
                throw new Exception("Entered a list item while there was no list in progress.");
                break;
            case ListStatus.LIST_STARTED:
                listStatus = ListStatus.LONG_LIST;
                break;
            case ListStatus.LONG_LIST:
                if (startingLine) indent();
                output.write(",");
                needSpaceBeforeNextItem = true;
                startingLine = false;
                break;
        }
    }

    void newline()
    {
        output.write("\n");
        startingLine = true;
    }
    void semicolon()
    {
        if (startingLine) indent();
        output.write(";");
        startingLine = false;
    }
}

class PackagePathWriter : PackageVisitor
{
    public:
    string result;
    this()
    {
        result = "";
    }

    override void visitPackage(const Package pack)
    {
        if (pack.getParent())
        {
            pack.getParent().visit(this);
        }

        if (pack.getName().length > 0)
        {
            result ~= pack.getName() ~ ".";
        }
    }

    override void visitModule(const Module mod)
    {
        if (mod.getParent())
        {
            mod.getParent().visit(this);
        }

        if (mod.getName().length > 0)
        {
            result ~= mod.getName() ~ ".";
        }
    }
}

class TypeWriter : TypeVisitor
{
    private DOutputContext output;
    public:
    this(DOutputContext o)
    {
        output = o;
    }

    string writeModulePath(const FileDir fd)
    {
        PackagePathWriter pkgWriter = new PackagePathWriter();
        fd.visit(pkgWriter);
        return pkgWriter.result;
    }

    string writeContainingScope(const Declaration decl)
    {
        // FIXME!
        Declaration parent_decl = cast(Declaration)(decl.parent);
        string answer;
        if(parent_decl)
        {
            answer = writeContainingScope(parent_decl) ~ parent_decl.name ~ ".";
        }
        else {
            FileDir parent_module = cast(FileDir)decl.parent;
            if (parent_module)
            {
                answer = writeModulePath(parent_module);
            }
            else if (!cast(StringType)decl)
            {
                //std::cerr << "WARNING: Cannot produce scope for decl " << decl.name << " derived from (" << decl.derived_from << "):\n";
                //decl.derived_from->decl()->dump();
            }
        }
        return answer;
    }

    override void visitString(const StringType strType)
    {
        output.putItem(strType.name);
    }

    override void visitStruct(const Struct type)
    {
        output.putItem(writeContainingScope(type) ~ type.name);
    }

    override void visitTypeAlias(const TypeAlias type)
    {
        output.putItem(writeContainingScope(type) ~ type.name);
    }
    override void visitEnum(const Enum type)
    {
        output.putItem(writeContainingScope(type) ~ type.name);
    }
    override void visitPointer(const PointerType type)
    {
        if( PointerType.PointerOrRef.REFERENCE == type.pointer_vs_ref)
        {
            output.putItem("ref");
        }
        type.target.visit(this);

        if (PointerType.PointerOrRef.POINTER == type.pointer_vs_ref)
        {
            output.putItem("*");
        }
    }

    override void visitUnion(const Union type)
    {
        output.putItem(writeContainingScope(type) ~ type.name);
    }

    override void visitClass(const Class type)
    {
        output.putItem(writeContainingScope(type) ~ type.name);
    }

    void visitInterface(const dlang_decls.Interface type)
    {
        output.putItem(writeContainingScope(type) ~ type.name);
    }
};

class DeclarationWriter : DeclarationVisitor
{
    Linkage current_linkage;
    DOutputContext output;

    // RAII struct to track linkage
    struct LinkageSegment
    {
        DeclarationWriter writer;
        Linkage old_linkage;
        this(DeclarationWriter w, Linkage nl)
        {
            writer = w;
            old_linkage = writer.current_linkage;

            if (nl.lang == Language.C && old_linkage.lang != Language.C)
            {
                writer.output.putItem("extern(C)");
            }
            else if (nl.lang == Language.CPP && old_linkage.lang != Language.CPP)
            {
                if (nl.name_space.length > 0 && nl.name_space != "::")
                {
                    if (   nl.name_space.length > 2
                        && nl.name_space[0] == ':'
                        && nl.name_space[1] == ':')
                    {
                        nl.name_space = nl.name_space[2 .. $];
                    }
                    writer.output.putItem("extern(C++, " ~ nl.name_space ~ ")");
                }
                else
                {
                    writer.output.putItem("extern(C++)");
                }
            }
            else if (nl.lang == Language.D && old_linkage.lang != Language.D )
            {
                throw new Error("Moving from non-D linkage to D linkage.  I need to think about this.");
            }
            else {
                throw new Error("Unrecognized linkage language");
            }
        }

        ~this()
        {
            writer.current_linkage = old_linkage;
        }
    };

    public:
    this(DOutputContext ctx)
    {
        current_linkage = Linkage(Language.D, "");
        output = ctx;
    }

    override void visitFunction(const Function func)
    {
        LinkageSegment ls = LinkageSegment(this, func.linkage);
        TypeWriter type = new TypeWriter(output);
        func.return_type.visit(type);

        output.putItem(func.name);

        output.beginList("(");
        foreach (arg ; func.arguments)
        {
            output.listItem();
            visitArgument(arg);
        }
        output.endList(")");

        output.semicolon();
        output.newline();
        output.newline();
    }

    override void visitArgument(const Argument argument)
    {
        TypeWriter type = new TypeWriter(output);
        argument.type.visit(type);
        if( argument.name.length > 0 )
        {
            output.putItem(argument.name);
        }
    }

    override void visitVariable(const Variable variable)
    {
        LinkageSegment ls = LinkageSegment(this, variable.linkage);
        TypeWriter type = new TypeWriter(output);
        variable.type.visit(type);

        output.putItem(variable.name);

        output.semicolon();
        output.newline();
        output.newline();
    }

    override void visitInterface(const dlang_decls.Interface inter)
    {
        LinkageSegment ls = LinkageSegment(this, inter.linkage);
        output.putItem("interface");
        output.putItem(inter.name);

        TypeWriter type = new TypeWriter(output);
        if (inter.superclasses.length > 0)
        {
            output.putItem(":");
            output.beginList("");
            foreach (const(dlang_decls.Interface) superclass; inter.superclasses)
            {
                output.listItem();
                superclass.visit(type);
            }
            output.endList("");
        }

        output.newline();

        output.putItem("{");
        output.newline();

        DOutputContext innerContext = new DOutputContext(output, 4);
        DeclarationWriter innerWriter = new DeclarationWriter(innerContext);
        foreach (method ; inter.methods)
        {
            innerWriter.putVisibility(method.visibility);
            method.visit(innerWriter);
        }

        output.putItem("}");
        output.newline();
        output.newline();
    }

    override void visitStruct(const Struct structure)
    {
        LinkageSegment ls = LinkageSegment(this, structure.linkage);
        output.putItem("struct");
        output.putItem(structure.name);
        output.newline();

        output.putItem("{");
        output.newline();

        DOutputContext innerContext = new DOutputContext(output, 4);
        DeclarationWriter innerWriter = new DeclarationWriter(innerContext);
        foreach (field; structure.getChildren())
        {
            innerWriter.putVisibility(field.visibility);
            field.visit(innerWriter);
        }

        output.newline();
        foreach (method ; structure.methods)
        {
            innerWriter.putVisibility(method.visibility);
            innerWriter.visitMethod(method, false);
        }

        output.putItem("}");
        output.newline();
        output.newline();
    }

    override void visitClass(const Class)
    {
        throw new Error("TODO: implement DeclarationWriter::visitClass()");
    }

    override void visitTypeAlias(const TypeAlias aliasDecl)
    {
        output.putItem("alias");
        output.putItem(aliasDecl.name);

        output.putItem("=");

        TypeWriter type = new TypeWriter(output);
        aliasDecl.target_type.visit(type);

        output.semicolon();
        output.newline();
    }

    override void visitEnum(const Enum enumDecl)
    {
        output.putItem("enum");
        output.putItem(enumDecl.name);
        output.newline();

        output.putItem("{");

        DOutputContext innerContext = new DOutputContext(output, 4);
        DeclarationWriter innerWriter = new DeclarationWriter(innerContext);

        innerContext.beginList("");
        foreach (field ; enumDecl.values)
        {
            innerContext.listItem();
            innerContext.newline();
            field.visit(innerWriter);
        }
        innerContext.endList("");
        output.newline();

        output.putItem("}");
        output.newline();
        output.newline();
    }

    override void visitEnumConstant(const EnumConstant constant)
    {
        import std.conv : to;
        output.putItem(constant.name);
        output.putItem("=");
        output.putItem(to!string(constant.value));
    }

    override void visitField(const Field field)
    {
        TypeWriter type = new TypeWriter(output);
        field.type.visit(type);

        output.putItem(field.name);
        output.semicolon();
        output.newline();
    }

    void visitMethod(const Method method, bool displayFinal)
    {
        final switch (method.kind)
        {
            case Method.Kind.STATIC:
                output.putItem("static");
                break;
            case Method.Kind.FINAL:
                if (displayFinal)
                {
                    output.putItem("final");
                }
                break;
            case Method.Kind.VIRTUAL:
                // TODO fill this in with an assert or something
                break;
        }

        TypeWriter type = new TypeWriter(output);
        method.return_type.visit(type);

        output.putItem(method.name);
        output.beginList("(");
        foreach (arg ; method.arguments)
        {
            output.listItem();
            visitArgument(arg);
        }
        output.endList(")");
        output.semicolon();
        output.newline();
    }

    override void visitMethod(const Method method)
    {
        visitMethod(method, true);
    }

    override void visitUnion(const Union)
    {
        throw new Error("TODO: implement DeclarationWriter::visitUnion()");
    }

    private:
    void putVisibility(dlang_decls.Visibility visibility)
    {
        final switch (visibility)
        {
            case Visibility.PRIVATE:
                output.putItem("private");
                break;
            case Visibility.PROTECTED:
                output.putItem("protected");
                break;
            case Visibility.PUBLIC:
                output.putItem("public");
                break;
            case Visibility.PACKAGE:
                output.putItem("package");
                break;
            case Visibility.EXPORT:
                // FIXME I think this is an error for structs
                // I think it only makes sesnse for top-level functions
                output.putItem("export");
                break;
        }
    }
};

class PackageWriter : PackageVisitor
{
    import std.array : join;
    import std.file : mkdir;
    import std.path;

    string path_prefix;
    public:
    this(string prefix)
    {
        path_prefix = prefix;
    }

    override void visitPackage(const Package pack)
    {
        string sub_path = join([path_prefix, pack.getName()], dirSeparator);
        if (!exists(sub_path))
        {
            mkdir(sub_path);
        }
        else if (!isDir(sub_path))
        {
            throw new Exception("Cannot create package because "~sub_path~" exists and is a file.");
        }
        foreach (child ; pack.getChildren().byValue)
        {
            PackageWriter sub_writer = new PackageWriter(sub_path);
            child.visit(sub_writer);
        }
    }

    override void visitModule(const Module mod)
    {
        string module_path = join([path_prefix, mod.getName() ~ ".d"], dirSeparator);
        File outputFile = File(module_path, "w");
        DOutputContext output = new DOutputContext(outputFile, 0);
        output.putItem("module");
        output.putItem(mod.getName());
        output.semicolon();
        output.newline();
        output.newline();

        foreach (const(Declaration) decl ; mod.getChildren())
        {
            DOutputContext sub_output = new DOutputContext(outputFile, 0);
            DeclarationWriter writer = new DeclarationWriter(sub_output);
            decl.visit(writer);
        }
    }
};

// This is mostly here so that the header doesn't depend on boost
void produceOutputForPackage(Package pack, string path_prefix)
{
    PackageWriter writer = new PackageWriter(path_prefix);
    pack.visit(writer);
}
