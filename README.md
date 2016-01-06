# `cpp_binder`

This tool reads C++ headers and generates D bindings to the declarations there.
It is licensed under the GNU GPLv3.

## Usage

```
cpp_binder --config-file base_types.json --config-file project_info.json header.h -o output_module
```

The configuration files are described in [doc/design.md].
The header files are parsed for C++ declarations.
There can be multiple header files.
The D modules are placed into `output_dir`; there can be only one.
The arguments can appear in any order.

Someday, when this is a real tool, I'll ship a configuration file in
`/etc/cpp_binder.json` with builtin types and such and that will get parsed
automatically.

The configuration needs to specify "resource-dir" to clang.  This appears to be
dependent on the particular version of clang installed.  See `config/builtin_types.json`


## Dependencies

*   dmd 2.067 or higher
*   dub
*   clang 3.7 (dev packages).  clang 3.6 or 3.5 can be used by replacing the references in: CMakeLists.txt, dub.json, and (optionally) config/cpp_binder.json
*   boost filesystem (and boost system)
*   C++11 compiler
