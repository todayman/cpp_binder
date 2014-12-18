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

import core.exception : RangeError;
import std.stdio : stdout;

static import binder;
static import unknown;

enum Visibility
{
    PRIVATE,
    PACKAGE,
    PROTECTED,
    PUBLIC,
    EXPORT,
}

interface PackageVisitor
{
    public:
    void visitPackage(in Package pack);
    void visitModule(in Module mod);
}
interface DeclarationVisitor
{
    public:
    void visitFunction(in Function);
    void visitArgument(in Argument);
    void visitVariable(in Variable);
    void visitInterface(in Interface);
    void visitStruct(in Struct);
    void visitClass(in Class);
    void visitTypeAlias(in TypeAlias);
    void visitEnum(in Enum);
    void visitEnumConstant(in EnumConstant);
    void visitField(in Field);
    void visitUnion(in Union);
    void visitMethod(in Method);
}
interface TypeVisitor
{
    public:
    void visitString(const StringType);
    void visitStruct(const Struct);
    void visitTypeAlias(const TypeAlias);
    void visitEnum(const Enum);
    void visitPointer(const PointerType);
    void visitUnion(const Union);
    void visitClass(const Class);
    void visitInterface(const Interface);
}


class Declaration
{
    public:
    string name;
    DeclarationContainer parent;
    Visibility visibility;
    unknown.Declaration derived_from;

    this(unknown.Declaration df)
    {
        name = "";
        parent = null;
        visibility = Visibility.PRIVATE;
        derived_from = df;
    }

    abstract void visit(DeclarationVisitor visitor) const;
}

interface DeclarationContainer
{
    void insert(Declaration decl);
    inout(Declaration)[] getChildren() inout;
}

mixin template DeclContainerImpl()
{
    private Declaration[] children;
    void insert(Declaration decl)
    {
        children ~= decl;
        decl.parent = this;
    }

    inout(Declaration)[] getChildren() inout
    {
        return children;
    }
}

enum Language
{
    C,
    CPP,
    D
}

struct Linkage
{
    Language lang;
    string name_space;
}

// Needs to be separate from declarations for builtins like int that don't have declarations
interface Type
{
    public:
    void visit(TypeVisitor visitor) const;
}

class StringType : Type
{
    public:
    string name;

    this(string n)
    {
        name = n;
    }

    override
    void visit(TypeVisitor visitor) const
    {
        visitor.visitString(this);
    }
}

class PointerType : Type
{
    public:
    enum PointerOrRef {
        POINTER,
        REFERENCE
    };
    PointerOrRef pointer_vs_ref;
    Type target;
    /* An idea for how to handle classes:
    // True when the target of this pointer is a reference type, i.e. a class
    // Usages of this type then omit the (*) or (ref) indicator
    bool points_to_reference_type;
    */

    this(Type tgt, PointerOrRef p)
    {
        pointer_vs_ref = p;
        target = tgt;
    }

    override
    void visit(TypeVisitor visitor) const
    {
        visitor.visitPointer(this);
    }
}

// Need a superclass for Module and Package to use Composite pattern
interface FileDir
{
    public:
    string getName() const;

    inout(Package) getParent() inout;

    void visit(PackageVisitor visitor) const;
}

mixin template FileDirImpl()
{
    override inout(Package) getParent() inout
    {
        return parent;
    }
}

class Module : DeclarationContainer, FileDir
{
    private:
    string name;
    Package parent;

    public:
    this(string n, Package p)
    {
        name = n;
        parent = p;
    }

    override string getName() const
    {
        return name;
    }

    mixin DeclContainerImpl!();
    mixin FileDirImpl!();

    override
    void visit(PackageVisitor visitor) const
    {
        visitor.visitModule(this);
    }
}

class Package : FileDir
{
    private:
    string name;
    Package parent;
    FileDir[string] children;

    FileDir findChild(string path, out string remainder)
    {
        import std.algorithm : findSplit;
        auto search_result = findSplit(path, ".");
        remainder = search_result[2];

        if (search_result[0].length == 0)
        {
            throw new Exception("Attempted to find the package / module with the empty name ("")");
        }

        try {
            return children[search_result[0]];
        }
        catch (RangeError e)
        {
            return null;
        }
    }
    public:
    this(string n, Package p)
    {
        name = n;
        parent = p;
    }

    ref const (FileDir[string]) getChildren() const
    {
        return children;
    }

    override
    void visit(PackageVisitor visitor) const
    {
        visitor.visitPackage(this);
    }

    // These return weak pointers because every package is owned by its
    // parent, and the root package owns all the top level packages.
    // Not entirely sure that's the right choice, though.
    Result findForName(Result)(string path)
    {
        string rest_of_path;
        FileDir search_result = findChild(path, rest_of_path);
        if (search_result !is null) // FIXME
        {
            return null;
        }

        if (!rest_of_path.empty)
        {
            // This means that there are more letters after the dot,
            // so the current name is a package name, so recurse
            Package subpackage = cast(Package)search_result;
            if( subpackage )
            {
                return subpackage.findForName!Result(rest_of_path);
            }
            else
            {
                return null;
            }
        }
        else
        {
            return cast(Result)(search_result);
        }
    }

