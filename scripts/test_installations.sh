#!/bin/bash
# Test script for verifying escript and hex archive installations

set -e

echo "==================================="
echo "Testing Muex Installation Methods"
echo "==================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test directory
TEST_PROJECT="/tmp/muex_test_project_$$"

cleanup() {
    echo ""
    echo "${YELLOW}Cleaning up...${NC}"
    rm -rf "$TEST_PROJECT"
}

trap cleanup EXIT

# Create test project
echo "${YELLOW}Creating test Elixir project...${NC}"
mix new "$TEST_PROJECT" --sup
cd "$TEST_PROJECT"

# Create a simple module to test
cat > lib/muex_test_project.ex << 'EOF'
defmodule MuexTestProject do
  def add(a, b) do
    a + b
  end

  def multiply(a, b) do
    a * b
  end

  def is_positive?(n) do
    n > 0
  end
end
EOF

# Create test file
cat > test/muex_test_project_test.exs << 'EOF'
defmodule MuexTestProjectTest do
  use ExUnit.Case

  test "add/2 adds two numbers" do
    assert MuexTestProject.add(2, 3) == 5
    assert MuexTestProject.add(-1, 1) == 0
  end

  test "multiply/2 multiplies two numbers" do
    assert MuexTestProject.multiply(2, 3) == 6
    assert MuexTestProject.multiply(-1, 5) == -5
  end

  test "is_positive?/1 checks if number is positive" do
    assert MuexTestProject.is_positive?(5)
    refute MuexTestProject.is_positive?(-5)
    refute MuexTestProject.is_positive?(0)
  end
end
EOF

echo "${GREEN}Test project created${NC}"
echo ""

# Test 1: Escript
echo "==================================="
echo "Test 1: Escript Installation"
echo "==================================="
echo ""

ESCRIPT_PATH="$OLDPWD/muex"

if [ -f "$ESCRIPT_PATH" ]; then
    echo "${YELLOW}Testing escript...${NC}"
    
    # Test version
    echo "Testing --version:"
    "$ESCRIPT_PATH" --version
    echo ""
    
    # Test help
    echo "Testing --help (first 10 lines):"
    "$ESCRIPT_PATH" --help | head -10
    echo ""
    
    # Run mutation testing with limited scope
    echo "Running mutation testing with escript:"
    if "$ESCRIPT_PATH" --files "lib/muex_test_project.ex" --max-mutations 10 --format terminal; then
        echo "${GREEN}✓ Escript test passed${NC}"
    else
        echo "${RED}✗ Escript test failed${NC}"
        exit 1
    fi
else
    echo "${RED}✗ Escript not found at $ESCRIPT_PATH${NC}"
    echo "${YELLOW}Run 'mix escript.build' first${NC}"
    exit 1
fi

echo ""

# Test 2: Hex Archive (if installed)
echo "==================================="
echo "Test 2: Hex Archive Installation"
echo "==================================="
echo ""

# Check if archive is installed
if mix archive | grep -q "muex"; then
    echo "${YELLOW}Testing hex archive...${NC}"
    
    # Run mutation testing with limited scope
    echo "Running mutation testing with mix muex:"
    if mix muex --files "lib/muex_test_project.ex" --max-mutations 10 --format terminal; then
        echo "${GREEN}✓ Hex archive test passed${NC}"
    else
        echo "${RED}✗ Hex archive test failed${NC}"
        exit 1
    fi
else
    echo "${YELLOW}Hex archive not installed${NC}"
    echo "${YELLOW}To test, run: mix archive.install $OLDPWD/muex-0.2.0.ez${NC}"
    echo "${YELLOW}Then run this script again${NC}"
fi

echo ""
echo "==================================="
echo "${GREEN}All tests passed!${NC}"
echo "==================================="
