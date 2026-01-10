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
  @spec compile(map(), term(), atom(), module()) ::
          {:ok, {module(), binary()}} | {:error, term()}
  def compile(mutation, original_ast, module_name, language_adapter) do
    # Store original module binary before mutating
    original_binary = get_module_binary(module_name)

    # Replace the mutation point in the original AST
    mutated_full_ast = apply_mutation(original_ast, mutation)

    with {:ok, source} <- language_adapter.unparse(mutated_full_ast),
         {:ok, module} <- compile_and_load(source, module_name) do
      {:ok, {module, original_binary}}
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
    # Purge and delete the mutated module
    :code.purge(module_name)
    :code.delete(module_name)

    # Reload the original module
    case :code.load_binary(module_name, ~c"nofile", original_binary) do
      {:module, ^module_name} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  # Get the current binary of a module
  defp get_module_binary(module_name) do
    case :code.get_object_code(module_name) do
      {^module_name, binary, _filename} -> binary
      :error -> nil
    end
  end

  # Compile source and load module with proper purging
  defp compile_and_load(source, module_name) do
    # Purge existing module first
    :code.purge(module_name)
    :code.delete(module_name)

    # Compile the source
    [{^module_name, binary}] = Code.compile_string(source)

    # Load the new binary
    case :code.load_binary(module_name, ~c"nofile", binary) do
      {:module, ^module_name} -> {:ok, module_name}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # Apply mutation to the AST by walking and replacing the mutation point
  defp apply_mutation(ast, mutation) do
    # Track if we've found and replaced the mutation
    mutation_ast = Map.get(mutation, :ast)
    mutation_line = get_in(mutation, [:location, :line])

    # Walk the AST and replace the matching node
    Macro.prewalk(ast, fn node ->
      if matches_mutation?(node, mutation_ast, mutation_line) do
        mutation_ast
      else
        node
      end
    end)
  end

  # Check if a node matches the mutation we're looking for
  defp matches_mutation?(node, mutation_ast, mutation_line) do
    # For now, match based on line number and node structure
    # This is a simplified approach - in production we'd need more sophisticated matching
    node_line = get_node_line(node)
    node_line == mutation_line && structurally_similar?(node, mutation_ast)
  end

  # Extract line number from AST node metadata
  defp get_node_line({_form, meta, _args}) when is_list(meta) do
    Keyword.get(meta, :line, 0)
  end

  defp get_node_line(_), do: 0

  # Check if two nodes are structurally similar (ignoring metadata)
  defp structurally_similar?({form1, _meta1, args1}, {form2, _meta2, args2}) do
    form1 == form2 && length(args1 || []) == length(args2 || [])
  end

  defp structurally_similar?(_, _), do: false
end
