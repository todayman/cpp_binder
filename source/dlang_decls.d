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

import std.d.ast;

static import binder;
static import unknown;

interface PackageVisitor
{
    public:
    void visitPackage(in Package pack);
    void visitModule(in Module mod);
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

class Module : FileDir
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

    mixin FileDirImpl!();
    private std.d.ast.Declaration[] children;
    void insert(std.d.ast.Declaration decl)
    {
        children ~= decl;
    }

    inout(std.d.ast.Declaration)[] getChildren() inout
    {
        return children;
    }

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

Package rootPackage;

static this()
{
    rootPackage = new Package("", null);
}
