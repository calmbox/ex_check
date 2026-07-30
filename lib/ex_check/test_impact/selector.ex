defmodule ExCheck.TestImpact.Selector do
  @moduledoc false

  @broad_paths ["mix.exs", "mix.lock", ".check.exs", "test/test_helper.exs"]
  @broad_prefixes ["config/", "priv/repo/migrations/"]

  def select(graph, changed_paths, previous_path_modules) do
    select_data(
      graph.modules,
      graph.sources,
      graph.test_sources,
      graph.test_files,
      changed_paths,
      previous_path_modules,
      graph.path_modules,
      graph.test_external
    )
  end

  def select_data(
        modules,
        sources,
        test_sources,
        test_files,
        changed_paths,
        previous_path_modules
      ) do
    current_path_modules = path_modules(modules)

    select_data(
      modules,
      sources,
      test_sources,
      test_files,
      changed_paths,
      previous_path_modules,
      current_path_modules,
      %{}
    )
  end

  defp select_data(
         _modules,
         sources,
         test_sources,
         test_files,
         changed_paths,
         previous_path_modules,
         current_path_modules,
         test_external
       ) do
    changed_paths = Enum.sort(changed_paths)

    path_modules =
      Map.merge(previous_path_modules, current_path_modules, fn _path, previous, current ->
        MapSet.union(previous, current)
      end)

    reasons = broad_reasons(changed_paths, path_modules)

    if reasons == [] do
      seed_modules = modules_for_paths(path_modules, changed_paths)
      affected_modules = closure(seed_modules, sources)

      referenced = referenced_tests(test_sources, affected_modules)
      direct = directly_changed_tests(changed_paths)
      external = tests_for_external_changes(test_external, changed_paths)
      colocated = colocated_tests(test_files, changed_paths)

      tests =
        referenced
        |> Kernel.++(direct)
        |> Kernel.++(external)
        |> Kernel.++(colocated)
        |> Enum.filter(&(&1 in test_files))
        |> Enum.uniq()
        |> Enum.sort()

      %{
        mode: :selected,
        tests: tests,
        seed_modules: module_names(seed_modules),
        affected_modules: module_names(affected_modules),
        groups: %{
          direct: Enum.sort(direct),
          referenced: Enum.sort(referenced),
          external: Enum.sort(external),
          colocated: Enum.sort(colocated)
        }
      }
    else
      %{mode: :full, reasons: reasons, tests: Enum.sort(test_files)}
    end
  end

  defp path_modules(modules) do
    Enum.reduce(modules, %{}, fn
      {module, {:module, _kind, source_paths, _export, _recompile, _timestamp}}, acc ->
        Enum.reduce(source_paths, acc, &put_path_module(&2, &1, module))
    end)
  end

  defp put_path_module(path_modules, path, module) do
    Map.update(path_modules, path, MapSet.new([module]), &MapSet.put(&1, module))
  end

  defp broad_reasons(changed_paths, path_modules) do
    direct = Enum.filter(changed_paths, &(&1 in @broad_paths))

    prefixed =
      Enum.filter(changed_paths, fn path ->
        Enum.any?(@broad_prefixes, &String.starts_with?(path, &1))
      end)

    unmapped =
      changed_paths
      |> Enum.filter(fn path ->
        relevant_elixir_source?(path) and not Map.has_key?(path_modules, path)
      end)
      |> Enum.map(&"unmapped_elixir_source:#{&1}")

    Enum.sort(direct ++ prefixed ++ unmapped)
  end

  defp relevant_elixir_source?(path) do
    String.ends_with?(path, ".ex") and
      (String.starts_with?(path, "lib/") or String.starts_with?(path, "test/support/"))
  end

  defp modules_for_paths(path_modules, changed_paths) do
    Enum.reduce(changed_paths, MapSet.new(), fn path, modules ->
      MapSet.union(modules, Map.get(path_modules, path, MapSet.new()))
    end)
  end

  defp closure(modules, sources) do
    expanded = one_hop(modules, sources)

    if MapSet.equal?(modules, expanded), do: expanded, else: closure(expanded, sources)
  end

  defp one_hop(modules, sources) do
    Enum.reduce(sources, modules, fn
      {_path,
       {:source, _size, _mtime, _digest, compile, export, _runtime, _compile_env, _external,
        _compile_warnings, _runtime_warnings, defined_modules}},
      acc ->
        references = MapSet.new(compile ++ export)

        if MapSet.disjoint?(references, modules) do
          acc
        else
          Enum.reduce(defined_modules, acc, &MapSet.put(&2, &1))
        end
    end)
  end

  defp referenced_tests(test_sources, modules) do
    for {path, {:source, compile, runtime, _external}} <- test_sources,
        references = MapSet.new(compile ++ runtime),
        not MapSet.disjoint?(references, modules),
        do: path
  end

  defp directly_changed_tests(changed_paths) do
    Enum.filter(changed_paths, &String.ends_with?(&1, "_test.exs"))
  end

  defp tests_for_external_changes(test_external, changed_paths) do
    Enum.flat_map(changed_paths, &Map.get(test_external, &1, []))
  end

  defp colocated_tests(test_files, changed_paths) do
    for source <- changed_paths,
        test <- test_files,
        owned_test?(source, test),
        do: test
  end

  defp owned_test?("lib/" <> source, "test/" <> test) do
    exact = String.replace_suffix(source, ".ex", "_test.exs")

    if String.contains?(source, "_web/live/") and String.ends_with?(source, "_live.ex") do
      [web_prefix, live_stem] = String.split(source, "/live/", parts: 2)
      route_stem = String.trim_trailing(live_stem, "_live.ex")

      test == exact or
        String.starts_with?(test, "#{web_prefix}/live/#{String.trim_trailing(live_stem, ".ex")}/") or
        String.starts_with?(test, "#{web_prefix}/live/#{route_stem}_")
    else
      test == exact
    end
  end

  defp owned_test?(_source, _test), do: false

  defp module_names(modules), do: modules |> Enum.map(&inspect/1) |> Enum.sort()
end
