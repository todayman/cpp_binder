module unknown;


import 
    manual_types, 
    binder;

extern (C++) interface ConfigurationException : std.runtime_error {}

extern (C++) void applyConfigToObject(const binder.binder.string name, clang.ASTUnit* ast, const(unknown.DeclarationAttributes) decl_attributes, const(unknown.TypeAttributes) type_attributes);

extern (C++) void parseAndApplyConfiguration(size_t config_count, const(char)** config_files, clang.ASTUnit* astunit);

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

extern (C++) interface TypeAttributes
{

    static public TypeAttributes make();

    public void setStrategy(unknown.Strategy s);

    public void setTargetName(binder.binder.string new_target);

    public void setTargetModule(binder.binder.string new_module);
}

extern (C++) interface Type
{

    static public void printTypeNames();

    static public unknown.Type get(const(clang.Type)* type, const(clang.PrintingPolicy)* pp);

    static public unknown.Type get(const ref clang.QualType qType, const(clang.PrintingPolicy)* pp);

    final public unknown.Type.Kind getKind() const;

    final public void chooseReplaceStrategy(const binder.binder.string replacement);

    final public void setStrategy(unknown.Strategy s);

    final public unknown.Strategy getStrategy() const;

    public bool isReferenceType() const;

    final public binder.binder.string getReplacement() const;

    final public binder.binder.string getReplacementModule() const;

    final public void setReplacementModule(binder.binder.string mod);

    public unknown.Declaration getDeclaration() const;

    public void visit(unknown.TypeVisitor visitor);

    public void dump() const;

    final public void applyAttributes(const(unknown.TypeAttributes)* attribs);

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
Enum =   10,
Qualified =   11,
TemplateArgument =   12,
TemplateSpecialization =   13,
Delayed =   14
    }

    extern (C++) interface DontSetUnknown : std.runtime_error {}

    extern (C++) interface UseReplaceMethod : std.runtime_error {}

    extern (C++) interface WrongStrategy : std.runtime_error {}
}

extern (C++) interface TypeVisitor
{

    public void visit(unknown.InvalidType type);

    public void visit(unknown.BuiltinType type);

    public void visit(unknown.PointerType type);

    public void visit(unknown.ReferenceType type);

    public void visit(unknown.NonTemplateRecordType type);

    public void visit(unknown.TemplateRecordType type);

    public void visit(unknown.UnionType type);

    public void visit(unknown.ArrayType type);

    public void visit(unknown.FunctionType type);

    public void visit(unknown.TypedefType type);

    public void visit(unknown.VectorType type);

    public void visit(unknown.EnumType type);

    public void visit(unknown.QualifiedType type);

    public void visit(unknown.TemplateArgumentType type);

    public void visit(unknown.TemplateSpecializationType type);

    public void visit(unknown.DelayedType type);
}

extern (C++) interface InvalidType : unknown.Type {}

extern (C++) interface BuiltinType : unknown.Type {}

extern (C++) interface RecordType : unknown.Type
{

    public unknown.RecordDeclaration getRecordDeclaration() const;
}

extern (C++) interface NonTemplateRecordType : unknown.RecordType {}

extern (C++) interface TemplateRecordType : unknown.RecordType {}

extern (C++) interface PointerOrReferenceType : unknown.Type
{

    public unknown.Type getPointeeType() const;
}

extern (C++) interface PointerType : unknown.PointerOrReferenceType {}

extern (C++) interface ReferenceType : unknown.PointerOrReferenceType {}

extern (C++) interface TypedefType : unknown.Type
{

    final public unknown.TypedefDeclaration getTypedefDeclaration() const;
}

extern (C++) interface EnumType : unknown.Type
{

    final public unknown.EnumDeclaration getEnumDeclaration() const;
}

extern (C++) interface UnionType : unknown.Type
{

    final public unknown.UnionDeclaration getUnionDeclaration() const;
}

extern (C++) interface ArrayType : unknown.Type {}

extern (C++) interface FunctionType : unknown.Type {}

extern (C++) interface QualifiedType : unknown.Type
{

    final public unknown.Type unqualifiedType();

    final public const unknown.Type unqualifiedType() const;

    final public bool isConst() const;
}

extern (C++) interface VectorType : unknown.Type {}

extern (C++) interface TemplateArgumentType : unknown.Type
{

    final public unknown.TemplateTypeArgumentDeclaration getTemplateTypeArgumentDeclaration() const;

    final public void setTemplateList(clang.TemplateParameterList* tl);
}

extern (C++) interface TemplateSpecializationType : unknown.Type
{

    final public unknown.Declaration getTemplateDeclaration() const;

    final public uint getTemplateArgumentCount() const;

    final public unknown.TemplateArgumentInstanceIterator getTemplateArgumentBegin();

    final public unknown.TemplateArgumentInstanceIterator getTemplateArgumentEnd();
}

