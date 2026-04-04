defmodule Muex.Mutator.StatementDeletionTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.StatementDeletion

  @context %{file: "test.ex"}

  describe "mutate/2 - __block__ with multiple statements" do
    test "two statements: produces one mutation deleting the first" do
      ast =
        {:__block__, [line: 1],
         [
           {:=, [line: 1], [{:x, [], Elixir}, 1]},
           {:+, [line: 2], [{:x, [], Elixir}, 2]}
         ]}

      mutations = StatementDeletion.mutate(ast, @context)

      assert [mutation] = mutations
      # Deleting the first statement collapses the block to the last expr
      assert mutation.ast == {:+, [line: 2], [{:x, [], Elixir}, 2]}
      assert mutation.description =~ "delete statement 1 of 2"
    end

    test "three statements: produces two mutations (first and second)" do
      stmt1 = {:=, [line: 1], [{:x, [], Elixir}, 1]}
      stmt2 = {:=, [line: 2], [{:y, [], Elixir}, 2]}
      stmt3 = {:+, [line: 3], [{:x, [], Elixir}, {:y, [], Elixir}]}

      ast = {:__block__, [line: 1], [stmt1, stmt2, stmt3]}

      mutations = StatementDeletion.mutate(ast, @context)

      assert length(mutations) == 2

      # First mutation: delete stmt1, keep stmt2 + stmt3
      assert Enum.any?(mutations, fn m ->
               m.ast == {:__block__, [line: 1], [stmt2, stmt3]} and
                 m.description =~ "delete statement 1 of 3"
             end)

      # Second mutation: delete stmt2, keep stmt1 + stmt3
      assert Enum.any?(mutations, fn m ->
               m.ast == {:__block__, [line: 1], [stmt1, stmt3]} and
                 m.description =~ "delete statement 2 of 3"
             end)
    end

    test "four statements: produces three mutations" do
      stmts = for i <- 1..4, do: {:stmt, [line: i], [i]}
      ast = {:__block__, [line: 1], stmts}

      mutations = StatementDeletion.mutate(ast, @context)

      assert length(mutations) == 3
    end

    test "never deletes the last statement" do
      stmt1 = {:call, [line: 1], [:a]}
      stmt2 = {:call, [line: 2], [:b]}
      stmt3 = {:result, [line: 3], []}

      ast = {:__block__, [line: 1], [stmt1, stmt2, stmt3]}

      mutations = StatementDeletion.mutate(ast, @context)

      # Every mutation should still contain stmt3
      assert Enum.all?(mutations, fn m ->
               case m.ast do
                 {:__block__, _, stmts} -> List.last(stmts) == stmt3
                 single -> single == stmt3
               end
             end)
    end

    test "block collapse: removing from 2-statement block produces bare expression" do
      stmt1 = {:setup, [line: 1], []}
      stmt2 = {:result, [line: 2], []}

      ast = {:__block__, [line: 1], [stmt1, stmt2]}

      [mutation] = StatementDeletion.mutate(ast, @context)

      # Should collapse to bare expression, not {:__block__, _, [stmt2]}
      assert mutation.ast == stmt2
    end
  end

  describe "mutate/2 - metadata" do
    test "includes proper metadata" do
      ast =
        {:__block__, [line: 5],
         [
           {:=, [line: 5], [{:x, [], Elixir}, 1]},
           {:x, [line: 6], Elixir}
         ]}

      context = %{file: "lib/my_module.ex"}
      [mutation] = StatementDeletion.mutate(ast, context)

      assert mutation.mutator == Muex.Mutator.StatementDeletion
      assert mutation.description =~ "StatementDeletion:"
      assert mutation.location.file == "lib/my_module.ex"
      assert mutation.location.line == 5
    end
  end

  describe "mutate/2 - non-matching nodes" do
    test "single-statement block returns empty" do
      ast = {:__block__, [line: 1], [{:x, [], Elixir}]}

      assert [] = StatementDeletion.mutate(ast, @context)
    end

    test "non-block nodes return empty" do
      assert [] = StatementDeletion.mutate({:+, [line: 1], [1, 2]}, @context)
      assert [] = StatementDeletion.mutate(:foo, @context)
      assert [] = StatementDeletion.mutate(42, @context)
      assert [] = StatementDeletion.mutate("hello", @context)
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "StatementDeletion" = StatementDeletion.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = StatementDeletion.description()
      assert is_binary(desc)
      assert desc =~ "statement"
    end
  end
end
