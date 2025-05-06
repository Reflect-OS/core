defmodule ReflectOS.Core.Sections.Note do
  use ReflectOS.Kernel.Section, has_children: false

  alias Scenic.Graph
  alias Scenic.Assets.Static
  import Scenic.Primitives, only: [{:text, 3}]

  import Phoenix.Component, only: [sigil_H: 2]

  import ReflectOS.Kernel.Typography
  alias ReflectOS.Kernel.Settings.System
  alias ReflectOS.Kernel.Section.Definition
  alias ReflectOS.Kernel.{OptionGroup, Option}
  import ReflectOS.Kernel.Primitives, only: [render_section_label: 3]

  @section_width 350

  embedded_schema do
    field(:show_label?, :boolean, default: false)
    field(:label, :string)
    field(:note, :string)
  end

  @impl true
  def changeset(%__MODULE__{} = section, params \\ %{}) do
    section
    |> cast(params, [:show_label?, :label, :note])
  end

  @doc false
  @impl true
  def section_definition(),
    do: %Definition{
      name: "Note",
      icon: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><
          !--!Font Awesome Free 6.7.2 by @fontawesome - https://fontawesome.com License - https://fontawesome.com/license/free Copyright 2025 Fonticons, Inc.-->
          <path d="M64 32C28.7 32 0 60.7 0 96L0 416c0 35.3 28.7 64 64 64l224 0 0-112c0-26.5 21.5-48 48-48l112 0 0-224c0-35.3-28.7-64-64-64L64 32zM448 352l-45.3 0L336 352c-8.8 0-16 7.2-16 16l0 66.7 0 45.3 32-32 64-64 32-32z"/>
        </svg>
      """,
      description: fn assigns ->
        ~H"""
        This section allows you to to write a simple note for display on ReflectOS.
        """
      end
    }

  @impl true
  def section_options(),
    do: [
      # Label
      %OptionGroup{
        label: "Label",
        options: [
          %Option{
            key: :show_label?,
            label: "Show Label",
            config: %{
              type: "checkbox"
            }
          },
          %Option{
            key: :label,
            label: "Label Text",
            hidden: fn %{show_label?: show_label?} ->
              !show_label?
            end
          }
        ]
      },
      # Descrition
      %Option{
        key: :note,
        label: "Note",
        config: %{
          type: "textarea",
          placeholder: "Write your note here!"
        }
      }
    ]

  @doc false
  @impl true
  def init_section(scene, %__MODULE__{} = section_config, opts) do
    scene =
      scene
      |> assign(
        layout_align: opts[:layout_align],
        show_label?: section_config.show_label?,
        label: section_config.label,
        note: section_config.note
      )
      |> render()

    {:ok, scene}
  end

  # --------------------------------------------------------
  defp render(%Scenic.Scene{} = scene) do
    graph = render_graph(scene.assigns)

    scene
    |> push_section(graph)
  end

  defp render_graph(%{
         layout_align: layout_align,
         show_label?: show_label?,
         label: label,
         note: note
       }) do
    graph =
      if is_binary(note) do
        {:ok, {Static.Font, fm}} = Static.meta(:roboto)

        wrapped = FontMetrics.wrap(note, @section_width, 32, fm)

        Graph.build()
        |> text(
          wrapped,
          [
            id: :note,
            text_base: :top,
            text_align: :left,
            t: {0, 0}
          ]
          |> h7()
        )
      else
        Graph.build()
      end

    graph
    |> render_section_label(%{show_label?: show_label?, label: label},
      align: layout_align
    )
  end
end
