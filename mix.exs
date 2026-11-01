defmodule RefractDb.MixProject do
  use Mix.Project

  def project do
    [
      app: :refract_db,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      plt_add_apps: [:ex_unit],
      list_unused_filters: true
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:refract, path: "../refract"},
      {:ecto_sql, "~> 3.13"},
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:ecto_sqlite3, "~> 0.17", only: :test},
      {:postgrex, "~> 0.20", only: :test},
      {:myxql, "~> 0.7", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
