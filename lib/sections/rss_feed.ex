defmodule ReflectOS.Core.Sections.RssFeed do
  use ReflectOS.Kernel.Section, has_children: false

  require Logger
  alias Scenic.Graph
  alias Scenic.Assets.Static
  import Scenic.Primitives, only: [{:text, 3}, {:line, 3}]
  import Phoenix.Component, only: [sigil_H: 2]

  import ReflectOS.Kernel.Typography
  alias ReflectOS.Kernel.Section.Definition
  alias ReflectOS.Kernel.{OptionGroup, Option}
  import ReflectOS.Kernel.Primitives, only: [render_section_label: 3]

  embedded_schema do
    field(:show_label?, :boolean, default: false)
    field(:label, :string)
    field(:rss_feed, :string)
    field(:show_description?, :boolean, default: true)
    field(:refresh_interval, :integer, default: 4 * 60)
    field(:max_items, :integer, default: 5)
    field(:cutoff_condition, :string)
  end

  @impl true
  def changeset(%__MODULE__{} = section, params \\ %{}) do
    section
    |> cast(params, [
      :show_label?,
      :label,
      :rss_feed,
      :max_items,
      :cutoff_condition,
      :refresh_interval,
      :show_description?
    ])
    |> validate_required([:rss_feed, :max_items, :refresh_interval])
  end

  @doc false
  @impl true
  def section_definition(),
    do: %Definition{
      name: "RSS Feed",
      description: fn assigns ->
        ~H"""
        RSS (Really Simple Syndication) Feeds are a very common way blogs, news sites,
        and other organizations distribute streams of information.  This section allows you
        to display the title and summary for each item in the feed.
        """
      end,
      icon: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512">
          <!--!Font Awesome Free 6.6.0 by @fontawesome - https://fontawesome.com License - https://fontawesome.com/license/free Copyright 2024 Fonticons, Inc.-->
          <path d="M0 64C0 46.3 14.3 32 32 32c229.8 0 416 186.2 416 416c0 17.7-14.3 32-32 32s-32-14.3-32-32C384 253.6 226.4 96 32 96C14.3 96 0 81.7 0 64zM0 416a64 64 0 1 1 128 0A64 64 0 1 1 0 416zM32 160c159.1 0 288 128.9 288 288c0 17.7-14.3 32-32 32s-32-14.3-32-32c0-123.7-100.3-224-224-224c-17.7 0-32-14.3-32-32s14.3-32 32-32z"/>
        </svg>
      """
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
      # RSS Feed
      %Option{
        key: :rss_feed,
        label: "RSS Feed Url"
      },
      # Show Description
      %Option{
        key: :show_description?,
        label: "Show Description",
        config: %{
          type: "checkbox"
        }
      },
      # Refresh Interval
      %Option{
        key: :refresh_interval,
        label: "Refresh Interval (minutes)",
        config: %{
          type: "tel"
        }
      },
      # Max Items
      %Option{
        key: :max_items,
        label: "Max Number of Items",
        config: %{
          type: "tel"
        }
      },
      # Cutoff Condition
      %Option{
        key: :cutoff_condition,
        label: "Cutoff Condition",
        config: %{
          help_text: fn assigns ->
            ~H"""
            Since some RSS feeds include a LOT of content and it's often just boilerplate,
            this field gives you the option of only showing text up until the "cutoff condition"
            is found. <br /><br /> For example, the
            <a target="_blank" href="https://www.merriam-webster.com/word-of-the-day">
              Merriam-Webster Word of the Day
            </a>
            feed has a lot of text after the text <code>[see the entry &gt;]</code>.  This text could be
            used in this field to hide all of the boiler plate.
            """
          end
        }
      }
    ]

  @doc false
  @impl true
  def init_section(scene, %__MODULE__{} = section_config, opts) do
    refresh_interval = section_config.refresh_interval * 60_000

    scene =
      scene
      |> assign(
        layout_align: opts[:layout_align],
        show_label?: section_config.show_label?,
        label: section_config.label,
        rss_feed: section_config.rss_feed,
        max_items: section_config.max_items,
        cutoff_condition: section_config.cutoff_condition,
        refresh_interval: refresh_interval,
        show_description?: section_config.show_description?
      )
      |> refresh()

    schedule_refresh(refresh_interval)

    {:ok, scene}
  end

  # --------------------------------------------------------
  def handle_info(:refresh, scene) do
    scene = refresh(scene)
    schedule_refresh(scene.assigns[:refresh_interval])
    {:noreply, refresh(scene)}
  end

  # --------------------------------------------------------
  defp refresh(
         %Scenic.Scene{
           assigns:
             %{
               rss_feed: rss_feed,
               max_items: max_items
             } = assigns
         } = scene
       ) do
    case retrieve_feed(rss_feed) do
      {:ok, items} ->
        graph =
          items
          |> Enum.take(max_items)
          |> render_graph(assigns)

        push_section(scene, graph)

      {:error, %Req.TransportError{reason: _} = error} ->
        count = get(scene, :retry_count, 0)
        Logger.error("Error: #{inspect(error)} for url: #{rss_feed}, retries: #{count}")
        schedule_refresh(1_000)

        scene
        |> assign(:retry_count, count + 1)

      error ->
        Logger.error("Error retrieving feed: #{inspect(error)}")
        scene
    end
  end

  defp render_graph(
         items,
         %{
           layout_align: layout_align,
           show_label?: show_label?,
           label: label,
           cutoff_condition: cutoff_condition,
           show_description?: show_description?
         }
       ) do
    width = 350

    {:ok, {Static.Font, fm}} = Static.meta(:roboto)
    {:ok, {Static.Font, fm_light}} = Static.meta(:roboto_light)

    graph = Graph.build()

    items
    |> Enum.reduce(graph, fn item, graph ->
      title = item["title"]

      bottom =
        case Graph.bounds(graph) do
          {_, _, _, bottom} ->
            bottom

          _ ->
            0
        end

      title = FontMetrics.wrap(title, width, 32, fm)

      graph =
        graph
        |> text(title, [text_base: :top, t: {0, bottom}] |> h7())

      graph =
        if show_description? do
          summary = get_summary(item)
          summary = cutoff_summary(summary, cutoff_condition)
          summary = FontMetrics.wrap(summary, width, 24, fm_light)

          bottom = Graph.bounds(graph) |> elem(3)

          graph
          |> text(summary, [text_base: :top, t: {0, bottom}] |> p() |> light())
        else
          graph
        end

      bottom = Graph.bounds(graph) |> elem(3)

      graph
      |> line({{0, bottom}, {width, bottom}}, stroke: {1, :white})
      |> line({{0, bottom + 24}, {width, bottom + 24}}, stroke: {1, :black})
    end)
    |> render_section_label(%{show_label?: show_label?, label: label},
      align: layout_align
    )
  end

  defp retrieve_feed(feed_url) do
    with {:ok, resp} <- Req.get(feed_url, decode_body: false),
         # Remove newlines between XML elements, SAXMap doesn't handle them well
         cleaned <- String.replace(resp.body, ~r/>[\s\r\n]*</, "><"),
         {:ok, parsed} <- SAXMap.from_string(cleaned) do
      items = get_in(parsed, ["rss", "channel", "item"])

      # If it's a map, it means there is only one items in the feed
      # so wrap it in a list
      result =
        cond do
          is_map(items) -> [items]
          is_list(items) -> items
          true -> []
        end

      {:ok, result}
    else
      error ->
        error
    end
  end

  defp get_summary(%{"itunes:summary" => summary}), do: summary
  defp get_summary(%{"description" => summary}), do: summary
  defp get_summary(_), do: ""

  defp cutoff_summary(summary, nil), do: summary

  defp cutoff_summary(summary, condition) when is_binary(condition) do
    parts =
      case Regex.compile(condition) do
        {:ok, regex} ->
          Regex.split(regex, summary)

        _ ->
          String.split(summary, condition)
      end

    case parts do
      [first | _rest] ->
        first
        |> String.trim()

      _ ->
        summary
    end
  end

  defp schedule_refresh(interval) do
    Process.send_after(self(), :refresh, interval)
  end
end
