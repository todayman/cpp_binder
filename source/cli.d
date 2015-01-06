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

module cli;

import std.stdio;

struct CLIArguments
{
    string[] config_files;
    string[] header_files;
    string output_dir;
}

bool parse_args(string[] argv, out CLIArguments args)
{
    bool setOutput = false;

    for (int cur_arg_idx = 1; cur_arg_idx < argv.length; ++cur_arg_idx)
    {
        string arg_str = argv[cur_arg_idx];
        if (arg_str == "config_file" || arg_str == "-c")
        {
            cur_arg_idx += 1;
            if (cur_arg_idx == argv.length)
            {
                stderr.writeln("ERROR: Expected path to configuration file after ", arg_str, ".");
                return false;
            }
            args.config_files ~= argv[cur_arg_idx];
        }
        else if (arg_str == "--output" || arg_str == "-o")
        {
            if (setOutput)
            {
                stderr.writeln("ERROR: Only one output directory may be specified.");
                return false;
            }

            cur_arg_idx += 1;
            if (cur_arg_idx == argv.length)
            {
                stderr.writeln("ERROR: Expected path to output directory after ", arg_str, ".");
                return false;
            }
            args.output_dir = argv[cur_arg_idx];
            setOutput = true;
        }
        else
        {
            args.header_files ~= arg_str;
        }
    }

    if (args.header_files.length == 0)
    {
        stderr.writeln("ERROR: No input files specified.");
        return false;
    }

    if( args.config_files.length == 0)
    {
        stderr.writeln("WARNING: No configuration files found.  I will not know how to translate basic types like \"int\".  Diving into the abyss.  You did tell me to, after all.");
    }

    return true;
}