defmodule ReflectOS.Core.Sections.Calendar do
  use ReflectOS.Kernel.Section

  require Logger

  alias Scenic.Graph
  alias Scenic.Scene
  alias Scenic.Assets.Static
  import Scenic.Primitives
  alias ICalendar.Event

  import Phoenix.Component, only: [sigil_H: 2]

  alias ReflectOS.Kernel.{Option, OptionGroup}
  import ReflectOS.Kernel.Primitives, only: [render_section_label: 3]
  import ReflectOS.Kernel.Typography
  alias ReflectOS.Kernel.Section.Definition
  alias ReflectOS.Kernel.Settings.System

  alias ReflectOS.Core.Sections.Calendar.Service

  embedded_schema do
    field(:show_label?, :boolean, default: false)
    field(:label, :string, default: "Calendar")
    field(:max_displayed_events, :integer, default: 5)
    field(:polling_interval_seconds, :integer, default: 60)

    field(:ical_url_1, :string)
    field(:ical_url_2, :string)
    field(:ical_url_3, :string)
    field(:ical_url_4, :string)
    field(:ical_url_5, :string)
  end

  @impl true
  def changeset(%__MODULE__{} = section, params \\ %{}) do
    section
    |> cast(params, [
      :show_label?,
      :label,
      :max_displayed_events,
      :polling_interval_seconds,
      :ical_url_1,
      :ical_url_2,
      :ical_url_3,
      :ical_url_4,
      :ical_url_5
    ])
    |> validate_required([
      :show_label?,
      :max_displayed_events,
      :polling_interval_seconds,
      :ical_url_1
    ])
  end

  @impl true
  def section_definition(),
    do: %Definition{
      name: "Calendar",
      icon: """
        <svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24">
          <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 10h16m-8-3V4M7 7V4m10 3V4M5 20h14a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1Zm3-7h.01v.01H8V13Zm4 0h.01v.01H12V13Zm4 0h.01v.01H16V13Zm-8 4h.01v.01H8V17Zm4 0h.01v.01H12V17Zm4 0h.01v.01H16V17Z"/>
        </svg>
      """,
      description: fn assigns ->
        ~H"""
        This section provides an agenda view of upcoming events -
        all you need to provide is an iCal calendar link.
        There are number of calendar providers which have feeds you can use.
        For example, Google allows you to use a “secret address” for your
        calendar which works with ReflectOS - check out
        <a
          class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
          target="_blank"
          href="https://support.google.com/calendar/answer/37648?hl=en#zippy=%2Csecret-address%2Cget-your-calendar-view-only"
        >
          the instructions.
        </a>.
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
      %OptionGroup{
        label: "Calendars",
        description: fn assigns ->
          ~H"""
          Calendar Urls in iCal format (usually ends with .ics).
          Many calendar systems provide this type of feed.  For example,
          instructions for Google Calendar can be found
          <a
            target="_blank"
            href="https://support.google.com/calendar/answer/37648?hl=en#zippy=%2Csecret-address%2Cget-your-calendar-view-only"
            class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
          >
            here</a>. <br /><br /> You can add up to five calendars.
          """
        end,
        options: [
          # iCal URLs
          %Option{
            key: :ical_url_1,
            label: "Calendar Url 1"
          },
          %Option{
            key: :ical_url_2,
            label: "Calendar Url 2"
          },
          %Option{
            key: :ical_url_3,
            label: "Calendar Url 3"
          },
          %Option{
            key: :ical_url_4,
            label: "Calendar Url 4"
          },
          %Option{
            key: :ical_url_5,
            label: "Calendar Url 5"
          }
        ]
      },
      %OptionGroup{
        label: "Display",
        options: [
          # Max displayed events
          %Option{
            key: :max_displayed_events,
            label: "Number of displayed events",
            config: %{
              type: "number"
            }
          },
          # Refresh Interval
          %Option{
            key: :polling_interval_seconds,
            label: "Refresh Interval (seconds)",
            config: %{
              type: "number"
            }
          }
        ]
      }
    ]

  @time_width 96
  @total_width 430
  @summary_width @total_width - @time_width

  @summary_style %{
    font_size: 24,
    font: :roboto
  }

  @doc false
  @impl ReflectOS.Kernel.Section
  def init_section(
        scene,
        %__MODULE__{
          polling_interval_seconds: polling_interval_seconds,
          max_displayed_events: max_displayed_events,
          label: calendar_name,
          show_label?: show_label?
        } = section_config,
        opts
      ) do
    polling_interval = polling_interval_seconds * 1000

    ical_urls =
      [
        section_config.ical_url_1,
        section_config.ical_url_2,
        section_config.ical_url_3,
        section_config.ical_url_4,
        section_config.ical_url_5
      ]
      |> Enum.filter(fn url ->
        is_binary(url) and url |> String.trim() |> String.length() > 0
      end)

    System.subscribe("timezone")
    System.subscribe("time_format")

    scene =
      scene
      |> assign(
        polling_interval: polling_interval,
        ical_urls: ical_urls,
        max_displayed_events: max_displayed_events,
        timezone: System.timezone(),
        time_format: System.time_format(),
        calendar_name: calendar_name,
        show_label?: show_label?,
        layout_align: opts[:layout_align]
      )

    graph = refresh(scene.assigns)

    schedule_poll(polling_interval)

    {:ok, push_section(scene, graph)}
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll_feed, interval)
  end

  @impl true
  def handle_info(:poll_feed, %Scene{assigns: %{polling_interval: polling_interval}} = scene) do
    graph = refresh(scene.assigns)
    schedule_poll(polling_interval)
    {:noreply, push_section(scene, graph)}
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

    graph = refresh(scene.assigns)
    {:noreply, push_section(scene, graph)}
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

    graph = refresh(scene.assigns)
    {:noreply, push_section(scene, graph)}
  end

  @spec refresh(%{
          :calendar_name => nil | binary(),
          :ical_urls => list({binary(), binary()}),
          :max_displayed_events => integer(),
          :timezone => binary(),
          :time_format => binary(),
          optional(any()) => any()
        }) :: Scenic.Graph.t()
  def refresh(
        %{
          ical_urls: ical_urls,
          timezone: timezone,
          max_displayed_events: max_displayed_events
        } = assigns
      ) do
    Service.retrieve_calendar_events(ical_urls, timezone)
    |> Enum.take(max_displayed_events)
    |> render(assigns)
  end

  def render(events, %{
        timezone: timezone,
        calendar_name: calendar_name,
        show_label?: show_label?,
        time_format: time_format,
        layout_align: layout_align
      }) do
    Graph.build(text_align: :left)
    |> render_events(events, timezone, time_format)
    |> render_section_label(%{label: calendar_name, show_label?: show_label?},
      align: layout_align
    )
  end

  defp render_events(graph, events, timezone, time_format) do
    grouped_events =
      events
      |> Enum.group_by(fn %{dtstart: dtstart} ->
        dtstart
        |> DateTime.to_date()
      end)

    grouped_events
    |> Map.keys()
    |> Enum.sort(Date)
    |> Enum.reduce(graph, fn date, graph ->
      events = grouped_events[date]

      graph =
        graph
        |> render_date(date, timezone)
        |> render_events_for_date(events, time_format)

      v_offset = get_bottom_bound(graph) + 4

      graph
      |> line({{0, v_offset}, {@total_width, v_offset}}, stroke: {1, :white})
    end)
  end

  defp render_date(graph, date, timezone) do
    styles =
      []
      |> h7()
      |> bold()

    font_size = Keyword.get(styles, :font_size)
    font = Keyword.get(styles, :font, :roboto)

    day_of_week = format_day_of_week(date, timezone)
    date_formatted = Calendar.strftime(date, "%b %-d")

    v_offset = get_bottom_bound(graph) + font_size + 4

    {:ok, {Static.Font, fm}} = Static.meta(font)
    day_of_week_width = FontMetrics.width(day_of_week, font_size, fm)

    graph
    |> text(day_of_week, styles ++ [t: {0, v_offset}])
    |> text(
      date_formatted,
      (h7() |> light()) ++ [t: {day_of_week_width + 4, v_offset}]
    )
  end

  defp render_events_for_date(graph, events, time_format) do
    {:ok, {Static.Font, fm}} = Static.meta(@summary_style.font)

    events
    |> Enum.reduce(graph, fn event, graph ->
      v_offset = get_bottom_bound(graph)

      formatted_time = format_event_time(event, time_format)

      summary =
        FontMetrics.wrap(event.summary, @summary_width, @summary_style.font_size, fm)

      graph
      |> text(formatted_time,
        font_size: @summary_style.font_size - 4,
        t: {0, v_offset + @summary_style.font_size}
      )
      |> text(summary,
        font: @summary_style.font,
        font_size: @summary_style.font_size,
        t: {@time_width, v_offset + @summary_style.font_size},
        id: :event
      )
    end)
  end

  defp get_bottom_bound(graph) do
    case Graph.bounds(graph) do
      nil -> 0
      bounds -> elem(bounds, 3)
    end
  end

  defp format_day_of_week(%Date{} = date, timezone) do
    today =
      DateTime.now!(timezone)
      |> DateTime.to_date()

    cond do
      date == today -> "Today"
      date == Date.add(today, 1) -> "Tomorrow"
      true -> Calendar.strftime(date, "%A")
    end
  end

  defp format_event_time(%Event{dtstart: start_time} = event, time_format) do
    cond do
      Service.all_day_event?(event) ->
        "Allday"

      true ->
        Calendar.strftime(start_time, time_format)
    end
  end
end
