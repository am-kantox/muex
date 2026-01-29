# Language Extension Analysis for Muex

This document analyzes the feasibility of extending Muex to support additional programming languages beyond Elixir and Erlang. For each language, we evaluate the architecture requirements, available tooling, implementation complexity, and specific challenges.

## Architecture Overview

Muex's current architecture has two critical dependencies on the BEAM VM:

1. **Language Adapter Requirements** (`Muex.Language` behaviour):
   - `parse/1`: Source → AST
   - `unparse/1`: AST → Source
   - `compile/2`: Source → Compiled module
   - File extension and test pattern detection

2. **Hot Module Swapping**: The current implementation relies on BEAM's ability to dynamically load and unload modules using `:code.purge/1`, `:code.delete/1`, and `:code.load_binary/3`.

### Core Challenge: Module Hot-Swapping

The **critical blocker** for non-BEAM languages is that Muex currently compiles mutated code directly into the running BEAM VM and hot-swaps it during test execution. This works for Elixir/Erlang because:
- They compile to BEAM bytecode
- The BEAM VM supports runtime module replacement
- Tests run in the same VM as the mutation framework

For other languages, we need an alternative approach since they cannot be loaded into BEAM.

## Alternative Architecture: Port-Based Execution

To support non-BEAM languages, we need to use **port-based execution** where:

1. Mutated source code is written to a temporary file
2. A new OS process is spawned to run tests against the mutated code
3. Results are captured and analyzed
4. The process is terminated and cleaned up

This approach is **already partially supported** in Muex via `Muex.Compiler.compile_to_file/3`, which writes mutated AST to a temporary file for external compilation.

### Required Modifications

To fully support non-BEAM languages, we would need:

1. **Test Runner Abstraction**: Add a callback to the `Muex.Language` behaviour:
   ```elixir
   @callback run_tests(file_path :: String.t(), test_command :: String.t()) ::
             {:ok, :passed | :failed} | {:error, term()}
   ```

2. **Process-Based Test Execution**: Extend `Muex.Runner` to support spawning external processes via ports when the language adapter is not BEAM-based.

3. **Configuration for Test Commands**: Allow users to specify test commands per language (e.g., `npm test`, `pytest`, `go test`).

## Language-by-Language Analysis

### 1. JavaScript

**Difficulty: Medium**

