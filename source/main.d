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

module main;

import std.stdio;

import cli;
import configuration;
import manual_types;
import unknown;
import translate.decls;
import dlang_decls : rootPackage;
import dlang_output;

extern(C++) __gshared const(clang.SourceManager)* source_manager = null;

int main(string[] argv)
{
    CLIArguments args;
    if (!parse_args(argv, args))
    {
        return -1;
    }

    string[] clang_args;
    try {
        clang_args = parseClangArgs(args.config_files);
    }
    catch (ConfigurationException exc)
    {
        stderr.writeln("ERROR: ", exc.msg);
        return -1;
    }

    char*[] raw_clang_args = new char*[clang_args.length];
    foreach (ulong idx, string str; clang_args)
    {
        raw_clang_args[idx] = toStringz(str)[0 .. str.length+1].dup.ptr;
    }

    string contents;
    foreach (filename; args.header_files)
    {
        contents ~= "#include \"" ~ filename ~ "\"\n";
    }

    // FIXME potential collisions with cpp_binder.cpp will really confuse clang
    // If you pass a header here and the source #includes that header,
    // then clang recurses infinitely
    char* contentz = toStringz(contents)[0 .. contents.length+1].dup.ptr;
    clang.ASTUnit* ast = buildAST(contentz, raw_clang_args.length, raw_clang_args.ptr, "cpp_binder.cpp".dup.ptr);
    traverseDeclsInAST(ast);

    const(char)*[] raw_files = new char*[args.header_files.length];
    foreach (ulong idx, string str; args.header_files)
    {
        raw_files[idx] = toStringz(str);
    }
    enableDeclarationsInFiles(raw_files.length, raw_files.ptr);

    const(char)*[] raw_config_files = new char*[args.config_files.length];
    foreach (ulong idx, string str; args.config_files)
    {
        raw_config_files[idx] = toStringz(str);
    }
    try {
        parseAndApplyConfiguration(raw_config_files.length, raw_config_files.ptr, ast);
    }
    catch (ConfigurationException exc)
    {
        stderr.writeln("ERROR: ", exc.msg);
        return -1;
    }

    try {
        populateDAST();
    }
    catch (Exception exc)
    {
        stderr.writeln("ERROR: ", exc.msg);
        return -1;
    }

    if (args.output_dir.length == 0)
        produceOutputForPackage(rootPackage, ".");
    else
        produceOutputForPackage(rootPackage, args.output_dir);

    return 0;
}