extern (C++) interface DelayedType : unknown.Type
{

    final public unknown.Type resolveType() const;
}

extern (C++) interface TemplateArgumentInstanceIterator
{

    public unknown.Type get();

    public void advance();

    public bool equals(unknown.TemplateArgumentInstanceIterator other);
}

extern (C++) interface FatalTypeNotWrappable : unknown.NotWrappableException
{

    public const(clang.Type)* getType() const;
}

extern (C++) interface SkipUnwrappableType : unknown.NotWrappableException
{

    public const(clang.Type)* getType() const;
}

extern (C++) interface SkipRValueRef : unknown.SkipUnwrappableType
{

    public const(char)* what() const;
}

extern (C++) interface SkipTemplate : unknown.SkipUnwrappableType
{

    public const(char)* what() const;
}

extern (C++) interface SkipMemberPointer : unknown.SkipUnwrappableType
{

    public const(char)* what() const;
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

extern (C++) bool isCXXRecord(const(clang.Decl)* decl);

extern (C++) bool isTemplateTypeParmDecl(const(clang.Decl)* decl);

extern (C++) interface DeclarationAttributes
{

    static public unknown.DeclarationAttributes make();

    final public void setBound(bool value);

    final public void setTargetModule(binder.binder.string value);

    final public void setVisibility(unknown.Visibility value);

    final public void setRemovePrefix(binder.binder.string value);
}

extern (C++) interface Declaration
{

    protected void setSourceName(binder.binder.string name);

    protected void markUnwrappable();

    public clang.SourceLocation getSourceLocation() const;

    public binder.binder.string getSourceName() const;

    public binder.binder.string getTargetName() const;

    public bool isWrappable() const;

    public void shouldBind(bool decision);

    public bool getShouldBind() const;

    public void setTargetModule(binder.binder.string target);

    public bool isTargetModuleSet() const;

    public binder.binder.string getTargetModule() const;

    public unknown.Visibility getVisibility() const;

    public void setVisibility(unknown.Visibility vis);

    public void removePrefix(binder.binder.string prefix);

    public unknown.Type getType() const;

    public void visit(unknown.DeclarationVisitor visitor);

    public void dump();

    final public void applyAttributes(const(unknown.DeclarationAttributes)* attribs);
}

extern (C++) void applyAttributesToDeclByName(const(unknown.DeclarationAttributes)* attribs, const binder.binder.string declName);

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

    public void visitRecordTemplate(unknown.RecordTemplateDeclaration node);

    public void visitTypedef(unknown.TypedefDeclaration node);

    public void visitEnum(unknown.EnumDeclaration node);

    public void visitField(unknown.FieldDeclaration node);

    public void visitEnumConstant(unknown.EnumConstantDeclaration node);

    public void visitUnion(unknown.UnionDeclaration node);

    public void visitSpecializedRecord(unknown.SpecializedRecordDeclaration node);

    public void visitMethod(unknown.MethodDeclaration node);

    public void visitConstructor(unknown.ConstructorDeclaration node);

    public void visitDestructor(unknown.DestructorDeclaration node);

    public void visitArgument(unknown.ArgumentDeclaration node);

    public void visitVariable(unknown.VariableDeclaration node);

    public void visitTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration node);

    public void visitUnwrappable(unknown.UnwrappableDeclaration node);
}

extern (C++) interface ConstructorDeclaration : unknown.Declaration {}

extern (C++) interface DestructorDeclaration : unknown.Declaration {}

extern (C++) interface VariableDeclaration : unknown.Declaration
{

    public clang.LanguageLinkage getLinkLanguage() const;
}

extern (C++) interface ArgumentDeclaration : unknown.Declaration {}

extern (C++) interface NamespaceDeclaration : unknown.Declaration
{

    public unknown.DeclarationIterator getChildBegin();

    public unknown.DeclarationIterator getChildEnd();
}

extern (C++) interface TypedefDeclaration : unknown.Declaration
{

    final public unknown.TypedefType getTypedefType() const;

    final public unknown.Type getTargetType() const;
}

extern (C++) interface EnumDeclaration : unknown.Declaration
{

    final public unknown.EnumType getEnumType() const;

    public unknown.Type getMemberType() const;

    public unknown.DeclarationIterator getChildBegin();

    public unknown.DeclarationIterator getChildEnd();
}

extern (C++) interface EnumConstantDeclaration : unknown.Declaration
{

    public long getLLValue() const;
}

extern (C++) interface ArgumentIterator
{

    public unknown.ArgumentDeclaration get();

    public void advance();

    public bool equals(unknown.ArgumentIterator other);
}

