defmodule ReflectOS.Core.Sections.Weather.Providers.NOAA do
  require Logger

  @behaviour ReflectOS.Core.Sections.Weather.Provider
  alias ReflectOS.Core.Sections.Weather.Provider

  defstruct current_weather_url: nil,
            hourly_forecast_url: nil,
            daily_forecast_url: nil,
            coordinates: nil,
            timezone: nil

  @default_url "https://api.weather.gov"

  @impl Provider
  def new(%{latitude: latitude, longitude: longitude})
      when is_number(latitude) and is_number(longitude) do
    points_endpoint = "/points/#{latitude},#{longitude}"

    with {:ok, points_response} <- api_get(points_endpoint),
         {:ok, stations_response} <-
           api_get(points_response.body["properties"]["observationStations"]) do
      feature =
        get_in(stations_response.body, ["features"])
        |> Enum.at(0)

      {:ok,
       %__MODULE__{
         coordinates: {latitude, longitude},
         timezone: get_in(feature, ["properties", "timeZone"]),
         current_weather_url: feature["id"] <> "/observations/latest",
         hourly_forecast_url: points_response.body["properties"]["forecastHourly"] <> "?units=si",
         daily_forecast_url: points_response.body["properties"]["forecast"] <> "?units=si"
       }}
    else
      {:error, error} ->
        {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
        Logger.error(Exception.format(:error, error, stacktrace))
        {:error, error}
    end
  end

  @impl Provider
  def fetch_weather(
        %__MODULE__{
          current_weather_url: current_weather_url,
          hourly_forecast_url: hourly_forecast_url,
          daily_forecast_url: daily_forecast_url
        } = provider
      ) do
    [current, hourly, daily] =
      [
        Task.async(fn ->
          Logger.info(current_weather_url)
          api_get_weather(provider, current_weather_url, &format_current_response/2)
        end),
        Task.async(fn ->
          api_get_weather(provider, hourly_forecast_url, &format_hourly_response/2)
        end),
        Task.async(fn ->
          api_get_weather(provider, daily_forecast_url, &format_daily_response/2)
        end)
      ]
      |> Task.await_many()

    %{
      current: current,
      hourly: hourly,
      daily: daily
    }
  end

  #####
  # Fetch Weather
  #####

  defp api_get_weather(provider, url, formatter) do
    case api_get(url) do
      {:ok, %{body: body}} ->
        formatter.(body, provider)

      error ->
        {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
        Logger.error(Exception.format(:error, error, stacktrace))
        error
    end
  end

  ##########
  # CURRENT
  ##########

  defp format_current_response(
         %{"properties" => properties, "geometry" => %{"coordinates" => [long, lat]}},
         %{timezone: timezone}
       ) do
    now = DateTime.now!(timezone)

    case(Provider.get_sunrise_sunset({lat, long}, DateTime.to_date(now))) do
      {:ok, sunrise, sunset} ->
        sunrise = DateTime.shift_zone!(sunrise, now.time_zone)
        sunset = DateTime.shift_zone!(sunset, now.time_zone)

        temperature = get_in(properties, ["temperature", "value"])

        wind_chill = get_in(properties, ["windChill", "value"])
        heat_index = get_in(properties, ["heatIndex", "value"])

        apparent_temperature =
          cond do
            wind_chill != nil -> wind_chill
            heat_index != nil -> heat_index
            true -> temperature
          end

        {:ok,
         %{
           icon:
             get_icon(
               properties["textDescription"],
               Provider.daytime?({:ok, sunrise, sunset}, now)
             ),
           sunrise: sunrise,
           sunset: sunset,
           temperature: temperature,
           apparent_temperature: apparent_temperature
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp format_current_response(body, _config) do
    Logger.error("[Weather - NOAA] Invalid response for current weather, got: #{inspect(body)}")
    {:error, "Invalid response from NOAA for current weather"}
  end

  ##########
  # HOURLY
  ##########

  defp format_hourly_response(%{"properties" => %{"periods" => periods}}, %{
         timezone: timezone,
         coordinates: coordinates
       }) do
    today =
      DateTime.now!(timezone)
      |> DateTime.to_date()

    sunrise_sunset = Provider.get_sunrise_sunset(coordinates, today)

    hours =
      periods
      |> Enum.map(fn period ->
        {:ok, timestamp, _offset} = DateTime.from_iso8601(period["startTime"])

        %{
          timestamp: DateTime.shift_zone!(timestamp, timezone),
          icon: get_icon(period["shortForecast"], Provider.daytime?(sunrise_sunset, timestamp)),
          temperature: period["temperature"]
        }
      end)

    {:ok, hours}
  end

  ##########
  # DAILY
  ##########

  defp format_daily_response(%{"properties" => %{"periods" => periods}}, %{
         timezone: timezone
       }) do
    days =
      periods
      |> Enum.chunk_by(fn period ->
        # Chunk by start date so we can group min/max temperatures
        DateTime.from_iso8601(period["startTime"])
        |> elem(1)
        |> DateTime.shift_zone!(timezone)
        |> DateTime.to_date()
      end)
      |> Enum.map(fn chunk ->
        case chunk do
          [night_period] ->
            # If there's only one, it means we're already in the evening time
            %{
              date:
                night_period["startTime"]
                |> DateTime.from_iso8601()
                |> elem(1)
                |> DateTime.shift_zone!(timezone)
                |> DateTime.to_date(),
              timezone: timezone,
              icon: get_icon(night_period["shortForecast"], false),
              temperature_max: night_period["temperature"]
            }

          [day_period, night_period] ->
            %{
              date:
                day_period["startTime"]
                |> DateTime.from_iso8601()
                |> elem(1)
                |> DateTime.shift_zone!(timezone)
                |> DateTime.to_date(),
              timezone: timezone,
              icon: get_icon(day_period["shortForecast"], true),
              temperature_min: min(day_period["temperature"], night_period["temperature"]),
              temperature_max: max(day_period["temperature"], night_period["temperature"])
            }

          [_morning_period, day_period, night_period] ->
            %{
              date:
                day_period["startTime"]
                |> DateTime.from_iso8601()
                |> elem(1)
                |> DateTime.shift_zone!(timezone)
                |> DateTime.to_date(),
              timezone: timezone,
              icon: get_icon(day_period["shortForecast"], true),
              temperature_min: min(day_period["temperature"], night_period["temperature"]),
              temperature_max: max(day_period["temperature"], night_period["temperature"])
            }
        end
      end)

    {:ok, days}
  end

  ##########
  # HELPERS
  ##########

  defp get_icon(summary, daytime?) do
    cond do
      String.contains?(summary, ["Cloudy", "Partly"]) ->
        if daytime?, do: :fontawesome_cloud_sun, else: :fontawesome_cloud_moon

      String.contains?(summary, ["Overcast"]) ->
        if daytime?, do: :fontawesome_cloud, else: :fontawesome_cloud_moon

      String.contains?(summary, ["Freezing", "Ice", "Showers"]) and
          !String.contains?(summary, ["Slight"]) ->
        if daytime?, do: :fontawesome_cloud_showers_heavy, else: :fontawesome_cloud_moon_rain

      String.contains?(summary, "Snow") and !String.contains?(summary, ["Slight"]) ->
        :fontawesome_snowflake

      String.contains?(summary, "Thunderstorm") and !String.contains?(summary, ["Slight"]) ->
        :fontawesome_cloud_bolt

      String.contains?(summary, ["Rain", "Drizzle"]) and !String.contains?(summary, ["Slight"]) ->
        if daytime?, do: :fontawesome_cloud_rain, else: :fontawesome_cloud_moon_rain

      String.contains?(summary, ["Breezy", "Windy"]) ->
        :fontawesome_wind

      String.contains?(summary, ["Dust", "Sand", "Fog", "Smoke", "Haze"]) ->
        :fontawesome_smog

      # Default to sun/moon
      true ->
        if daytime?, do: :fontawesome_sun, else: :fontawesome_moon
    end
  end

  ####
  # Api Helpers
  ####
  defp api_get("/" <> _ = path) do
    base_url =
      Application.get_env(:reflect_os_Core, :weather, [])
      |> Keyword.get(:base_url, @default_url)

    [
      base_url: base_url
    ]
    |> Keyword.put(:url, path)
    |> api_get()
  end

  defp api_get(uri) when is_binary(uri), do: api_get(url: uri)

  defp api_get(opts) when is_list(opts) do
    config_opts =
      Application.get_env(:reflect_os_Core, :noaa, [])
      |> Keyword.drop([:base_url])

    {:ok, hostname} = :inet.gethostname()

    opts
    |> Keyword.merge(config_opts)
    |> Keyword.put(:headers, %{"user-agent": hostname})
    |> Req.request()
  end
end
