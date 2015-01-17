module unknown;


import 
    manual_types, 
    binder;

extern (C++) interface NotWrappableException : std.runtime_error {}

enum Strategy : uint 

{
UNKNOWN =   0,
REPLACE =   1,
STRUCT =   2,
INTERFACE =   3,
CLASS =   4,
OPAQUE_CLASS =   5
}

extern (C++) interface Declaration
{

    protected void setSourceName(binder.binder.string name);

    protected void markUnwrappable();

    public clang.SourceLocation getSourceLocation();

    public binder.binder.string getSourceName();

    public binder.binder.string getTargetName();

    public bool isWrappable();

    public void shouldBind(bool decision);

    public bool getShouldBind();

    public void setTargetModule(binder.binder.string target);

    public bool isTargetModuleSet();

    public binder.binder.string getTargetModule();

    public unknown.Visibility getVisibility();

    public void setVisibility(unknown.Visibility vis);

    public void removePrefix(binder.binder.string prefix);

    public unknown.Type* getType();

    public void visit(unknown.DeclarationVisitor visitor);

    public void dump();
}

extern (C++) interface RecordDeclaration : unknown.Declaration
{

    public unknown.FieldIterator getFieldBegin();

    public unknown.FieldIterator getFieldEnd();

    public unknown.DeclarationIterator getChildBegin();

    public unknown.DeclarationIterator getChildEnd();

    public unknown.MethodIterator getMethodBegin();

    public unknown.MethodIterator getMethodEnd();

    public unknown.SuperclassIterator getSuperclassBegin();

    public unknown.SuperclassIterator getSuperclassEnd();

    public bool isCXXRecord();

    public bool hasDefinition();

    public unknown.RecordDeclaration getDefinition();

    public bool isDynamicClass();

    public bool isCanonical();
}

extern (C++) interface TypedefDeclaration : unknown.Declaration
{

    public unknown.Type* getTargetType();
}

extern (C++) interface EnumDeclaration : unknown.Declaration
{

    public unknown.Type* getMemberType();

    public unknown.DeclarationIterator getChildBegin();

    public unknown.DeclarationIterator getChildEnd();
}

extern (C++) interface UnionDeclaration : unknown.Declaration
{

    public unknown.FieldIterator getFieldBegin();

    public unknown.FieldIterator getFieldEnd();

    public unknown.DeclarationIterator getChildBegin();

    public unknown.DeclarationIterator getChildEnd();
}

extern (C++) struct Type
{

    clang.Type* cpp_type;

    unknown.Type.Kind kind;

    unknown.Strategy strategy;

    binder.binder.string target_name;

    binder.binder.string target_module;

    static public void printTypeNames();

    static public unknown.Type* get(clang.QualType* qType, clang.PrintingPolicy* pp);

    static public unknown.Type* getByName(binder.binder.string name);

    final public clang.Type* cppType();

    final public void setKind(unknown.Type.Kind k);

    final public unknown.Type.Kind getKind();

    final public void chooseReplaceStrategy(binder.binder.string replacement);

    final public void setStrategy(unknown.Strategy s);

    final public unknown.Strategy getStrategy();

    final public binder.binder.string getReplacement();

    final public binder.binder.string getReplacementModule();

    final public void setReplacementModule(binder.binder.string mod);

    final public unknown.Declaration getDeclaration();

    final public unknown.RecordDeclaration getRecordDeclaration();

    final public unknown.Type* getPointeeType();

    final public unknown.TypedefDeclaration getTypedefDeclaration();

    final public unknown.EnumDeclaration getEnumDeclaration();

    final public unknown.UnionDeclaration getUnionDeclaration();

    final public void dump();

    extern (C++) struct Type {}

    enum Kind : uint 

    {
Invalid =   0,
Builtin =   1,
Pointer =   2,
Reference =   3,
Record =   4,
Union =   5,
Array =   6,
Function =   7,
Typedef =   8,
Vector =   9,
Enum =   10
    }

    extern (C++) interface DontSetUnknown : std.runtime_error {}

    extern (C++) interface UseReplaceMethod : std.runtime_error {}

    extern (C++) interface WrongStrategy : std.runtime_error {}
}

extern (C++) interface FatalTypeNotWrappable : unknown.NotWrappableException
{

    public clang.Type* getType();
}

extern (C++) interface SkipUnwrappableType : unknown.NotWrappableException
{

    public clang.Type* getType();
}

extern (C++) interface SkipRValueRef : unknown.SkipUnwrappableType
{

    public char* what();
}

extern (C++) interface SkipTemplate : unknown.SkipUnwrappableType
{

    public char* what();
}

extern (C++) interface SkipMemberPointer : unknown.SkipUnwrappableType
{

    public char* what();
}

