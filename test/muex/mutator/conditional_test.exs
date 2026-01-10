defmodule Muex.Mutator.ConditionalTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.Conditional

  describe "mutate/2 - if with else" do
    test "inverts condition and provides branch mutations" do
      ast = {:if, [line: 1], [:condition, [do: :true_branch, else: :false_branch]]}
      context = %{file: "test.ex"}

      mutations = Conditional.mutate(ast, context)

      assert [_, _, _] = mutations

      # Check for inverted condition
      assert Enum.any?(mutations, fn m ->
               match?(
                 {:if, [line: 1],
                  [{:not, [], [:condition]}, [do: :true_branch, else: :false_branch]]},
                 m.ast
               )
             end)

      # Check for always true branch
      assert Enum.any?(mutations, &(&1.ast == :true_branch))

      # Check for always false branch
      assert Enum.any?(mutations, &(&1.ast == :false_branch))
    end
  end

  describe "mutate/2 - if without else" do
    test "inverts condition and provides mutations" do
      ast = {:if, [line: 2], [:x, [do: :body]]}
      context = %{file: "test.ex"}

      mutations = Conditional.mutate(ast, context)

      assert [_, _, _] = mutations

      # Check for inverted condition
      assert Enum.any?(mutations, fn m ->
               match?({:if, [line: 2], [{:not, [], [:x]}, [do: :body]]}, m.ast)
             end)

      # Check for always execute body
      assert Enum.any?(mutations, &(&1.ast == :body))

      # Check for remove if
      assert Enum.any?(mutations, &(&1.ast == nil))
    end
  end

  describe "mutate/2 - unless without else" do
    test "converts to if and provides mutations" do
      ast = {:unless, [line: 3], [:condition, [do: :body]]}
      context = %{file: "test.ex"}

      mutations = Conditional.mutate(ast, context)

      assert [_, _] = mutations

      # Check for unless to if conversion
      assert Enum.any?(mutations, fn m ->
               match?({:if, [line: 3], [:condition, [do: :body]]}, m.ast)
             end)

      # Check for always execute body
      assert Enum.any?(mutations, &(&1.ast == :body))
    end
  end

  describe "mutate/2 - unless with else" do
    test "converts to if and provides branch mutations" do
      ast = {:unless, [line: 4], [:x, [do: :unless_body, else: :else_body]]}
      context = %{file: "test.ex"}

      mutations = Conditional.mutate(ast, context)

      assert [_, _, _] = mutations

      # Check for unless to if conversion
      assert Enum.any?(mutations, fn m ->
               match?({:if, [line: 4], [:x, [do: :unless_body, else: :else_body]]}, m.ast)
             end)

      # Check for always execute unless body
      assert Enum.any?(mutations, &(&1.ast == :unless_body))

      # Check for always execute else
      assert Enum.any?(mutations, &(&1.ast == :else_body))
    end
  end

  describe "mutate/2 - metadata" do
    test "includes proper metadata in mutations" do
      ast = {:if, [line: 10], [:cond, [do: :body]]}
      context = %{file: "lib/my_module.ex"}

      mutations = Conditional.mutate(ast, context)

      assert [mutation1, _, _] = mutations
      assert mutation1.mutator == Muex.Mutator.Conditional
      assert mutation1.description =~ "Conditional:"
      assert mutation1.location.file == "lib/my_module.ex"
      assert mutation1.location.line == 10
    end
  end

  describe "mutate/2 - edge cases" do
    test "returns empty list for non-conditional expressions" do
      ast = {:+, [line: 1], [1, 2]}
      context = %{}

      assert [] = Conditional.mutate(ast, context)
    end

    test "returns empty list for atoms" do
      ast = :foo
      context = %{}

      assert [] = Conditional.mutate(ast, context)
    end

    test "returns empty list for numbers" do
      ast = 42
      context = %{}

      assert [] = Conditional.mutate(ast, context)
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "Conditional" = Conditional.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = Conditional.description()
      assert is_binary(desc)
      assert desc =~ "conditional"
    end
  end
end
