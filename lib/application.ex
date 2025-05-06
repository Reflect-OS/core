defmodule ReflectOS.Core.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias ReflectOS.Kernel.Section.Registry, as: SectionRegistry
  alias ReflectOS.Kernel.Layout.Registry, as: LayoutRegistry
  alias ReflectOS.Kernel.LayoutManager.Registry, as: LayoutManagerRegistry

  @impl true
  def start(_type, _args) do
    children = [
      # Start a task to register Core ReflectOS plugins
      {Task, fn -> reflect_os_register() end}
    ]

    opts = [strategy: :one_for_one, name: ReflectOS.Core.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp reflect_os_register() do
    # Sections
    SectionRegistry.register([
      ReflectOS.Core.Sections.Weather,
      ReflectOS.Core.Sections.DateTime,
      ReflectOS.Core.Sections.Calendar,
      ReflectOS.Core.Sections.Countdown,
      ReflectOS.Core.Sections.RssFeed,
      ReflectOS.Core.Sections.Note
    ])

    # Layouts
    LayoutRegistry.register([
      ReflectOS.Core.Layouts.FourCorners
    ])

    # Layout Managers
    LayoutManagerRegistry.register([
      ReflectOS.Core.LayoutManagers.Static,
      ReflectOS.Core.LayoutManagers.WebCondition
    ])
  end
end