**AST Tooling:**
- **Parser**: [Babel Parser](https://babeljs.io/docs/en/babel-parser) - Production-ready, used by Babel
  - Supports modern JavaScript (ES2024+) and JSX
  - Can be invoked via Node.js from Elixir using ports
  - Alternative: [Acorn](https://github.com/acornjs/acorn) (lighter weight)
  
- **Unparsing**: [@babel/generator](https://babeljs.io/docs/en/babel-generator)
  - Converts Babel AST back to source code
  - Handles formatting and source map generation

**Test Execution:**
- Popular frameworks: Jest, Mocha, Vitest
- Standard command: `npm test` or `npx jest`
- Easy to invoke from Elixir via port

**Implementation Path:**
1. Create `Muex.Language.JavaScript` module
2. Use port communication to invoke Node.js for parsing/unparsing:
   ```elixir
   def parse(source) do
     node_script = """
     const parser = require('@babel/parser');
     const source = process.argv[2];
     const ast = parser.parse(source);
     console.log(JSON.stringify(ast));
     """
     # Execute via port and parse JSON response
   end
   ```
3. Use `compile_to_file/3` to write mutated code
4. Run tests via `System.cmd("npm", ["test"])`

**AST Structure Example:**
```javascript
// Source: a + b
// Babel AST:
{
  "type": "BinaryExpression",
  "operator": "+",
  "left": {"type": "Identifier", "name": "a"},
  "right": {"type": "Identifier", "name": "b"}
}
```

**Mutator Compatibility:**
- Arithmetic: Full support (BinaryExpression with operator field)
- Comparison: Full support (same structure as arithmetic)
- Boolean: Full support (LogicalExpression, UnaryExpression)
- Literal: Full support (NumericLiteral, StringLiteral, etc.)
- FunctionCall: Full support (CallExpression)
- Conditional: Full support (IfStatement, ConditionalExpression)

**Challenges:**
- Node.js must be installed
- Port communication overhead for each parse/unparse
- Handling async/await constructs in mutations
- Different module systems (CommonJS, ESM)

**Recommendation:** **Feasible** with medium effort. The tooling is mature and widely used.

---

### 2. TypeScript

**Difficulty: Medium**

**AST Tooling:**
- **Parser**: [TypeScript Compiler API](https://github.com/microsoft/TypeScript/wiki/Using-the-Compiler-API)
  - Official TypeScript parser/compiler
  - Comprehensive AST support
  - Can be invoked via Node.js
  
- **Unparsing**: [ts-morph](https://ts-morph.com/) or TypeScript Printer API
  - `ts-morph` provides high-level manipulation
  - Built-in printer: `ts.createPrinter().printNode()`

**Test Execution:**
- Same as JavaScript (Jest with ts-jest, Vitest, etc.)
- Requires compilation step before testing
- Command: `npm test` or `npx jest`

**Implementation Path:**
Similar to JavaScript, but using TypeScript Compiler API:
```javascript
const ts = require('typescript');
const source = fs.readFileSync('file.ts', 'utf8');
const sourceFile = ts.createSourceFile('file.ts', source, ts.ScriptTarget.Latest);
// AST is in sourceFile
```

**AST Structure:**
TypeScript's AST is similar to JavaScript but includes type annotations:
```typescript
// Source: const x: number = 5 + 3
// AST includes VariableDeclaration with type annotation and BinaryExpression
```

**Mutator Compatibility:**
Same as JavaScript - full support for all current mutators.

**Challenges:**
- Type checking may cause mutations to fail compilation
- Need to handle type annotations in mutations
- More complex AST due to type system
- May need to disable strict type checking for some mutations

**Recommendation:** **Feasible** with medium effort. Can reuse most JavaScript infrastructure.

---

### 3. Python

**Difficulty: Easy-Medium**

**AST Tooling:**
- **Parser**: Python's built-in `ast` module
  - Ships with Python, no external dependencies
  - Comprehensive and well-documented
  - Can be invoked via Python script from Elixir
  
- **Unparsing**: `ast.unparse()` (Python 3.9+) or [astor](https://github.com/berkerpeksag/astor)
  - Built-in unparsing since Python 3.9
  - Astor for older versions or more control

**Test Execution:**
- Popular frameworks: pytest, unittest
- Standard command: `pytest` or `python -m pytest`
- Very straightforward to invoke

**Implementation Path:**
```elixir
defmodule Muex.Language.Python do
  def parse(source) do
    python_script = """
    import ast
    import json
    import sys
    source = sys.argv[1]
    tree = ast.parse(source)
    # Convert AST to JSON-serializable format
    print(json.dumps(ast.dump(tree)))
    """
    # Execute via port
  end
end
```

**AST Structure Example:**
```python
# Source: a + b
# AST:
BinOp(
  left=Name(id='a'),
  op=Add(),
  right=Name(id='b')
)
```

**Mutator Compatibility:**
- Arithmetic: Full support (BinOp with Add, Sub, Mult, Div operators)
- Comparison: Full support (Compare with Eq, NotEq, Lt, Gt, etc.)
- Boolean: Full support (BoolOp with And/Or, UnaryOp with Not)
- Literal: Full support (Constant node for literals)
- FunctionCall: Full support (Call node)
- Conditional: Full support (If node)

**Challenges:**
- Python 2 vs 3 compatibility (focus on Python 3)
- Indentation-sensitive syntax (unparsing must preserve it)
- Dynamic typing means mutations may not fail type checks
- AST node structure serialization to/from JSON

**Recommendation:** **Highly feasible** with low-medium effort. Python's built-in AST support makes this straightforward.

---

### 4. Go

**Difficulty: Medium-Hard**

**AST Tooling:**
- **Parser**: `go/parser` and `go/ast` (standard library)
  - Built into Go, very robust
  - Used by many Go tools (gofmt, gopls, etc.)
  - No Node.js-like runtime; needs compiled Go binary
  
- **Unparsing**: `go/printer` or `go/format`
  - Standard library support
  - Maintains Go formatting conventions

**Test Execution:**
- Built-in testing: `go test`
- Standard and well-defined
- Easy to invoke from Elixir

**Implementation Path:**
Need to create a **Go helper binary** that Muex can invoke:
```go
// muex-go-helper/main.go
package main

import (
    "encoding/json"
    "fmt"
    "go/ast"
    "go/parser"
    "go/printer"
    "go/token"
    "os"
)

func main() {
    // Read source from stdin or file
    // Parse to AST
    // Serialize AST to JSON
    // Or: read JSON AST, convert to Go AST, unparse
}
```

From Elixir:
```elixir
def parse(source) do
  # Write source to temp file
  # Invoke: muex-go-helper parse temp_file.go
  # Read JSON output and convert to Elixir term
end
```

**AST Structure Example:**
```go
// Source: a + b
// AST:
&ast.BinaryExpr{
    X: &ast.Ident{Name: "a"},
    Op: token.ADD,
    Y: &ast.Ident{Name: "b"},
}
```

**Mutator Compatibility:**
- Arithmetic: Full support (BinaryExpr with ADD, SUB, MUL, QUO tokens)
- Comparison: Full support (BinaryExpr with EQL, NEQ, LSS, GTR, etc.)
- Boolean: Full support (BinaryExpr with LAND, LOR; UnaryExpr with NOT)
- Literal: Full support (BasicLit for numbers/strings)
- FunctionCall: Full support (CallExpr)
- Conditional: Full support (IfStmt)

**Challenges:**
- Requires distributing a Go binary with Muex
- More complex AST serialization (Go ASTs are not directly JSON-serializable)
- Need to handle Go modules and package structure
- Type checking is strict; mutations may cause compilation failures
- Position information (token.Pos) is tied to token.FileSet

**Recommendation:** **Feasible** but requires more infrastructure. Need to maintain a separate Go helper tool.

---

### 5. Rust

**Difficulty: Hard**

**AST Tooling:**
- **Parser**: [syn](https://github.com/dtolnay/syn) crate
  - De facto standard for Rust parsing
  - Used by procedural macros
  - Very comprehensive but complex
  
- **Unparsing**: [quote](https://github.com/dtolnay/quote) crate or [prettyplease](https://github.com/dtolnay/prettyplease)
  - `quote` for macro-style generation
  - `prettyplease` for formatting syn ASTs back to source

**Test Execution:**
- Built-in: `cargo test`
- Standard and easy to invoke

**Implementation Path:**
Similar to Go, need a **Rust helper binary**:
```rust
// muex-rust-helper/src/main.rs
use syn::{parse_file, File};
use serde_json;

fn main() {
    // Parse Rust source to syn::File
    // Serialize to JSON
    // Or deserialize JSON and unparse using prettyplease
}
```

**AST Structure Example:**
```rust
// Source: a + b
// syn AST:
Expr::Binary(ExprBinary {
    left: Box::new(Expr::Path(...)),
    op: BinOp::Add,
    right: Box::new(Expr::Path(...)),
})
```

**Mutator Compatibility:**
- Arithmetic: Full support (ExprBinary with Add, Sub, Mul, Div)
- Comparison: Full support (ExprBinary with Eq, Ne, Lt, Gt, etc.)
- Boolean: Full support (ExprBinary with And, Or; ExprUnary with Not)
- Literal: Partial support (ExprLit, but need careful handling of types)
- FunctionCall: Full support (ExprCall, ExprMethodCall)
- Conditional: Full support (ExprIf, ExprMatch)

**Challenges:**
- **Most complex AST** among all languages listed
- Extremely strict type system and borrow checker
- Many mutations will fail to compile
- Macro expansion complicates AST
- Requires distributing Rust binary (larger than Go)
- Lifetime and ownership annotations must be preserved
- Pattern matching is pervasive and complex to mutate

**Recommendation:** **Feasible but challenging**. High implementation effort, many mutations will be invalid due to type system.

---

### 6. C# (CSharp)

**Difficulty: Medium-Hard**

**AST Tooling:**
- **Parser**: [Roslyn](https://github.com/dotnet/roslyn) (Microsoft.CodeAnalysis)
  - Official .NET compiler platform
  - Comprehensive syntax and semantic APIs
  - Requires .NET runtime
  
- **Unparsing**: Roslyn's `SyntaxNode.ToFullString()`
  - Built-in unparsing preserves formatting

**Test Execution:**
- Standard: `dotnet test`
- xUnit, NUnit, MSTest frameworks
- Easy to invoke

**Implementation Path:**
Need a **.NET helper binary**:
```csharp
// MuexCSharpHelper/Program.cs
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using System.Text.Json;

var source = File.ReadAllText(args[0]);
var tree = CSharpSyntaxTree.ParseText(source);
var root = tree.GetRoot();
// Serialize to JSON
Console.WriteLine(JsonSerializer.Serialize(root));
```

**AST Structure Example:**
```csharp
// Source: a + b
// Roslyn AST:
BinaryExpressionSyntax {
    Left: IdentifierNameSyntax("a"),
    OperatorToken: Token(PlusToken),
    Right: IdentifierNameSyntax("b")
}
```

**Mutator Compatibility:**
- Arithmetic: Full support (BinaryExpressionSyntax with different operators)
- Comparison: Full support (same structure)
- Boolean: Full support (BinaryExpressionSyntax, PrefixUnaryExpressionSyntax)
- Literal: Full support (LiteralExpressionSyntax)
- FunctionCall: Full support (InvocationExpressionSyntax)
- Conditional: Full support (IfStatementSyntax, ConditionalExpressionSyntax)

**Challenges:**
- Requires .NET runtime installed
- Larger binary distribution
- Strong typing means many mutations fail compilation
- Complex AST structure (Roslyn is very detailed)
- Need to handle different .NET versions and frameworks
- LINQ expressions add complexity

**Recommendation:** **Feasible** with moderate-high effort. Roslyn is excellent but requires .NET ecosystem.

---

### 7. Java

**Difficulty: Medium-Hard**

**AST Tooling:**
- **Parser**: [JavaParser](https://javaparser.org/)
  - Most popular Java parsing library
  - Pure Java, no external dependencies
  - Good AST manipulation support
  
- **Unparsing**: JavaParser's `toString()` or `LexicalPreservingPrinter`
  - Can preserve or regenerate formatting

**Test Execution:**
- JUnit, TestNG
- Maven: `mvn test`
- Gradle: `gradle test`
- Requires compilation first

**Implementation Path:**
Need a **Java helper application**:
```java
// MuexJavaHelper.java
import com.github.javaparser.JavaParser;
import com.github.javaparser.ast.CompilationUnit;
import com.google.gson.Gson;

public class MuexJavaHelper {
    public static void main(String[] args) {
        CompilationUnit cu = JavaParser.parse(new File(args[0]));
        String json = new Gson().toJson(cu);
        System.out.println(json);
    }
}
```

**AST Structure Example:**
```java
// Source: a + b
// JavaParser AST:
BinaryExpr {
    left: NameExpr("a"),
    operator: PLUS,
    right: NameExpr("b")
}
```

**Mutator Compatibility:**
- Arithmetic: Full support (BinaryExpr with PLUS, MINUS, MULTIPLY, DIVIDE)
- Comparison: Full support (BinaryExpr with EQUALS, NOT_EQUALS, LESS, etc.)
- Boolean: Full support (BinaryExpr with AND, OR; UnaryExpr with NOT)
- Literal: Full support (IntegerLiteralExpr, StringLiteralExpr, etc.)
- FunctionCall: Full support (MethodCallExpr)
- Conditional: Full support (IfStmt, ConditionalExpr)

**Challenges:**
- Requires JVM runtime
- Must distribute JavaParser JAR
- Strong static typing limits valid mutations
- Verbose syntax and boilerplate
- Must handle imports and package structure
- Different Java versions (8, 11, 17, 21) have syntax differences

**Recommendation:** **Feasible** with moderate effort. JavaParser is mature and well-documented.

---

### 8. Ruby

**Difficulty: Medium**

**AST Tooling:**
- **Parser**: [parser](https://github.com/whitequark/parser) gem
  - Production-quality, used by RuboCop and others
  - Supports Ruby 1.8 through 3.x
  - Can be invoked via Ruby from Elixir
  
- **Unparsing**: [unparser](https://github.com/mbj/unparser) gem
  - Converts parser AST back to source
  - Maintains semantic equivalence

**Test Execution:**
- RSpec, Minitest
- Command: `rspec` or `rake test`
- Very straightforward

**Implementation Path:**
```elixir
defmodule Muex.Language.Ruby do
  def parse(source) do
    ruby_script = """
    require 'parser/current'
    require 'json'
    
    source = ARGV[0]
    ast = Parser::CurrentRuby.parse(source)
    # Convert to JSON-serializable format
    puts ast.to_sexp_array.to_json
    """
    # Execute via port
  end
end
```

**AST Structure Example:**
```ruby
# Source: a + b
# parser AST (s-expression):
(send
  (lvar :a) :+
  (lvar :b))
```

**Mutator Compatibility:**
- Arithmetic: Full support (send nodes with :+, :-, :*, :/ operators)
- Comparison: Full support (send nodes with :==, :!=, :<, :>, etc.)
- Boolean: Full support (and, or nodes; send with :! operator)
- Literal: Full support (int, str, sym nodes)
- FunctionCall: Full support (send nodes)
- Conditional: Full support (if node)

**Challenges:**
- Ruby must be installed
- Dynamic typing means mutations rarely fail
- Multiple ways to express same logic (blocks, procs, lambdas)
- Metaprogramming constructs (define_method, etc.)
- AST is s-expression based (different from most languages)

**Recommendation:** **Highly feasible** with moderate effort. Ruby's parser gem is excellent and well-maintained.

---

## Summary Table

| Language   | Difficulty | Parser Tool | Unparsing Tool | Test Command | Binary Required | Overall Feasibility |
|------------|-----------|-------------|----------------|--------------|-----------------|-------------------|
| JavaScript | Medium    | Babel Parser | @babel/generator | npm test | No (Node.js) | High |
| TypeScript | Medium    | TS Compiler API | ts-morph/Printer | npm test | No (Node.js) | High |
| Python     | Easy-Med  | ast (builtin) | ast.unparse | pytest | No | Very High |
| Go         | Med-Hard  | go/parser | go/printer | go test | Yes | Moderate |
| Rust       | Hard      | syn crate | prettyplease | cargo test | Yes | Moderate-Low |
| C#         | Med-Hard  | Roslyn | SyntaxNode | dotnet test | Yes (.NET) | Moderate |
| Java       | Med-Hard  | JavaParser | JavaParser | mvn/gradle test | Yes (JVM) | Moderate |
| Ruby       | Medium    | parser gem | unparser gem | rspec | No | High |

## Implementation Priority Recommendations

Based on feasibility, ecosystem maturity, and community demand:

**Tier 1 (Implement First):**
1. **Python** - Easiest implementation, huge user base, built-in AST support
2. **JavaScript** - Massive ecosystem, mature tooling, high demand
3. **Ruby** - Clean AST library, dynamic language similar to Elixir philosophy

**Tier 2 (Medium Priority):**
4. **TypeScript** - Can reuse JS infrastructure, growing popularity
5. **Go** - Simple language, good tooling, but requires binary helper
6. **Java** - Large enterprise use, mature ecosystem, requires JVM

**Tier 3 (Lower Priority):**
7. **C#** - Good tooling but requires .NET, smaller open-source presence
8. **Rust** - Complex type system makes mutation testing difficult

## Required Core Changes to Muex

To support any of these languages, the following changes are needed:

### 1. Extend `Muex.Language` Behaviour

Add test execution callback:
```elixir
@callback run_tests(test_command :: String.t(), mutated_file :: String.t()) ::
          {:ok, :passed | :failed} | {:error, term()}

@callback requires_external_process?() :: boolean()
```

### 2. Modify `Muex.Runner`

Add logic to detect if language requires external process:
```elixir
defp run_test_for_mutation(mutation, language_adapter) do
  if language_adapter.requires_external_process?() do
    run_external_test(mutation, language_adapter)
  else
    run_beam_test(mutation, language_adapter)
  end
end
```

### 3. Add Port-Based Execution Mode

Create helper functions for spawning processes and capturing output:
```elixir
defp run_external_test(mutation, language_adapter) do
  with {:ok, temp_file} <- write_mutated_source(mutation),
       {:ok, result} <- language_adapter.run_tests(temp_file),
       :ok <- cleanup_temp_file(temp_file) do
    classify_result(result)
  end
end
```

### 4. Add AST Serialization Layer

For languages requiring external processes, need JSON serialization:
```elixir
defmodule Muex.AST.Serializer do
  def to_json(ast), do: Jason.encode(ast)
  def from_json(json), do: Jason.decode(json)
end
```

### 5. Create Language Helper Binaries (for compiled languages)

For Go, Rust, Java, C#:
- Create separate repository or subdirectory
- Provide build scripts
- Include pre-built binaries for common platforms (optional)
- Document installation requirements

## Example Implementation: Python Language Adapter

Here's a complete example showing what a Python adapter would look like:

```elixir
defmodule Muex.Language.Python do
  @behaviour Muex.Language
  
  @impl true
  def parse(source) do
    script = """
    import ast
    import json
    import sys
    
    source = sys.stdin.read()
    tree = ast.parse(source)
    # Convert AST to JSON dict
    result = ast_to_dict(tree)
    print(json.dumps(result))
    """
    
    case System.cmd("python3", ["-c", script], input: source) do
      {output, 0} -> {:ok, Jason.decode!(output)}
      {error, _} -> {:error, error}
    end
  end
  
  @impl true
  def unparse(ast) do
    script = """
    import ast
    import json
    import sys
    
    ast_dict = json.loads(sys.stdin.read())
    tree = dict_to_ast(ast_dict)
    source = ast.unparse(tree)
    print(source)
    """
    
    case System.cmd("python3", ["-c", script], input: Jason.encode!(ast)) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end
  
  @impl true
  def compile(source, _module_name) do
    # Python is interpreted, no compilation needed
    # Just validate syntax
    case parse(source) do
      {:ok, _} -> {:ok, :valid}
      error -> error
    end
  end
  
  @impl true
  def file_extensions, do: [".py"]
  
  @impl true
  def test_file_pattern, do: ~r/test_.*\.py$/
  
  @impl true
  def run_tests(test_command, mutated_file) do
    # Replace original file with mutated version temporarily
    # Or set PYTHONPATH to load mutated module
    case System.cmd("pytest", ["-x"], env: [{"MUEX_MUTATED_FILE", mutated_file}]) do
      {_output, 0} -> {:ok, :passed}
      {_output, _} -> {:ok, :failed}
    end
  end
  
  @impl true
  def requires_external_process?, do: true
end
```

## Conclusion

Extending Muex to support non-BEAM languages is **definitely feasible** but requires:

1. **Architecture modifications** to support port-based test execution
2. **Per-language adapters** using language-specific parsing tools
3. **Helper binaries** for compiled languages (Go, Rust, Java, C#)
4. **Careful AST mapping** to make mutators work across languages

The **easiest wins** are Python, JavaScript, and Ruby, which have excellent runtime-based AST libraries and can be invoked via ports without distributing binaries.

The **hardest implementations** are Rust and C# due to complex type systems, strict compilation requirements, and infrastructure needs.

**Overall assessment**: Extending to 3-5 additional languages (Python, JavaScript, TypeScript, Ruby, Go) is a realistic goal with moderate development effort (2-4 weeks per language for full implementation and testing).
