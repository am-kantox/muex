defmodule Muex.Mutator.GuardSimplification do
  @moduledoc """
  Mutator that weakens guard clauses by removing individual terms.

  For `when is_binary(x) and x != "" and byte_size(x) < 100`, generates:
  - Remove `is_binary(x)`: `when x != "" and byte_size(x) < 100`
  - Remove `x != ""`: `when is_binary(x) and byte_size(x) < 100`
  - Remove `byte_size(x) < 100`: `when is_binary(x) and x != ""`

  High value for testing that guard conditions are individually necessary.
  """
  @behaviour Muex.Mutator

  @impl true
  def name, do: "GuardSimplification"

  @impl true
  def description, do: "Removes individual terms from guard clause conjunctions"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate({:when, meta, [call, guard]}, context) when is_tuple(guard) do
    terms = flatten_and(guard)

    if length(terms) >= 2 do
      line = Keyword.get(meta, :line, 0)

      terms
      |> Enum.with_index()
      |> Enum.map(fn {term, idx} ->
        remaining = List.delete_at(terms, idx)
        simplified_guard = rebuild_and(remaining, meta)
        term_desc = Macro.to_string(term)

        build_mutation(
          {:when, meta, [call, simplified_guard]},
          "remove guard term `#{term_desc}`",
          context,
          line
        )
      end)
    else
      []
    end
  end

  def mutate(_ast, _context), do: []

  # Flatten nested :and into a list of terms
  defp flatten_and({:and, _, [left, right]}) do
    flatten_and(left) ++ flatten_and(right)
  end

  defp flatten_and(term), do: [term]

  # Rebuild a list of terms into nested :and
  defp rebuild_and([single], _meta), do: single

  defp rebuild_and([first | rest], meta) do
    {:and, meta, [first, rebuild_and(rest, meta)]}
  end

  defp build_mutation(mutated_ast, desc, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{desc}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
