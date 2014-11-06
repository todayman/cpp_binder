module manual_types;

extern(C++, clang)
{
    struct Decl;
    struct SourceManager;
    struct QualType;
    struct PrintingPolicy;

    enum LanguageLinkage;
    enum AccessSpecifier;
}

extern(C++) interface runtime_error
{
    const(char)* what() const;
}
