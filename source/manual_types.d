module manual_types;

extern(C++, clang)
{
    struct ASTContext;
    struct ASTUnit;
    struct Decl;
    struct SourceManager;
    struct TemplateParameterList;
    struct RecordDecl;

    // Dummy implementation to have the same size as a pointer
    struct QualType
    {
        void * val;
    }

    struct Type;
    struct PrintingPolicy;

    enum LanguageLinkage {
        CLanguageLinkage,
        CXXLanguageLinkage,
        NoLanguageLinkage,
    }
    enum AccessSpecifier : int;

    // This isn't the correct implementation, but it is 32 bits!
    struct SourceLocation {
        int val;
    }
}

extern(C++, std) interface runtime_error
{
    const(char)* what() const;
}
