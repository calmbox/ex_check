defmodule ExCheck.FastFullAudit do
  @moduledoc false

  alias ExCheck.ContentSnapshot
  alias ExCheck.Printer
  alias ExCheck.TestImpact.State

  @version 1
  @version_string Integer.to_string(@version)
  @filename "ex_check.fast_full_audit"

  def finish(opts, starting_snapshot, ending_snapshot, passed?) do
    if opts[:debug] do
      finish_debug(opts, starting_snapshot, ending_snapshot, passed?)
    end
  end

  defp finish_debug(opts, starting_snapshot, ending_snapshot, passed?) do
    starting_generation = ContentSnapshot.generation(starting_snapshot)
    ending_generation = ContentSnapshot.generation(ending_snapshot)

    cond do
      opts[:explain] || qualified?(opts) ->
        :ok

      opts[:full] ->
        compare_full(starting_generation, ending_generation, passed?)

      true ->
        record_fast(starting_generation, ending_generation, passed?)
    end
  end

  defp qualified?(opts), do: opts[:only] not in [nil, []] or opts[:except] not in [nil, []]

  defp record_fast({:ok, generation}, {:ok, generation}, passed?) do
    State.atomic_write!(path(), "#{@version} #{generation} #{passed?}\n")
  end

  defp record_fast(_starting_generation, _ending_generation, _passed?), do: :ok

  defp compare_full({:ok, generation}, {:ok, generation}, full_passed?) do
    case read() do
      {:ok, ^generation, true} when full_passed? ->
        Printer.info([:green, "=> same-generation fast/full comparison: no fast miss"])
        Printer.info()

      {:ok, ^generation, true} ->
        Printer.info([
          :red,
          :bright,
          "=> fast miss: same source generation passed fast mode but failed full mode"
        ])

        Printer.info()

      {:ok, ^generation, false} ->
        Printer.info([:cyan, "=> same-generation fast/full comparison: fast mode already failed"])
        Printer.info()

      _ ->
        print_not_comparable()
    end
  end

  defp compare_full(_starting_generation, _ending_generation, _full_passed?) do
    print_not_comparable()
  end

  defp print_not_comparable do
    Printer.info([:cyan, "=> fast/full comparison unavailable for this source generation"])
    Printer.info()
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read do
    case File.read(path()) do
      {:ok, binary} ->
        case String.split(binary) do
          [@version_string, generation, "true"] ->
            {:ok, generation, true}

          [@version_string, generation, "false"] ->
            {:ok, generation, false}

          _ ->
            :error
        end

      {:error, _reason} ->
        :error
    end
  rescue
    _ -> :error
  end

  defp path, do: Path.join(Mix.Project.manifest_path(), @filename)
end
