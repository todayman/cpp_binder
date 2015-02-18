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
import std.exception : enforce;
import std.file;
import std.json;
import std.string : toStringz, fromStringz, toLower;
import std.c.string;

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
    this(in JSONValue)
    {
        super("Expected JSON object, got something like number, array, etc.");
    }
}

class ExpectedInteger : ConfigurationException
{
    this(in JSONValue)
    {
        super("Expected JSON integer, got something like object, array, etc.");
    }
}

class ExpectedArray : ConfigurationException
{
    this(in JSONValue)
    {
        super("Expected JSON array, got something like number, object, etc.");
    }
}

class ExpectedString : ConfigurationException
{
    this(in JSONValue)
    {
        super("Expected JSON string, got something like number, object, etc.");
    }
}

class ExpectedNObjects : ConfigurationException
{
    public:
    this(in JSONValue container, size_t expected_count)
    {
        super("Dummy");
        msg = "Expected an object with " ~ to!string(expected_count) ~
            " elements, but found " ~ to!string(container.object.length) ~
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
    public this(in JSONValue)
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

private JSONValue parseJSON(string filename)
{
    string config_contents = readFile(filename);

    return std.json.parseJSON(config_contents);
}

private void applyRootObjectForClang(in JSONValue obj, ref string[] clang_args)
{
    enforce(obj.type == JSON_TYPE.OBJECT);
    foreach (name, sub_obj; obj.object)
    {
        if (name == "clang_args")
        {
            if (sub_obj.type != JSON_TYPE.ARRAY)
            {
                throw new ExpectedArray(sub_obj);
            }
            collectClangArguments(sub_obj, clang_args);
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

private void collectClangArguments(in JSONValue obj, ref string[] clang_args)
in {
    assert(obj.type == JSON_TYPE.ARRAY);
}
body {
    foreach (ref const sub_obj; obj.array)
    {
        if (sub_obj.type != JSON_TYPE.STRING)
        {
            throw new ExpectedString(sub_obj);
        }
        clang_args ~= sub_obj.str;
    }
}

private void applyClangConfig(string filename, ref string[] clang_args)
{
    JSONValue tree_root = parseJSON(filename);
    applyRootObjectForClang(tree_root, clang_args);
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
    JSONValue tree_root = parseJSON(filename);
    applyRootObjectForAttributes(tree_root, astunit);
}

private void applyRootObjectForAttributes(in JSONValue obj, clang.ASTUnit* astunit)
{
    foreach (name, ref const sub_obj; obj.object)
    {
        if (name == "clang_args")
        {
            continue;
        }
        else if (name == "binding_attributes")
        {
            if (sub_obj.type != JSON_TYPE.OBJECT)
            {
                throw new ExpectedObject(sub_obj);
            }
            applyConfigToObjectMap(sub_obj, astunit);
        }
        else
        {
            throw new ConfigurationException("Unexpected top-level key \"" ~ name ~ "\".");
        }
    }
}

private void applyConfigToObjectMap(in JSONValue obj, clang.ASTUnit* astunit)
{
    foreach (name, ref const sub_obj; obj.object)
    {
        if (sub_obj.type != JSON_TYPE.OBJECT)
        {
            throw new ExpectedObject(sub_obj);
        }
        
        unknown.DeclarationAttributes decl_attributes = unknown.DeclarationAttributes.make();
        unknown.TypeAttributes type_attributes = unknown.TypeAttributes.make();

        parseAttributes(sub_obj, &decl_attributes, &type_attributes);

        unknown.applyConfigToObject(binder.toBinderString(name), astunit, decl_attributes, type_attributes);
    }
}

private void parseAttributes(in JSONValue obj, unknown.DeclarationAttributes* decl_attributes, unknown.TypeAttributes* type_attributes)
{
    foreach (attrib_name, ref const sub_obj; obj.object)
    {
        // TODO get these string constants out of here
        // TODO change to a hash table of functions??
        if (attrib_name == "bound" )
        {
            // FIXME bools might come through as strings
            if (sub_obj.type != JSON_TYPE.INTEGER)
            {
                throw new ExpectedInteger(sub_obj);
            }
            decl_attributes.setBound(to!bool(sub_obj.integer));
        }
        else if (attrib_name == "target_module")
        {
            if (sub_obj.type != JSON_TYPE.STRING)
            {
                throw new ExpectedString(sub_obj);
            }
            decl_attributes.setTargetModule(binder.toBinderString(sub_obj.str));
            type_attributes.setTargetModule(binder.toBinderString(sub_obj.str));
        }
        else if (attrib_name == "visibility")
        {
            if (sub_obj.type != JSON_TYPE.STRING)
            {
                throw new ExpectedString(sub_obj);
            }
            string vis_str = sub_obj.str;
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
            if (sub_obj.type != JSON_TYPE.STRING)
            {
                throw new ExpectedString(sub_obj);
            }
            decl_attributes.setRemovePrefix(binder.toBinderString(sub_obj.str));
        }
        else if (attrib_name == "strategy")
        {
            if (sub_obj.type != JSON_TYPE.OBJECT)
            {
                throw new ExpectedObject(sub_obj);
            }
            readStrategyConfiguration(sub_obj, type_attributes);
        }
        else {
            // throw UnrecognizedAttribute(attrib_name);
            // TODO I think I should just log this instead
            throw new UnrecognizedAttribute(attrib_name);
        }
    }
}

private void readStrategyConfiguration(in JSONValue container, unknown.TypeAttributes* type_attributes)
{
    bool setTargetName = false;
    foreach (name, ref const obj; container.object)
    {
        if ("name" == name)
        {
            if (obj.type != JSON_TYPE.STRING)
            {
                throw new ExpectedString(obj);
            }

            string name_str = obj.str;
            if (name_str == "replace")
            {
                if (container.object.length != 2)
                {
                    throw new ExpectedNObjects(container, 2);
                }

                type_attributes.setStrategy(unknown.Strategy.REPLACE);
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
        else if ("d_decl" == name)
        {
            if (obj.type != JSON_TYPE.STRING)
            {
                throw new ExpectedString(obj);
            }
            type_attributes.setTargetName(binder.toBinderString(obj.str));
            setTargetName = true;
        }
    }

    if (type_attributes.getStrategy() == unknown.Strategy.REPLACE && !setTargetName)
    {
        throw new ExpectedDDecl(container);
    }
}
