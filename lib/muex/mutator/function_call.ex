defmodule Muex.Mutator.FunctionCall do
  @moduledoc """
  Mutator for function calls.

  Applies mutations to function calls:
  - Remove function calls (replace with nil)
  - Swap function arguments (when there are 2+ args)
  """

  @behaviour Muex.Mutator

  @impl true
  def name, do: "FunctionCall"

  @impl true
  def description, do: "Mutates function calls (remove calls, swap arguments)"

  @impl true
  # credo:disable-for-lines:74
  def mutate(ast, context) do
    case ast do
      # Local function call with arguments: foo(a, b)
      {func, meta, args} when is_atom(func) and is_list(args) and args != [] ->
        line = Keyword.get(meta, :line, 0)

        # Don't mutate special forms or operators
        if special_form?(func) do
          []
        else
          mutations = []

          # Remove function call - replace with nil
          mutations = [
            build_mutation(nil, "remove #{func}() call", context, line) | mutations
          ]

          # Swap arguments if there are 2 or more
          mutations =
            if length(args) >= 2 do
              swapped_args = swap_first_two(args)

              [
                build_mutation(
                  {func, meta, swapped_args},
                  "swap arguments in #{func}()",
                  context,
                  line
                )
                | mutations
              ]
            else
              mutations
            end

          Enum.reverse(mutations)
        end

      # Remote function call: Module.foo(a, b)
      {{:., dot_meta, [module, func]}, meta, args} when is_list(args) and args != [] ->
        line = Keyword.get(meta, :line, 0)
        mutations = []

        # Remove function call
        mutations = [
          build_mutation(nil, "remove #{inspect(module)}.#{func}() call", context, line)
          | mutations
        ]

        # Swap arguments if there are 2 or more
        mutations =
          if length(args) >= 2 do
            swapped_args = swap_first_two(args)

            [
              build_mutation(
                {{:., dot_meta, [module, func]}, meta, swapped_args},
                "swap arguments in #{inspect(module)}.#{func}()",
                context,
                line
              )
              | mutations
            ]
          else
            mutations
          end

        Enum.reverse(mutations)

      _ ->
        []
    end
  end

  # Special forms that should not be mutated
  defp special_form?(func) do
    func in [
      :def,
      :defp,
      :defmodule,
      :defstruct,
      :import,
      :require,
      :alias,
      :use,
      :quote,
      :unquote,
      :if,
      :unless,
      :case,
      :cond,
      :for,
      :with,
      :receive,
      :try,
      :__block__,
      :=,
      :|>,
      :.,
      :&
    ]
  end

  defp swap_first_two([first, second | rest]) do
    [second, first | rest]
  end

  defp swap_first_two(args), do: args

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{
        file: Map.get(context, :file, "unknown"),
        line: line
      }
    }
  end
end
