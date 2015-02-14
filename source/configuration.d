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

module configuration;

import std.file;
import std.string : toStringz;
import std.c.string;

import yajl.c.tree;

import manual_types;

class ConfigurationException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

class ExpectedObject : ConfigurationException
{
    this(const yajl_val_s*)
    {
        super("Expected JSON object, got something like number, array, etc.");
    }
}

class ExpectedInteger : ConfigurationException
{
    this(const yajl_val_s*)
    {
        super("Expected JSON integer, got something like object, array, etc.");
    }
}

class ExpectedArray : ConfigurationException
{
    this(const yajl_val_s*)
    {
        super("Expected JSON array, got something like number, object, etc.");
    }
}

class ExpectedString : ConfigurationException
{
    this(const yajl_val_s*)
    {
        super("Expected JSON string, got something like number, object, etc.");
    }
}

string readFile(string filename)
{
    return cast(string)read(filename);
}

bool YAJL_IS_OBJECT(const yajl_val val)
{
    return val.type == yajl_type.yajl_t_object;
}

bool YAJL_IS_ARRAY(const yajl_val val)
{
    return val.type == yajl_type.yajl_t_array;
}

bool YAJL_IS_STRING(const yajl_val val)
{
    return val.type == yajl_type.yajl_t_string;
}

private yajl_val_s * parseJSON(string filename)
{
    string config_contents = readFile(filename);
    enum BUFFER_SIZE = 512;
    char[BUFFER_SIZE] error_buffer;

    yajl_val tree_root = yajl_tree_parse(toStringz(config_contents), error_buffer.ptr, BUFFER_SIZE);
    if (!tree_root)
    {
        throw new ConfigurationException(error_buffer.idup);
    }

    if (!YAJL_IS_OBJECT(tree_root))
    {
        throw new ExpectedObject(tree_root);
    }

    return tree_root;
}

private void applyRootObjectForClang(ref yajl_val_s obj, ref string[] clang_args)
{
    for( size_t idx = 0; idx < obj.object.len; ++idx )
    {
        ulong length = strlen(obj.object.keys[idx]);
        string name = obj.object.keys[idx][0 .. length].idup;
        const yajl_val_s* sub_obj = obj.object.values[idx];
        if( !sub_obj )
        {
            throw new ExpectedObject(null);
        }

        if (name == "clang_args")
        {
            if (!YAJL_IS_ARRAY(sub_obj))
            {
                throw new ExpectedArray(sub_obj);
            }
            collectClangArguments(*sub_obj, clang_args);
        }
        else if (name == "binding_attributes")
        {
            continue;
        }
        else {
            throw new ConfigurationException("Unexpected top-level key \"" ~ name ~ "\".");
        }
    }
}

private void collectClangArguments(const ref yajl_val_s obj, ref string[] clang_args)
{
    for( size_t idx = 0; idx < obj.array.len; ++idx )
    {
        const yajl_val_s* sub_obj = obj.array.values[idx];
        if( !sub_obj )
        {
            throw new ExpectedString(null);
        }

        if( !YAJL_IS_STRING(sub_obj) )
        {
            throw new ExpectedString(sub_obj);
        }
        ulong length = strlen(sub_obj.string);
        clang_args ~= sub_obj.string[0 .. length].idup;
    }
}

private void applyClangConfig(string filename, ref string[] clang_args)
{
    yajl_val_s * tree_root = parseJSON(filename);
    applyRootObjectForClang(*tree_root, clang_args);
}

string[] parseClangArgs(string[] config_files)
{
    string[] clang_args = new string[0];

    foreach (string filename; config_files)
    {
        applyClangConfig(filename, clang_args);
    }

    return clang_args;
}
