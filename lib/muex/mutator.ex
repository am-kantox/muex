defmodule Muex.Mutator do
  @moduledoc """
  Behaviour for mutation operators that transform AST nodes.

  Mutators implement specific mutation strategies (e.g., arithmetic operators,
  boolean operators, literals) and return a list of possible mutations for a given AST.

  Each mutator declares which languages it supports via `supported_languages/0`.
  Mutators targeting the same AST family (e.g., Elixir and Erlang both use BEAM
  AST) can declare support for multiple languages.

  ## Equivalent Mutations

  Mutators can declare that a generated mutation is semantically equivalent to the
  original code — meaning no test can ever kill it. This avoids polluting mutation
  scores with false negatives.

  There are two ways to mark equivalence:

  1. **At generation time** — set `equivalent: true` in the mutation map returned
     by `mutate/2`. Use this when the mutator knows at generation time that the
     mutation is equivalent (e.g., swapping arguments to a commutative operator).

  2. **Via the `equivalent?/1` callback** — implement this for more complex
     analysis that needs to inspect the full mutation map. The default
     implementation checks the `:equivalent` key.

  ## Example

      defmodule Muex.Mutator.MyMutator do
        @behaviour Muex.Mutator

        @impl true
        def mutate(ast, _context) do
          # Return list of mutated AST variants
          [mutated_ast_1, mutated_ast_2]
        end

        @impl true
        def name, do: "My Mutator"

        @impl true
        def description, do: "Mutates specific AST patterns"

        @impl true
        def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

        # Optional: override for complex equivalence detection
        @impl true
        def equivalent?(%{description: "swap arguments in +()" <> _}), do: true
        def equivalent?(_mutation), do: false
      end
  """
  @typedoc """
  Represents a single mutation with its metadata.

  The `:equivalent` key is optional. When `true`, the mutation is considered
  semantically equivalent to the original and will be filtered out by the optimizer.
  """
  @type mutation :: %{
          ast: term(),
          original_ast: term(),
          mutator: module(),
          description: String.t(),
          location: %{file: String.t(), line: non_neg_integer()}
        }

  @doc """
  Applies mutations to the given AST.

  ## Parameters

    - `ast` - The AST to mutate
    - `context` - Map containing additional context (file path, line number, etc.)

  ## Returns

    List of `mutation` maps, each representing a possible mutation
  """
  @callback mutate(ast :: term(), context :: map()) :: [mutation()]

  @doc """
  Returns the name of the mutator.
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what this mutator does.
  """
  @callback description() :: String.t()

  @doc """
  Returns the list of language adapter modules this mutator supports.

  Mutators that work with the same AST format (e.g., BEAM languages like
  Elixir and Erlang) can declare multiple languages. Discovery will filter
  mutators based on the active language.

  ## Returns

    List of language adapter modules (e.g., `[Muex.Language.Elixir, Muex.Language.Erlang]`)
  """
  @callback supported_languages() :: [module()]

  @doc """
  Returns whether a mutation is semantically equivalent to the original code.

  Equivalent mutations can never be killed by any test and should be filtered out
  to avoid inflating the "survived" count.

  The default implementation checks for `equivalent: true` in the mutation map.
  Override this callback in your mutator for more sophisticated detection.
  """
  @callback equivalent?(mutation :: mutation()) :: boolean()

  @optional_callbacks [equivalent?: 1]

  @doc """
  Checks whether a mutation is equivalent, delegating to the mutator module.

  Falls back to checking the `:equivalent` key in the mutation map if the
  mutator does not implement `equivalent?/1`.
  """
  @spec equivalent?(mutation()) :: boolean()
  def equivalent?(%{mutator: mutator} = mutation) do
    if function_exported?(mutator, :equivalent?, 1) do
      mutator.equivalent?(mutation)
    else
      Map.get(mutation, :equivalent, false)
    end
  end

  def equivalent?(_mutation), do: false

  @doc """
  Walks through an AST and applies all registered mutators.

  ## Parameters

    - `ast` - The AST to traverse
    - `mutators` - List of mutator modules to apply
    - `context` - Context map with file information

  ## Returns

    List of all possible mutations found in the AST
  """
  @spec walk(ast :: term(), mutators :: [module()], context :: map()) :: [mutation()]
  def walk(ast, mutators, context) do
    {_ast, mutations} =
      Macro.prewalk(ast, [], fn node, acc ->
        node_mutations =
          Enum.flat_map(mutators, fn mutator ->
            node
            |> mutator.mutate(context)
            |> Enum.map(&Map.put(&1, :original_ast, node))
          end)

        {node, acc ++ node_mutations}
      end)

    mutations
  end
end
