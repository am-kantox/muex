defmodule Muex.Mutator.ArithmeticTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Arithmetic

  describe "mutate/2" do
    test "mutates addition operator" do
      ast = {:+, [line: 1], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:-, [line: 1], [:a, :b]}))
      assert Enum.any?(mutations, &(&1.ast == 0))
    end

    test "mutates subtraction operator" do
      ast = {:-, [line: 2], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:+, [line: 2], [:x, :y]}))
      assert Enum.any?(mutations, &(&1.ast == 0))
    end

    test "mutates multiplication operator" do
      ast = {:*, [line: 3], [:m, :n]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:/, [line: 3], [:m, :n]}))
      assert Enum.any?(mutations, &(&1.ast == 1))
    end

    test "mutates division operator" do
      ast = {:/, [line: 4], [:p, :q]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:*, [line: 4], [:p, :q]}))
      assert Enum.any?(mutations, &(&1.ast == 1))
    end

    test "produces correct mutation descriptions" do
      ast = {:+, [line: 5], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [mutation1, mutation2] = mutations
      assert mutation1.description == "Arithmetic: + to -"
      assert mutation2.description == "Arithmetic: + to 0 (remove)"
    end

    test "includes proper metadata in mutations" do
      ast = {:*, [line: 10], [:x, :y]}
      context = %{file: "lib/calculator.ex"}

      mutations = Arithmetic.mutate(ast, context)

      assert [mutation1, mutation2] = mutations
      assert mutation1.mutator == Muex.Mutator.Arithmetic
      assert mutation1.location.file == "lib/calculator.ex"
      assert mutation1.location.line == 10
      assert mutation2.mutator == Muex.Mutator.Arithmetic
      assert mutation2.location.line == 10
    end

    test "returns empty list for non-arithmetic operators" do
      ast = {:foo, [], []}
      context = %{}

      assert [] = Arithmetic.mutate(ast, context)
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "Arithmetic" = Arithmetic.name()
    end
  end
end
