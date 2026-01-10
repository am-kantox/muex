defmodule Muex.Mutator.Conditional do
  @moduledoc """
  Mutator for conditional expressions.

  Applies mutations to conditionals:
  - Invert if conditions: `if x` -> `if not x`
  - Remove if/else branches
  - Mutate unless to if
  """

  @behaviour Muex.Mutator

  @impl true
  def name, do: "Conditional"

  @impl true
  def description, do: "Mutates conditional expressions (if, unless, case)"

  @impl true
  def mutate(ast, context) do
    case ast do
      # if condition do: true_branch, else: false_branch
      {:if, meta, [condition, [do: true_branch, else: false_branch]]} ->
        line = Keyword.get(meta, :line, 0)

        [
          # Invert condition
          build_mutation(
            {:if, meta, [negate(condition), [do: true_branch, else: false_branch]]},
            "invert if condition",
            context,
            line
          ),
          # Always take true branch
          build_mutation(
            true_branch,
            "always take if branch",
            context,
            line
          ),
          # Always take false branch
          build_mutation(
            false_branch,
            "always take else branch",
            context,
            line
          )
        ]

      # if condition do: true_branch (no else)
      {:if, meta, [condition, [do: true_branch]]} ->
        line = Keyword.get(meta, :line, 0)

        [
          # Invert condition
          build_mutation(
            {:if, meta, [negate(condition), [do: true_branch]]},
            "invert if condition",
            context,
            line
          ),
          # Always take true branch
          build_mutation(
            true_branch,
            "always take if branch",
            context,
            line
          ),
          # Remove if (replace with nil)
          build_mutation(
            nil,
            "remove if statement",
            context,
            line
          )
        ]

      # unless condition do: body
      {:unless, meta, [condition, [do: body]]} ->
        line = Keyword.get(meta, :line, 0)

        [
          # Convert unless to if (they are opposites)
          build_mutation(
            {:if, meta, [condition, [do: body]]},
            "unless to if",
            context,
            line
          ),
          # Always execute body
          build_mutation(
            body,
            "always execute unless body",
            context,
            line
          )
        ]

      # unless condition do: body, else: else_branch
      {:unless, meta, [condition, [do: body, else: else_branch]]} ->
        line = Keyword.get(meta, :line, 0)

        [
          # Convert unless to if
          build_mutation(
            {:if, meta, [condition, [do: body, else: else_branch]]},
            "unless to if",
            context,
            line
          ),
          # Always take unless body
          build_mutation(
            body,
            "always execute unless body",
            context,
            line
          ),
          # Always take else branch
          build_mutation(
            else_branch,
            "always execute unless else",
            context,
            line
          )
        ]

      _ ->
        []
    end
  end

  # Negate a condition by wrapping it in `not`
  defp negate(condition) do
    {:not, [], [condition]}
  end

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
