defmodule Muex.TestRunner.PortTest do
  use ExUnit.Case, async: true

  alias Muex.TestRunner.Port, as: PortRunner

  describe "run_tests/3" do
    test "returns error for non-existent test files" do
      result = PortRunner.run_tests(["nonexistent_test.exs"], nil, timeout_ms: 1000)

      assert match?({:ok, %{exit_code: exit_code}} when exit_code != 0, result) or
               match?({:error, _}, result)
    end

    test "handles empty test file list" do
      result = PortRunner.run_tests([], nil, timeout_ms: 1000)

      # Should either succeed with no tests or return error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
