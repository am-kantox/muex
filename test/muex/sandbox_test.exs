defmodule Muex.SandboxTest do
  use ExUnit.Case

  alias Muex.Sandbox

  @project_root File.cwd!()

  describe "create_sandbox/4" do
    test "creates a sandbox directory with expected structure" do
      root = Path.join(System.tmp_dir!(), "muex_test_sandbox_#{System.system_time(:microsecond)}")

      on_exit(fn -> File.rm_rf!(root) end)

      sandbox = Sandbox.create_sandbox(root, @project_root, "test", ["test"])

      assert sandbox.root == root
      assert sandbox.project_root == @project_root

      # mix.exs should be symlinked
      assert File.exists?(Path.join(root, "mix.exs"))
      assert {:ok, _} = File.read_link(Path.join(root, "mix.exs"))

      # deps/ should be symlinked
      assert File.exists?(Path.join(root, "deps"))
      assert {:ok, _} = File.read_link(Path.join(root, "deps"))

      # lib/ should be a real directory (not a symlink) containing symlinks
      lib_dir = Path.join(root, "lib")
      assert File.dir?(lib_dir)
      # lib/ itself should NOT be a symlink
      assert {:error, _} = File.read_link(lib_dir)

      # Source files inside lib/ should be symlinks
      lib_files = Path.wildcard(Path.join([root, "lib", "**", "*.ex"]))
      assert length(lib_files) > 0

      for file <- lib_files do
        assert {:ok, _target} = File.read_link(file),
               "Expected #{file} to be a symlink"
      end

      # test/ should be symlinked
      assert File.exists?(Path.join(root, "test"))

      # _build should exist
      assert File.dir?(Path.join(root, "_build"))
    end
  end

  describe "apply_mutation/4 and restore/2" do
    setup do
      root = Path.join(System.tmp_dir!(), "muex_test_sandbox_#{System.system_time(:microsecond)}")
      sandbox = Sandbox.create_sandbox(root, @project_root, "test", ["test"])
      on_exit(fn -> File.rm_rf!(root) end)
      %{sandbox: sandbox}
    end

    test "replaces a source file symlink with mutated content", %{sandbox: sandbox} do
      target_file = "lib/muex.ex"
      sandbox_path = Path.join(sandbox.root, target_file)

      # Before: should be a symlink
      assert {:ok, _} = File.read_link(sandbox_path)

      # Apply mutation
      :ok = Sandbox.apply_mutation(sandbox, target_file, "# mutated content", nil)

      # After: should be a real file with mutated content
      assert {:error, _} = File.read_link(sandbox_path)
      assert File.read!(sandbox_path) == "# mutated content"

      # Original file should be untouched
      original = File.read!(Path.join(@project_root, target_file))
      refute original == "# mutated content"
    end

    test "restore re-creates the symlink", %{sandbox: sandbox} do
      target_file = "lib/muex.ex"
      sandbox_path = Path.join(sandbox.root, target_file)

      :ok = Sandbox.apply_mutation(sandbox, target_file, "# mutated", nil)
      assert {:error, _} = File.read_link(sandbox_path)

      :ok = Sandbox.restore(sandbox, target_file)
      assert {:ok, _} = File.read_link(sandbox_path)

      # Content should match original
      original = File.read!(Path.join(@project_root, target_file))
      assert File.read!(sandbox_path) == original
    end
  end

  describe "create_pool/2" do
    test "creates the requested number of sandboxes" do
      sandboxes = Sandbox.create_pool(3, project_root: @project_root, test_paths: ["test"])
      on_exit(fn -> Sandbox.cleanup(sandboxes) end)

      assert length(sandboxes) == 3

      # Each sandbox should have its own root
      roots = Enum.map(sandboxes, & &1.root)
      assert roots == Enum.uniq(roots)

      # Each should have lib/ with files
      for sandbox <- sandboxes do
        lib_files = Path.wildcard(Path.join([sandbox.root, "lib", "**", "*.ex"]))
        assert length(lib_files) > 0
      end
    end
  end

  describe "cleanup/1" do
    test "removes all sandbox directories" do
      sandboxes = Sandbox.create_pool(2, project_root: @project_root, test_paths: ["test"])
      roots = Enum.map(sandboxes, & &1.root)

      for root <- roots, do: assert(File.dir?(root))

      Sandbox.cleanup(sandboxes)

      for root <- roots, do: refute(File.dir?(root))
    end

    test "handles empty list" do
      assert :ok = Sandbox.cleanup([])
    end
  end

  describe "isolation" do
    test "mutations in one sandbox don't affect another" do
      sandboxes = Sandbox.create_pool(2, project_root: @project_root, test_paths: ["test"])
      on_exit(fn -> Sandbox.cleanup(sandboxes) end)

      [sb1, sb2] = sandboxes
      target_file = "lib/muex.ex"

      # Mutate in sandbox 1
      :ok = Sandbox.apply_mutation(sb1, target_file, "# sandbox 1 mutation", nil)

      # Sandbox 2 should still have the original (via symlink)
      sb2_path = Path.join(sb2.root, target_file)
      sb2_content = File.read!(sb2_path)
      original = File.read!(Path.join(@project_root, target_file))
      assert sb2_content == original

      # Sandbox 1 should have mutated content
      sb1_path = Path.join(sb1.root, target_file)
      assert File.read!(sb1_path) == "# sandbox 1 mutation"

      # Restore sandbox 1
      :ok = Sandbox.restore(sb1, target_file)
      assert File.read!(sb1_path) == original
    end
  end
end
