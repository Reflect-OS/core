defmodule ReflectOS.Core.Sections.Countdown do
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

  embedded_schema do
    field(:show_label?, :boolean, default: false)
    field(:label, :string)
    field(:countdown_datetime, :naive_datetime)
    field(:description, :string)
  end

  @impl true
  def changeset(%__MODULE__{} = section, params \\ %{}) do
    section
    |> cast(params, [:show_label?, :label, :countdown_datetime, :description])
    |> validate_required([:countdown_datetime])
  end

  @doc false
  @impl true
  def section_definition(),
    do: %Definition{
      name: "Countdown",
      icon: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512">
          <!--!Font Awesome Free 6.6.0 by @fontawesome - https://fontawesome.com License - https://fontawesome.com/license/free Copyright 2024 Fonticons, Inc.-->
          <path d="M176 0c-17.7 0-32 14.3-32 32s14.3 32 32 32l16 0 0 34.4C92.3 113.8 16 200 16 304c0 114.9 93.1 208 208 208s208-93.1 208-208c0-41.8-12.3-80.7-33.5-113.2l24.1-24.1c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0L355.7 143c-28.1-23-62.2-38.8-99.7-44.6L256 64l16 0c17.7 0 32-14.3 32-32s-14.3-32-32-32L224 0 176 0zm72 192l0 128c0 13.3-10.7 24-24 24s-24-10.7-24-24l0-128c0-13.3 10.7-24 24-24s24 10.7 24 24z"/>
        </svg>
      """,
      description: fn assigns ->
        ~H"""
        This section allows you to configure a date and time, and show a countdown on your ReflectOS
        dashboard.
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
      # Countdown DateTime
      %Option{
        key: :countdown_datetime,
        label: "Countdown Until",
        config: %{
          type: "datetime-local"
        }
      },
      # Descrition
      %Option{
        key: :description,
        label: "Description",
        config: %{
          type: "textarea",
          placeholder: "Until the next release of ReflectOS!"
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
        countdown_datetime:
          DateTime.from_naive!(section_config.countdown_datetime, System.timezone()),
        description: section_config.description,
        last: nil
      )
      |> render()

    # Get notified if the system timezone changes
    System.subscribe("timezone")

    # send a message to self to start the clock a fraction of a second
    # into the future to hopefully line it up closer to when the seconds
    # actually are. Note that I want it to arrive just slightly after
    # the one second mark, which is way better than just slighty before.
    # avoid trunc errors and such that way even if it means the second
    # timer is one millisecond behind the actual time.
    {microseconds, _} = Time.utc_now().microsecond
    Process.send_after(self(), :start_clock, 1001 - trunc(microseconds / 1000))
    {:ok, scene}
  end

  # --------------------------------------------------------
  @doc false
  # should be shortly after the actual one-second mark
  @impl GenServer
  def handle_info(:start_clock, scene) do
    # start the timer on a one-second interval
    {:ok, timer} = :timer.send_interval(1000, :tick_tock)

    scene =
      scene
      |> assign(:timer, timer)
      |> render()

    # update the clock
    {:noreply, scene}
  end

  # --------------------------------------------------------
  def handle_info(:tick_tock, scene) do
    {:noreply, render(scene)}
  end

  def handle_info(
        %PropertyTable.Event{
          property: ["system", "timezone"],
          value: timezone
        },
        scene
      ) do
    countdown_datetime = get(scene, :countdown_datetime)

    scene =
      scene
      |> assign(:countdown_datetime, DateTime.shift_zone(countdown_datetime, timezone))

    {:noreply, render(scene)}
  end

  # --------------------------------------------------------
  defp render(
         %Scenic.Scene{
           assigns: %{
             countdown_datetime: countdown_datetime,
             last: last
           }
         } = scene
       ) do
    date_time = DateTime.now!(countdown_datetime.time_zone) |> DateTime.truncate(:second)

    if date_time != last do
      graph = render_graph(scene.assigns)

      scene
      |> assign(last: date_time)
      |> push_section(graph)
    else
      scene
    end
  end

  defp render_graph(
         %{
           layout_align: layout_align,
           show_label?: show_label?,
           label: label,
           countdown_datetime: countdown_datetime,
           description: description
         } = assigns
       ) do
    diff = DateTime.diff(countdown_datetime, DateTime.now!(countdown_datetime.time_zone))

    diff =
      if diff < 0 do
        # We hit the target date, let's cancel the timer
        if assigns[:timer] != nil, do: :timer.cancel(assigns[:timer])

        # Just show zeroes instead of negative numbers if we're past the countdown date/time
        0
      else
        diff
      end

    # TODO - account for leap years
    {years, rem} = divmod(diff, 60 * 60 * 24 * 365)
    {days, rem} = divmod(rem, 60 * 60 * 24)
    {hours, rem} = divmod(rem, 60 * 60)
    {minutes, seconds} = divmod(rem, 60)

    {:ok, {Static.Font, fm}} = Static.meta(:roboto)

    [{part1_count, part1_label}, {part2_count, part2_label}, {part3_count, part3_label}] =
      cond do
        years >= 1 ->
          [{years, "years"}, {days, "days"}, {hours, "hours"}]

        days >= 1 ->
          [{days, "days"}, {hours, "hours"}, {minutes, "mins"}]

        true ->
          [{hours, "hours"}, {minutes, "mins"}, {seconds, "secs"}]
      end

    label_y = 72

    space_width = FontMetrics.width(" ", 72, fm)

    # Part 1
    padded_count = "#{String.pad_leading("#{part1_count}", 2, "0")}"
    count_width = FontMetrics.width(padded_count, 72, fm)
    label_x = 0 - count_width + space_width

    graph =
      Graph.build()
      |> text(
        "#{padded_count} :",
        [id: :part1_count, text_base: :top, text_align: :right]
        |> h2()
        |> bold()
      )
      |> text(
        part1_label,
        [id: :part1_label, text_base: :top, text_align: :center, t: {label_x, label_y}]
        |> h7()
        |> light()
      )

    # Part 2
    {_left, _top, right, _bottom} = Graph.bounds(graph)
    right = right + space_width
    padded_count = "#{String.pad_leading("#{part2_count}", 2, "0")}"
    count_width = FontMetrics.width(padded_count, 72, fm)
    label_x = right + count_width / 2

    graph =
      graph
      |> text(
        "#{padded_count} : ",
        [id: :part2_count, text_base: :top, text_align: :left, t: {right, 0}]
        |> h2()
        |> bold()
      )
      |> text(
        part2_label,
        [id: :part2_label, text_base: :top, text_align: :center, t: {label_x, label_y}]
        |> h7()
        |> light()
      )

    # Part 3
    {_left, _top, right, _bottom} = Graph.bounds(graph)
    padded_count = "#{String.pad_leading("#{part3_count}", 2, "0")}"
    count_width = FontMetrics.width(padded_count, 72, fm)
    label_x = right + count_width / 2

    graph =
      graph
      |> text(
        padded_count,
        [id: :part2_count, text_base: :top, text_align: :left, t: {right, 0}]
        |> h2()
        |> bold()
      )
      |> text(
        part3_label,
        [id: :part2_label, text_base: :top, text_align: :center, t: {label_x, label_y}]
        |> h7()
        |> light()
      )

    graph =
      if is_binary(description) do
        {left, _top, right, bottom} = Graph.bounds(graph)
        width = right - left
        wrapped = FontMetrics.wrap(description, width, 32, fm)

        graph
        |> text(
          wrapped,
          [
            id: :description,
            text_base: :top,
            text_align: :center,
            t: {(right + left) / 2, bottom + 12}
          ]
          |> h7()
        )
      else
        graph
      end

    graph
    |> render_section_label(%{show_label?: show_label?, label: label},
      align: layout_align
    )
  end

  defp divmod(e, d) do
    ~w|div rem|a
    |> Enum.map(&apply(Kernel, &1, [e, d]))
    |> List.to_tuple()
  end
end
