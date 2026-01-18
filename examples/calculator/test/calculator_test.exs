defmodule CalculatorTest do
  use ExUnit.Case
  doctest Calculator

  describe "add/2" do
    test "adds two positive numbers" do
      assert Calculator.add(2, 3) == 5
    end

    test "adds positive and negative numbers" do
      assert Calculator.add(5, -3) == 2
    end

    test "adds two negative numbers" do
      assert Calculator.add(-5, -3) == -8
    end

    test "adds zero" do
      assert Calculator.add(0, 5) == 5
      assert Calculator.add(5, 0) == 5
    end

    test "adds floats" do
      assert Calculator.add(2.5, 3.5) == 6.0
    end
  end

  describe "subtract/2" do
    test "subtracts two positive numbers" do
      assert Calculator.subtract(5, 3) == 2
    end

    test "subtracts negative number" do
      assert Calculator.subtract(5, -3) == 8
    end

    test "subtracts from zero" do
      assert Calculator.subtract(0, 5) == -5
    end

    test "subtracts zero" do
      assert Calculator.subtract(5, 0) == 5
    end

    test "subtracts floats" do
      assert Calculator.subtract(5.5, 2.5) == 3.0
    end
  end

  describe "multiply/2" do
    test "multiplies two positive numbers" do
      assert Calculator.multiply(3, 4) == 12
    end

    test "multiplies by zero" do
      assert Calculator.multiply(5, 0) == 0
      assert Calculator.multiply(0, 5) == 0
    end

    test "multiplies by one" do
      assert Calculator.multiply(5, 1) == 5
      assert Calculator.multiply(1, 5) == 5
    end

    test "multiplies negative numbers" do
      assert Calculator.multiply(-3, 4) == -12
      assert Calculator.multiply(-3, -4) == 12
    end

    test "multiplies floats" do
      assert Calculator.multiply(2.5, 4.0) == 10.0
    end
  end

  describe "divide/2" do
    test "divides two positive numbers" do
      assert Calculator.divide(10, 2) == {:ok, 5.0}
    end

    test "divides by one" do
      assert Calculator.divide(5, 1) == {:ok, 5.0}
    end

    test "divides negative numbers" do
      assert Calculator.divide(-10, 2) == {:ok, -5.0}
      assert Calculator.divide(10, -2) == {:ok, -5.0}
      assert Calculator.divide(-10, -2) == {:ok, 5.0}
    end

    test "returns error on division by zero" do
      assert Calculator.divide(5, 0) == {:error, :division_by_zero}
      assert Calculator.divide(0, 0) == {:error, :division_by_zero}
    end

    test "divides floats" do
      assert Calculator.divide(7.5, 2.5) == {:ok, 3.0}
    end
  end

  describe "power/2" do
    test "calculates power of positive numbers" do
      assert Calculator.power(2, 3) == 8.0
    end

    test "calculates power with zero exponent" do
      assert Calculator.power(5, 0) == 1.0
    end

    test "calculates power with one exponent" do
      assert Calculator.power(5, 1) == 5.0
    end

    test "calculates power with negative exponent" do
      assert Calculator.power(2, -2) == 0.25
    end
  end

  describe "abs/1" do
    test "returns absolute value of positive number" do
      assert Calculator.abs(5) == 5
    end

    test "returns absolute value of negative number" do
      assert Calculator.abs(-5) == 5
    end

    test "returns zero for zero" do
      assert Calculator.abs(0) == 0
    end

    test "works with floats" do
      assert Calculator.abs(-3.5) == 3.5
      assert Calculator.abs(3.5) == 3.5
    end
  end

  describe "positive?/1" do
    test "returns true for positive numbers" do
      assert Calculator.positive?(5)
      assert Calculator.positive?(0.1)
    end

    test "returns false for negative numbers" do
      refute Calculator.positive?(-5)
      refute Calculator.positive?(-0.1)
    end

    test "returns false for zero" do
      refute Calculator.positive?(0)
    end
  end

  describe "negative?/1" do
    test "returns true for negative numbers" do
      assert Calculator.negative?(-5)
      assert Calculator.negative?(-0.1)
    end

    test "returns false for positive numbers" do
      refute Calculator.negative?(5)
      refute Calculator.negative?(0.1)
    end

    test "returns false for zero" do
      refute Calculator.negative?(0)
    end
  end

  describe "zero?/1" do
    test "returns true for zero" do
      assert Calculator.zero?(0)
      assert Calculator.zero?(0.0)
    end

    test "returns false for non-zero numbers" do
      refute Calculator.zero?(1)
      refute Calculator.zero?(-1)
      refute Calculator.zero?(0.1)
    end
  end

  describe "max/2" do
    test "returns larger number" do
      assert Calculator.max(5, 3) == 5
      assert Calculator.max(3, 5) == 5
    end

    test "returns first when equal" do
      assert Calculator.max(5, 5) == 5
    end

    test "works with negative numbers" do
      assert Calculator.max(-5, -3) == -3
      assert Calculator.max(-5, 3) == 3
    end

    test "works with floats" do
      assert Calculator.max(3.5, 3.2) == 3.5
    end
  end

  describe "min/2" do
    test "returns smaller number" do
      assert Calculator.min(5, 3) == 3
      assert Calculator.min(3, 5) == 3
    end

    test "returns first when equal" do
      assert Calculator.min(5, 5) == 5
    end

    test "works with negative numbers" do
      assert Calculator.min(-5, -3) == -5
      assert Calculator.min(-5, 3) == -5
    end

    test "works with floats" do
      assert Calculator.min(3.5, 3.2) == 3.2
    end
  end

  describe "factorial/1" do
    test "calculates factorial of zero" do
      assert Calculator.factorial(0) == 1
    end

    test "calculates factorial of one" do
      assert Calculator.factorial(1) == 1
    end

    test "calculates factorial of positive integers" do
      assert Calculator.factorial(5) == 120
      assert Calculator.factorial(3) == 6
      assert Calculator.factorial(4) == 24
    end
  end
end
