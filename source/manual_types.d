module manual_types;

extern(C++, clang)
{
    struct ASTContext;
    struct ASTUnit;
    struct Decl;
    struct SourceManager;
    struct QualType;
    struct Type;
    struct PrintingPolicy;

    enum LanguageLinkage {
        CLanguageLinkage,
        CXXLanguageLinkage,
        NoLanguageLinkage,
    }
    enum AccessSpecifier;
}

extern(C++, std) interface runtime_error
{
    const(char)* what() const;
}
