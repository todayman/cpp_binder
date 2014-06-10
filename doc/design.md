# CPP Binder

The goal of this tool is to produce D bindings to C++ libraries.

## Overall Design

The tool runs three (and 1/2) different passes:

 - Reads and parses input

    Most of this (hopefully) is parsing actual C++ code.
    There is also parsing of human-written configuration of the translation process.

 - Determines how to do translation from C++ to D
 - Generates the translated output


-----

#### Why not modify DStep?

The conversion process here is a lot more complicated, and DStep does everything in one pass, or very tightly integrated passes.
I think that modifying DStep would amount to rewriting it anyway.
For instance, a function `void func(A * a)` could be translated as `void func(A * a)` if `A` is a `struct`, but `void func(A a)` if `A` is a `class`.
If `A` is forward declared, it is not possible to make this decision at the point `func` is declared.

-----

## First Pass

These are the input parsing passes.

The primary portion of this pass consists of reading the C++ headers and generating internal representations of the things to be bound.
This section is written using C++ terminology, namely `class == struct`.

All visible declarations need to be captured.
These include:

 - Functions, including their arguments and return types
 - Namespaces and their contents
 - Classes and their members, both variables and functions, their superclases
 - `typedef`s, including those inside classes
 - `enum`s and their members
 - `union`s and their members
 - TODO down the line, figure out how to deal with macros.
   These could be used like `typedef`s or `enums`, so we do want to map these.
   Maybe they have to be explicitly listed in the configuration files.

Register an entry for each declaration.

At the same time, identify all of the types used, and put these into a set.
These types should be as close as possible to the original C++ source, i.e., before replacing `typedef`s with the actual type.

The goal of the type-parsing section is to translate the C++ AST into a catalog of type information.

### Representation of C++ types

 - `class`: which contains its members, and references their types.
            Member functions are in different groups: constructors, destructor, operator overloads, casting, and others.
 - `union`: ditto
 - `enum`
 - primitives like `int`, etc.
 - Qualified use of another type, consisting of a set of qualifiers (`const`, `volatile`, are there others?) and a reference to the unqualified type.
 - Pointer to another type, consisting of a tag and a pointer to the other type (including qualifiers)
 - Reference to another type, see above

In the near future, I plan on ignoring pointers to members.  I think I saw them used once.

The representation of a C++ type is linked to the (not-yet-filled-in) D translation of that type.
This way, if I am a `Klass *`, I can reference the translation of `Klass`.

------

For now, this pass is going to be written in C++.
I want to be able to write a `clang::RecursiveASTVisitor` to parse C++.
Unfortunatly, `RecursiveASTVisitor` uses the [Curiously Recurring Template Pattern](http://en.wikipedia.org/wiki/Curiously_recurring_template_pattern), so it will not be bound directly any time soon.
I would like to write a C++ subclass of it that uses virtual methods and could be bound to D; along with binding the clang AST types, this should allow the tool to be written almost entirely in D.

An option, for now, is to write the first pass in C++ and have it output results to a JSON file or something, then a tool in D can pick up from there.
However, that limits the second phase from analyzing the C++ source to determine whether, i.e., constructors are trivial.
This might be useful when deciding whether something can be translated into a D `struct`.
Or maybe this will get good enough that the first pass can be written in C++ and bound to D!

------

TODO allow configuration of how to parse the C++, i.e. command line flags to `clang`.

## One-and-a-half Phase

This parses user supplied configuration about the translation process.
The conceptual model is of attaching annotations to elements that are translated.
For instance, adding annotations to a function.
The general format is a key-value store; keys indicate the element receiving annotations.
For now, keys are referenced by their fully-qualifed name.

Attributes read during this phase are applied directly onto the declarations or type information generated previously.
The configuration file does not distinguish whether the target of an attribute is a declaration or a type; that should be clear from the attribute.
For now, the configuration file is formatted as JSON.

The list of attributes is:

on declarations:

 - `name`: the fully qualified name of the declared thing.
 - `bound`: whether this declaration should generate a D binding.
            This is true by default, but could be set to false so as to only
            expose part of the C++ content to D.
 - `target_module`: the module where the bound declaration should be placed.
 - `visbility`: whether the D declaration should be `public`, `private`, etc.
 - on Functions
    - stuff to manage memory of the arguments / return type

 - on `enums`
    - `remove_prefix`: a prefix to delete from all of the constant members of this enumeration.
        This is to facilitate mapping from: `enum Color { COLOR_RED }` to `enum Color { RED }` so that the usages map from `COLOR_RED` to `Color.RED`.

on types:

 - `strategy`: how to translate this type.
    The value is a dictionary with at least a `name` field.  Acceptable `name`s are `struct`, `class`, `interface`, and `replace`.
    For `replace`, there must be another key, `d_type`, specifying the type to use in D.
    More details on these strategies are in the next section.
    Hopefully these can be left out and automagically determinied someday.

Some of these attributes, namely `target_module`, may be applied to all declarations by including an entry without a `name` attribute.

TODO syntax for applying an attribute to several entries.

## Second Phase

Build a D AST that describes the interface to the C++ library.

For each of the declarations, create a D equivalent.
For functions, compute the translated return type and argument types.

For now, the transtivity of const/immutable-ness is being ignored.
Also, exceptions.

### Type / Class translation strategies

Much of these strategies, but not all, is based on the talk at DConf 2014 by Adam ??.

#### `struct`

Define a D `struct` that has identical behavior to the C++ `class`.
The struct will have the same members in the same order as the C++ instance.
Only public methods are bound.
Methods are implemented by calling the C++ method, probably via a mechanism similar to the `class` strategy.

#### `class`
Defines a D class that is equivalent to the C++ one.
I do not know how to do this yet.  Maybe a combination of an interface for the vtable and a struct for the data?

#### `interface`
Generates an `extern (C++)` interface that contains all methods from the C++ class.

#### `replace`
The `replace` strategy requires an additional field: `d_type`.
All references to the C++ type are translated directly to the value of `d_type`.
There is no attempt to generate the `d_type` or anything else; it must be implemented by the user.

#### `opaque_class`
Is this different than interface? Need to see talk from Adam again.


The representation of D types is very similar to the representation of C++ types, and the words above are general enough, so that is omitted for now.
Obviously, `struct`s are different from `class`es here.

## Third phase

Here, the D source and any C++ glue needed gets generated.

High-level plan:

 - Loop over the list of declarations and sort them into modules.
 - For each module:
    - Compute the imports needed
    - Walk the list of declarations and emit them
    - Generate a C++ source file with the glue needed for this module.
