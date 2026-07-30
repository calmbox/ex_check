defmodule ExCheck.TestImpact.Runner do
  @moduledoc false

  alias ExCheck.Command
  alias ExCheck.Lock
  alias ExCheck.TestImpact.Graph
  alias ExCheck.TestImpact.Inputs
  alias ExCheck.TestImpact.Selector
  alias ExCheck.TestImpact.State

  @max_selected_files 500
  @max_selected_path_bytes 100_000

  def run(opts) do
    project_root = File.cwd!()

    Lock.with_lock(fn -> do_run(project_root, opts) end,
      path: runner_lock_path(project_root)
    )
  end

  defp do_run(project_root, opts) do
    graph_result = Graph.load(project_root)
    external_paths = external_paths(graph_result)
    starting_inputs = Inputs.capture(project_root, external_paths)
    previous_result = State.read()

    {changed_paths, selection} =
      choose_selection(opts, graph_result, previous_result, starting_inputs)

    if opts[:debug] || opts[:explain] do
      print_selection(starting_inputs, changed_paths, selection, opts)
    end

    if opts[:explain] do
      :ok
    else
      execute(project_root, graph_result, starting_inputs, external_paths, selection, opts)
    end
  end

  defp choose_selection(opts, graph_result, previous_result, starting_inputs) do
    previous_inputs = previous_inputs(previous_result)
    changed_paths = Inputs.changed_paths(previous_inputs, starting_inputs)

    selection =
      cond do
        opts[:full] ->
          full_selection(graph_result, "explicit --full")

        match?({:error, _}, graph_result) ->
          {:error, reason} = graph_result
          full_selection(graph_result, reason)

        match?({:error, _}, previous_result) ->
          {:error, reason} = previous_result
          full_selection(graph_result, reason)

        previous_inputs.identity != starting_inputs.identity ->
          full_selection(graph_result, "toolchain or project identity changed")

        true ->
          {:ok, graph} = graph_result
          {:ok, previous} = previous_result

          previous_path_modules =
            carry_renamed_modules(previous.path_modules, previous.inputs, starting_inputs)

          Selector.select(graph, changed_paths, previous_path_modules)
      end

    {changed_paths, broaden_oversized_selection(selection, graph_result)}
  end

  defp previous_inputs({:ok, previous}), do: previous.inputs
  defp previous_inputs({:error, _reason}), do: nil

  defp carry_renamed_modules(path_modules, previous_inputs, current_inputs) do
    deleted = Map.drop(previous_inputs.files, Map.keys(current_inputs.files))
    added = Map.drop(current_inputs.files, Map.keys(previous_inputs.files))

    Enum.reduce(added, path_modules, fn {added_path, hash}, mappings ->
      matching_deleted = for {deleted_path, ^hash} <- deleted, do: deleted_path

      case matching_deleted do
        [deleted_path] ->
          case Map.fetch(path_modules, deleted_path) do
            {:ok, modules} -> Map.put(mappings, added_path, modules)
            :error -> mappings
          end

        _ ->
          mappings
      end
    end)
  end

  defp full_selection({:ok, graph}, reason) do
    %{mode: :full, reasons: [reason], tests: graph.test_files}
  end

  defp full_selection({:error, _reason}, reason) do
    %{mode: :full, reasons: [reason], tests: []}
  end

  defp broaden_oversized_selection(%{mode: :selected, tests: tests} = selection, graph_result) do
    path_bytes = Enum.reduce(tests, 0, &(byte_size(&1) + &2 + 1))

    if length(tests) > @max_selected_files or path_bytes > @max_selected_path_bytes do
      full_selection(graph_result, "selected test command exceeds safe argument limits")
    else
      selection
    end
  end

  defp broaden_oversized_selection(selection, _graph_result), do: selection

  defp execute(project_root, graph_result, starting_inputs, external_paths, selection, opts) do
    result =
      case selection do
        %{mode: :selected, tests: []} ->
          if opts[:debug], do: IO.puts("No affected tests")
          {:ok, nil}

        %{mode: :selected, tests: tests} ->
          {:ok, graph} = graph_result
          run_selected(graph, tests)

        %{mode: :full} ->
          run_full()
      end

    finish_run(project_root, starting_inputs, external_paths, result)
  end

  defp run_selected(graph, tests) do
    {manifest_path, backup} = manifest_backup = capture_file(graph.test_manifest)

    try do
      {:ok, original_sources} = Graph.read_test_sources(manifest_path)
      staged_sources = Map.drop(original_sources, tests)
      State.atomic_write!(manifest_path, Graph.encode_test_sources(staged_sources))

      status = run_mix_test(["--stale" | tests])

      if status == 0 do
        case Graph.read_test_sources(manifest_path) do
          {:ok, refreshed_sources} ->
            current_tests = MapSet.new(graph.test_files)

            merged_sources =
              original_sources
              |> Map.drop(tests)
              |> Map.merge(refreshed_sources)
              |> Map.filter(fn {path, _source} -> MapSet.member?(current_tests, path) end)

            State.atomic_write!(manifest_path, Graph.encode_test_sources(merged_sources))
            {:ok, manifest_backup}

          {:error, reason} ->
            restore_file!(manifest_path, backup)
            IO.puts(:stderr, "ex_check test-impact manifest error: #{reason}")
            {:error, 1}
        end
      else
        restore_file!(manifest_path, backup)
        {:error, status}
      end
    rescue
      error ->
        restore_file!(manifest_path, backup)
        reraise error, __STACKTRACE__
    end
  end

  defp run_full do
    test_manifest = Path.join(Mix.Project.manifest_path(), "compile.test_stale")
    {manifest_path, backup} = manifest_backup = capture_file(test_manifest)
    status = run_mix_test(["--stale", "--force"])

    if status == 0 do
      {:ok, manifest_backup}
    else
      restore_file!(manifest_path, backup)
      {:error, status}
    end
  end

  defp finish_run(_project_root, _starting_inputs, _external_paths, {:error, status}) do
    {:error, status}
  end

  defp finish_run(project_root, starting_inputs, external_paths, {:ok, manifest_backup}) do
    ending_inputs = Inputs.capture(project_root, external_paths)

    if ending_inputs.digest == starting_inputs.digest do
      case Graph.load(project_root) do
        {:ok, final_graph} ->
          final_inputs = Inputs.capture(project_root, final_graph.external_paths)
          State.write!(final_inputs, final_graph.path_modules)
          :ok

        {:error, reason} ->
          restore_manifest_backup(manifest_backup)
          IO.puts(:stderr, "ex_check could not advance test-impact state: #{reason}")
          {:error, 1}
      end
    else
      restore_manifest_backup(manifest_backup)

      IO.puts(
        :stderr,
        "ex_check inputs changed while affected tests were running; retrying is required"
      )

      {:error, 1}
    end
  end

  defp run_mix_test(args) do
    {_output, status, _duration} = Command.run(["mix", "test" | args], stream: true)
    status
  end

  defp print_selection(inputs, changed_paths, selection, opts) do
    mode = if selection.mode == :full, do: "full fallback", else: "selected"
    action = if opts[:explain], do: "explain", else: "run"

    IO.puts("ex_check test impact: #{mode} #{action}")
    IO.puts("generation: #{String.slice(inputs.digest, 0, 12)}")
    IO.puts("changed inputs: #{length(changed_paths)}")
    print_items(changed_paths, "changed", opts)

    case selection do
      %{mode: :full, reasons: reasons} ->
        Enum.each(reasons, &IO.puts("  fallback: #{&1}"))

      %{mode: :selected, seed_modules: seed, affected_modules: affected, groups: groups} ->
        IO.puts("seed modules: #{length(seed)}")
        IO.puts("compile/export closure: #{length(affected)}")

        Enum.each(groups, fn {group, tests} ->
          if tests != [], do: IO.puts("  #{group}: #{length(tests)}")
        end)
    end

    IO.puts("selected test files: #{length(selection.tests)}")
    print_items(selection.tests, "test", opts)
  end

  defp print_items(items, label, opts) do
    limit = if opts[:explain], do: length(items), else: 20

    items
    |> Enum.take(limit)
    |> Enum.each(&IO.puts("  #{label}: #{&1}"))

    if length(items) > limit do
      IO.puts("  ... #{length(items) - limit} more; use --explain for the complete list")
    end
  end

  defp external_paths({:ok, graph}), do: graph.external_paths
  defp external_paths({:error, _reason}), do: []

  # sobelow_skip ["Traversal.FileModule"]
  defp capture_file(path) do
    case File.read(path) do
      {:ok, content} -> {path, {:present, content}}
      {:error, :enoent} -> {path, :missing}
    end
  end

  defp restore_manifest_backup(nil), do: :ok
  defp restore_manifest_backup({path, backup}), do: restore_file!(path, backup)

  # sobelow_skip ["Traversal.FileModule"]
  defp restore_file!(path, {:present, content}), do: State.atomic_write!(path, content)

  # sobelow_skip ["Traversal.FileModule"]
  defp restore_file!(path, :missing) do
    File.rm(path)
    :ok
  end

  defp runner_lock_path(project_root) do
    id = :crypto.hash(:sha256, Path.expand(project_root)) |> Base.url_encode64(padding: false)
    Path.join(System.tmp_dir!(), "ex_check-test-impact-#{id}.lease")
  end
end
