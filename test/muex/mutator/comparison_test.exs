defmodule Muex.Mutator.ComparisonTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Comparison

  describe "mutate/2" do
    test "mutates == operator" do
      ast = {:==, [line: 1], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Comparison.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:!=, [line: 1], [:a, :b]}))
    end

    test "mutates != operator" do
      ast = {:!=, [line: 2], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Comparison.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:==, [line: 2], [:x, :y]}))
    end

    test "mutates > operator" do
      ast = {:>, [line: 3], [:m, :n]}
      context = %{file: "test.ex"}

      mutations = Comparison.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:<, [line: 3], [:m, :n]}))
      assert Enum.any?(mutations, &(&1.ast == {:>=, [line: 3], [:m, :n]}))
    end

    test "mutates < operator" do
      ast = {:<, [line: 4], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Comparison.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:>, [line: 4], [:a, :b]}))
      assert Enum.any?(mutations, &(&1.ast == {:<=, [line: 4], [:a, :b]}))
    end

    test "mutates >= operator" do
      ast = {:>=, [line: 5], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Comparison.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:<=, [line: 5], [:x, :y]}))
      assert Enum.any?(mutations, &(&1.ast == {:>, [line: 5], [:x, :y]}))
    end

    test "mutates <= operator" do
      ast = {:<=, [line: 6], [:p, :q]}
      context = %{file: "test.ex"}

      mutations = Comparison.mutate(ast, context)

      assert [_, _] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:>=, [line: 6], [:p, :q]}))
      assert Enum.any?(mutations, &(&1.ast == {:<, [line: 6], [:p, :q]}))
    end

    test "mutates === operator" do
      ast = {:===, [line: 7], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Comparison.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:!==, [line: 7], [:a, :b]}))
    end

    test "mutates !== operator" do
      ast = {:!==, [line: 8], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Comparison.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:===, [line: 8], [:x, :y]}))
    end

    test "includes proper metadata in mutations" do
      ast = {:==, [line: 10], [:a, :b]}
      context = %{file: "lib/my_module.ex"}

      [mutation] = Comparison.mutate(ast, context)

      assert mutation.mutator == Muex.Mutator.Comparison
      assert mutation.description =~ "Comparison:"
      assert mutation.location.file == "lib/my_module.ex"
      assert mutation.location.line == 10
    end

    test "returns empty list for non-comparison operators" do
      ast = {:foo, [], []}
      context = %{}

      assert [] = Comparison.mutate(ast, context)
    end

    test "returns empty list for arithmetic operators" do
      ast = {:+, [line: 1], [:a, :b]}
      context = %{}

      assert [] = Comparison.mutate(ast, context)
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "Comparison" = Comparison.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = Comparison.description()
      assert is_binary(desc)
      assert desc =~ "comparison"
    end
  end
end
