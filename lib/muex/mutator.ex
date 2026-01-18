defmodule Muex.Mutator do
  @moduledoc "Behaviour for mutation operators that transform AST nodes.\n\nMutators implement specific mutation strategies (e.g., arithmetic operators,\nboolean operators, literals) and return a list of possible mutations for a given AST.\n\nEach mutator is language-agnostic and works with the raw AST structure provided\nby the language adapter.\n\n## Example\n\n    defmodule Muex.Mutator.MyMutator do\n      @behaviour Muex.Mutator\n\n      @impl true\n      def mutate(ast, _context) do\n        # Return list of mutated AST variants\n        [mutated_ast_1, mutated_ast_2]\n      end\n\n      @impl true\n      def name, do: \"My Mutator\"\n\n      @impl true\n      def description, do: \"Mutates specific AST patterns\"\n    end\n"
  @typedoc "Represents a single mutation with its metadata.\n"
  @type mutation :: %{
          ast: term(),
          mutator: module(),
          description: String.t(),
          location: %{file: String.t(), line: non_neg_integer()}
        }
  @doc "Applies mutations to the given AST.\n\n## Parameters\n\n  - `ast` - The AST to mutate\n  - `context` - Map containing additional context (file path, line number, etc.)\n\n## Returns\n\n  List of `mutation` maps, each representing a possible mutation\n"
  @callback mutate(ast :: term(), context :: map()) :: [mutation()]
  @doc "Returns the name of the mutator.\n\n## Returns\n\n  String name identifying this mutator\n"
  @callback name() :: String.t()
  @doc "Returns a description of what this mutator does.\n\n## Returns\n\n  String describing the mutation strategy\n"
  @callback description() :: String.t()
  @doc "Walks through an AST and applies all registered mutators.\n\n## Parameters\n\n  - `ast` - The AST to traverse\n  - `mutators` - List of mutator modules to apply\n  - `context` - Context map with file information\n\n## Returns\n\n  List of all possible mutations found in the AST\n"
  @spec walk(ast :: term(), mutators :: [module()], context :: map()) :: [mutation()]
  def walk(ast, mutators, context) do
    {_ast, mutations} =
      Macro.prewalk(ast, [], fn node, acc ->
        node_mutations = Enum.flat_map(mutators, fn mutator -> mutator.mutate(node, context) end)
        {node, acc ++ node_mutations}
      end)

    mutations
  end
end
