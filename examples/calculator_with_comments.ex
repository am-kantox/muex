defmodule CalculatorWithComments do
  @moduledoc """
  This is a module for testing comment preservation.
  """

  # This is a single-line comment
  # that spans multiple lines
  # and should be preserved
  def add(a, b) do
    # Add two numbers
    a + b
  end

  # Another multiline comment
  # with important information
  # that must not be lost
  def subtract(a, b) do
    a - b
  end

  # Final comment
  def multiply(a, b) do
    a * b
  end
end
