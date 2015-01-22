# `cpp_binder`

[![build status](https://ci.acm.jhu.edu/projects/1/status.png?ref=master)](https://ci.acm.jhu.edu/projects/1?ref=master)

This tool reads C++ headers and generates D bindings to the declarations there.
It is licensed under the GNU GPLv3.

## Usage

```
cpp_binder --config-file base_types.json --config-file project_info.json header.h -o output_dir
```

The configuration files are described in [doc/design.md].
The header files are parsed for C++ declarations.
There can be multiple header files.
The D modules are placed into `output_dir`; there can be only one.
The arguments can appear in any order.

Someday, when this is a real tool, I'll ship a configuration file in `/etc/cpp_binder.json` with builtin types and such and that will get parsed automatically.

## Dependencies

*   dmd 2.066 or higher
*   dub
*   clang 3.5 (dev packages)
*   yajl 2.1 or higher (maybe 2.0 works, but I haven't tested)
*   boost filesystem (and boost system)
*   C++11 compiler
