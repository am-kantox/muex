defmodule Muex.Mutator.StatementDeletion do
  @moduledoc """
  Mutator that removes individual statements from blocks.

  Targets `__block__` nodes with two or more statements. For each
  non-final statement, produces a mutation that deletes it from the block.
  The final statement (the return value) is left to the ReturnValue mutator.

  This is one of the highest-value mutation operators: if deleting a
  statement doesn't cause any test to fail, that statement is either
  dead code or untested side-effect logic.
  """
  @behaviour Muex.Mutator

  @impl true
  def name, do: "StatementDeletion"

  @impl true
  def description, do: "Deletes individual statements from blocks"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate({:__block__, meta, statements}, context) when length(statements) >= 2 do
    statements
    |> Enum.with_index()
    # Skip the last statement — that's the return value
    |> Enum.reject(fn {_stmt, idx} -> idx == length(statements) - 1 end)
    |> Enum.map(fn {stmt, idx} ->
      remaining = List.delete_at(statements, idx)
      mutated_ast = simplify_block(meta, remaining)
      stmt_line = get_statement_line(stmt)

      build_mutation(
        mutated_ast,
        "delete statement #{idx + 1} of #{length(statements)}",
        context,
        stmt_line
      )
    end)
  end

  def mutate(_ast, _context), do: []

  # A block with one remaining statement collapses to that statement.
  defp simplify_block(_meta, [single]), do: single
  defp simplify_block(meta, stmts), do: {:__block__, meta, stmts}

  defp get_statement_line({_form, meta, _args}) when is_list(meta) do
    Keyword.get(meta, :line, 0)
  end

  defp get_statement_line(_), do: 0

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
