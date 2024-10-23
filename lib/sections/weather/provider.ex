defmodule ReflectOS.Core.Sections.Weather.Provider do
  @type error :: {:error, any()}

  @type current :: %{
          icon: atom(),
          sunrise: DateTime.t(),
          sunset: DateTime.t(),
          temperature: number(),
          apparent_temperature: number()
        }

  @type hourly ::
          list(%{
            timestamp: DateTime.t(),
            icon: atom(),
            temperature: number()
          })

  @type daily ::
          list(%{
            timestamp: Date.t(),
            icon: atom(),
            temperature_max: number(),
            temperature_min: number()
          })

  @type forecast :: %{
          current: {:ok, current} | error(),
          hourly: {:ok, hourly} | error(),
          daily: {:ok, daily} | error()
        }

  @callback new(%{latitude: number(), longitude: number(), api_key: String.t()}) :: any()

  @callback fetch_weather(any()) :: forecast()

  def daytime?({:ok, sunrise, sunset}, %DateTime{} = timestamp) do
    DateTime.compare(timestamp, sunrise) in [:gt, :eq] &&
      DateTime.compare(timestamp, sunset) in [:lt, :eq]
  end

  # Default to true
  def daytime?(_, _), do: true

  def get_sunrise_sunset({lat, long}, %Date{} = date) do
    with {:ok, sunrise} <- Solarex.Sun.rise(date, lat, long),
         {:ok, sunset} <- Solarex.Sun.set(date, lat, long) do
      {:ok, DateTime.from_naive!(sunrise, "Etc/UTC"), DateTime.from_naive!(sunset, "Etc/UTC")}
    else
      {:error, error} ->
        {:error, error}
    end
  end
end
