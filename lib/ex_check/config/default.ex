defmodule ExCheck.Config.Default do
  @moduledoc false

  # Default tool order tries to put short-running tools first in order for sequential output
  # streaming to display as many outputs as possible as soon as possible.
  #
  # Base commands are the fast iterative defaults. `mix check --full` selects each tool's `:full`
  # command and enables `:full_only` tools for authoritative verification.
  @curated_tools [
    {:compiler, "mix compile --warnings-as-errors", env: %{"MIX_ENV" => "test"}},
    {:unused_deps, "mix deps.unlock --check-unused",
     detect: [{:elixir, ">= 1.10.0"}], fix: "mix deps.unlock --unused", full_only: true},
    {:formatter, "mix format --check-formatted",
     detect: [{:file, ".formatter.exs"}],
     env: %{"MIX_ENV" => "test"},
     fix: "mix format {mix,.formatter}.exs {config,lib,test}/**/*.{ex,exs}",
     content_changed: true,
     content_changed_extensions: ~w[.ex .exs],
     content_changed_include: ~w[mix.exs .formatter.exs config/ lib/ test/ apps/],
     content_changed_full: [".formatter.exs"]},
    {:mix_audit, "mix deps.audit", detect: [{:package, :mix_audit}], full_only: true},
    {:credo, "mix credo",
     detect: [{:package, :credo}],
     content_changed: true,
     content_changed_extensions: ~w[.ex .exs],
     content_changed_include: ~w[.credo.exs lib/ src/ test/ web/ apps/],
     content_changed_full: [".credo.exs"]},
    {:doctor, "mix doctor", detect: [{:package, :doctor}, {:elixir, ">= 1.8.0"}]},
    {:sobelow, "mix sobelow --exit",
     umbrella: [recursive: true], detect: [{:package, :sobelow}], full_only: true},
    {:ex_doc, "mix docs", detect: [{:package, :ex_doc}]},
    {:ex_unit, "mix check.test",
     detect: [{:file, "test"}],
     env: %{"MIX_ENV" => "test"},
     retry: "mix test --failed",
     full: "mix check.test --full"},
    {:dialyzer, "mix dialyzer", detect: [{:package, :dialyxir}], full_only: true},
    {:gettext, "mix gettext.extract --check-up-to-date",
     detect: [{:package, :gettext}], deps: [:ex_unit]},
    {:npm_test, "npm test", cd: "assets", detect: [{:file, "package.json", else: :disable}]}
  ]

  @default_config [
    parallel: true,
    skipped: true,
    full: false,
    tools: @curated_tools
  ]

  def get do
    @default_config
  end

  def tool_order(tool) do
    Enum.find_index(@curated_tools, &(elem(&1, 0) == tool))
  end
end
