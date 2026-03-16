defmodule ExCheck.LockTest do
  use ExUnit.Case, async: true

  import ExCheck.CaseHelpers

  alias ExCheck.Lock

  setup do
    tmp_dir = create_tmp_directory()
    lock_path = Path.join(tmp_dir, "lock.lease")

    on_exit(fn -> remove_tmp_directory(tmp_dir) end)

    {:ok,
     lock_path: lock_path,
     lock_opts: [
       path: lock_path,
       poll_interval_ms: 20,
       heartbeat_interval_ms: 20,
       stale_after_ms: 120
     ]}
  end

  test "releases lease on normal exit", %{lock_path: lock_path, lock_opts: lock_opts} do
    Lock.with_lock(
      fn ->
        assert File.dir?(lock_path)
        assert File.exists?(Path.join(lock_path, "owner"))
        assert File.exists?(Path.join(lock_path, "heartbeat"))
      end,
      lock_opts
    )

    refute File.exists?(lock_path)
  end

  test "waits while another process holds the lease", %{lock_opts: lock_opts} do
    parent = self()
    release_ref = make_ref()

    holder =
      Task.async(fn ->
        Lock.with_lock(
          fn ->
            send(parent, {:holding, self()})

            receive do
              {:release, ^release_ref} -> :ok
            end
          end,
          lock_opts
        )
      end)

    assert_receive {:holding, holder_pid}

    waiter =
      Task.async(fn ->
        started_at = System.monotonic_time(:millisecond)

        Lock.with_lock(fn -> System.monotonic_time(:millisecond) - started_at end, lock_opts)
      end)

    assert Task.yield(waiter, 50) == nil

    send(holder_pid, {:release, release_ref})

    waited_ms = Task.await(waiter)
    assert waited_ms >= 40
    assert Task.await(holder) == :ok
  end

  test "heartbeat keeps an active lease from being reclaimed", %{lock_opts: lock_opts} do
    parent = self()
    release_ref = make_ref()

    holder =
      Task.async(fn ->
        Lock.with_lock(
          fn ->
            send(parent, {:holding, self()})

            receive do
              {:release, ^release_ref} -> :ok
            end
          end,
          lock_opts
        )
      end)

    assert_receive {:holding, holder_pid}

    waiter =
      Task.async(fn ->
        Lock.with_lock(fn -> :acquired_after_release end, lock_opts)
      end)

    Process.sleep(180)
    assert Task.yield(waiter, 20) == nil

    send(holder_pid, {:release, release_ref})

    assert Task.await(waiter) == :acquired_after_release
    assert Task.await(holder) == :ok
  end

  test "reclaims an abandoned stale lease", %{lock_path: lock_path, lock_opts: lock_opts} do
    seed_stale_lease(lock_path, 500)

    assert Lock.with_lock(fn -> :ok end, lock_opts) == :ok
    refute File.exists?(lock_path)
  end

  test "stale reclaim is race-safe with multiple waiters", %{
    lock_path: lock_path,
    lock_opts: lock_opts
  } do
    seed_stale_lease(lock_path, 500)
    parent = self()

    first =
      Task.async(fn ->
        Lock.with_lock(
          fn ->
            send(parent, {:acquired, :first})
            Process.sleep(40)
            :first
          end,
          lock_opts
        )
      end)

    second =
      Task.async(fn ->
        Lock.with_lock(
          fn ->
            send(parent, {:acquired, :second})
            :second
          end,
          lock_opts
        )
      end)

    assert_receive {:acquired, acquired_one}
    assert_receive {:acquired, acquired_two}
    assert Enum.sort([acquired_one, acquired_two]) == [:first, :second]
    assert Enum.sort([Task.await(first), Task.await(second)]) == [:first, :second]
  end

  defp seed_stale_lease(lock_path, age_ms) do
    File.mkdir_p!(lock_path)
    File.write!(Path.join(lock_path, "owner"), "stale owner")

    File.write!(
      Path.join(lock_path, "heartbeat"),
      Integer.to_string(System.system_time(:millisecond) - age_ms)
    )
  end
end
