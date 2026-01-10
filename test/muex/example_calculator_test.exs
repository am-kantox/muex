defmodule Muex.ExampleCalculatorTest do
  use ExUnit.Case, async: true

  alias Muex.ExampleCalculator

  describe "arithmetic operations" do
    test "add/2 adds two numbers" do
      assert ExampleCalculator.add(2, 3) == 5
      assert ExampleCalculator.add(0, 5) == 5
      assert ExampleCalculator.add(-1, 1) == 0
    end

    test "subtract/2 subtracts two numbers" do
      assert ExampleCalculator.subtract(5, 3) == 2
      assert ExampleCalculator.subtract(10, 5) == 5
      assert ExampleCalculator.subtract(0, 5) == -5
    end

    test "multiply/2 multiplies two numbers" do
      assert ExampleCalculator.multiply(2, 3) == 6
      assert ExampleCalculator.multiply(0, 5) == 0
      assert ExampleCalculator.multiply(-2, 3) == -6
    end

    test "divide/2 divides two numbers" do
      assert ExampleCalculator.divide(6, 2) == 3.0
      assert ExampleCalculator.divide(10, 5) == 2.0
      assert ExampleCalculator.divide(7, 2) == 3.5
    end
  end

  describe "comparison operations" do
    test "compare_equal/2 checks equality" do
      assert ExampleCalculator.compare_equal(5, 5) == true
      assert ExampleCalculator.compare_equal(3, 5) == false
      assert ExampleCalculator.compare_equal(0, 0) == true
    end

    test "compare_greater/2 checks greater than" do
      assert ExampleCalculator.compare_greater(5, 3) == true
      assert ExampleCalculator.compare_greater(3, 5) == false
      assert ExampleCalculator.compare_greater(5, 5) == false
    end
  end
end
