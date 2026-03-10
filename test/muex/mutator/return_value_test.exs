defmodule Muex.Mutator.ReturnValueTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.ReturnValue

  @context %{file: "test.ex"}

  describe "mutate/2 - single-expression body" do
    test "integer return: replaces with 0" do
      ast = {:def, [line: 1], [{:foo, [], [{:x, [], Elixir}]}, [do: 42]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == 0
      assert mutation.description =~ "replace return value of foo with 0"
    end

    test "float return: replaces with 0.0" do
      ast = {:def, [line: 1], [{:foo, [], []}, [do: 3.14]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == +0.0
    end

    test "string return: replaces with empty string" do
      ast = {:def, [line: 1], [{:greet, [], []}, [do: "hello"]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == ""
      assert mutation.description =~ ~s("")
    end

    test "boolean true: replaces with false" do
      ast = {:def, [line: 1], [{:valid?, [], []}, [do: true]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == false
    end

    test "boolean false: replaces with true" do
      ast = {:def, [line: 1], [{:valid?, [], []}, [do: false]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == true
    end

    test ":ok atom: replaces with :error" do
      ast = {:def, [line: 1], [{:do_thing, [], []}, [do: :ok]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == :error
    end

    test ":error atom: replaces with :ok" do
      ast = {:def, [line: 1], [{:do_thing, [], []}, [do: :error]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == :ok
    end

    test "{:ok, val} tuple: replaces with {:error, :mutated}" do
      ast = {:def, [line: 1], [{:fetch, [], []}, [do: {:ok, {:result, [], Elixir}}]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == {:error, :mutated}
      assert mutation.description =~ "{:error, :mutated}"
    end

    test "{:error, reason} tuple: replaces with {:ok, :mutated}" do
      ast = {:def, [line: 1], [{:fetch, [], []}, [do: {:error, "not found"}]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == {:ok, :mutated}
    end

    test "non-empty list: replaces with []" do
      ast = {:def, [line: 1], [{:items, [], []}, [do: [1, 2, 3]]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == []
    end

    test "map: replaces with %{}" do
      ast = {:def, [line: 1], [{:config, [], []}, [do: {:%{}, [line: 1], [a: 1]}]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == {:%{}, [], []}
    end

    test "struct: replaces with %{}" do
      struct_ast =
        {:%, [line: 1],
         [{:__aliases__, [alias: false], [:MyStruct]}, {:%{}, [line: 1], [field: 1]}]}

      ast = {:def, [line: 1], [{:new, [], []}, [do: struct_ast]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == {:%{}, [], []}
    end

    test "3+ element tuple: replaces with {}" do
      tuple_ast = {:{}, [line: 1], [:a, :b, :c]}
      ast = {:def, [line: 1], [{:triple, [], []}, [do: tuple_ast]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == {:{}, [], []}
    end

    test "variable/call fallback: replaces with nil" do
      ast = {:def, [line: 1], [{:compute, [], []}, [do: {:result, [line: 2], Elixir}]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == nil
    end
  end

  describe "mutate/2 - multi-statement body" do
    test "replaces only the last expression" do
      body =
        {:__block__, [],
         [
           {:=, [line: 1], [{:x, [], Elixir}, 1]},
           42
         ]}

      ast = {:def, [line: 1], [{:foo, [], []}, [do: body]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: {:__block__, _, stmts}]]} = mutation.ast
      # First statement preserved, last replaced with 0
      assert [{:=, [line: 1], [{:x, [], Elixir}, 1]}, 0] = stmts
    end

    test "skips when last expression is already the zero value" do
      body = {:__block__, [], [{:setup, [], []}, nil]}
      ast = {:def, [line: 1], [{:foo, [], []}, [do: body]]}

      assert [] = ReturnValue.mutate(ast, @context)
    end
  end

  describe "mutate/2 - defp" do
    test "works with private functions" do
      ast = {:defp, [line: 1], [{:helper, [], []}, [do: "result"]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      assert {:defp, _, _} = mutation.ast
      {:defp, _, [_, [do: body]]} = mutation.ast
      assert body == ""
    end
  end

  describe "mutate/2 - guard clauses" do
    test "extracts function name from when guard" do
      signature = {:when, [], [{:foo, [], [{:x, [], Elixir}]}, {:is_integer, [], [{:x, [], Elixir}]}]}
      ast = {:def, [line: 1], [signature, [do: 42]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      assert mutation.description =~ "foo"
    end
  end

  describe "mutate/2 - skip cases" do
    test "nil body returns empty" do
      ast = {:def, [line: 1], [{:foo, [], []}, [do: nil]]}

      assert [] = ReturnValue.mutate(ast, @context)
    end

    test "zero integer: replaces with nil" do
      ast = {:def, [line: 1], [{:foo, [], []}, [do: 0]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == nil
    end

    test "empty string: replaces with nil" do
      ast = {:def, [line: 1], [{:foo, [], []}, [do: ""]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == nil
    end

    test "empty list: replaces with nil" do
      ast = {:def, [line: 1], [{:foo, [], []}, [do: []]]}

      [mutation] = ReturnValue.mutate(ast, @context)

      {:def, _, [_, [do: body]]} = mutation.ast
      assert body == nil
    end

    test "non-def nodes return empty" do
      assert [] = ReturnValue.mutate({:+, [line: 1], [1, 2]}, @context)
      assert [] = ReturnValue.mutate(:foo, @context)
      assert [] = ReturnValue.mutate(42, @context)
    end
  end

  describe "mutate/2 - metadata" do
    test "includes proper metadata" do
      ast = {:def, [line: 10], [{:compute, [], []}, [do: 42]]}
      context = %{file: "lib/my_module.ex"}

      [mutation] = ReturnValue.mutate(ast, context)

      assert mutation.mutator == Muex.Mutator.ReturnValue
      assert mutation.description =~ "ReturnValue:"
      assert mutation.location.file == "lib/my_module.ex"
      assert mutation.location.line == 10
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "ReturnValue" = ReturnValue.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = ReturnValue.description()
      assert is_binary(desc)
      assert desc =~ "return value"
    end
  end
end
