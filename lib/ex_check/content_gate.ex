defmodule ExCheck.ContentGate do
  @moduledoc false

  alias ExCheck.ContentSnapshot
  alias ExCheck.TestImpact.State

  @version 1
  @max_appended_files 500
  @max_appended_path_bytes 100_000

  def prepare(_name, command, tool_opts, _run_opts)
      when not is_list(tool_opts) do
    {:ok, command, nil}
  end

  def prepare(name, command, tool_opts, run_opts) do
    if tool_opts[:content_changed] do
      prepare_gate(name, command, tool_opts, run_opts)
    else
      {:ok, command, nil}
    end
  end

  def finish(results, {:ok, ending_snapshot}) do
    Enum.each(results, fn
      {:ok, {_name, _command, opts}, _result} -> maybe_commit(opts[:content_gate], ending_snapshot)
      _result -> :ok
    end)
  end

  def finish(_results, :unavailable), do: :ok

  defp prepare_gate(name, command, tool_opts, run_opts) do
    case run_opts[:content_snapshot] do
      {:ok, snapshot} ->
        prepare_snapshot(name, command, tool_opts, run_opts, snapshot)

      :unavailable ->
        {:ok, command, nil}

      nil ->
        {:ok, command, nil}
    end
  end

  defp prepare_snapshot(name, command, tool_opts, run_opts, snapshot) do
    extensions = tool_opts[:content_changed_extensions]
    includes = tool_opts[:content_changed_include]
    current = ContentSnapshot.filter(snapshot, extensions, includes)
    identity = identity(name, command, tool_opts)
    path = state_path(name)
    previous = read(path, identity)
    changed_paths = ContentSnapshot.changed_paths(previous, current)

    gate = %{
      broad: tool_opts[:content_changed_full] || [],
      current: current,
      extensions: extensions,
      identity: identity,
      includes: includes,
      path: path
    }

    choose_command(command, tool_opts, run_opts, changed_paths, gate)
  end

  defp choose_command(command, tool_opts, run_opts, changed_paths, gate) do
    cond do
      run_opts[:full] ->
        {:ok, command, gate}

      changed_paths == [] ->
        {:skip, "no content changes"}

      append?(tool_opts) and safe_to_append?(changed_paths, gate.current, gate.broad) ->
        {:ok, command ++ changed_paths, gate}

      true ->
        {:ok, command, gate}
    end
  end

  defp append?(tool_opts), do: Keyword.get(tool_opts, :content_changed_append, true)

  defp safe_to_append?(changed_paths, current, broad_paths) do
    path_bytes = Enum.reduce(changed_paths, 0, &(byte_size(&1) + &2 + 1))

    length(changed_paths) <= @max_appended_files and
      path_bytes <= @max_appended_path_bytes and
      Enum.all?(changed_paths, &Map.has_key?(current, &1)) and
      Enum.all?(changed_paths, &(not broad_path?(&1, broad_paths)))
  end

  defp broad_path?(path, broad_paths) do
    Enum.any?(broad_paths, &String.starts_with?(path, &1))
  end

  defp maybe_commit(nil, _ending_snapshot), do: :ok

  defp maybe_commit(gate, ending_snapshot) do
    ending = ContentSnapshot.filter(ending_snapshot, gate.extensions, gate.includes)

    if ending == gate.current do
      State.atomic_write!(
        gate.path,
        :erlang.term_to_binary(%{version: @version, identity: gate.identity, files: ending}, [
          :compressed
        ])
      )
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read(path, identity) do
    case path |> File.read!() |> :erlang.binary_to_term([:safe]) do
      %{version: @version, identity: ^identity, files: files} when is_map(files) -> files
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp identity(name, command, tool_opts) do
    relevant_opts =
      Keyword.take(tool_opts, [
        :cd,
        :content_changed_append,
        :content_changed_extensions,
        :content_changed_full,
        :content_changed_include,
        :env
      ])

    {name, command, relevant_opts}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp state_path(name) do
    name_hash =
      name
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    Path.join(Mix.Project.manifest_path(), "ex_check.content_gate.#{name_hash}")
  end
end
