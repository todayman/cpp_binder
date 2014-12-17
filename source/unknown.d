module unknown;

import binder;
import manual_types;

extern(C++) extern __gshared clang.SourceManager * source_manager;

extern(C++) void arrayOfFreeDeclarations(size_t * count, unknown.Declaration * * array);

extern(C++) void enableDeclarationsInFiles(size_t count, const(char) * * filenames);

extern(C++) void traverseDeclsInAST(clang.ASTUnit* ast);

extern(C++) clang.ASTUnit* buildAST(const(char) * contents, size_t arg_len, const(char)** clang_args, const(char) * filename);

extern(C++) interface RecordDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
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
    public bool isDynamicClass();
    //public void dump();
    public bool isCanonical();
}

extern(C++) interface MethodIterator
{
    public unknown.MethodDeclaration get();
    public void advance();
    public bool equals(unknown.MethodIterator other);
}

extern(C++) interface MethodDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public bool isStatic();
    public bool isVirtual();
    public bool isOverloadedOperator();
    public unknown.Type * getReturnType();
    public unknown.ArgumentIterator getArgumentBegin();
    public unknown.ArgumentIterator getArgumentEnd();
    //public void dump();
}

extern(C++) interface FunctionDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public clang.LanguageLinkage getLinkLanguage();
    public unknown.Type * getReturnType();
    public unknown.ArgumentIterator getArgumentBegin();
    public unknown.ArgumentIterator getArgumentEnd();
    public bool isOverloadedOperator();
    //public void dump();
}

extern(C++) interface ArgumentIterator
{
    public unknown.ArgumentDeclaration get();
    public void advance();
    public bool equals(unknown.ArgumentIterator other);
}

extern(C++) interface EnumConstantDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public long getLLValue();
    //public void dump();
}

extern(C++) interface EnumDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public unknown.DeclarationIterator getChildBegin();
    public unknown.DeclarationIterator getChildEnd();
    //public void dump();
}

extern(C++) interface TypedefDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public unknown.Type * getTargetType();
    //public void dump();
}

extern(C++) interface ArgumentDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    //public void dump();
}

extern(C++) interface VariableDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    public clang.LanguageLinkage getLinkLanguage();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public void dump();
}

extern(C++) interface ConstDeclarationVisitor
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

extern(C++) interface ConstructorDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    //public void dump();
}

extern(C++) interface UnionDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public unknown.FieldIterator getFieldBegin();
    public unknown.FieldIterator getFieldEnd();
    public unknown.DeclarationIterator getChildBegin();
    public unknown.DeclarationIterator getChildEnd();
    //public void dump();
}

extern(C++) interface NamespaceDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public unknown.DeclarationIterator getChildBegin();
    public unknown.DeclarationIterator getChildEnd();
    //public void dump();
}

extern(C++) interface SkipTemplate : unknown.SkipUnwrappableType
{
    public char * what();
}

extern(C++) interface SkipRValueRef : unknown.SkipUnwrappableType
{
    public char * what();
}

extern(C++) struct Type
{
    private Type * cpp_type;
    private unknown.Type.Kind kind;
    private unknown.Strategy strategy;
    private binder.binder.string target_name;
    public enum Kind : int
    {
        Invalid = 0,
        Builtin = 1,
        Pointer = 2,
        Reference = 3,
        Record = 4,
        Union = 5,
        Array = 6,
        Function = 7,
        Typedef = 8,
        Vector = 9,
        Enum = 10
    }


    public static void printTypeNames();
    public static unknown.Type * get(ref clang.QualType qType, clang.PrintingPolicy * pp);
    public static unknown.Type * getByName(binder.binder.string name);
    public Type * cppType();
    public void setKind(unknown.Type.Kind k);
    public unknown.Type.Kind getKind();
    public void chooseReplaceStrategy(binder.binder.string replacement);
    public void setStrategy(unknown.Strategy s);
    public unknown.Strategy getStrategy();
    public binder.binder.string getReplacement();

    // Needed to avoid exposing Clang types
    public RecordDeclaration getRecordDeclaration();
    public Type* getPointeeType();
    public TypedefDeclaration getTypedefDeclaration();
    public EnumDeclaration getEnumDeclaration();
    public UnionDeclaration getUnionDeclaration();
    public void dump();
}

enum Strategy : int
{
    UNKNOWN = 0,
    REPLACE = 1,
    STRUCT = 2,
    INTERFACE = 3,
    CLASS = 4,
    OPAQUE_CLASS = 5
}

extern(C++) interface SkipMemberPointer : unknown.SkipUnwrappableType
{
    public char * what();
}

extern(C++) interface DestructorDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    //public void dump();
}

extern(C++) interface Declaration
{
    protected void setSourceName(binder.binder.string name);
    protected void markUnwrappable();

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
    public unknown.Type * getType();
    public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    public void dump();
}

enum Visibility : int
{
    UNSET = 0,
    PRIVATE = 1,
    PACKAGE = 2,
    PROTECTED = 3,
    PUBLIC = 4,
    EXPORT = 5
}

extern(C++) interface FieldDeclaration : unknown.Declaration
{
    //public unknown.Visibility getVisibility();
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    //public void dump();
}

extern(C++) struct Superclass
{
    public bool isVirtual;
    public unknown.Visibility visibility;
    public unknown.Type * base;

}

extern(C++) interface FatalTypeNotWrappable : unknown.NotWrappableException
{
    public Type * getType();
}

extern(C++) interface NotTypeDecl : runtime_error
{
}

extern(C++) interface SkipUnwrappableDeclaration : unknown.NotWrappableException
{
}

extern(C++) interface UnwrappableDeclaration : unknown.Declaration
{
    //public unknown.Type * getType();
    //public void visit(unknown.DeclarationVisitor visitor);
    //public void visit(unknown.ConstDeclarationVisitor visitor);
    //public void dump();
}

extern(C++) interface DeclarationVisitor
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

extern(C++) interface SkipUnwrappableType : unknown.NotWrappableException
{
    public Type * getType();
}

extern(C++) interface NotWrappableException : runtime_error
{
}

extern(C++) unknown.Visibility accessSpecToVisibility(AccessSpecifier as);

extern(C++) unknown.Declaration getDeclaration(clang.Decl * decl);

extern(C++) interface FieldIterator
{
    public unknown.FieldDeclaration get();
    public void advance();
    public bool equals(unknown.FieldIterator other);
}

extern(C++) interface SuperclassIterator
{
    public unknown.Superclass * get();
    public void advance();
    public bool equals(unknown.SuperclassIterator other);
}

extern(C++) interface DeclarationIterator
{
    public unknown.Declaration get();
    public void advance();
    public bool equals(unknown.DeclarationIterator other);
}

