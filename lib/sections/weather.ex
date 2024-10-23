defmodule ReflectOS.Core.Sections.Weather do
  use ReflectOS.Kernel.Section, has_children: false

  require Logger

  alias ReflectOS.Kernel.OptionGroup
  alias Scenic.Graph
  alias Scenic.Scene
  import Scenic.Primitives

  import Phoenix.Component, only: [sigil_H: 2]

  alias ReflectOS.Kernel.Ecto

  alias ReflectOS.Kernel.GraphHelpers
  import ReflectOS.Kernel.Typography
  import ReflectOS.Kernel.Primitives, only: [render_section_label: 3]
  alias ReflectOS.Kernel.Section.Definition
  alias ReflectOS.Kernel.Option
  alias ReflectOS.Kernel.Settings.System

  embedded_schema do
    field(:show_label?, :boolean, default: false)
    field(:label, :string, default: "Weather")
    field(:show_current?, :boolean, default: true)
    field(:show_hourly?, :boolean, default: true)
    field(:forecast_hours, :integer, default: 12)
    field(:show_daily?, :boolean, default: true)
    field(:forecast_days, :integer, default: 5)
    field(:temperature_unit, :string, default: "f")
    field(:use_zipcode?, :boolean, default: true)
    field(:zipcode, :string)
    field(:latitude, :float)
    field(:longitude, :float)
    field(:time_format, :string, default: "system")
    field(:provider, Ecto.Module, default: ReflectOS.Core.Sections.Weather.Providers.NOAA)
    field(:api_key, :string)
  end

  @impl true
  def changeset(%__MODULE__{} = section, params \\ %{}) do
    section
    |> cast(params, [
      :show_label?,
      :label,
      :show_current?,
      :show_hourly?,
      :forecast_hours,
      :show_daily?,
      :forecast_days,
      :temperature_unit,
      :use_zipcode?,
      :zipcode,
      :latitude,
      :longitude,
      :time_format,
      :provider,
      :api_key
    ])
    |> lookup_zipcode()
    |> validate_required([
      :latitude,
      :longitude,
      :provider,
      :temperature_unit,
      :time_format
    ])
    |> validate_number(:forecast_hours, less_than: 24)
    |> validate_number(:forecast_days, less_than: 7)
    |> validate_api_key()
  end

  defp validate_api_key(changeset) do
    case get_field(changeset, :provider) do
      ReflectOS.Core.Sections.Weather.Providers.NOAA ->
        changeset

      _ ->
        changeset
        |> validate_required([:api_key],
          message: "The provider you selected requires an API Key."
        )
    end
  end

  defp lookup_zipcode(%{changes: %{zipcode: zipcode}} = changeset) do
    if get_field(changeset, :use_zipcode?) do
      case ZIPCodes.lat_long(zipcode) do
        {lat, long} ->
          changeset
          |> put_change(:latitude, lat)
          |> put_change(:longitude, long)

        _ ->
          changeset
          |> add_error(
            :zipcode,
            "Unable to lookup zipcode location.  If the zipcode is correct, you can uncheck Use Zipcode and provide Lat/Long directly"
          )
      end
    else
      changeset
    end
  end

  defp lookup_zipcode(changeset), do: changeset

  @impl true
  def section_definition(),
    do: %Definition{
      name: "Weather",
      icon: """
        <svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24">
          <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5V3m0 18v-2M7.05 7.05 5.636 5.636m12.728 12.728L16.95 16.95M5 12H3m18 0h-2M7.05 16.95l-1.414 1.414M18.364 5.636 16.95 7.05M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z"/>
        </svg>
      """
    }

  @impl true
  def section_options(),
    do: [
      %OptionGroup{
        label: "Forecast Location",
        description: fn assigns ->
          ~H"""
          There are many tools online which can be used for determining this.
          Note that all dates/times displayed represent local time in the location provided.
          """
        end,
        options: [
          %Option{
            key: :use_zipcode?,
            label: "Use Zipcode",
            config: %{
              type: "checkbox"
            }
          },
          %Option{
            key: :zipcode,
            label: "Zipcode",
            hidden: fn %{use_zipcode?: use_zipcode?} ->
              !use_zipcode?
            end,
            config: %{
              "phx-debounce" => "blur"
            }
          },
          # Latitude
          %Option{
            key: :latitude,
            label: "Latitude",
            hidden: fn %{use_zipcode?: use_zipcode?} ->
              use_zipcode?
            end,
            config: %{
              type: "number"
            }
          },
          # Longitude
          %Option{
            key: :longitude,
            label: "Longitude",
            hidden: fn %{use_zipcode?: use_zipcode?} ->
              use_zipcode?
            end,
            config: %{
              type: "number"
            }
          }
        ]
      },
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
        label: "Current Weather",
        options: [
          %Option{
            key: :show_current?,
            label: "Show Current Weather",
            config: %{
              type: "checkbox"
            }
          }
        ]
      },
      %OptionGroup{
        label: "Hourly Forecast",
        options: [
          %Option{
            key: :show_hourly?,
            label: "Show Hourly Weather for Today",
            config: %{
              type: "checkbox"
            }
          },
          %Option{
            key: :forecast_hours,
            label: "Max Number of Forecast Hours to Show",
            hidden: fn %{show_hourly?: show_hourly?} ->
              !show_hourly?
            end,
            config: %{
              type: "number",
              help_text: fn assigns ->
                ~H"""
                Hourly forecast is shown for the number of hours selected above or until midnight, whichever comes first.
                """
              end
            }
          }
        ]
      },
      %OptionGroup{
        label: "Daily Forecast",
        options: [
          %Option{
            key: :show_daily?,
            label: "Show Daily Weather Forecast",
            config: %{
              type: "checkbox"
            }
          },
          %Option{
            key: :forecast_days,
            label: "Number of Forecast Days to Show",
            hidden: fn %{show_daily?: show_daily?} ->
              !show_daily?
            end,
            config: %{
              type: "number"
            }
          }
        ]
      },
      %OptionGroup{
        label: "Formatting / Units",
        options: [
          %Option{
            key: :temperature_unit,
            label: "Temperature Unit",
            config: %{
              type: "select",
              options: [
                {"Farenheit", "f"},
                {"Celcius", "c"}
              ]
            }
          },

          # Time Format
          %Option{
            key: :time_format,
            label: "Time Format",
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
          }
        ]
      },
      %OptionGroup{
        label: "Weather Data Provider",
        options: [
          # Provider
          %Option{
            key: :provider,
            label: "Weather Forecast Provider",
            config: %{
              type: "select",
              help_text: fn assigns ->
                ~H"""
                Source of the weather data.  Pirate Weather requires a free API Key,
                which can be obtained
                <a
                  class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
                  href="https://pirate-weather.apiable.io/products/weather-data/Details"
                  target="_blank"
                >here</a>.
                """
              end,
              options: [
                {"NOAA", ReflectOS.Core.Sections.Weather.Providers.NOAA},
                {"Pirate Weather", ReflectOS.Core.Sections.Weather.Providers.PirateWeather}
              ]
            }
          },
          # Provider
          %Option{
            key: :api_key,
            label: "Provider API Key",
            hidden: fn %{provider: provider} ->
              provider == ReflectOS.Core.Sections.Weather.Providers.NOAA
            end
          }
        ]
      }
    ]

  @poll_interval 1_000 * 60 * 15

  @width 275

  @doc false
  @impl ReflectOS.Kernel.Section
  def init_section(scene, %__MODULE__{} = section_config, opts) do
    provider = section_config.provider

    section_config =
      if section_config.time_format == "system" do
        System.subscribe("time_format")
        %{section_config | time_format: System.time_format()}
      else
        section_config
      end

    scene =
      scene
      |> assign(:config, section_config)
      |> assign(:label_align, get_in(opts, [:layout_align]))

    scene =
      with {:ok, service} <- provider.new(section_config),
           %{
             current: {:ok, current},
             hourly: {:ok, hourly},
             daily: {:ok, daily}
           } <- provider.fetch_weather(service) do
        # We pattern match on a successful result because
        # we want to be sure that everything loads Ok
        # before we start polling
        schedule_poll()

        scene
        |> Scene.assign(service: service)
        |> Scene.assign(current: {:ok, current})
        |> Scene.assign(hourly: {:ok, hourly})
        |> Scene.assign(daily: {:ok, daily})
        |> render_weather()
      else
        {:error, %Req.TransportError{reason: :nxdomain}} ->
          Logger.error("Could not resolve weather url domain, starting to poll")
          schedule_poll(1_000)

          scene
          |> assign(:retry_count, 0)

        error ->
          Logger.error("Error loading weather data: #{inspect(error)}")

          graph =
            Graph.build()
            |> text("An error occurred loading weather data: #{inspect(error)}", p())

          scene
          |> push_graph(graph)
      end

    {:ok, scene}
  end

  def handle_info(
        %PropertyTable.Event{
          property: ["system", "time_format"],
          value: time_format
        },
        %Scene{assigns: %{config: config}} = scene
      ) do
    scene =
      scene
      |> assign(config: %{config | time_format: time_format})
      |> render_weather()

    {:noreply, scene}
  end

  def handle_info(
        :fetch_weather,
        %Scene{
          assigns: %{
            service: service,
            config: %{provider: provider}
          }
        } = scene
      ) do
    last_hourly = get(scene, :hourly)
    last_daily = get(scene, :daily)

    scene =
      case provider.fetch_weather(service) do
        %{current: current, hourly: hourly, daily: daily} ->
          hourly =
            case hourly do
              {:error, _} ->
                last_hourly

              _ ->
                hourly
            end

          daily =
            case daily do
              {:error, _} -> last_daily
              _ -> daily
            end

          scene
          |> assign(:current, current)
          |> assign(:hourly, hourly)
          |> assign(:daily, daily)
          |> render_weather()

        {:error, %Req.TransportError{reason: :nxdomain}} ->
          count = get(scene, :retry_count, 0)
          Logger.error("Could not resolve weather url domain, retries: #{count}")
          schedule_poll(1_000)

          scene
          |> assign(:retry_count, count + 1)

        error ->
          Logger.error("Error fetching weather: #{inspect(error)}")
          scene
      end

    schedule_poll()

    {:noreply, scene}
  end

  ############################
  # Render Current Conditions
  ############################

  defp render_weather(
         %Scene{
           assigns: %{
             config: config,
             label_align: label_align,
             current: current,
             hourly: hourly,
             daily: daily
           }
         } = scene
       ) do
    graph =
      Graph.build()
      |> render_current(current, config)
      |> render_hourly(hourly, config)
      |> render_daily(daily, config)
      |> render_section_label(config, align: label_align)

    scene
    |> push_section(graph)
  end

  defp render_current(graph, _data, %{show_current?: false}), do: graph
  defp render_current(graph, nil, _config), do: graph

  defp render_current(graph, {:error, _error}, _config) do
    graph
    |> text("Error loading current weather conditions")
  end

  defp render_current(
         graph,
         {:ok,
          %{
            temperature: temperature,
            sunrise: sunrise,
            sunset: sunset,
            icon: icon,
            apparent_temperature: apparent_temperature
          }},
         %{
           time_format: time_format,
           temperature_unit: temperature_unit
         }
       ) do
    graph
    |> ScenicFontAwesome.Solid.fontawesome_arrow_up({11, 3}, fill: :light, height: 18)
    |> text(
      format_time(sunrise, time_format),
      [t: {35, 0}, text_base: :top] |> p() |> light()
    )
    |> ScenicFontAwesome.Solid.fontawesome_arrow_down({140, 3}, fill: :light, height: 18)
    |> text(
      format_time(sunset, time_format),
      [t: {166, 0}, text_base: :top] |> p() |> light()
    )
    |> text(
      "#{convert_temperature(temperature, temperature_unit)}°",
      [t: {144, 30}, text_base: :top, text_align: :right] |> h1() |> bold()
    )
    |> then(&apply(ScenicFontAwesome.Solid, icon, [&1, {162, 38}, [fill: :light, height: 54]]))
    |> text(
      "Feels like #{convert_temperature(apparent_temperature, temperature_unit)}°",
      [t: {@width / 2, 104}, text_base: :top, text_align: :center] |> h6() |> light()
    )
  end

  ############################
  # Render Hourly Conditions
  ############################

  defp render_hourly(graph, _data, %{show_hourly?: false}), do: graph
  defp render_hourly(graph, nil, _config), do: graph

  defp render_hourly(graph, {:error, _error}, _config) do
    graph
    |> text("Error loading current weather conditions")
  end

  defp render_hourly(graph, {:ok, hourly}, %{forecast_hours: forecast_hours} = config) do
    top = GraphHelpers.get_bottom_bound(graph)
    label_y = top + 24
    line_y = label_y + 6

    graph =
      graph
      |> text("Today", [t: {0, label_y}] |> p() |> bold())
      |> line({{0, line_y}, {@width, line_y}}, stroke: {1, :white})
      # Add some padding
      |> line({{0, line_y + 8}, {@width, line_y + 8}}, stroke: {1, :black})

    now = DateTime.now!("Etc/UTC")

    hourly
    |> Enum.drop_while(fn %{timestamp: timestamp} ->
      DateTime.compare(timestamp, now) == :lt
    end)
    |> Enum.take(forecast_hours)
    |> Enum.take_while(fn %{timestamp: timestamp} ->
      timestamp.hour != 0
    end)
    |> Enum.reduce(graph, &render_hour(&1, &2, config))
  end

  defp render_hour(%{timestamp: timestamp, icon: icon, temperature: temperature}, graph, %{
         time_format: time_format,
         temperature_unit: temperature_unit
       }) do
    top = GraphHelpers.get_bottom_bound(graph)
    top = top + 4

    graph
    |> text(
      format_hour(timestamp, time_format),
      [t: {0, top}, text_base: :top] |> p() |> light()
    )
    |> then(
      &apply(ScenicFontAwesome.Solid, icon, [&1, {128 + 25, top}, [fill: :light, height: 22]])
    )
    |> text(
      "#{convert_temperature(temperature, temperature_unit)}°",
      [t: {205 + 25, top}, text_base: :top, text_align: :right] |> p() |> light()
    )
  end

  ############################
  # Render Daily Conditions
  ############################

  defp render_daily(graph, _data, %{show_daily?: false}), do: graph
  defp render_daily(graph, nil, _config), do: graph

  defp render_daily(graph, {:error, _error}, _config) do
    graph
    |> text("Error loading daily weather conditions")
  end

  defp render_daily(
         graph,
         {:ok, daily},
         %{forecast_days: forecast_days, show_hourly?: show_hourly?} =
           config
       ) do
    top = GraphHelpers.get_bottom_bound(graph)
    line_y = top + 6

    graph =
      graph
      |> then(
        &if show_hourly? do
          line(&1, {{0, line_y}, {@width, line_y}}, stroke: {1, :white})
        else
          &1
        end
      )
      # Add some padding
      |> line({{0, line_y + 8}, {@width, line_y + 8}}, stroke: {1, :black})

    if(show_hourly?,
      do: Enum.drop(daily, 1),
      else: daily
    )
    |> Enum.take(forecast_days)
    |> Enum.reduce(graph, &render_day(&1, &2, config))
  end

  defp render_day(
         %{date: date, timezone: timezone, icon: icon, temperature_max: temperature_max} =
           forecast,
         graph,
         %{
           temperature_unit: temperature_unit
         }
       ) do
    top = GraphHelpers.get_bottom_bound(graph)
    top = top + 4

    graph
    |> text(
      format_date(date, timezone),
      [t: {0, top}, text_base: :top] |> p() |> bold()
    )
    |> then(
      &apply(ScenicFontAwesome.Solid, icon, [&1, {128 + 25, top}, [fill: :light, height: 22]])
    )
    |> text(
      "#{convert_temperature(temperature_max, temperature_unit)}°",
      [t: {205 + 25, top}, text_base: :top, text_align: :right] |> p() |> light()
    )
    |> then(fn graph ->
      case Map.fetch(forecast, :temperature_min) do
        {:ok, temperature_min} when not is_nil(temperature_min) ->
          graph
          |> text(
            "|",
            [t: {213 + 25, top}, text_base: :top, text_align: :center] |> p() |> light()
          )
          |> text(
            "#{convert_temperature(temperature_min, temperature_unit)}°",
            [t: {221 + 25, top}, text_base: :top, text_align: :left] |> p() |> light()
          )

        _ ->
          graph
      end
    end)
  end

  defp convert_temperature(nil, _), do: ""
  defp convert_temperature(temp, "f"), do: round(temp * 9 / 5 + 32)
  defp convert_temperature(temp, "c"), do: round(temp)

  defp format_time(time, format), do: Calendar.strftime(time, format)

  defp format_hour(time, "%-I:%M %p"), do: Calendar.strftime(time, "%-I%P")
  defp format_hour(time, format), do: Calendar.strftime(time, format)

  defp format_date(date, timezone) do
    today =
      DateTime.now!(timezone)
      |> DateTime.to_date()

    cond do
      date == today ->
        "Today"

      date == Date.add(today, 1) ->
        "Tomorrow"

      true ->
        Calendar.strftime(date, "%A")
    end
  end

  defp schedule_poll(interval \\ @poll_interval) do
    Process.send_after(self(), :fetch_weather, interval)
  end
end