enum Visibility : uint 

{
UNSET =   0,
PRIVATE =   1,
PACKAGE =   2,
PROTECTED =   3,
PUBLIC =   4,
EXPORT =   5
}

extern (C++) unknown.Visibility accessSpecToVisibility(clang.AccessSpecifier as);

extern (C++) interface NotTypeDecl : std.runtime_error {}

extern (C++) interface DeclarationIterator
{

    public unknown.Declaration get();

    public void advance();

    public bool equals(unknown.DeclarationIterator other);
}

extern (C++) interface DeclarationVisitor
{

    public void visitFunction(unknown.FunctionDeclaration node);

    public void visitNamespace(unknown.NamespaceDeclaration node);

    public void visitRecord(unknown.RecordDeclaration node);

    public void visitTypedef(unknown.TypedefDeclaration node);

    public void visitEnum(unknown.EnumDeclaration node);

    public void visitField(unknown.FieldDeclaration node);

    public void visitEnumConstant(unknown.EnumConstantDeclaration node);

    public void visitUnion(unknown.UnionDeclaration node);

    public void visitMethod(unknown.MethodDeclaration node);

    public void visitConstructor(unknown.ConstructorDeclaration node);

    public void visitDestructor(unknown.DestructorDeclaration node);

    public void visitArgument(unknown.ArgumentDeclaration node);

    public void visitVariable(unknown.VariableDeclaration node);

    public void visitUnwrappable(unknown.UnwrappableDeclaration node);
}

extern (C++) interface ConstructorDeclaration : unknown.Declaration {}

extern (C++) interface DestructorDeclaration : unknown.Declaration {}

extern (C++) interface VariableDeclaration : unknown.Declaration
{

    public clang.LanguageLinkage getLinkLanguage();
}

extern (C++) interface ArgumentDeclaration : unknown.Declaration {}

extern (C++) interface NamespaceDeclaration : unknown.Declaration
{

    public unknown.DeclarationIterator getChildBegin();

    public unknown.DeclarationIterator getChildEnd();
}

extern (C++) interface EnumConstantDeclaration : unknown.Declaration
{

    public long getLLValue();
}

extern (C++) interface ArgumentIterator
{

    public unknown.ArgumentDeclaration get();

    public void advance();

    public bool equals(unknown.ArgumentIterator other);
}

extern (C++) interface FunctionDeclaration : unknown.Declaration
{

    public clang.LanguageLinkage getLinkLanguage();

    public unknown.Type* getReturnType();

    public unknown.ArgumentIterator getArgumentBegin();

    public unknown.ArgumentIterator getArgumentEnd();

    public bool isOverloadedOperator();
}

extern (C++) interface FieldDeclaration : unknown.Declaration {}

extern (C++) interface OverriddenMethodIterator
{

    public unknown.MethodDeclaration get();

    public void advance();

    public bool equals(unknown.OverriddenMethodIterator other);
}

extern (C++) interface MethodDeclaration : unknown.Declaration
{

    public bool isStatic();

    public bool isVirtual();

    public bool isOverloadedOperator();

    public unknown.Type* getReturnType();

    public unknown.ArgumentIterator getArgumentBegin();

    public unknown.ArgumentIterator getArgumentEnd();

    public unknown.OverriddenMethodIterator getOverriddenBegin();

    public unknown.OverriddenMethodIterator getOverriddenEnd();

    public bool isConst();
}

extern (C++) interface FieldIterator
{

    public unknown.FieldDeclaration get();

    public void advance();

    public bool equals(unknown.FieldIterator other);
}

extern (C++) interface MethodIterator
{

    public unknown.MethodDeclaration get();

    public void advance();

    public bool equals(unknown.MethodIterator other);
}

extern (C++) struct Superclass
{

    bool isVirtual;

    unknown.Visibility visibility;

    unknown.Type* base;

    extern (C++) struct Superclass {}
}

extern (C++) interface SuperclassIterator
{

    public unknown.Superclass* get();

    public void advance();

    public bool equals(unknown.SuperclassIterator other);
}

extern (C++) interface UnwrappableDeclaration : unknown.Declaration {}

extern (C++) void traverseDeclsInAST(clang.ASTUnit* ast);

extern (C++) void enableDeclarationsInFiles(size_t count, char** filenames);

extern (C++) void arrayOfFreeDeclarations(size_t* count, unknown.Declaration** array);

extern (C++) unknown.Declaration getDeclaration(clang.Decl* decl);

extern (C++) interface SkipUnwrappableDeclaration : unknown.NotWrappableException {}

extern (C++) extern clang.SourceManager* source_manager;

extern (C++) clang.ASTUnit* buildAST(char* contents, size_t arg_len, char** raw_args, char* filename);