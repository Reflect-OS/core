defmodule ReflectOS.Core.Sections.DateTime do
  use ReflectOS.Kernel.Section, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives, only: [{:text, 3}]

  import ReflectOS.Kernel.Typography

  alias ReflectOS.Kernel.Settings.System
  alias ReflectOS.Kernel.Section.Definition
  alias ReflectOS.Kernel.{OptionGroup, Option}
  import ReflectOS.Kernel.Primitives, only: [render_section_label: 3]

  embedded_schema do
    field(:show_label?, :boolean, default: false)
    field(:label, :string, default: "Date/Time")
    field(:timezone, :string, default: "system")
    field(:time_format, :string, default: "system")
    field(:show_date?, :boolean, default: true)
    field(:date_format, :string, default: "%A, %b %-d")
  end

  @impl true
  def changeset(%__MODULE__{} = section, params \\ %{}) do
    section
    |> cast(params, [:show_label?, :label, :timezone, :time_format, :show_date?, :date_format])
    |> validate_required([:timezone, :time_format, :date_format])
  end

  @doc false
  @impl true
  def section_definition(),
    do: %Definition{
      name: "Date/Time",
      icon: """
        <svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24">
          <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/>
        </svg>
      """,
      auto_align: true
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
      # Timezone
      %Option{
        key: :timezone,
        label: "Timezone",
        config: %{
          type: "select",
          options: [
            {"System Default [#{System.timezone()}]", "system"}
            | NervesTimeZones.time_zones()
              |> Enum.sort(fn tz1, tz2 ->
                case {tz1, tz2} do
                  {"US/" <> rest1, "US/" <> rest2} ->
                    rest1 <= rest2

                  {"US/" <> _, _} ->
                    true

                  {_, "US/" <> _} ->
                    false

                  _ ->
                    tz1 <= tz2
                end
              end)
          ]
        }
      },
      # Time Format
      %Option{
        key: :time_format,
        label: "Hour Format",
        config: %{
          type: "select",
          options: [
            {"12 Hour (6:30 PM)", "%-I:%M %p"},
            {"24 Hour (18:30)", "%-H:%M"},
            {"System Default [#{case System.time_format() do
               "%-I:%M %p" -> "12 Hour (6:30 PM)"
               "%-H:%M" -> "24 Hour (18:30)"
               _ -> ""
             end}]", "system"}
          ]
        }
      },
      %Option{
        key: :show_date?,
        label: "Show Date?",
        config: %{
          type: "checkbox"
        }
      },
      # Date Format
      %Option{
        key: :date_format,
        label: "Date Format",
        hidden: fn %{show_date?: show_date?} ->
          !show_date?
        end,
        config: %{
          type: "select",
          options: [
            {"Day of the week with Month, Date, and Year", "%A, %b %-d %Y"},
            {"Day of the week with Month and Date", "%A, %b %-d"},
            {"Month Date, and Year", "%B %-d, %Y"},
            {"Month and Date", "%B %-d"},
            {"mm/dd/yyyy", "%-m/%-d/%Y"}
          ]
        }
      }
    ]

  @doc false
  @impl true
  def init_section(scene, %__MODULE__{} = section_config, opts) do
    styles = Keyword.get(opts, :styles, [])

    timezone =
      case section_config.timezone do
        "system" ->
          System.subscribe("timezone")
          System.timezone()

        tz ->
          tz
      end

    time_format =
      if section_config.time_format == "system" do
        System.subscribe("time_format")
        System.time_format()
      else
        section_config.time_format
      end

    scene =
      scene
      |> assign(
        styles: styles,
        layout_align: opts[:layout_align],
        show_label?: section_config.show_label?,
        label: section_config.label,
        time_format: time_format,
        show_date?: section_config.show_date?,
        date_format: section_config.date_format,
        timezone: timezone
      )
      |> assign_new(timer: nil, last: nil)
      |> render()

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
          property: ["system", "time_format"],
          value: time_format
        },
        scene
      ) do
    scene =
      scene
      |> assign(time_format: time_format)

    {:noreply, render(scene)}
  end

  def handle_info(
        %PropertyTable.Event{
          property: ["system", "timezone"],
          value: timezone
        },
        scene
      ) do
    scene =
      scene
      |> assign(timezone: timezone)

    {:noreply, render(scene)}
  end

  # --------------------------------------------------------
  defp render(
         %Scenic.Scene{
           assigns: %{
             styles: styles,
             layout_align: layout_align,
             time_format: time_format,
             date_format: date_format,
             timezone: timezone,
             last: last,
             show_date?: show_date?,
             show_label?: show_label?,
             label: label
           }
         } = scene
       ) do
    date_time = DateTime.now!(timezone) |> DateTime.truncate(:second)

    if date_time != last do
      # set up the requested graph
      graph =
        Graph.build(styles)
        |> text(
          Calendar.strftime(date_time, time_format),
          [id: :time, text_base: :top] |> h1() |> bold()
        )
        # Conditionally render the date field based on config
        |> then(fn graph ->
          if show_date? do
            graph
            |> text(
              Calendar.strftime(date_time, date_format),
              [id: :date, t: {0, 80}, text_base: :top] |> h5() |> light()
            )
          else
            graph
          end
        end)
        |> render_section_label(%{show_label?: show_label?, label: label},
          align: layout_align
        )

      scene
      |> assign(last: date_time)
      |> push_section(graph)
    else
      scene
    end
  end
end
