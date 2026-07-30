defmodule Mix.Tasks.Check.Test do
  @moduledoc false

  use Mix.Task

  alias ExCheck.TestImpact.Runner

  @recursive true
  @preferred_cli_env :test
  @switches [debug: :boolean, explain: :boolean, full: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, []} = OptionParser.parse!(args, strict: @switches)

    case Runner.run(opts) do
      :ok -> :ok
      {:error, status} -> System.halt(status)
    end
  end
end
