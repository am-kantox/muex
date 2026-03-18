defmodule Muex.Mutator.PipelineDeletion do
  @moduledoc """
  Mutator that removes individual stages from pipeline (`|>`) chains.

  High value for Ecto changeset pipelines, Phoenix plugs, and other
  pipeline-heavy Elixir code where each stage performs validation,
  transformation, or side effects.

  For `a |> b() |> c() |> d()`, generates:
  - Delete `b()`: `a |> c() |> d()`  (via replacing inner `a |> b()` with `a`)
  - Delete `c()`: `a |> b() |> d()`
  - Delete `d()`: `a |> b() |> c()`
  """
  @behaviour Muex.Mutator

  @impl true
  def name, do: "PipelineDeletion"

  @impl true
  def description, do: "Deletes individual stages from |> pipeline chains"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate({:|>, meta, [left, right]}, context) do
    line = Keyword.get(meta, :line, 0)
    stage_name = describe_stage(right)

    [build_mutation(left, "delete pipeline stage #{stage_name}", context, line)]
  end

  def mutate(_ast, _context), do: []

  defp describe_stage({func, _, _}) when is_atom(func), do: "#{func}()"
  defp describe_stage({{:., _, [mod, func]}, _, _}), do: "#{Macro.to_string(mod)}.#{func}()"
  defp describe_stage(_), do: "<expr>"

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
