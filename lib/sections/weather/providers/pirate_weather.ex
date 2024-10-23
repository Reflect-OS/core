defmodule ReflectOS.Core.Sections.Weather.Providers.PirateWeather do
  @behaviour ReflectOS.Core.Sections.Weather.Provider
  require Logger
  alias ReflectOS.Core.Sections.Weather.Provider

  defstruct api_key: nil,
            latitude: nil,
            longitude: nil

  @default_url "https://api.pirateweather.net"

  @impl Provider
  def new(%{latitude: latitude, longitude: longitude, api_key: api_key}) do
    {:ok,
     %__MODULE__{
       api_key: api_key,
       latitude: latitude,
       longitude: longitude
     }}
  end

  @impl Provider
  def fetch_weather(%__MODULE__{
        api_key: api_key,
        latitude: latitude,
        longitude: longitude
      }) do
    result =
      [
        url: "/forecast/#{api_key}/#{latitude},#{longitude}",
        params: [exclude: "minutely", units: "si"]
      ]
      |> api_get()

    case result do
      {:ok, %{body: body}} ->
        format_weather(body)

      error ->
        Logger.error("Error getting Pirate Weather: #{inspect(error)}")
        error
    end
  end

  defp format_weather(%{
         "timezone" => timezone,
         "latitude" => latitude,
         "longitude" => longitude,
         "currently" => current,
         "hourly" => hourly,
         "daily" => daily
       }) do
    %{
      current: {:ok, format_current(current, {latitude, longitude}, timezone)},
      hourly: {:ok, format_hourly(hourly, {latitude, longitude}, timezone)},
      daily: {:ok, format_daily(daily, timezone)}
    }
  end

  ##########
  # CURRENT
  ##########

  defp format_current(
         %{
           "icon" => icon,
           "temperature" => temperature,
           "apparentTemperature" => apparent_temperature
         },
         coords,
         timezone
       ) do
    now = DateTime.now!(timezone)

    case Provider.get_sunrise_sunset(coords, DateTime.to_date(now)) do
      {:ok, sunrise, sunset} ->
        sunrise = DateTime.shift_zone!(sunrise, timezone)
        sunset = DateTime.shift_zone!(sunset, timezone)

        %{
          icon:
            get_icon(
              icon,
              Provider.daytime?({:ok, sunrise, sunset}, now)
            ),
          sunrise: sunrise,
          sunset: sunset,
          temperature: temperature,
          apparent_temperature: apparent_temperature
        }

      {:error, error} ->
        {:error, error}
    end
  end

  ##########
  # HOURLY
  ##########

  defp format_hourly(
         %{"data" => hours},
         coordinates,
         timezone
       ) do
    hours
    |> Enum.map(fn %{"time" => timestamp, "icon" => icon, "temperature" => temperature} ->
      timestamp =
        timestamp
        |> DateTime.from_unix!()
        |> DateTime.shift_zone!(timezone)

      daytime? =
        Provider.daytime?(
          Provider.get_sunrise_sunset(coordinates, DateTime.to_date(timestamp)),
          timestamp
        )

      %{
        timestamp: timestamp,
        icon: get_icon(icon, daytime?),
        temperature: temperature
      }
    end)
  end

  # TODO
  defp format_daily(%{"data" => days}, timezone) do
    days
    |> Enum.map(fn %{
                     "time" => timestamp,
                     "icon" => icon,
                     "temperatureHigh" => temperature_max,
                     "temperatureLow" => temperature_min
                   } ->
      %{
        date:
          timestamp
          |> DateTime.from_unix!()
          |> DateTime.shift_zone!(timezone)
          |> DateTime.to_date(),
        timezone: timezone,
        icon: get_icon(icon, true),
        temperature_min: temperature_min,
        temperature_max: temperature_max
      }
    end)
  end

  defp get_icon(icon, daytime?) do
    case icon do
      "rain" ->
        if daytime?, do: :fontawesome_cloud_rain, else: :fontawesome_cloud_moon_rain

      "snow" ->
        :fontawesome_snowflake

      "sleet" ->
        :fontawesome_cloud_showers_heavy

      "wind" ->
        :fontawesome_wind

      "fog" ->
        :fontawesome_smog

      "cloudy" ->
        if daytime?, do: :fontawesome_cloud, else: :fontawesome_cloud_moon

      "partly-cloudy-day" ->
        :fontawesome_cloud_sun

      "partly-cloudy-night" ->
        :fontawesome_cloud_moon

      _ ->
        if daytime?, do: :fontawesome_sun, else: :fontawesome_moon
    end
  end

  defp api_get(opts) when is_list(opts) do
    config_opts =
      Application.get_env(:reflect_os_Core, :pirate_weather, base_url: @default_url)

    opts
    |> dbg()
    |> Keyword.merge(config_opts)
    |> Req.request()
  end
end