extern (C++) interface FunctionDeclaration : unknown.Declaration
{

    public clang.LanguageLinkage getLinkLanguage() const;

    public unknown.Type getReturnType() const;

    public unknown.ArgumentIterator getArgumentBegin();

    public unknown.ArgumentIterator getArgumentEnd();

    public bool isOverloadedOperator() const;
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

    public bool isConst() const;

    public bool isStatic() const;

    public bool isVirtual() const;

    public bool isOverloadedOperator() const;

    public unknown.Type getReturnType() const;

    public unknown.ArgumentIterator getArgumentBegin();

    public unknown.ArgumentIterator getArgumentEnd();

    public unknown.OverriddenMethodIterator getOverriddenBegin();

    public unknown.OverriddenMethodIterator getOverriddenEnd();
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

    public bool isVirtual;

    public unknown.Visibility visibility;

    public unknown.Type base;
}

extern (C++) interface SuperclassIterator
{

    public unknown.Superclass* get();

    public void advance();

    public bool equals(unknown.SuperclassIterator other);
}

extern (C++) interface RecordDeclaration : unknown.Declaration
{

    final protected const(clang.RecordDecl)* definitionOrThis();

    final public unknown.RecordType getRecordType() const;

    public unknown.FieldIterator getFieldBegin();

    public unknown.FieldIterator getFieldEnd();

    public unknown.DeclarationIterator getChildBegin();

    public unknown.DeclarationIterator getChildEnd();

    public unknown.MethodIterator getMethodBegin();

    public unknown.MethodIterator getMethodEnd();

    public unknown.SuperclassIterator getSuperclassBegin();

    public unknown.SuperclassIterator getSuperclassEnd();

    public bool isCXXRecord() const;

    public bool hasDefinition() const;

    public const unknown.RecordDeclaration getDefinition() const;

    public bool isDynamicClass() const;

    public bool isCanonical() const;

    public uint getTemplateArgumentCount() const;
}

extern (C++) interface UnionDeclaration : unknown.Declaration
{

    final public unknown.UnionType getUnionType() const;

    public unknown.FieldIterator getFieldBegin();

    public unknown.FieldIterator getFieldEnd();

    public unknown.DeclarationIterator getChildBegin();

    public unknown.DeclarationIterator getChildEnd();

    public uint getTemplateArgumentCount() const;
}

extern (C++) interface TemplateArgumentIterator
{

    public unknown.Declaration get();

    public void advance();

    public bool equals(unknown.TemplateArgumentIterator other);
}

extern (C++) interface TemplateDeclaration
{

    public uint getTemplateArgumentCount() const;

    public unknown.TemplateArgumentIterator getTemplateArgumentBegin();

    public unknown.TemplateArgumentIterator getTemplateArgumentEnd();
}

extern (C++) interface SpecializedRecordDeclaration : unknown.RecordDeclaration
{

    public unknown.TemplateArgumentInstanceIterator getTemplateArgumentBegin();

    public unknown.TemplateArgumentInstanceIterator getTemplateArgumentEnd();
}

extern (C++) interface SpecializedRecordIterator
{

    public unknown.SpecializedRecordDeclaration get();

    public void advance();

    public bool equals(unknown.SpecializedRecordIterator other);
}

extern (C++) interface RecordTemplateDeclaration : unknown.RecordDeclaration
{

    public unknown.TemplateArgumentIterator getTemplateArgumentBegin();

    public unknown.TemplateArgumentIterator getTemplateArgumentEnd();

    public unknown.SpecializedRecordIterator getSpecializationBegin();

    public unknown.SpecializedRecordIterator getSpecializationEnd();
}

extern (C++) interface UnionTemplateDeclaration : unknown.UnionDeclaration
{

    public unknown.TemplateArgumentIterator getTemplateArgumentBegin();

    public unknown.TemplateArgumentIterator getTemplateArgumentEnd();
}

extern (C++) interface TemplateTypeArgumentDeclaration : unknown.Declaration
{

    final public unknown.TemplateArgumentType getTemplateArgumentType() const;
}

extern (C++) interface UnwrappableDeclaration : unknown.Declaration {}

extern (C++) void traverseDeclsInAST(clang.ASTUnit* ast);

extern (C++) void enableDeclarationsInFiles(size_t count, char** filenames);

extern (C++) void arrayOfFreeDeclarations(size_t* count, unknown.Declaration** array);

extern (C++) unknown.Declaration getDeclaration(const(clang.Decl)* decl);

extern (C++) interface SkipUnwrappableDeclaration : unknown.NotWrappableException {}

extern (C++) extern const(clang.SourceManager)* source_manager;

extern (C++) clang.ASTUnit* buildAST(char* contents, size_t arg_len, char** raw_args, char* filename);
