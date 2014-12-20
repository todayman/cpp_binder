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

import std.d.formatter;

import dlang_decls;

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
        /*DOutputContext output = new DOutputContext(outputFile, 0);
        output.putItem("module");
        output.putItem(mod.getName());
        output.semicolon();
        output.newline();
        output.newline();*/

        foreach (const(std.d.ast.Declaration) decl ; mod.getChildren())
        {
            format(delegate (string s) => (outputFile.write(s)), decl);
            /*DOutputContext sub_output = new DOutputContext(outputFile, 0);
            DeclarationWriter writer = new DeclarationWriter(sub_output);
            decl.visit(writer);*/
        }
    }
};

// This is mostly here so that the header doesn't depend on boost
void produceOutputForPackage(Package pack, string path_prefix)
{
    PackageWriter writer = new PackageWriter(path_prefix);
    pack.visit(writer);
}
