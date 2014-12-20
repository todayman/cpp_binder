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

import std.array : Appender, join;
import std.file : exists, isDir, mkdir;
import std.path;
import std.stdio;

import std.d.ast;
import std.d.formatter;
import std.d.lexer;

import dlang_decls;

void visitModule(const Module mod, string path_prefix)
{
    Appender!string path_appender;
    path_appender.put(path_prefix);
    foreach (Token t; mod.moduleDeclaration.moduleName.identifiers)
    {
        path_appender.put(dirSeparator);
        path_appender.put(t.text);
    }
    path_appender.put(".d");
    File outputFile = File(path_appender.data, "w");
    format(delegate (string s) => (outputFile.write(s)), mod);
}

void produceOutputForPackage(Package pack, string path_prefix)
{
    foreach (const Module mod; pack.children.byValue)
    {
        visitModule(mod, path_prefix);
    }
}
