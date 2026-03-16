defmodule ExCheck.Lock do
  @moduledoc false

  alias ExCheck.Printer

  @escape Enum.map(~c" [~#%&*{}\\:<>?/+|\"]", &<<&1::utf8>>)
  @poll_interval_ms 1_000
  @heartbeat_interval_ms 1_000
  @stale_after_ms 10_000
  @owner_filename "owner"
  @heartbeat_filename "heartbeat"

  def with_lock(fun, opts \\ []) do
    acquire(opts)

    try do
      fun.()
    after
      release(opts)
    end
  end

  def acquire(opts \\ false) do
    opts = normalize_opts(opts)
    path = Keyword.fetch!(opts, :path)

    File.mkdir_p!(Path.dirname(path))
    ensure_not_owned!(path)
    do_acquire(path, opts, false)
    put_heartbeat_pid(path, start_heartbeat(path, opts))
    :ok
  end

  def release(opts \\ false) do
    opts = normalize_opts(opts)
    path = Keyword.fetch!(opts, :path)

    stop_heartbeat(path)
    File.rm_rf(path)
    :ok
  end

  defp do_acquire(path, opts, printed_waiting?) do
    case try_lock(path, opts) do
      :ok ->
        :ok

      :locked ->
        unless printed_waiting? do
          Printer.info([
            :yellow,
            "=> waiting for previous mix check to complete..."
          ])
        end

        Process.sleep(Keyword.fetch!(opts, :poll_interval_ms))
        do_acquire(path, opts, true)
    end
  end

  defp try_lock(path, opts) do
    case File.mkdir(path) do
      :ok ->
        initialize_lease(path)
        :ok

      {:error, :eexist} ->
        case reclaim_stale_lock(path, opts) do
          :reclaimed ->
            try_lock(path, opts)

          :active ->
            :locked

          :gone ->
            try_lock(path, opts)
        end
    end
  end

  defp initialize_lease(path) do
    File.write!(owner_path(path), owner_metadata())
    refresh_heartbeat(path)
  end

  defp reclaim_stale_lock(path, opts) do
    if stale_lock?(path, opts) do
      stale_path = "#{path}.stale.#{System.unique_integer([:positive])}"

      case File.rename(path, stale_path) do
        :ok ->
          File.rm_rf(stale_path)
          :reclaimed

        {:error, :enoent} ->
          :gone

        {:error, :eexist} ->
          reclaim_stale_lock(path, opts)

        {:error, reason} ->
          raise File.Error, reason: reason, action: "rename", path: path
      end
    else
      :active
    end
  end

  defp stale_lock?(path, opts) do
    stale_after_ms = Keyword.fetch!(opts, :stale_after_ms)

    case heartbeat_age_ms(path) do
      {:ok, age_ms} -> age_ms >= stale_after_ms
      {:error, :enoent} -> false
    end
  end

  defp heartbeat_age_ms(path) do
    heartbeat_path = heartbeat_path(path)

    with true <- File.exists?(heartbeat_path),
         {:ok, content} <- File.read(heartbeat_path),
         {last_refreshed_ms, ""} <- Integer.parse(String.trim(content)) do
      {:ok, System.system_time(:millisecond) - last_refreshed_ms}
    else
      false ->
        directory_age_ms(path)

      {:error, :enoent} ->
        directory_age_ms(path)

      :error ->
        directory_age_ms(path)
    end
  end

  defp directory_age_ms(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> {:ok, System.os_time(:second) * 1_000 - stat.mtime * 1_000}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_heartbeat(path, opts) do
    heartbeat_interval_ms = Keyword.fetch!(opts, :heartbeat_interval_ms)

    spawn_link(fn -> heartbeat_loop(path, heartbeat_interval_ms) end)
  end

  defp heartbeat_loop(path, heartbeat_interval_ms) do
    receive do
      {:stop, caller, ref} ->
        send(caller, {ref, :stopped})
        :ok
    after
      heartbeat_interval_ms ->
        refresh_heartbeat(path)
        heartbeat_loop(path, heartbeat_interval_ms)
    end
  end

  defp stop_heartbeat(path) do
    case Process.delete(heartbeat_pid_key(path)) do
      nil ->
        :ok

      heartbeat_pid ->
        ref = Process.monitor(heartbeat_pid)
        stop_ref = make_ref()
        send(heartbeat_pid, {:stop, self(), stop_ref})

        receive do
          {^stop_ref, :stopped} ->
            Process.demonitor(ref, [:flush])
            :ok

          {:DOWN, ^ref, :process, ^heartbeat_pid, _reason} ->
            :ok
        after
          @poll_interval_ms ->
            Process.demonitor(ref, [:flush])
            :ok
        end
    end
  end

  defp put_heartbeat_pid(path, heartbeat_pid) do
    Process.put(heartbeat_pid_key(path), heartbeat_pid)
  end

  defp heartbeat_pid_key(path), do: {__MODULE__, :heartbeat_pid, path}

  defp ensure_not_owned!(path) do
    if Process.get(heartbeat_pid_key(path)) do
      raise "lock already acquired by current process: #{path}"
    end
  end

  defp refresh_heartbeat(path) do
    File.write!(heartbeat_path(path), Integer.to_string(System.system_time(:millisecond)))
  end

  defp owner_metadata do
    %{
      owner_pid: inspect(self()),
      system_pid: System.pid(),
      acquired_at_ms: System.system_time(:millisecond)
    }
    |> inspect(pretty: true)
  end

  defp owner_path(path), do: Path.join(path, @owner_filename)
  defp heartbeat_path(path), do: Path.join(path, @heartbeat_filename)

  defp normalize_opts(opts) when is_boolean(opts), do: normalize_opts(global: opts)

  defp normalize_opts(opts) when is_list(opts) do
    global? = Keyword.get(opts, :global, false)

    [
      path: Keyword.get_lazy(opts, :path, fn -> lease_path(default_path(global?)) end),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @poll_interval_ms),
      heartbeat_interval_ms: Keyword.get(opts, :heartbeat_interval_ms, @heartbeat_interval_ms),
      stale_after_ms: Keyword.get(opts, :stale_after_ms, @stale_after_ms)
    ]
  end

  defp default_path(true = _global?) do
    Path.join(System.tmp_dir!(), "ex_check.lock")
  end

  defp default_path(false = _global?) do
    app_id = File.cwd!() |> String.replace(@escape, "_") |> String.replace(~r/^_+/, "")
    Path.join(System.tmp_dir!(), "ex_check-lock-#{app_id}.lock")
  end

  defp lease_path(path), do: path <> ".lease"
end
