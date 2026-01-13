# Understanding MTL

Learn the fundamental concepts of the Model-to-Text Language.

## Overview

MTL (Model-to-Text Language) is a template-based code generation language defined by the
[OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/) standard.
The most widely used MTL implementation is [Eclipse Acceleo](https://eclipse.dev/acceleo/).

MTL allows you to define templates that combine static text with dynamic content
extracted from models.

## Template Structure

An MTL module consists of:

1. **Module declaration**: Names the module and declares required metamodels
2. **Templates**: Define generation entry points
3. **Queries**: Reusable expressions for model navigation
4. **Comments**: Documentation within templates

```mtl
[comment encoding = UTF-8 /]
[module myGenerator('http://example.com/metamodel')]

[query public helper(e : Element) : String = e.name.toUpper() /]

[template public generate(e : Element)]
Content here...
[/template]
```

## Block Types

### Text Blocks

Plain text is output directly:

```mtl
[template public example(c : Class)]
This is plain text that will appear in the output.
The class name is: [c.name/]
[/template]
```

### Expression Blocks

Expressions are evaluated and their result is inserted:

```mtl
[c.name/]                           -- Simple navigation
[c.name.toUpper()/]                 -- With operation
[c.attributes->size()/]            -- Collection operation
[if c.isAbstract then 'abstract ' else '' endif/]  -- Inline conditional
```

### File Blocks

File blocks create output files:

```mtl
[file (expression, appendMode, encoding)]
... content ...
[/file]
```

Parameters:
- **expression**: Filename (can include path)
- **appendMode**: `false` to overwrite, `true` to append
- **encoding**: Character encoding (e.g., 'UTF-8')

```mtl
[file (c.name.concat('.swift'), false, 'UTF-8')]
// Content for [c.name/].swift
[/file]
```

### For Blocks

Iterate over collections:

```mtl
[for (variable : Type | collection)]
... body executed for each element ...
[/for]
```

Options:
- **separator**: Text between iterations
- **before**: Text before the loop (if not empty)
- **after**: Text after the loop (if not empty)

```mtl
[for (attr : Attribute | c.attributes) separator(', ')]
[attr.name/]
[/for]
-- Output: name1, name2, name3
```

### If Blocks

Conditional content:

```mtl
[if (condition)]
... content if true ...
[elseif (otherCondition)]
... content if other condition true ...
[else]
... content if all conditions false ...
[/if]
```

### Let Blocks

Define local variables:

```mtl
[let name : String = c.name.toUpper()]
The uppercase name is: [name/]
[/let]
```

### Protected Area Blocks

Preserve user content across regeneration:

```mtl
[protected (id)]
// User content here is preserved
[/protected]
```

The `id` must be unique within the file. During regeneration, MTL:
1. Scans the existing file for protected regions
2. Stores their content
3. Regenerates the file
4. Restores the protected content

## Queries

Queries are reusable expressions that can be called from templates or other queries.

### Simple Queries

```mtl
[query public fullName(c : Class) : String =
    c.package.name.concat('.').concat(c.name)
/]
```

### Queries with Multiple Expressions

```mtl
[query public swiftType(t : Type) : String =
    if t.name = 'String' then 'String'
    else if t.name = 'Integer' then 'Int'
    else if t.name = 'Boolean' then 'Bool'
    else if t.name = 'Double' then 'Double'
    else 'Any'
    endif endif endif endif
/]
```

### Collection Queries

```mtl
[query public publicAttributes(c : Class) : Sequence(Attribute) =
    c.attributes->select(a | a.visibility = 'public')
/]

[query public attributeNames(c : Class) : Sequence(String) =
    c.attributes->collect(a | a.name)
/]
```

## Template Visibility

Templates can be:
- **public**: Can be called from other modules
- **protected**: Can be called from this module and submodules
- **private**: Can only be called within this module

```mtl
[template public generatePublic(c : Class)]...[/template]
[template protected generateProtected(c : Class)]...[/template]
[template private generatePrivate(c : Class)]...[/template]
```

## Template Overriding

Templates can override templates from imported modules:

```mtl
[module myGenerator('http://example.com/mm') extends baseGenerator]

[template public generate(c : Class) overrides generate]
-- This replaces the base template
[/template]
```

## AQL Integration

MTL uses AQL (Acceleo Query Language) for expressions. Common operations:

### Navigation

```mtl
[c.name/]                    -- Attribute
[c.package/]                 -- Reference
[c.package.name/]            -- Chained navigation
```

### Collections

```mtl
[c.attributes->size()/]                          -- Count
[c.attributes->first()/]                         -- First element
[c.attributes->select(a | a.isRequired)/]       -- Filter
[c.attributes->collect(a | a.name)/]            -- Map
[c.attributes->forAll(a | a.name <> '')/]       -- All match
[c.attributes->exists(a | a.isId)/]             -- Any match
[c.attributes->reject(a | a.isDerived)/]        -- Exclude
```

### Strings

```mtl
[name.toUpper()/]                    -- Uppercase
[name.toLower()/]                    -- Lowercase
[name.concat('.swift')/]             -- Concatenation
[name.substring(0, 5)/]              -- Substring
[name.startsWith('get')/]            -- Prefix check
[name.replaceAll('_', '')/]          -- Replace
```

### Type Operations

```mtl
[c.oclIsKindOf(Entity)/]             -- Type check (including subtypes)
[c.oclIsTypeOf(Entity)/]             -- Exact type check
[c.oclAsType(Entity)/]               -- Type cast
```

## Whitespace Control

MTL preserves whitespace by default. Control it with:

### Trimming

```mtl
[c.name.trim()/]                     -- Trim result
```

### Line Control

Place tags at line boundaries to avoid extra blank lines:

```mtl
[for (attr : Attribute | c.attributes)]
    var [attr.name/]: [attr.type/]
[/for]
```

## Error Handling

Handle potential errors gracefully:

```mtl
[if (c.superClass <> null)]
extends [c.superClass.name/]
[/if]

[-- Use oclIsUndefined to check for null --]
[if (not c.documentation.oclIsUndefined())]
/// [c.documentation/]
[/if]
```

## Best Practices

1. **Organise templates**: One template per generated file type
2. **Use queries**: Extract complex expressions into reusable queries
3. **Protect user code**: Use protected regions for customisation points
4. **Handle nulls**: Check for undefined values before navigation
5. **Comment templates**: Document parameters and purpose
6. **Test incrementally**: Verify output before adding complexity

## Execution Flow

1. **Parse**: MTL file is parsed into a module structure
2. **Bind**: Model is registered with the execution context
3. **Execute**: Templates are invoked with model elements
4. **Evaluate**: Expressions navigate the model and produce text
5. **Output**: Generated content is written via the generation strategy

## Next Steps

- <doc:GettingStarted> - Practical examples
- ``MTLTemplate`` - Template API
- ``MTLProtectedAreaManager`` - Protected region management
- ``MTLExecutionContext`` - Execution configuration

## See Also

- [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/)
- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
