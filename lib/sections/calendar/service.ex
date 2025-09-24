defmodule ReflectOS.Core.Sections.Calendar.Service do
  require Logger

  require IEx
  alias ICalendar.Event

  def all_day_event?(%Event{dtstart: start_time, dtend: end_time} = event) do
    Time.compare(DateTime.to_time(start_time), ~T[00:00:00]) == :eq and
      (end_time == nil || Time.compare(DateTime.to_time(end_time), ~T[00:00:00]) == :eq)
  end

  def retrieve_calendar_events(ical_urls, timezone) do
    ical_urls
    |> Task.async_stream(
      fn url ->
        case retrieve_calendar(url) do
          {:ok, events} ->
            events
            |> process_event_timezones(timezone)
            |> expand_multiday_events()
            |> expand_recurring_events(timezone)
            |> filter_events(timezone)

          error ->
            # TODO raise alert so it gets displayed on the console
            Logger.error("Error fetching calendar url: #{inspect(error)}", ical_url: url)
            []
        end
      end,
      ordered: false,
      timeout: 20_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce([], fn result, acc ->
      case result do
        {:ok, events} ->
          acc ++ events

        error ->
          Logger.error("Error retrieving calendar events, got error: #{inspect(error)}.")
          acc
      end
    end)
    |> Enum.sort_by(& &1.dtstart, DateTime)
  end

  defp retrieve_calendar(ical_url) do
    case Req.get(ical_url, decode_body: false) do
      {:ok, %{body: body}} ->
        {:ok, ICalendar.from_ics(body)}

      error ->
        error
    end
  end

  defp filter_events(events, timezone) do
    last_midnight =
      DateTime.now!(timezone)
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00], timezone)

    events
    |> Enum.filter(fn %{dtstart: dtstart} ->
      DateTime.compare(dtstart, last_midnight) in [:gt, :eq]
    end)
  end

  defp process_event_timezones(events, timezone) do
    events
    |> Enum.map(fn event ->
      process_timezone(event, timezone)
    end)
  end

  defp process_timezone(%Event{dtstart: start_time, dtend: end_time} = event, timezone) do
    midnight = Time.new!(0, 0, 0)

    {start_time, end_time} =
      if all_day_event?(event) do
        {start_time
         |> DateTime.to_date()
         |> DateTime.new!(midnight, timezone),
         if end_time == nil do
           start_time
           |> DateTime.to_date()
           |> DateTime.new!(midnight, timezone)
         else
           end_time
           |> DateTime.to_date()
           |> DateTime.new!(midnight, timezone)
         end}
      else
        start_time = DateTime.shift_zone!(start_time, timezone)

        end_time =
          if end_time != nil do
            DateTime.shift_zone!(end_time, timezone)
          else
            nil
          end

        {start_time, end_time}
      end

    %{event | dtstart: start_time, dtend: end_time}
  end

  defp expand_recurring_events(events, timezone) do
    events
    |> Enum.flat_map(fn event -> expand_recurring_event(event, timezone) end)
  end

  defp expand_recurring_event(%Event{rrule: nil} = event, _),
    do: [event]

  defp expand_recurring_event(
         %Event{dtstart: start_time, rrule: %{until: until}} = event,
         timezone
       ) do
    midnight =
      DateTime.now!(timezone)
      |> to_previous_midnight()

    max_count = 5

    if DateTime.compare(until, midnight) == :lt do
      # If this event recurrs to a date before today, don't bother expanding it
      []
    else
      acc =
        if DateTime.compare(start_time, midnight) == :lt do
          []
        else
          [event]
        end

      ICalendar.Recurrence.get_recurrences(event)
      |> Enum.reduce_while(acc, fn %Event{dtstart: start_time} = event, acc ->
        if DateTime.compare(start_time, midnight) == :lt do
          {:cont, acc}
        else
          acc = [event | acc]

          if Enum.count(acc) > max_count do
            {:halt, acc}
          else
            {:cont, acc}
          end
        end
      end)
    end
  end

  defp expand_recurring_event(
         %Event{dtstart: start_time, rrule: rrule} = event,
         timezone
       ) do
    midnight =
      DateTime.now!(timezone)
      |> to_previous_midnight()

    fallback_until =
      midnight
      |> DateTime.add(180, :day)

    max_count =
      case rrule do
        %{count: count} -> count
        _ -> 10
      end

    acc =
      if DateTime.compare(start_time, midnight) == :lt do
        []
      else
        [event]
      end

    ICalendar.Recurrence.get_recurrences(event, fallback_until)
    |> Enum.reduce_while(acc, fn %Event{dtstart: start_time} = event, acc ->
      if DateTime.compare(start_time, midnight) == :lt do
        {:cont, acc}
      else
        acc = [event | acc]

        if Enum.count(acc) > max_count do
          {:halt, acc}
        else
          {:cont, acc}
        end
      end
    end)
  end

  defp expand_multiday_events(events) do
    events
    |> Enum.flat_map(fn event -> expand_multiday_event(event) end)
  end

  defp expand_multiday_event(%Event{dtstart: start_time, dtend: end_time} = event) do
    start_date = DateTime.to_date(start_time)

    end_date = if end_time != nil, do: DateTime.to_date(end_time), else: start_date

    diff = Date.diff(end_date, start_date)

    if diff > 1 and all_day_event?(event) do
      0..(diff - 1)
      |> Enum.map(fn days ->
        %{
          event
          | dtstart: DateTime.shift(start_time, day: days),
            dtend: DateTime.shift(end_time, day: days)
        }
      end)
    else
      [event]
    end
  end

  defp to_previous_midnight(date_time) do
    %{date_time | hour: 0, minute: 0, second: 0}
  end
end
