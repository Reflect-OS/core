defmodule ReflectOS.Core.Layouts.FourCorners do
  alias Scenic.Graph
  alias Scenic.Scene
  alias Scenic.Primitive

  import Phoenix.Component, only: [sigil_H: 2]

  alias ReflectOS.Kernel.Section
  alias ReflectOS.Kernel.OptionGroup
  alias ReflectOS.Kernel.Option
  alias ReflectOS.Kernel.Layout.Definition

  use ReflectOS.Kernel.Layout

  @locations [:top_left, :top_right, :bottom_left, :bottom_right]

  @base_location_options [
    %Option{
      key: :stack_orientation,
      label: "Stack Orientation",
      config: %{
        type: "select",
        options: [
          {"Vertical", :vertical},
          {"Horizontal", :horizontal}
        ]
      }
    },
    %Option{
      key: :spacing,
      label: "Spacing",
      config: %{
        type: "select",
        options: [
          {"Compact", 12},
          {"Default", 24},
          {"Comfortable", 48},
          {"Spacious", 96}
        ]
      }
    }
  ]

  @location_options for location <- @locations,
                        do: %OptionGroup{
                          label:
                            Atom.to_string(location)
                            |> String.split("_")
                            |> Enum.map(&String.capitalize/1)
                            |> Enum.join(" "),
                          options:
                            @base_location_options
                            |> Enum.map(fn option ->
                              %{option | key: String.to_atom("#{location}_#{option.key}")}
                            end)
                        }

  embedded_schema do
    # Top Left
    field(:top_left_stack_orientation, Ecto.Enum,
      values: [:horizontal, :vertical],
      default: :vertical
    )

    field(:top_left_spacing, :integer, default: 24)

    # Top Right
    field(:top_right_stack_orientation, Ecto.Enum,
      values: [:horizontal, :vertical],
      default: :vertical
    )

    field(:top_right_spacing, :integer, default: 24)

    # Bottom Left
    field(:bottom_left_stack_orientation, Ecto.Enum,
      values: [:horizontal, :vertical],
      default: :vertical
    )

    field(:bottom_left_spacing, :integer, default: 24)

    # Bottom Right
    field(:bottom_right_stack_orientation, Ecto.Enum,
      values: [:horizontal, :vertical],
      default: :vertical
    )

    field(:bottom_right_spacing, :integer, default: 24)
  end

  @impl true
  def changeset(%__MODULE__{} = section, params \\ %{}) do
    section
    |> cast(params, [
      :top_left_stack_orientation,
      :top_left_spacing,
      :top_right_stack_orientation,
      :top_right_spacing,
      :bottom_left_stack_orientation,
      :bottom_left_spacing,
      :bottom_right_stack_orientation,
      :bottom_right_spacing
    ])
    |> validate_required([
      :top_left_stack_orientation,
      :top_right_stack_orientation,
      :bottom_left_stack_orientation,
      :bottom_right_stack_orientation
    ])
  end

  @doc false
  @impl ReflectOS.Kernel.Layout
  def layout_definition(),
    do: %Definition{
      name: "Four Corner",
      description: fn assigns ->
        ~H"""
        Allows placing sections in each of the four corners of the screen, with options for
        stacking (vertical vs. horizontal) and spacing.
        """
      end,
      icon: """
        <svg class="text-gray-800 dark:text-white" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="currentColor" viewBox="0 0 24 24">
          <path fill-rule="evenodd" d="M4.857 3A1.857 1.857 0 0 0 3 4.857v4.286C3 10.169 3.831 11 4.857 11h4.286A1.857 1.857 0 0 0 11 9.143V4.857A1.857 1.857 0 0 0 9.143 3H4.857Zm10 0A1.857 1.857 0 0 0 13 4.857v4.286c0 1.026.831 1.857 1.857 1.857h4.286A1.857 1.857 0 0 0 21 9.143V4.857A1.857 1.857 0 0 0 19.143 3h-4.286Zm-10 10A1.857 1.857 0 0 0 3 14.857v4.286C3 20.169 3.831 21 4.857 21h4.286A1.857 1.857 0 0 0 11 19.143v-4.286A1.857 1.857 0 0 0 9.143 13H4.857Zm10 0A1.857 1.857 0 0 0 13 14.857v4.286c0 1.026.831 1.857 1.857 1.857h4.286A1.857 1.857 0 0 0 21 19.143v-4.286A1.857 1.857 0 0 0 19.143 13h-4.286Z" clip-rule="evenodd"/>
        </svg>
      """,
      locations:
        @locations
        |> Enum.map(fn l ->
          %{
            key: l,
            label:
              Atom.to_string(l)
              |> String.split("_")
              |> Enum.map(&String.capitalize/1)
              |> Enum.join(" ")
          }
        end)
    }

  @impl ReflectOS.Kernel.Layout
  def layout_options() do
    @location_options
  end

  @impl ReflectOS.Kernel.Layout
  def init_layout(
        %Scene{} = scene,
        %{
          config: config,
          sections: sections,
          viewport_size: viewport_size
        },
        _opts
      ) do
    locations = format_locations(config, sections)

    # Collect the fully build graph and a list of section bounds,
    # where the key is {location, index} (e.g. {:top_left, 2})
    # and the value is the bounds for that section
    # We'll store that for later to make recalculating the layout easier
    {graph, section_bounds} =
      locations
      |> Enum.reduce({Graph.build(), []}, fn location, {acc_graph, acc_bounds} ->
        {graph, section_bounds} =
          acc_graph
          |> render_location(location, viewport_size)

        {graph, [section_bounds | acc_bounds]}
      end)

    section_bounds =
      section_bounds
      |> Enum.flat_map(& &1)
      |> Map.new()

    scene =
      scene
      |> assign(locations: locations)
      |> assign(section_bounds: section_bounds)
      |> assign(viewport_size: viewport_size)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:ok, scene}
  end

  @impl true
  def handle_section_update(
        %Scene{
          assigns: %{
            graph: graph,
            section_bounds: section_bounds,
            locations: locations,
            viewport_size: {viewport_width, viewport_height} = viewport_size
          }
        } =
          scene,
        {location, _index} = layout_tracker,
        %Graph{} = section_graph
      ) do
    bounds =
      Graph.bounds(section_graph)

    section_bounds =
      section_bounds
      |> Map.put(layout_tracker, bounds)

    location_bounds =
      section_bounds
      |> Enum.filter(fn {{bound_location, _}, _} ->
        bound_location == location
      end)
      |> Enum.sort_by(fn {{_, index}, _} ->
        index
      end)
      |> Enum.map(fn {_, bounds} ->
        bounds
      end)

    %{config: %{stack_orientation: orientation, spacing: spacing}} = locations[location]

    location_width = viewport_width / 2
    location_height = viewport_height / 2

    spacing =
      calculate_spacing(spacing, orientation, {location_width, location_height}, location_bounds)

    graph =
      graph
      |> adjust_section_origins(
        location,
        orientation,
        spacing,
        viewport_size,
        location_bounds
      )

    scene
    |> assign(section_bounds: section_bounds)
    |> assign(graph: graph)
    |> push_graph(graph)
  end

  defp format_locations(config, sections) do
    @locations
    |> Enum.reduce([], fn location, acc ->
      [
        {location,
         %{
           config:
             config
             |> Map.from_struct()
             |> Enum.filter(fn {k, _v} ->
               Atom.to_string(k)
               |> String.starts_with?(Atom.to_string(location))
             end)
             |> Enum.map(fn {k, v} ->
               {Atom.to_string(k)
                |> String.replace("#{location}_", "")
                |> String.to_atom(), v}
             end)
             |> Map.new(),
           sections: Map.get(sections, location, [])
         }}
        | acc
      ]
    end)
  end

  defp render_location(
         %Graph{} = graph,
         {location,
          %{config: %{stack_orientation: orientation, spacing: spacing}, sections: sections}},
         {viewport_width, viewport_height}
       ) do
    # Each component gets an id based on the location and the index in the list of sections
    # We also generate the size of each section at this time
    {graph, section_bounds} =
      graph
      |> add_location_sections(location, sections)

    # Determine the proper spacing
    location_width = viewport_width / 2
    location_height = viewport_height / 2

    location_bounds =
      section_bounds
      |> Enum.map(fn {_, bounds} -> bounds end)

    spacing =
      calculate_spacing(spacing, orientation, {location_width, location_height}, location_bounds)

    # Modify each primitive's transform based on spacing and assigned location
    {graph
     |> adjust_section_origins(
       location,
       orientation,
       spacing,
       {viewport_width, viewport_height},
       location_bounds
     ), section_bounds}
  end

  ########################################
  # Top Left - Adjust Section Origins
  ########################################
  defp adjust_section_origins(
         %Graph{} = graph,
         :top_left = location,
         :horizontal,
         spacing,
         {_, _},
         section_bounds
       ) do
    # Since this on the left, work our left to right
    start_x = 0
    start_y = 0
    start_index = 0

    {graph, _, _} =
      section_bounds
      |> Enum.reduce({graph, start_index, start_x}, fn {left, top, right, _bottom},
                                                       {graph, index, x} ->
        section_width = right - left
        x = x - left

        graph =
          graph
          |> Graph.modify(
            {location, index},
            &Primitive.put_transform(&1, :translate, {x, start_y + -1 * top})
          )

        {graph, index + 1, x + section_width + spacing}
      end)

    graph
  end

  defp adjust_section_origins(
         %Graph{} = graph,
         :top_left = location,
         :vertical,
         spacing,
         {_, _},
         section_bounds
       ) do
    # Since this on the top, work our way down
    start_x = 0
    start_y = 0
    start_index = 0

    {graph, _, _} =
      section_bounds
      |> Enum.reduce({graph, start_index, start_y}, fn {left, top, _right, bottom},
                                                       {graph, index, y} ->
        section_height = bottom - top
        x = start_x - left

        graph =
          graph
          |> Graph.modify(
            {location, index},
            &Primitive.put_transform(&1, :translate, {x, y + -1 * top})
          )

        {graph, index + 1, y + section_height + spacing}
      end)

    graph
  end

  ########################################
  # Top Right - Adjust Section Origins
  ########################################
  defp adjust_section_origins(
         %Graph{} = graph,
         :top_right = location,
         :horizontal,
         spacing,
         {start_x, _},
         section_bounds
       ) do
    # Since this on the right, work right to left
    start_y = 0
    start_index = Enum.count(section_bounds) - 1

    {graph, _, _} =
      section_bounds
      |> Enum.reverse()
      |> Enum.reduce({graph, start_index, start_x}, fn {left, top, right, _bottom},
                                                       {graph, index, start_x} ->
        section_width = right - left

        %Primitive{opts: opts} =
          graph
          |> Graph.get!({location, index})

        auto_align =
          opts
          |> get_in([:styles, :text_align])
          |> Kernel.==(:right)

        x =
          if auto_align do
            start_x
          else
            start_x - right
          end

        y = start_y - top

        graph =
          graph
          |> Graph.modify(
            {location, index},
            &Primitive.put_transform(&1, :translate, {x, y})
          )

        {graph, index - 1, start_x - section_width - spacing}
      end)

    graph
  end

  defp adjust_section_origins(
         %Graph{} = graph,
         :top_right = location,
         :vertical,
         spacing,
         {start_x, _},
         section_bounds
       ) do
    # Since this on the top, work our way down
    start_y = 0
    start_index = 0

    {graph, _, _} =
      section_bounds
      |> Enum.reduce({graph, start_index, start_y}, fn {_left, top, right, bottom},
                                                       {graph, index, y} ->
        y = y - top
        section_height = bottom - top

        %Primitive{opts: opts} =
          graph
          |> Graph.get!({location, index})

        auto_align =
          opts
          |> get_in([:styles, :text_align])
          |> Kernel.==(:right)

        x =
          if auto_align do
            start_x
          else
            start_x - right
          end

        graph =
          graph
          |> Graph.modify(
            {location, index},
            &Primitive.put_transform(&1, :translate, {x, y})
          )

        {graph, index + 1, y + section_height + spacing}
      end)

    graph
  end

  ########################################
  # Bottom Left - Adjust Section Origins
  ########################################
  defp adjust_section_origins(
         %Graph{} = graph,
         :bottom_left = location,
         :horizontal,
         spacing,
         {_, start_y},
         section_bounds
       ) do
    # Since this on the left, work our left to right
    start_x = 0
    start_index = 0

    {graph, _, _} =
      section_bounds
      |> Enum.reduce({graph, start_index, start_x}, fn {left, top, right, bottom},
                                                       {graph, index, x} ->
        section_height = bottom - top
        section_width = right - left
        x = x - left

        graph =
          graph
          |> Graph.modify(
            {location, index},
            &Primitive.put_transform(&1, :translate, {x, start_y - section_height})
          )

        {graph, index + 1, x + section_width + spacing}
      end)

    graph
  end

  defp adjust_section_origins(
         %Graph{} = graph,
         :bottom_left = location,
         :vertical,
         spacing,
         {_viewport_width, start_y},
         section_bounds
       ) do
    # Since this on the bottom, work our bottom to top
    start_x = 0
    start_index = Enum.count(section_bounds) - 1

    {graph, _, _} =
      section_bounds
      |> Enum.reverse()
      |> Enum.reduce({graph, start_index, start_y}, fn {left, top, _right, bottom},
                                                       {graph, index, y} ->
        section_height = bottom - top
        y = y - section_height
        x = start_x - left

        graph =
          graph
          |> Graph.modify(
            {location, index},
            &Primitive.put_transform(&1, :translate, {x, y})
          )

        {graph, index - 1, y - spacing}
      end)

    graph
  end

  ########################################
  # Bottom Right - Adjust Section Origins
  ########################################
  defp adjust_section_origins(
         %Graph{} = graph,
         :bottom_right = location,
         :horizontal,
         spacing,
         {start_x, start_y},
         section_bounds
       ) do
    # Since this on the bottom right, work our right to left
    start_index = Enum.count(section_bounds) - 1

    {graph, _, _} =
      section_bounds
      |> Enum.reverse()
      |> Enum.reduce({graph, start_index, start_x}, fn {left, _top, right, bottom},
                                                       {graph, index, start_x} ->
        section_width = right - left

        %Primitive{opts: opts} =
          graph
          |> Graph.get!({location, index})

        auto_align =
          opts
          |> get_in([:styles, :text_align])
          |> Kernel.==(:right)

        x =
          if auto_align do
            start_x
          else
            start_x - right
          end

        y = start_y - bottom

        graph =
          graph
          |> Graph.modify(
            {location, index},
            &Primitive.put_transform(&1, :translate, {x, y})
          )

        {graph, index - 1, start_x - section_width - spacing}
      end)

    graph
  end

  defp adjust_section_origins(
         %Graph{} = graph,
         :bottom_right = location,
         :vertical,
         spacing,
         {start_x, start_y},
         section_bounds
       ) do
    # Since this on the bottom right, work our way up
    start_index = Enum.count(section_bounds) - 1

    {graph, _, _} =
      section_bounds
      |> Enum.reverse()
      |> Enum.reduce({graph, start_index, start_y}, fn {_left, top, right, bottom},
                                                       {graph, index, start_y} ->
        section_height = bottom - top
        y = start_y - bottom

        %Primitive{opts: opts} =
          graph
          |> Graph.get!({location, index})

        auto_align =
          opts
          |> get_in([:styles, :text_align])
          |> Kernel.==(:right)

        x =
          if auto_align do
            start_x
          else
            start_x - right
          end

        graph =
          graph
          |> Graph.modify(
            {location, index},
            &Primitive.put_transform(&1, :translate, {x, y})
          )

        {graph, index - 1, start_y - section_height - spacing}
      end)

    graph
  end

  ###################
  # Add Location Sections
  ###################
  defp add_location_sections(%Graph{} = graph, _location, []), do: {graph, []}

  defp add_location_sections(%Graph{} = graph, location, sections) do
    {graph, _, section_bounds} =
      sections
      |> Enum.reduce({graph, 0, []}, fn %Section{module: module, id: section_id},
                                        {graph, index, section_bounds} ->
        tracker = {location, index}

        %ReflectOS.Kernel.Section.Definition{auto_align: auto_align} = module.section_definition()

        styles =
          if location in [:top_right, :bottom_right] && auto_align do
            [text_align: :right]
          else
            []
          end

        layout_align =
          if location in [:top_right, :bottom_right] do
            :right
          else
            :left
          end

        graph =
          graph
          |> module.add_to_graph({tracker, section_id},
            id: tracker,
            styles: styles,
            layout_align: layout_align
          )

        # Create a fake graph so we can do a bounds check and get the size
        # TODO get bounds of just the relevant primitive
        bounds =
          case Graph.bounds(graph) do
            nil -> {0, 0, 0, 0}
            bounds -> bounds
          end

        {graph, index + 1, [{tracker, bounds} | section_bounds]}
      end)

    # Correct section_bound order
    section_bounds = Enum.reverse(section_bounds)

    {graph, section_bounds}
  end

  ###################
  # Calculate Spacing
  ###################
  # If there is 0 or 1 section, no need to actually figure out the proper spacing
  defp calculate_spacing(_, _, _, sections) when length(sections) < 2, do: 0

  # If a fix spacing is provided, just use that
  defp calculate_spacing(spacing, _orientation, _location_width, _section_bounds)
       when is_number(spacing) do
    spacing
  end

  defp calculate_spacing(_, :horizontal, {location_width, _location_height}, section_bounds) do
    sections_count = Enum.count(section_bounds)

    total_width =
      section_bounds
      |> Enum.reduce(0, fn {left, _, right, _}, total ->
        total + (right - left)
      end)

    (location_width - total_width) / sections_count
  end

  defp calculate_spacing(_, :vertical, {_location_width, location_height}, section_bounds) do
    sections_count = Enum.count(section_bounds)

    total_height =
      section_bounds
      |> Enum.reduce(0, fn {_, top, _, bottom}, total ->
        total + (bottom - top)
      end)

    (location_height - total_height) / sections_count
  end
end
