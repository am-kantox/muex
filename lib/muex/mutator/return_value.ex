defmodule Muex.Mutator.ReturnValue do
  @moduledoc """
  Mutator that replaces function return values with type-appropriate
  zero values.

  Targets `def` and `defp` function definitions. For multi-statement
  bodies (`__block__`), replaces the last expression. For single-expression
  bodies, replaces the entire body.

  The replacement value is inferred from the shape of the original return
  expression to preserve the caller's type expectations and avoid spurious
  `MatchError` / `FunctionClauseError` crashes that would mask real
  mutation-testing signal:

    - `{:ok, _}`  → `{:error, :mutated}`
    - `{:error, _}` → `{:ok, :mutated}`
    - `:ok` → `:error`
    - `:error` → `:ok`
    - `true` → `false`
    - `false` → `true`
    - integer → `0`
    - float → `0.0`
    - string → `""`
    - list → `[]`
    - map/struct → `%{}`
    - tuple → `{}`
    - everything else → `nil`

  Skips functions whose return expression already matches the zero value.

  Complements StatementDeletion: that mutator tests whether intermediate
  statements matter, this one tests whether the return value matters.
  """
  @behaviour Muex.Mutator

  @impl true
  def name, do: "ReturnValue"

  @impl true
  def description, do: "Replaces function return values with type-appropriate zero values"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate({kind, meta, [signature, [do: body]]}, context) when kind in [:def, :defp] do
    line = Keyword.get(meta, :line, 0)
    func_name = extract_func_name(signature)

    case body do
      # No body (protocol/behaviour header) or already nil
      nil ->
        []

      # Multi-statement body: replace last expression
      {:__block__, block_meta, statements} when is_list(statements) and statements != [] ->
        last = List.last(statements)
        replacement = zero_value(last)

        if replacement == last do
          []
        else
          new_statements = List.replace_at(statements, -1, replacement)
          mutated_body = {:__block__, block_meta, new_statements}

          [
            build_mutation(
              {kind, meta, [signature, [do: mutated_body]]},
              "replace return value of #{func_name} with #{describe_value(replacement)}",
              context,
              line
            )
          ]
        end

      # Single-expression body
      expr ->
        replacement = zero_value(expr)

        if replacement == expr do
          []
        else
          [
            build_mutation(
              {kind, meta, [signature, [do: replacement]]},
              "replace return value of #{func_name} with #{describe_value(replacement)}",
              context,
              line
            )
          ]
        end
    end
  end

  def mutate(_ast, _context), do: []

  # -- Zero-value inference --

  # {:ok, _} -> {:error, :mutated}
  defp zero_value({:ok, _}), do: {:error, :mutated}
  # {:error, _} -> {:ok, :mutated}
  defp zero_value({:error, _}), do: {:ok, :mutated}

  # :ok -> :error, :error -> :ok
  defp zero_value(:ok), do: :error
  defp zero_value(:error), do: :ok

  # Booleans
  defp zero_value(true), do: false
  defp zero_value(false), do: true

  # Numbers
  defp zero_value(n) when is_integer(n) and n != 0, do: 0
  defp zero_value(n) when is_float(n) and n != +0.0, do: +0.0

  # Strings
  defp zero_value(s) when is_binary(s) and s != "", do: ""

  # Lists (non-empty)
  defp zero_value([_ | _]), do: []

  # Maps: %{...} -> %{}
  defp zero_value({:%{}, _meta, fields}) when fields != [], do: {:%{}, [], []}

  # Structs: %Mod{...} -> %{}
  defp zero_value({:%, _meta, [_mod, _map]}), do: {:%{}, [], []}

  # Tuples (3+ elements): {a, b, c} -> {}
  defp zero_value({:{}, _meta, elems}) when elems != [], do: {:{}, [], []}

  # Fallback: anything else -> nil
  defp zero_value(_), do: nil

  # -- Helpers --

  defp extract_func_name({:when, _, [call | _]}), do: extract_func_name(call)
  defp extract_func_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp extract_func_name(_), do: "unknown"

  defp describe_value(:error), do: ":error"
  defp describe_value(:ok), do: ":ok"
  defp describe_value({:error, :mutated}), do: "{:error, :mutated}"
  defp describe_value({:ok, :mutated}), do: "{:ok, :mutated}"
  defp describe_value(true), do: "true"
  defp describe_value(false), do: "false"
  defp describe_value(0), do: "0"
  defp describe_value(+0.0), do: "0.0"
  defp describe_value(""), do: ~s("")
  defp describe_value([]), do: "[]"
  defp describe_value({:%{}, [], []}), do: "%{}"
  defp describe_value({:{}, [], []}), do: "{}"
  defp describe_value(nil), do: "nil"
  defp describe_value(other), do: inspect(other)

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
