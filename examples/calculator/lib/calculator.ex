defmodule Calculator do
  @moduledoc """
  A simple calculator module for demonstrating mutation testing.
  Provides basic arithmetic operations with validation.
  """

  @doc """
  Adds two numbers together.
  """
  def add(a, b) when is_number(a) and is_number(b) do
    a + b
  end

  @doc """
  Subtracts the second number from the first.
  """
  def subtract(a, b) when is_number(a) and is_number(b) do
    a - b
  end

  @doc """
  Multiplies two numbers together.
  """
  def multiply(a, b) when is_number(a) and is_number(b) do
    a * b
  end

  @doc """
  Divides the first number by the second.
  Returns {:ok, result} on success, {:error, reason} on failure.
  """
  def divide(_a, 0) do
    {:error, :division_by_zero}
  end

  def divide(a, b) when is_number(a) and is_number(b) do
    {:ok, a / b}
  end

  @doc """
  Calculates the power of a number.
  """
  def power(base, exponent) when is_number(base) and is_integer(exponent) do
    :math.pow(base, exponent)
  end

  @doc """
  Calculates the absolute value of a number.
  """
  def abs(n) when is_number(n) do
    if n < 0 do
      -n
    else
      n
    end
  end

  @doc """
  Checks if a number is positive.
  """
  def positive?(n) when is_number(n) do
    n > 0
  end

  @doc """
  Checks if a number is negative.
  """
  def negative?(n) when is_number(n) do
    n < 0
  end

  @doc """
  Checks if a number is zero.
  """
  def zero?(n) when is_number(n) do
    n == 0
  end

  @doc """
  Returns the maximum of two numbers.
  """
  def max(a, b) when is_number(a) and is_number(b) do
    if a >= b do
      a
    else
      b
    end
  end

  @doc """
  Returns the minimum of two numbers.
  """
  def min(a, b) when is_number(a) and is_number(b) do
    if a <= b do
      a
    else
      b
    end
  end

  @doc """
  Calculates the factorial of a non-negative integer.
  """
  def factorial(0) do
    1
  end

  def factorial(n) when is_integer(n) and n > 0 do
    n * factorial(n - 1)
  end
end
