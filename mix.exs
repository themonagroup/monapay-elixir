defmodule MonaPay.MixProject do
  use Mix.Project

  def project do
    [
      app: :monapay,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: [],
      description: "SDK Elixir stdlib-only cho MONA Pay",
      package: package(),
      source_url: "https://github.com/themonagroup/monapay-elixir",
      homepage_url: "https://monapay.vn/docs"
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl, :crypto, :public_key]]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "MONA Pay Docs" => "https://monapay.vn/docs",
        "Source" => "https://github.com/themonagroup/monapay-elixir"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE SECURITY.md examples)
    ]
  end
end
