/*
 *  test_runner: runs the tests for cpp_binder
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

module test_runner;

import std.algorithm : filter, findSplit, map;
import std.array;
import std.file;
import std.json;
import std.path;
import std.process : execute, spawnProcess, wait;
import std.range : put, zip;
import std.stdio;
import std.uuid;

import core.exception : RangeError;

import std.d.ast;
import std.d.lexer;
import std.d.parser;

private string myTmpDir;

int parse_args(string[] args, out string executable, out string test_directory)
{
    if (args.length < 3)
    {
        stderr.writeln("Usage: test_runner <executable> <directory containing tests>");
        return -1;
    }

    executable = args[1];
    test_directory = args[2];
    if (!exists(executable))
    {
        stderr.writeln("The path you specified to the executable does not exist: ", executable);
        return -1;
    }
    if (!isFile(executable))
    {
        stderr.writeln("The path you specified to the executable is not a file: ", executable);
        return -1;
    }

    if (!exists(test_directory))
    {
        stderr.writeln("The path you specified to the executable does not exist: ", test_directory);
        return -1;
    }
    if (!isDir(test_directory))
    {
        stderr.writeln("The path you specified to the executable is not a directory: ", test_directory);
        return -1;
    }

    return 0;
}

struct TestCase
{
    string directory;
    string[] configurationFiles;
    string[] inputFiles;
    string[] expectedOutputFiles;
    string[] relativeOutputFiles;
    string cmd;

    void configure(string directory)
    {
        this.directory = directory;

        string configFilePath = join([directory, "test.json"], dirSeparator);
        if (!exists(configFilePath))
        {
            fail("Could not find test configuration " ~ configFilePath);
        }
        if (!isFile(configFilePath))
        {
            fail("Configuration is not a file: " ~ configFilePath);
        }

        string configString = readText(configFilePath);
        JSONValue json = parseJSON(configString);
        if (json.type != JSON_TYPE.OBJECT)
        {
            fail("Configuration file is not a JSON object");
        }

        try
        {
            addPathOrArray!"config"(configurationFiles, json);
        }
        catch (RangeError)
        {
            // This just means that "config" was not in the configuration for this
            // test, so we proceed without passing in configuration files.
        }

        try
        {
            addPathOrArray!"input"(inputFiles, json);
        }
        catch (RangeError)
        {
            throw new TestFailure(this, "You must specify input files for " ~ directory);
        }

        try
        {
            addPathOrArray!"output"(expectedOutputFiles, json, &relativeOutputFiles);
        }
        catch (RangeError)
        {
            fail("You must specify output files for " ~ directory);
        }
    }

    void addPathOrArray(string section_name)(ref string[] output, in JSONValue json, string[]* relative_output = null)
    {
        enum NotStringMessage = "Entry in \"" ~ section_name ~"\" section of test configuration is not a string";

        JSONValue configArray = json[section_name];
        Appender!(string[]) files;
        Appender!(string[]) rel_files;
        if (configArray.type == JSON_TYPE.STRING)
        {
            string path = join([directory, configArray.str], dirSeparator);
            if (!exists(path))
                fail("Could not find input path " ~ path);
            addFiles(files, path, rel_files);
        }
        else if (configArray.type == JSON_TYPE.ARRAY)
        {
            foreach (configStringJSON; configArray.array)
            {
                if (configStringJSON.type != JSON_TYPE.STRING)
                {
                    fail(NotStringMessage);
                }
                string path = join([directory, configStringJSON.str], dirSeparator);
                if (!exists(path))
                    fail("Could not find input path " ~ path);
                addFiles(files, path, rel_files);
            }
        }
        output = files.data;
        if (relative_output)
            (*relative_output) = rel_files.data;
    }

    string run(string executable)
    {
        string runTmp = join([myTmpDir, directory], dirSeparator);
        // tmps/directory should be unique, so create it here without checking
        mkdir(runTmp);
        Appender!(string[]) options;
        // 1 for executable, "-c" config file, each input file, and "--output" output
        options.reserve(1 + 2 * configurationFiles.length + inputFiles.length + 2);
        options.put([executable]);
        foreach (config; configurationFiles)
            put(options, ["-c", config]);
        foreach (input; inputFiles)
            put(options, input);
        cmd = join(options.data, " ");
        options.put(["-o", runTmp]);
        execute(options.data);
        return runTmp;
    }

    void checkResults(string pathToOutput, StringCache* strCache)
    {
        foreach (file_pair; zip(expectedOutputFiles, relativeOutputFiles))
        {
            string expectedOutputFile = file_pair[0];
            string realOutputFile = buildNormalizedPath(join([pathToOutput, file_pair[1]], dirSeparator));

            if (!exists(realOutputFile))
                fail("Could not find output " ~ realOutputFile);

            ubyte[] expected = cast(ubyte[])read(expectedOutputFile);
            ubyte[] actual = cast(ubyte[])readText(realOutputFile);

            LexerConfig lexConfig = LexerConfig(file_pair[0], StringBehavior.source);
            const(Token)[] expectedTokens = getTokensForParser(expected, lexConfig, strCache);
            Module expectedModule = parseModule(expectedTokens, file_pair[0], null, &messageDropper);
            const(Token)[] actualTokens = getTokensForParser(actual, lexConfig, strCache);
            Module actualModule = parseModule(actualTokens, file_pair[0], null, &messageDropper);
            if (expectedModule != actualModule)
                fail(expectedOutputFile ~ " is incorrect");
        }
    }

    private void fail(string msg)
    {
        throw new TestFailure(this, msg);
    }
}

void messageDropper(string, size_t, size_t, string, bool)
{
}

class TestFailure : Exception
{
    public TestCase failedCase;
    this(TestCase fc, string msg)
    {
        super(msg);
        failedCase = fc;
    }
}

bool configure_and_run_test(string directory, string executable, StringCache* strCache)
{
    TestCase curTest;
    try {
        curTest.configure(directory);
        string output_path = curTest.run(executable);
        curTest.checkResults(output_path, strCache);
        writefln("%-16s\t%s", directory, "Passed");
    }
    catch (TestFailure failure)
    {
        writefln("%-16s\t%s", directory, "FAILED");
        if (failure.msg.length > 0)
            writeln("\t", failure.msg);
        if (curTest.cmd.length > 0)
            writeln("\t", curTest.cmd);
        return false;
    }
    return true;
}


void addFiles(ref Appender!(string[]) output, string path, ref Appender!(string[]) relative_output)
{
    if (isFile(path))
    {
        path = buildNormalizedPath(path);
        put(output, path);
        put(relative_output, path);
    }
    else if (isDir(path))
    {
        foreach (string possibleFile; dirEntries(path, SpanMode.depth))
        {
            if (isFile(possibleFile))
            {
                put(output, buildNormalizedPath(possibleFile));
                put(relative_output, buildNormalizedPath(findSplit(possibleFile, path)[2]));
            }
        }
    }
}

int main(string[] args)
{
    StringCache strCache = StringCache(32);
    string executable;
    string test_directory;
    {
        int err_code = parse_args(args, executable, test_directory);
        if (err_code != 0)
            return err_code;
    }

    // Find all the test cases
    auto test_cases =
        dirEntries(test_directory, SpanMode.shallow)
        .filter!(x=> (x.isDir && x.baseName()[0] != '.'));

    myTmpDir = join([tempDir(), "test_runner-" ~ randomUUID().toString()[0..8]], dirSeparator);
    mkdir(myTmpDir);
    scope(exit) rmdirRecurse(myTmpDir);
    bool success = true;
    foreach (d; test_cases)
        success = configure_and_run_test(d.name, executable, &strCache) && success;
    return (success ? 0 : 1);
}
