defmodule ExCheck.TestImpact.Graph do
  @moduledoc false

  alias Mix.Compilers.Elixir, as: ElixirCompiler

  def load(project_root) do
    manifest_dir = Mix.Project.manifest_path()
    compiler_manifest = Path.join(manifest_dir, "compile.elixir")
    test_manifest = Path.join(manifest_dir, "compile.test_stale")

    cond do
      not File.exists?(compiler_manifest) ->
        {:error, "missing compiler manifest: #{compiler_manifest}"}

      not File.exists?(test_manifest) ->
        {:error, "missing test-reference manifest: #{test_manifest}"}

      true ->
        {modules, sources} = ElixirCompiler.read_manifest(compiler_manifest)

        with {:ok, test_sources} <- read_test_sources(test_manifest) do
          path_modules = path_modules(modules, sources, project_root)
          test_external = test_external(test_sources, project_root)

          {:ok,
           %{
             modules: modules,
             sources: sources,
             test_sources: test_sources,
             test_files: test_files(project_root, test_sources),
             path_modules: path_modules,
             test_external: test_external,
             external_paths: Map.keys(path_modules) ++ Map.keys(test_external),
             test_manifest: test_manifest
           }}
        end
    end
  rescue
    _ -> {:error, "incompatible compiler or test-reference manifest"}
  end

  def read_test_sources(path) do
    # Match Mix.Compilers.Test: valid manifests contain test-module atoms that are not loaded in
    # the parent mix check VM, so `:safe` rejects them even though the child test run wrote them.
    case path |> File.read!() |> :erlang.binary_to_term() do
      [2 | sources] when is_map(sources) -> {:ok, sources}
      _ -> {:error, "unsupported test-reference manifest"}
    end
  rescue
    _ -> {:error, "corrupt test-reference manifest"}
  end

  def encode_test_sources(sources) when is_map(sources) do
    :erlang.term_to_binary([2 | sources], [:compressed])
  end

  defp path_modules(modules, sources, project_root) do
    from_modules =
      Enum.reduce(modules, %{}, fn
        {module, {:module, _kind, source_paths, _export, _recompile, _timestamp}}, acc ->
          Enum.reduce(source_paths, acc, &put_path_module(&2, normalize(&1, project_root), module))
      end)

    Enum.reduce(sources, from_modules, fn
      {source,
       {:source, _size, _mtime, _digest, _compile, _export, _runtime, _compile_env, external,
        _compile_warnings, _runtime_warnings, defined_modules}},
      acc ->
        source_path = normalize(source, project_root)
        acc = Enum.reduce(defined_modules, acc, &put_path_module(&2, source_path, &1))

        Enum.reduce(external, acc, fn external_resource, paths ->
          path = external_path(external_resource)

          Enum.reduce(
            defined_modules,
            paths,
            &put_path_module(&2, normalize(path, project_root), &1)
          )
        end)
    end)
  end

  defp test_external(test_sources, project_root) do
    Enum.reduce(test_sources, %{}, fn
      {test, {:source, _compile, _runtime, external}}, acc ->
        Enum.reduce(external, acc, fn path, paths ->
          normalized = normalize(path, project_root)
          Map.update(paths, normalized, [test], &[test | &1])
        end)
    end)
  end

  defp put_path_module(path_modules, path, module) do
    Map.update(path_modules, path, MapSet.new([module]), &MapSet.put(&1, module))
  end

  defp external_path({path, {_mtime, _size}, _digest}), do: path

  defp test_files(project_root, test_sources) do
    discovered =
      project_root
      |> Path.join("test/**/*_test.exs")
      |> Path.wildcard(match_dot: true)
      |> Enum.map(&Path.relative_to(&1, project_root))

    (Map.keys(test_sources) ++ discovered)
    |> Enum.filter(&File.exists?(Path.join(project_root, &1)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize(path, project_root) do
    expanded = Path.expand(path, project_root)

    if within_project?(expanded, project_root) do
      Path.relative_to(expanded, project_root)
    else
      expanded
    end
  end

  defp within_project?(path, project_root) do
    root = Path.expand(project_root)
    path == root or String.starts_with?(path, root <> "/")
  end
end
