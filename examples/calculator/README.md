# Calculator Example

A simple calculator application demonstrating mutation testing with Muex.

## Overview

This project provides basic arithmetic and mathematical operations:
- Arithmetic: `add/2`, `subtract/2`, `multiply/2`, `divide/2`
- Mathematical functions: `power/2`, `abs/1`, `factorial/1`
- Comparisons: `max/2`, `min/2`
- Predicates: `positive?/1`, `negative?/1`, `zero?/1`

## Running Tests

```bash
mix test
```

## Running Mutation Testing

Run mutation testing on all code:

```bash
mix muex
```

Run with specific mutators:

```bash
mix muex --mutators arithmetic,comparison
```

Run with custom concurrency and timeout:

```bash
mix muex --max-workers 2 --timeout 10000
```

## Results

Mutation testing with muex is fully functional and produces excellent results:

```
Mutation Testing Results
==================================================
Total mutants: 249
Killed: 216 (caught by tests)
Survived: 31 (not caught by tests)
Invalid: 0 (compilation errors)
Timeout: 2
==================================================
Mutation Score: 86.75%
```

The comprehensive test suite catches 86.75% of mutations, demonstrating strong test quality. The 31 survived mutations indicate areas where additional test coverage could be beneficial.

### Fixes Applied to Muex

While setting up this example, several critical fixes were applied to the muex library:

1. **Port.open with :spawn_executable**: Fixed Port.open to properly use `:spawn_executable` with charlists for command and environment variables, and added safe_close to handle already-closed ports
2. **AST mutation matching**: Added `original_ast` field to mutations so the compiler can correctly identify which AST node to replace (previously tried to match mutated AST against original code, which never matched)
3. **File replacement**: Modified worker to replace original file content with mutated content instead of creating separate files that cause module conflicts
4. **Beam file cleanup**: Added logic to delete compiled .beam files before running mutated tests

These fixes enable full end-to-end mutation testing with high accuracy.

## Project Structure

- `lib/calculator.ex` - Main calculator module with 13 functions covering arithmetic, mathematical operations, comparisons, and predicates
- `test/calculator_test.exs` - Comprehensive test suite with 47 tests
- `mix.exs` - Project configuration with muex dependency

