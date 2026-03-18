defmodule Muex.Compiler do
  @moduledoc """
  Compiles mutated ASTs and manages module hot-swapping.

  Uses the language adapter for converting AST to source and compiling modules.
  """
  @doc """
  Compiles a mutated AST and loads it into the BEAM.

  ## Parameters

    - `mutation` - The mutation map containing the mutated AST
    - `original_ast` - The original (complete) AST with mutation applied
    - `module_name` - The module name to compile
    - `language_adapter` - The language adapter module

  ## Returns

    - `{:ok, {module, original_binary}}` - Successfully compiled and loaded module with original binary
    - `{:error, reason}` - Compilation failed
  """
  @spec compile(map(), term(), atom(), module()) :: {:ok, {module(), binary()}} | {:error, term()}
  def compile(mutation, original_ast, module_name, language_adapter) do
    original_binary = get_module_binary(module_name)
    mutated_full_ast = apply_mutation(original_ast, mutation)

    with {:ok, source} <- language_adapter.unparse(mutated_full_ast),
         {:ok, module} <- compile_and_load(source, module_name) do
      {:ok, {module, original_binary}}
    end
  end

  @doc """
  Compiles a mutated AST and writes it to a temporary file.

  This is used for port-based test execution where the mutated source
  needs to be on disk for a separate BEAM VM to compile.

  ## Parameters

    - `mutation` - The mutation map containing the mutated AST
    - `file_entry` - The file entry containing the original AST and path
    - `language_adapter` - The language adapter module

  ## Returns

    - `{:ok, temp_file_path}` - Successfully wrote mutated source to temp file
    - `{:error, reason}` - Failed to write mutated source
  """
  @spec compile_to_file(map(), map(), module()) :: {:ok, Path.t()} | {:error, term()}
  def compile_to_file(mutation, file_entry, language_adapter) do
    case patch_source_text(mutation, file_entry, language_adapter) do
      {:ok, patched_source} ->
        write_to_temp_file(patched_source, file_entry.path)

      :fallback ->
        # Text patching failed; fall back to full AST round-trip
        mutated_full_ast = apply_mutation(file_entry.ast, mutation)

        with {:ok, source} <- language_adapter.unparse(mutated_full_ast) do
          write_to_temp_file(source, file_entry.path)
        end
    end
  end

  # Attempts a targeted text substitution on the mutation's line(s),
  # preserving all other source formatting. Falls back to :fallback
  # when the original expression can't be located in the source text.
  defp patch_source_text(mutation, file_entry, language_adapter) do
    mutation_line = get_in(mutation, [:location, :line])
    original_node = Map.get(mutation, :original_ast)
    mutated_node = Map.get(mutation, :ast)

    with {:ok, original_source} <- File.read(file_entry.path),
         {:ok, original_text} <- language_adapter.unparse(original_node),
         {:ok, mutated_text} <- language_adapter.unparse(mutated_node) do
      lines = String.split(original_source, "\n")
      original_text = String.trim(original_text)
      mutated_text = String.trim(mutated_text)

      case find_and_replace_at_line(lines, mutation_line, original_text, mutated_text) do
        {:ok, patched_lines} -> {:ok, Enum.join(patched_lines, "\n")}
        :not_found -> :fallback
      end
    else
      _ -> :fallback
    end
  rescue
    _ -> :fallback
  end

  # Finds the original expression text near the expected line and replaces it.
  # Checks the exact line first, then a small window around it (AST line numbers
  # can be slightly off from the actual source position).
  defp find_and_replace_at_line(lines, target_line, original_text, mutated_text) do
    # 0-indexed; target_line is 1-indexed
    idx = target_line - 1
    window = max(0, idx - 2)..min(length(lines) - 1, idx + 2)

    replaced =
      Enum.reduce_while(window, nil, fn i, _acc ->
        line = Enum.at(lines, i)

        if String.contains?(line, original_text) do
          {:halt, {i, String.replace(line, original_text, mutated_text, global: false)}}
        else
          {:cont, nil}
        end
      end)

    case replaced do
      {i, new_line} -> {:ok, List.replace_at(lines, i, new_line)}
      nil -> :not_found
    end
  end

  @doc """
  Restores the original module from its binary.

  ## Parameters

    - `module_name` - The module to restore
    - `original_binary` - The original module binary

  ## Returns

    - `:ok` - Successfully restored
    - `{:error, reason}` - Restoration failed
  """
  @spec restore(atom(), binary()) :: :ok | {:error, term()}
  def restore(module_name, original_binary) do
    :code.purge(module_name)
    :code.delete(module_name)

    case :code.load_binary(module_name, ~c"nofile", original_binary) do
      {:module, ^module_name} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp write_to_temp_file(source, original_path) do
    dir = Path.dirname(original_path)
    basename = Path.basename(original_path, Path.extname(original_path))
    timestamp = System.system_time(:microsecond)
    temp_file = Path.join(dir, "#{basename}_mutated_#{timestamp}#{Path.extname(original_path)}")

    case File.write(temp_file, source) do
      :ok -> {:ok, temp_file}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp get_module_binary(module_name) do
    case :code.get_object_code(module_name) do
      {^module_name, binary, _filename} -> binary
      :error -> nil
    end
  end

  defp compile_and_load(source, module_name) do
    :code.purge(module_name)
    :code.delete(module_name)
    [{^module_name, binary}] = Code.compile_string(source)

    case :code.load_binary(module_name, ~c"nofile", binary) do
      {:module, ^module_name} -> {:ok, module_name}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp apply_mutation(ast, mutation) do
    original_ast = Map.get(mutation, :original_ast)
    mutated_ast = Map.get(mutation, :ast)
    mutation_line = get_in(mutation, [:location, :line])

    Macro.prewalk(ast, fn node ->
      if matches_mutation?(node, original_ast, mutation_line) do
        mutated_ast
      else
        node
      end
    end)
  end

  defp matches_mutation?(node, original_ast, mutation_line) do
    node_line = get_node_line(node)
    node_line == mutation_line && structurally_equal?(node, original_ast)
  end

  defp get_node_line({_form, meta, _args}) when is_list(meta) do
    Keyword.get(meta, :line, 0)
  end

  defp get_node_line(_) do
    0
  end

  defp structurally_equal?({form1, _meta1, args1}, {form2, _meta2, args2}) do
    form1 == form2 && args_equal?(args1, args2)
  end

  defp structurally_equal?(val1, val2) do
    val1 == val2
  end

  defp args_equal?(nil, nil) do
    true
  end

  defp args_equal?([], []) do
    true
  end

  defp args_equal?([h1 | t1], [h2 | t2]) do
    structurally_equal?(h1, h2) && args_equal?(t1, t2)
  end

  defp args_equal?(_, _) do
    false
  end
end
