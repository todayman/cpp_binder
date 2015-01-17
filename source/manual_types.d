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

    // This isn't the correct implementation, but it is 32 bits!
    struct SourceLocation {
        int val;
    }
}

extern(C++, std) interface runtime_error
{
    const(char)* what() const;
}
