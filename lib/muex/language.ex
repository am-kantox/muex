defmodule Muex.Language do
  @moduledoc "Behaviour for language adapters that provide AST parsing, unparsing, and compilation.\n\nThis behaviour defines the interface for supporting different programming languages\nin mutation testing. Each language adapter implements the callbacks to handle\nlanguage-specific AST operations.\n\n## Example\n\n    defmodule Muex.Language.MyLanguage do\n      @behaviour Muex.Language\n\n      @impl true\n      def parse(source), do: {:ok, parse_to_ast(source)}\n\n      @impl true\n      def unparse(ast), do: {:ok, ast_to_string(ast)}\n\n      @impl true\n      def compile(source, module_name), do: {:ok, compiled_module}\n\n      @impl true\n      def file_extensions, do: [\".my\"]\n\n      @impl true\n      def test_file_pattern, do: ~r/_test\\.my$/\n    end\n"
  @doc "Parses source code into an Abstract Syntax Tree (AST).\n\n## Parameters\n\n  - `source` - String containing the source code to parse\n\n## Returns\n\n  - `{:ok, ast}` - Successfully parsed AST (term structure depends on language)\n  - `{:error, reason}` - Parsing failed with error details\n"
  @callback parse(source :: String.t()) :: {:ok, ast :: term()} | {:error, term()}
  @doc "Converts an AST back into source code string.\n\n## Parameters\n\n  - `ast` - The AST to convert back to source code\n\n## Returns\n\n  - `{:ok, source}` - Successfully generated source code\n  - `{:error, reason}` - Unparsing failed with error details\n"
  @callback unparse(ast :: term()) :: {:ok, String.t()} | {:error, term()}
  @doc "Compiles source code into a module that can be loaded into the BEAM.\n\n## Parameters\n\n  - `source` - String containing the source code to compile\n  - `module_name` - Atom representing the module name\n\n## Returns\n\n  - `{:ok, module}` - Successfully compiled module\n  - `{:error, reason}` - Compilation failed with error details\n"
  @callback compile(source :: String.t(), module_name :: atom()) ::
              {:ok, module()} | {:error, term()}
  @doc "Returns the list of file extensions for this language.\n\n## Returns\n\n  List of file extensions including the dot (e.g., `[\".ex\", \".exs\"]`)\n"
  @callback file_extensions() :: [String.t()]
  @doc "Returns a regex pattern to identify test files.\n\n## Returns\n\n  Regex that matches test file paths\n"
  @callback test_file_pattern() :: Regex.t()
end
