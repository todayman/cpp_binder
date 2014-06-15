#ifndef __CLI_HPP__
#define __CLI_HPP__

#include <string>
#include <vector>

struct CLIArguments
{
    std::vector<std::string> config_files;
    std::vector<std::string> header_files;
    std::string output_dir;
};

bool parse_args(int argc, const char** argv, CLIArguments& args);

#endif // __CLI_HPP__
