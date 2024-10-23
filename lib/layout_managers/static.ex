defmodule ReflectOS.Core.LayoutManagers.Static do
  use ReflectOS.Kernel.LayoutManager

  import Phoenix.Component, only: [sigil_H: 2]

  alias ReflectOS.Kernel.Option
  alias ReflectOS.Kernel.LayoutManager
  alias ReflectOS.Kernel.LayoutManager.Definition
  alias ReflectOS.Kernel.LayoutManager.State
  alias ReflectOS.Kernel.Settings.LayoutStore

  @impl true
  def layout_manager_definition() do
    %Definition{
      name: "Static Layout",
      icon: """
        <svg class="text-gray-800 dark:text-white" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24">
          <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7.757 12h8.486M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/>
        </svg>
      """,
      description: fn assigns ->
        ~H"""
        Allows selecting a single, static layout.
        """
      end
    }
  end

  embedded_schema do
    field(:layout, :string)
  end

  @impl true
  def changeset(%__MODULE__{} = layout_manager, params \\ %{}) do
    layout_manager
    |> cast(params, [:layout])
    |> validate_required([:layout])
  end

  @impl true
  def layout_manager_options(),
    do: [
      %Option{
        key: :layout,
        label: "Layout",
        config: %{
          type: "select",
          prompt: "--Select Layout--",
          options:
            LayoutStore.list()
            |> Enum.map(fn %{name: name, id: id} ->
              {name, id}
            end)
        }
      }
    ]

  @impl LayoutManager
  def init_layout_manager(%State{} = state, %{layout: layout_id}) do
    state =
      state
      |> push_layout(layout_id)

    {:ok, state}
  end
end
