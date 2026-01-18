# Cart Example - Real-World E-Commerce Business Logic

This example demonstrates mutation testing on a realistic shopping cart implementation with comprehensive business logic including pricing, discounts, inventory management, taxes, and shipping calculations.

## Features

### Product Management (`Cart.Product`)
- Product creation with validation (price, stock, weight, name)
- Stock availability checking
- Dynamic pricing with bulk discounts (5%, 10%, 15%, 20% at different tiers)
- Stock reduction and restoration
- Restock threshold calculation by category
- Shipping weight calculations
- Seasonal discount application
- Category-based business rules

### Shopping Cart (`Cart.ShoppingCart`)
- Add/remove/update items with stock validation
- Subtotal calculation with bulk discounts
- Coupon system with minimum purchase requirements
  - SAVE10: 10% off on orders $20+
  - SAVE20: 20% off on orders $50+
  - SAVE50: 50% off on orders $100+ (capped at $100 discount)
  - FREESHIP: Free shipping
- Address validation and shipping cost calculation
  - Weight-based tiers
  - Zone multipliers (US, CA, MX, International)
- Tax calculation (only on taxable items, after coupon discounts)
- Checkout validation
- Order summary generation

## Test Coverage

The example includes 84 comprehensive tests covering:
- Input validation and error handling
- Boundary conditions
- Complex business logic paths
- Edge cases (zero/negative values, insufficient stock, etc.)
- Integration scenarios (coupons + shipping + taxes)

## Mutation Testing Results

### Baseline (All Mutations)
```
Total mutants: 886
Killed: 884 (99.77%)
Survived: 2 (0.23%)
Invalid: 0
Timeout: 0
```

The high mutation score (99.77%) demonstrates excellent test quality. The 2 survived mutations are in private validation functions that are indirectly tested.

### With Optimization (Heuristics Enabled)
When using the mutation reduction heuristics:
- Equivalent mutants filtered out
- Low-complexity code mutations removed
- Similar mutations clustered and sampled
- High-impact mutations prioritized

Expected reduction: 50-70% fewer mutations while maintaining comparable mutation score.

## Running Mutation Testing

From the muex root directory:

```bash
# Run all mutations (baseline)
mix muex --files "examples/cart/lib"

# Run with optimization (future feature)
mix muex --files "examples/cart/lib" --optimize

# Run with specific mutators
mix muex --files "examples/cart/lib" --mutators arithmetic,comparison,boolean

# Generate HTML report
mix muex --files "examples/cart/lib" --format html
```

## Running Tests Only

```bash
cd examples/cart
mix test
```

## Key Business Logic Patterns

1. **Tiered Discounts**: Quantity-based bulk pricing
2. **Coupon Validation**: Minimum purchase requirements and discount caps
3. **Multi-Factor Pricing**: Combines base price, bulk discount, coupon, tax, shipping
4. **Category Rules**: Different restock thresholds and seasonal discounts by category
5. **Stock Management**: Add operations check total availability, not just increment
6. **Tax Calculation**: Proportional tax after discounts, only on taxable items

## Lessons for Mutation Testing

This example demonstrates several important patterns:

1. **Boundary Conditions**: Many mutations focus on `>=`, `<=`, `==` in discount/shipping tiers
2. **Complex Calculations**: Multi-step price/tax calculations create many arithmetic mutations
3. **Conditional Logic**: Category-based rules and validation create boolean/conditional mutations
4. **Guard Clauses**: Validation code generates many mutations but is well-tested
5. **Integration Testing**: Tests that exercise full workflows (add→coupon→address→total) kill more mutants

The high mutation score indicates that tests properly exercise:
- All discount tiers
- All coupon types and validation rules
- All shipping zones and weight tiers
- Error paths and edge cases
- Integration between modules
