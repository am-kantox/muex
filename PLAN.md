# Muex Evolution Plan: Basic Functionality to Multi-Language Support

## Overview
This plan outlines the evolution of Muex from its current basic implementation to a production-ready mutation testing library with support for Elixir, Rust, and C#. The plan progresses through foundational fixes, core functionality completion, advanced features, and finally multi-language adapter implementation.

## Current State Assessment
The codebase has:
- Basic architecture: Language behaviour, Mutator behaviour, Loader, Compiler, Runner, Reporter
- Two mutators: Arithmetic and Comparison (both implemented)
- One language adapter: Elixir (basic implementation)
- Test suite: 11 tests passing, but missing tests for Comparison mutator, Loader, Compiler, Runner, Reporter
- Known issues: Module hot-swapping shows redefining warnings, test runner returns mock results, mutation application in Compiler is incomplete

## Phase 1: Core Functionality Fixes

### 1.1 Fix Module Hot-Swapping
lib/muex/compiler.ex (24-32, 49-54)

The current implementation causes "redefining module" warnings. Need to properly manage module purging and reloading:
- Before loading mutated module, call `:code.purge/1` and `:code.delete/1`
- Store original module binary for restoration instead of recompiling from file
- Add proper error handling for module loading failures

### 1.2 Implement AST Mutation Application
lib/muex/compiler.ex (57-65)

The `apply_mutation/2` function is a stub. Need to:
- Track mutation location (line, column, or unique node identifier)
- Walk AST to find exact node to replace
- Replace node with mutated AST from mutation map
- Handle nested structures and preserve metadata

### 1.3 Implement Real Test Execution
lib/muex/runner.ex (106-113)

Currently returns mock results. Need to:
- Integrate with ExUnit to run actual test suite
- Capture test output and parse results
- Handle test failures, errors, and timeouts properly
- Ensure clean test environment between mutations

## Phase 2: Complete Test Coverage

### 2.1 Add Missing Mutator Tests
Create `test/muex/mutator/comparison_test.exs` with tests for:
- All comparison operators (==, !=, >, <, >=, <=, ===, !==)
- Proper mutation generation
- Edge cases and non-comparison operators

### 2.2 Add Core Component Tests
Create tests for:
- `test/muex/loader_test.exs`: File discovery, parsing, exclusion patterns
- `test/muex/compiler_test.exs`: AST mutation application, module compilation, restoration
- `test/muex/runner_test.exs`: Test execution, result classification, parallel execution
- `test/muex/reporter_test.exs`: Output formatting, summary calculation

### 2.3 Add Integration Tests
Create `test/integration/mutation_test.exs`:
- End-to-end mutation testing on ExampleCalculator
- Verify mutations are generated, executed, and reported
- Test with different mutator combinations
- Validate mutation score calculation

## Phase 3: Advanced Mutators

### 3.1 Boolean Logic Mutator
Create `lib/muex/mutator/boolean.ex`:
- Mutate `and` <-> `or`
- Mutate `&&` <-> `||`
- Negate boolean literals: `true` <-> `false`
- Remove negation: `not x` -> `x`

Add tests in `test/muex/mutator/boolean_test.exs`

### 3.2 Literal Mutator
Create `lib/muex/mutator/literal.ex`:
- Numeric literals: increment/decrement by 1
- String literals: empty string, add character
- List literals: empty list, remove first element
- Atom literals: change to different atom

Add tests in `test/muex/mutator/literal_test.exs`

### 3.3 Function Call Mutator
Create `lib/muex/mutator/function_call.ex`:
- Remove function calls (replace with nil or identity)
- Swap function arguments
- Remove function arguments

Add tests in `test/muex/mutator/function_call_test.exs`

### 3.4 Conditional Mutator
Create `lib/muex/mutator/conditional.ex`:
- Remove if/else branches
- Invert if conditions
- Replace case clauses
- Mutate guard clauses

Add tests in `test/muex/mutator/conditional_test.exs`

## Phase 4: Enhanced Reporting and Configuration

### 4.1 HTML Reporter
Create `lib/muex/reporter/html.ex`:
- Generate HTML report with mutation details
- Color-coded results (killed, survived, invalid, timeout)
- Show source code with highlighted mutations
- Add filtering and sorting capabilities

### 4.2 JSON Reporter
Create `lib/muex/reporter/json.ex`:
- Export results in structured JSON format
- Include all mutation metadata
- Support for CI/CD integration

### 4.3 Configuration File Support
Create `.muex.exs` configuration file support:
- Define mutators to use
- Set file patterns to include/exclude
- Configure thresholds and timeouts
- Specify reporter formats

Update `lib/mix/tasks/muex.ex` to read configuration

### 4.4 Mutation Filtering
Add options to filter mutations:
- By file path pattern
- By line number range
- By mutator type
- Incremental mode (only mutate changed files)

## Phase 5: Performance Optimization

### 5.1 Improve Parallel Execution
lib/muex/runner.ex (88-103)
- Add better concurrency management
- Implement work-stealing for load balancing
- Add progress tracking with ETS
- Optimize module loading/unloading

### 5.2 Caching System
Create `lib/muex/cache.ex`:
- Cache parsed ASTs to avoid reparsing
- Store mutation results to skip unchanged code
- Implement cache invalidation based on file checksums
- Add cache persistence to disk

### 5.3 Smart Mutation Selection
Create `lib/muex/selector.ex`:
- Prioritize mutations in frequently changed code
- Use heuristics to skip equivalent mutations
- Implement mutation sampling for large codebases

