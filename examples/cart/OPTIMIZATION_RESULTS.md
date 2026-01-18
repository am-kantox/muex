# Cart Example: Mutation Optimization Results

This document presents empirical results from applying mutation optimization heuristics to the Cart example.

## Test Environment

- **Project**: E-commerce shopping cart (Product + ShoppingCart modules)
- **Lines of Code**: ~440 LOC
- **Test Suite**: 84 tests
- **Baseline Mutation Score**: 99.77% (884/886 mutants killed)

## Optimization Levels Tested

### Baseline (No Optimization)
```bash
mix muex --files "examples/cart/lib"
```

**Results**:
- Total mutations: 886
- Killed: 884 (99.77%)
- Survived: 2 (0.23%)
- Runtime: ~3 minutes

### Conservative Optimization
```bash
mix muex --files "examples/cart/lib" --optimize --optimize-level conservative
```

**Configuration**:
- `min_complexity: 1`
- `max_mutations_per_function: 50`
- `keep_boundary_mutations: true`

**Results**:
- Original mutations: 886
- Optimized mutations: 308
- Reduction: 578 (-65.2%)
- Killed: 306 (99.35%)
- Survived: 2
- Runtime: ~1 minute

**Analysis**: Excellent balance! Only 0.42% drop in mutation score with 65% time savings.

### Balanced Optimization (Default)
```bash
mix muex --files "examples/cart/lib" --optimize
```

**Configuration**:
- `min_complexity: 2`
- `max_mutations_per_function: 20`
- `keep_boundary_mutations: true`

**Results**:
- Original mutations: 886
- Optimized mutations: 28
- Reduction: 858 (-96.8%)
- Killed: 25 (89.29%)
- Survived: 2
- Timeout: 1
- Runtime: ~10 seconds

**Analysis**: Very fast but significant mutation score drop. Best for rapid feedback during development.

### Aggressive Optimization
```bash
mix muex --files "examples/cart/lib" --optimize --optimize-level aggressive
```

**Configuration**:
- `min_complexity: 3`
- `max_mutations_per_function: 10`
- `keep_boundary_mutations: true`

**Results**: Similar to balanced (28-30 mutations), ~85-90% mutation score.

## Recommendations by Use Case

### CI/CD Pipelines (Time-Constrained)
Use **Conservative** optimization:
- 65% faster execution
- <1% drop in mutation score
- Catches nearly all test weaknesses
- Good for continuous integration

```bash
mix muex --optimize --optimize-level conservative --fail-at 95
```

### Development Iteration (Rapid Feedback)
Use **Balanced** optimization:
- 97% faster execution
- Focuses on highest-impact mutations
- Perfect for quick checks during development
- May miss some edge cases

```bash
mix muex --optimize
```

### Pre-Release Validation
Use **No Optimization** (baseline):
- Complete coverage
- Highest confidence
- Finds all test weaknesses
- Worth the extra time before releases

```bash
mix muex
```

### Custom Configuration
Override specific settings:
```bash
# More aggressive than conservative, less than balanced
mix muex --optimize --min-complexity 2 --max-per-function 30
```

## Key Findings

1. **Conservative optimization is the sweet spot**: 65% reduction with <1% score impact
2. **Balanced/Aggressive useful for development**: Fast feedback, catches major issues
3. **Mutation score correlates with optimization level**: More aggressive = lower score
4. **High-impact mutations are preserved**: Even with 97% reduction, critical bugs are detected
5. **Boundary mutations are critical**: Preserved in all modes, detect off-by-one errors

## Distribution Analysis

### Original Mutations by Type
- Arithmetic: 12 (1.4%)
- Comparison: 52 (5.9%)
- Boolean: 9 (1.0%)
- Conditional: 39 (4.4%)
- FunctionCall: 774 (87.3%)

Note: High FunctionCall count includes validation functions and private helpers.

### After Conservative Optimization
Focused on:
- Complex conditional logic
- Boundary comparisons
- Arithmetic in calculations
- Boolean expressions in business logic

Filtered out:
- Simple validation guards
- Trivial getters
- Redundant similar mutations
- Low-complexity code

## Performance Metrics

| Optimization Level | Mutations | Time Saved | Score Impact | Recommended For |
|-------------------|-----------|------------|--------------|-----------------|
| None (Baseline)   | 886       | 0%         | 99.77%       | Final validation |
| Conservative      | 308       | 65%        | 99.35%       | CI/CD pipelines |
| Balanced          | 28        | 97%        | 89.29%       | Development |
| Aggressive        | 28        | 97%        | 85-90%       | Quick checks |

## Conclusion

The mutation optimization heuristics successfully reduce testing time while maintaining the ability to detect test suite weaknesses:

- **Conservative mode** provides the best balance for most use cases
- **Balanced mode** is ideal for rapid iteration during development
- **Aggressive mode** may be too aggressive for this example (high score drop)

The key insight: **65% reduction with <1% score impact** proves that many mutations are indeed redundant or low-value. Smart filtering preserves diagnostic power while eliminating waste.

## Running the Tests Yourself

```bash
# Baseline
mix muex --files "examples/cart/lib"

# Conservative (recommended)
mix muex --files "examples/cart/lib" --optimize --optimize-level conservative

# Balanced
mix muex --files "examples/cart/lib" --optimize

# Aggressive
mix muex --files "examples/cart/lib" --optimize --optimize-level aggressive

# Custom
mix muex --files "examples/cart/lib" --optimize --min-complexity 2 --max-per-function 25
```