    Module getOrCreateModulePath(string path)
    {
        string rest_of_path;
        // rest of path is a string containing everything after the first '.'
        auto search_result = findChild(path, rest_of_path);
        if (search_result is null)
        {
            // Create
            if (rest_of_path.length == 0)
            {
                string next_name = path[];
                Module mod = new Module(next_name, this);
                FileDir result = mod;
                children[next_name] = result;
                return mod;
            }
            else {
                //When there is more than one path element, you also need to take off
                // the '.' between elements, but not when there is only one.
                string next_name = path[0 .. ($ - rest_of_path.length)];
                Package pack = new Package(next_name, this);
                FileDir result = pack;
                children[next_name] = result;
                return pack.getOrCreateModulePath(rest_of_path);
            }
        }

        // Entry exists, and this is not the end of the path
        if (rest_of_path.length > 0)
        {
            // This means that there are more letters after the dot,
            // so the current name is a package name, so recurse
            Package subpackage = cast(Package)(search_result);
            if (subpackage)
            {
                return subpackage.getOrCreateModulePath(rest_of_path);
            }
            else
            {
                // This is a module, but expected a package name
                // FIXME error message needs work.
                throw new Exception("Looking up a module ("~path~") by its path, but found a module where there should be a package, so I cannot continue.");
            }
        }
        else
        {
            // entry exists, and this is the end of the path
            Module mod = cast(Module)(search_result);
            if (!mod)
            {
                // This is a package, but expected a module
                throw new Exception("Looking up a module (" ~path ~") by its path, but found a package where there should be a module, so I cannot continue.");
            }
            else
            {
                return mod;
            }
        }
    }

    override string getName() const
    {
        return name;
    }

    mixin FileDirImpl!();
}

// FIXME has some commonality with Function
class Method : Declaration
{
    public:
    enum Kind {
        VIRTUAL,
        STATIC,
        FINAL
    }
    Kind kind;
    Type return_type;
    Argument[] arguments;

    this(unknown.Declaration cpp)
    {
        super(cpp);
        kind = Kind.VIRTUAL;
    }

    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitMethod(this);
    }
}

class Struct : Declaration, Type, DeclarationContainer
{
    public:
    Linkage linkage;
    Struct superclass;
    Method[] methods;

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(TypeVisitor visitor) const
    {
        visitor.visitStruct(this);
    }
    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitStruct(this);
    }

    mixin DeclContainerImpl!();
}

class Class : Declaration, Type, DeclarationContainer
{
    public:
    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitClass(this);
    }

    override
    void visit(TypeVisitor visitor) const
    {
        visitor.visitClass(this);
    }

    mixin DeclContainerImpl!();
}

class Field : Declaration
{
    public:
    Type type;
    Visibility visibility;
    // const, immutable, etc.

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitField(this);
    }
}

class Interface : Declaration, Type, DeclarationContainer
{
    public:
    Linkage linkage;
    Interface[] superclasses;
    Declaration[] methods;

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitInterface(this);
    }

    override
    void visit(TypeVisitor visitor) const
    {
        visitor.visitInterface(this);
    }

    mixin DeclContainerImpl!();
}

class Variable : Declaration
{
    public:
    Linkage linkage;
    Type type;

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitVariable(this);
    }
}

class Argument : Declaration
{
    public:
    Type type;

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitArgument(this);
    }
}

class Function : Declaration
{
    public:
    Type return_type;
    Argument[] arguments;
    Linkage linkage;

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitFunction(this);
    }
};

class TypeAlias : Declaration, Type
{
    public:
    Type target_type;

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(TypeVisitor visitor) const
    {
        visitor.visitTypeAlias(this);
    }
    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitTypeAlias(this);
    }
};

class EnumConstant : Declaration
{
    public:
    //llvm::APSInt value;
    long value;

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitEnumConstant(this);
    }
};

class Enum : Declaration, Type
{
    public:
    Type type;
    EnumConstant[] values;

    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(TypeVisitor visitor) const
    {
        visitor.visitEnum(this);
    }
    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitEnum(this);
    }
};

class Union : Declaration, Type, DeclarationContainer
{
    public:
    this(unknown.Declaration cpp)
    {
        super(cpp);
    }

    override
    void visit(TypeVisitor visitor) const
    {
        visitor.visitUnion(this);
    }
    override
    void visit(DeclarationVisitor visitor) const
    {
        visitor.visitUnion(this);
    }

    mixin DeclContainerImpl!();
};

Package rootPackage;

static this()
{
    rootPackage = new Package("", null);
}