## Phase 6: Erlang Language Adapter

### 6.1 Implement Erlang Parser
Create `lib/muex/language/erlang.ex`:
- Use `:erl_scan` and `:erl_parse` for parsing Erlang source
- Implement `parse/1` to convert Erlang to AST
- Implement `unparse/1` to convert AST back (using `:epp` and `:erl_prettypr`)
- Implement `compile/2` using `:compile` module
- Set `file_extensions/0` to return `[".erl"]`
- Set `test_file_pattern/0` to match Erlang test conventions

### 6.2 Erlang-Specific Mutators
Erlang AST structure differs from Elixir. Update existing mutators:
- Handle Erlang tuple-based AST format
- Support Erlang-specific operators and syntax
- Add tests with Erlang example code

### 6.3 Erlang Integration Tests
Create example Erlang module and tests:
- Add `examples/calculator.erl` with basic functions
- Add `examples/calculator_tests.erl` with EUnit tests
- Run mutation testing on Erlang code
- Validate mutation scores

## Phase 7: Rust Language Adapter

### 7.1 Rust Toolchain Integration
Create `lib/muex/language/rust.ex`:
- Use Port/NIFs to call Rust parser (syn crate)
- Or shell out to `rust-analyzer` for AST parsing
- Implement `parse/1` to parse Rust source to JSON AST
- Implement `unparse/1` to convert back (using quote crate or prettyplease)
- Implement `compile/2` to run `rustc` and load shared library
- Set `file_extensions/0` to return `[".rs"]`
- Set `test_file_pattern/0` to match Rust test conventions

### 7.2 Rust AST Adaptation Layer
Create `lib/muex/language/rust/ast_adapter.ex`:
- Convert Rust AST (JSON from syn) to normalized format
- Map Rust operators to generic mutation points
- Handle Rust-specific constructs (match, impl, traits)
- Preserve type annotations and lifetimes

### 7.3 Rust Test Runner Integration
Update `lib/muex/runner.ex` or create Rust-specific runner:
- Execute `cargo test` for Rust projects
- Parse test output (JSON format with --message-format=json)
- Map test failures to mutation results
- Handle Rust compilation errors as invalid mutations

### 7.4 Rust Mutator Adaptations
Create or adapt mutators for Rust:
- Arithmetic: handle Rust overflow behavior
- Comparison: handle Rust Ord/PartialOrd
- Boolean: handle Rust's `&&`, `||`, `!`
- Add Rust-specific mutators for Option, Result patterns

## Phase 8: C# Language Adapter

### 8.1 C# Toolchain Integration
Create `lib/muex/language/csharp.ex`:
- Use Roslyn API via Port or HTTP service
- Or create a .NET tool that exposes parsing/compilation as JSON API
- Implement `parse/1` to parse C# source to syntax tree
- Implement `unparse/1` using Roslyn formatting
- Implement `compile/2` to compile C# to assembly and load
- Set `file_extensions/0` to return `[".cs"]`
- Set `test_file_pattern/0` to match xUnit/NUnit conventions

### 8.2 C# AST Adaptation Layer
Create `lib/muex/language/csharp/ast_adapter.ex`:
- Convert Roslyn SyntaxTree to normalized format
- Map C# operators to generic mutation points
- Handle C# properties, LINQ, async/await
- Preserve type information and attributes

### 8.3 C# Test Runner Integration
Update `lib/muex/runner.ex` or create C#-specific runner:
- Execute `dotnet test` for C# projects
- Parse test output (--logger:trx or JSON format)
- Map test failures to mutation results
- Handle C# compilation errors as invalid mutations

### 8.4 C# Mutator Adaptations
Create or adapt mutators for C#:
- Arithmetic: handle checked/unchecked contexts
- Comparison: handle nullable reference types
- Boolean: handle C# logical operators
- Add C# LINQ query mutators
- Add C# null-coalescing operator mutators (??)
- Add C# async/await mutators

## Phase 9: Documentation and Publishing

### 9.1 Enhanced Documentation
- Add comprehensive README with examples for all languages
- Create guides for each language adapter
- Document all mutator types with examples
- Add troubleshooting section
- Create video tutorials or GIFs

### 9.2 Example Projects
Create example directories:
- `examples/elixir_project/` - Phoenix web application
- `examples/erlang_project/` - OTP application
- `examples/rust_project/` - CLI tool with tests
- `examples/csharp_project/` - ASP.NET Core API

### 9.3 Hex Package Publication
- Update mix.exs with complete metadata
- Ensure all dependencies are properly specified
- Generate ex_doc documentation
- Publish to hex.pm
- Set up automatic releases via GitHub Actions

### 9.4 Community and Support
- Create CONTRIBUTING.md
- Add issue templates for bug reports and feature requests
- Set up GitHub Discussions
- Create benchmarks comparing with other mutation testing tools

## Implementation Notes

### Language Adapter Complexity
Each language adapter requires:
1. Parser integration (native or external)
2. AST normalization layer
3. Compilation/execution strategy
4. Test framework integration
5. Language-specific mutator adaptations

### Cross-Platform Considerations
- Rust and C# adapters need respective toolchains installed
- Test on Linux, macOS, Windows
- Provide Docker images with all toolchains
- Add toolchain detection and helpful error messages

### Backwards Compatibility
- Maintain API stability for Elixir adapter
- Version configuration file format
- Deprecate features gracefully with warnings
