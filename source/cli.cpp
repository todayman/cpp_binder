#include <iostream>

#include "cli.hpp"

bool parse_args(int argc, const char** argv, CLIArguments& args)
{
    bool setOutput = false;
    for( int cur_arg_idx = 1; cur_arg_idx < argc; ++cur_arg_idx )
    {
        std::string arg_str(argv[cur_arg_idx]);
        if( arg_str == "--config-file" || arg_str == "-c" )
        {
            cur_arg_idx += 1;
            if( cur_arg_idx == argc ) {
                std::cout << "ERROR: Expected path to configuration file after " << arg_str << "\n";
                return false;
            }
            args.config_files.emplace_back(argv[cur_arg_idx]);
        }
        else if( arg_str == "--output" || arg_str == "-o" )
        {
            if( setOutput ) {
                std::cout << "ERROR: Only one output directory may be specified.\n";
                return false;
            }

            cur_arg_idx += 1;
            if( cur_arg_idx == argc ) {
                std::cout << "ERROR: Expected path to output directory after " << arg_str << "\n";
                return false;
            }
            args.output_dir = argv[cur_arg_idx];
            setOutput = true;
        }
        else {
            // TODO should I be using emplace_back here instead of push_back?
            args.header_files.emplace_back(arg_str);
        }
    }
    if( args.header_files.size() == 0 ) {
        std::cout << "ERROR: No input files specified.\n";
        return false;
    }
    if( args.config_files.size() == 0 ) {
        std::cout << "WARNING: No configuration files found.  I will not know how to translate basic types like \"int\".  Diving into the abyss.  You did tell me to, after all.\n";
    }
    return true;
}

