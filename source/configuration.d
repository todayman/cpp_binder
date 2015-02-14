/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014-2015 Paul O'Neil <redballoon36@gmail.com>
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

import std.algorithm : map;
import std.conv : to;
import std.file;
import std.string : toStringz, fromStringz, toLower;
import std.c.string;

import yajl.c.tree;

static import binder;
static import unknown;
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

class ExpectedNObjects : ConfigurationException
{
    public:
    this(ref const(yajl_val_s) container, size_t expected_count)
    {
        super("Dummy");
        msg = "Expected an object with " ~ to!string(expected_count) ~
            " elements, but found " ~ to!string(container.object.len) ~
            " instead.";
    }
}

class UnknownVisibility : ConfigurationException
{
    public:
    // TODO add context
    this(string str)
    {
        super("Unknown visibiility \"" ~ str ~"\".");
    }
}

class ExpectedDDecl : ConfigurationException
{
    public this(ref const(yajl_val_s))
    {
        super("Expected a \"d_decl\" entry for the REPLACE translation strategy.");
    }
}

class UnrecognizedAttribute : ConfigurationException
{
    public this(string attrib)
    {
        super("Unrecognized attribute \"" ~ attrib ~ "\".");
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

bool YAJL_IS_INTEGER(const yajl_val val)
{
    return val.type == yajl_type.yajl_t_number;
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
    for (size_t idx = 0; idx < obj.object.len; ++idx)
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
        if (!sub_obj)
        {
            throw new ExpectedString(null);
        }

        if (!YAJL_IS_STRING(sub_obj))
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

void parseAndApplyConfiguration(string[] config_files, clang.ASTUnit* astunit)
{
    foreach (filename; config_files)
    {
        applyConfigFromFile(filename, astunit);
    }
}

private void applyConfigFromFile(string filename, clang.ASTUnit* astunit)
{
    yajl_val_s* tree_root = parseJSON(filename);
    applyRootObjectForAttributes(*tree_root, astunit);
}

private void applyRootObjectForAttributes(ref const(yajl_val_s) obj, clang.ASTUnit* astunit)
{
    foreach (size_t idx; 0 .. obj.object.len)
    {
        ulong length = strlen(obj.object.keys[idx]);
        // TODO can probably avoid dup-ing the string
        string name = obj.object.keys[idx][0 .. length].idup;
        const yajl_val_s* sub_obj = obj.object.values[idx];

        if (!sub_obj)
        {
            throw new ExpectedObject(null);
        }

        if (name == "clang_args")
        {
            continue;
        }
        else if (name == "binding_attributes")
        {
            if (!YAJL_IS_OBJECT(sub_obj))
            {
                throw new ExpectedObject(sub_obj);
            }
            applyConfigToObjectMap(*sub_obj, astunit);
        }
        else
        {
            throw new ConfigurationException("Unexpected top-level key \"" ~ name ~ "\".");
        }
    }
}

private void applyConfigToObjectMap(ref const yajl_val_s obj, clang.ASTUnit* astunit)
{
    foreach (size_t idx; 0 .. obj.object.len)
    {
        ulong length = strlen(obj.object.keys[idx]);
        // TODO can probably avoid dup-ing the string
        string name = obj.object.keys[idx][0 .. length].idup;
        const yajl_val_s* sub_obj = obj.object.values[idx];

        if (!sub_obj || !YAJL_IS_OBJECT(sub_obj))
        {
            throw new ExpectedObject(null);
        }
        
        unknown.DeclarationAttributes decl_attributes = unknown.DeclarationAttributes.make();
        unknown.TypeAttributes type_attributes = unknown.TypeAttributes.make();

        parseAttributes(*sub_obj, &decl_attributes, &type_attributes);

        unknown.applyConfigToObject(binder.toBinderString(name), astunit, decl_attributes, type_attributes);
    }
}

private void parseAttributes(ref const yajl_val_s obj, unknown.DeclarationAttributes* decl_attributes, unknown.TypeAttributes* type_attributes)
in {
    assert(YAJL_IS_OBJECT(&obj));
}
body {
    foreach (size_t idx; 0 .. obj.object.len)
    {
        ulong length = strlen(obj.object.keys[idx]);
        // TODO can probably avoid dup-ing the string
        string attrib_name = obj.object.keys[idx][0 .. length].idup;
        const yajl_val_s* sub_obj = obj.object.values[idx];

        // TODO get these string constants out of here
        // TODO change to a hash table of functions??
        if (attrib_name == "bound" )
        {
            // FIXME bools might come through as strings
            if (!YAJL_IS_INTEGER(sub_obj))
            {
                throw new ExpectedInteger(sub_obj);
            }
            decl_attributes.setBound(to!bool(sub_obj.number.i));
        }
        else if (attrib_name == "target_module")
        {
            if (!YAJL_IS_STRING(sub_obj))
            {
                throw new ExpectedString(sub_obj);
            }
            // TODO kill the idup
            string str = fromStringz(sub_obj.string).idup;
            decl_attributes.setTargetModule(binder.toBinderString(str));
            type_attributes.setTargetModule(binder.toBinderString(str));
        }
        else if (attrib_name == "visibility")
        {
            if (!YAJL_IS_STRING(sub_obj))
            {
                throw new ExpectedString(sub_obj);
            }
            // TODO kill the idup
            string vis_str = fromStringz(sub_obj.string).idup;
            vis_str = toLower(vis_str);
            if (vis_str == "private")
            {
                decl_attributes.setVisibility(unknown.Visibility.PRIVATE);
            }
            else if (vis_str == "package")
            {
                decl_attributes.setVisibility(unknown.Visibility.PACKAGE);
            }
            else if (vis_str == "protected")
            {
                decl_attributes.setVisibility(unknown.Visibility.PROTECTED);
            }
            else if (vis_str == "public")
            {
                decl_attributes.setVisibility(unknown.Visibility.PUBLIC);
            }
            else if(vis_str == "export")
            {
                decl_attributes.setVisibility(unknown.Visibility.EXPORT);
            }
            else {
                throw new UnknownVisibility(vis_str);
            }
        }
        else if (attrib_name == "remove_prefix")
        {
            if (!YAJL_IS_STRING(sub_obj))
            {
                throw new ExpectedString(sub_obj);
            }
            // TODO kill the idup
            string str = fromStringz(sub_obj.string).idup;
            decl_attributes.setRemovePrefix(binder.toBinderString(str));
        }
        else if (attrib_name == "strategy")
        {
            if (!YAJL_IS_OBJECT(sub_obj))
            {
                throw new ExpectedObject(sub_obj);
            }
            readStrategyConfiguration(*sub_obj, type_attributes);
        }
        else {
            // throw UnrecognizedAttribute(attrib_name);
            // TODO I think I should just log this instead
            throw new UnrecognizedAttribute(attrib_name);
        }
    }
}

private void readStrategyConfiguration(ref const yajl_val_s container, unknown.TypeAttributes* type_attributes)
{
    foreach (size_t idx; 0 .. container.object.len)
    {
        if ("name" == fromStringz(container.object.keys[idx]) )
        {
            const yajl_val name_obj = container.object.values[idx];
            if (!YAJL_IS_STRING(name_obj))
            {
                throw new ExpectedString(name_obj);
            }

            // TODO kill the idup
            string name_str = toLower(fromStringz(name_obj.string)).idup;
            if (name_str == "replace")
            {
                if (container.object.len != 2)
                {
                    throw new ExpectedNObjects(container, 2);
                }

                // If this attribute is "replace", then the other must be d_decl
                // TODO kill the idup
                string tag_name = fromStringz(container.object.keys[1 - idx]).idup;
                if ("d_decl" != tag_name)
                {
                    throw new ExpectedDDecl(container);
                }

                const yajl_val target_obj = container.object.values[1 - idx];
                if (!YAJL_IS_STRING(target_obj))
                {
                    throw new ExpectedString(target_obj);
                }

                // TODO kill the idup
                string str = fromStringz(target_obj.string).idup;
                type_attributes.setStrategy(unknown.Strategy.REPLACE);
                type_attributes.setTargetName(binder.toBinderString(str));
            }
            else if (name_str == "struct")
            {
                type_attributes.setStrategy(unknown.Strategy.STRUCT);
            }
            else if (name_str == "interface")
            {
                type_attributes.setStrategy(unknown.Strategy.INTERFACE);
            }
            else if (name_str == "class")
            {
                type_attributes.setStrategy(unknown.Strategy.CLASS);
            }
            else if (name_str == "opaque_class")
            {
                type_attributes.setStrategy(unknown.Strategy.OPAQUE_CLASS);
            }
        }
    }
}
