defmodule Muex.Mutator.BooleanTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Boolean

  describe "mutate/2" do
    test "mutates and operator" do
      ast = {:and, [line: 1], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:or, [line: 1], [:a, :b]}))
    end

    test "mutates or operator" do
      ast = {:or, [line: 2], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:and, [line: 2], [:x, :y]}))
    end

    test "mutates && operator" do
      ast = {:&&, [line: 3], [:a, :b]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:||, [line: 3], [:a, :b]}))
    end

    test "mutates || operator" do
      ast = {:||, [line: 4], [:x, :y]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == {:&&, [line: 4], [:x, :y]}))
    end

    test "mutates true literal" do
      ast = true
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == false))
    end

    test "mutates false literal" do
      ast = false
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == true))
    end

    test "removes negation operator" do
      ast = {:not, [line: 5], [:x]}
      context = %{file: "test.ex"}

      mutations = Boolean.mutate(ast, context)

      assert [_] = mutations
      assert Enum.any?(mutations, &(&1.ast == :x))
    end

    test "includes proper metadata in mutations" do
      ast = {:and, [line: 10], [:a, :b]}
      context = %{file: "lib/my_module.ex"}

      [mutation] = Boolean.mutate(ast, context)

      assert mutation.mutator == Muex.Mutator.Boolean
      assert mutation.description =~ "Boolean:"
      assert mutation.location.file == "lib/my_module.ex"
      assert mutation.location.line == 10
    end

    test "returns empty list for non-boolean operators" do
      ast = {:+, [line: 1], [:a, :b]}
      context = %{}

      assert [] = Boolean.mutate(ast, context)
    end

    test "returns empty list for other atoms" do
      ast = :ok
      context = %{}

      assert [] = Boolean.mutate(ast, context)
    end

    test "returns empty list for numbers" do
      ast = 42
      context = %{}

      assert [] = Boolean.mutate(ast, context)
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "Boolean" = Boolean.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = Boolean.description()
      assert is_binary(desc)
      assert desc =~ "boolean"
    end
  end
end
