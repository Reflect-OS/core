defmodule ReflectOS.Core.MixProject do
  use Mix.Project

  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()

  @source_url "https://github.com/Reflect-OS/core"

  def project do
    [
      app: :reflect_os_core,
      description: description(),
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  defp description do
    """
    ReflectOS Core contains the set of sections, layouts, and layout managers
    which ship with the prebuild ReflectOS Firmware.
    """
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ReflectOS.Core.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Scenic
      {:scenic_fontawesome, "~>  0.1.0"},
      {:font_metrics, "~> 0.5"},

      # LiveView
      {:phoenix_live_view, "~> 1.1"},

      # ReflectOS Kernel
      {:reflect_os_kernel, "~> 0.10.0"},

      # For DateTime section
      {:nerves_time_zones, "~> 0.3.2"},

      # For Calendar section
      {:icalendar, "~> 1.1.2"},
      {:timex, "3.4.2"},
      {:req, "~> 0.5.0"},

      # For Weather section
      {:solarex, "~> 0.1.2"},
      {:zip_codes, "~> 0.1.0"},

      # For RSS Feed section,
      {:sax_map, "~> 1.2"},

      # For Web Condition Layout Manager
      {:html_sanitize_ex, "~> 1.4"}
    ]
  end

  defp package do
    [
      files: package_files(),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      name: "ReflectOS Core",
      source_url: "https://github.com/Reflect-OS/core",
      homepage_url: "https://github.com/Reflect-OS/core",
      source_ref: "v#{@version}",
      extras: ["README.md"],
      main: "readme"
    ]
  end

  defp package_files,
    do: [
      "lib",
      ".formatter.exs",
      "CHANGELOG.md",
      "LICENSE",
      "mix.exs",
      "README.md",
      "VERSION"
    ]
end
