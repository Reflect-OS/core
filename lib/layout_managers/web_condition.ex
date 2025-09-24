defmodule ReflectOS.Core.LayoutManagers.WebCondition do
  use ReflectOS.Kernel.LayoutManager

  import Phoenix.Component, only: [sigil_H: 2]

  require Logger
  alias ReflectOS.Kernel.{OptionGroup, Option}
  alias ReflectOS.Kernel.LayoutManager
  alias ReflectOS.Kernel.LayoutManager.Definition
  alias ReflectOS.Kernel.LayoutManager.State
  alias ReflectOS.Kernel.Settings.LayoutStore

  @impl true
  def layout_manager_definition() do
    %Definition{
      name: "Web Condition",
      description: fn assigns ->
        ~H"""
        The Web Condition layout manager allows your system to change the active layout based
        on any publicly available web page.  For example, you could use a weather page to change
        the layout based on whether the page contains the word "rain".  Additionally, you could use
        a service like
        <a
          class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
          href="https://ifttt.com/explore"
          target="_blank"
        >
          IFTTT
        </a>
        (If This Then That)
        to update web content (such as a Google Sheet) based on a trigger.
        """
      end,
      icon: """
        <svg class="text-gray-800 dark:text-white" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24">
          <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12V7.914a1 1 0 0 1 .293-.707l3.914-3.914A1 1 0 0 1 9.914 3H18a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-4m5-13v4a1 1 0 0 1-1 1H5m0 6h9m0 0-2-2m2 2-2 2"/>
        </svg>
      """
    }
  end

  embedded_schema do
    field(:url, :string)
    field(:interval_minutes, :integer, default: 15)

    field(:condition_1, :string)
    field(:layout_1, :string)

    field(:condition_2, :string)
    field(:layout_2, :string)

    field(:condition_3, :string)
    field(:layout_3, :string)

    field(:condition_4, :string)
    field(:layout_4, :string)

    field(:condition_5, :string)
    field(:layout_5, :string)

    field(:default_layout, :string)
  end

  @impl true
  def changeset(%__MODULE__{} = layout_manager, params \\ %{}) do
    layout_manager
    |> cast(params, [
      :url,
      :interval_minutes,
      :condition_1,
      :layout_1,
      :condition_2,
      :layout_2,
      :condition_3,
      :layout_3,
      :condition_4,
      :layout_4,
      :condition_5,
      :layout_5,
      :default_layout
    ])
    |> validate_required([:url, :condition_1, :layout_1, :default_layout])

    # TODO - validate url is valid and accessible
  end

  @impl true
  def layout_manager_options() do
    layout_options =
      LayoutStore.list()
      |> Enum.map(fn %{name: name, id: id} ->
        {name, id}
      end)

    [
      %OptionGroup{
        label: "Web Page",
        description: fn assigns ->
          ~H"""
          The system will check to see the webpage below contains any of the "condition"
          text you specify below.  Conditions will be evaluated in order, and the first
          one to find a match will activate the associated layout.
          """
        end,
        options: [
          %Option{
            key: :url,
            label: "Webpage Url"
          },
          %Option{
            key: :interval_minutes,
            label: "Refresh Interval (minutes)",
            config: %{
              type: "number",
              help_text: fn assigns ->
                ~H"""
                How frequently the system will check the webpage in minutes.
                """
              end
            }
          }
        ]
      },
      # Condition 1
      %OptionGroup{
        label: "Condition 1",
        options: [
          %Option{
            key: :condition_1,
            label: "Condition"
          },
          %Option{
            key: :layout_1,
            label: "Layout",
            config: %{
              type: "select",
              prompt: "--Select Layout--",
              options: layout_options
            }
          }
        ]
      },
      # Condition 2
      %OptionGroup{
        label: "Condition 2",
        options: [
          %Option{
            key: :condition_2,
            label: "Condition"
          },
          %Option{
            key: :layout_2,
            label: "Layout",
            config: %{
              type: "select",
              prompt: "--Select Layout--",
              options: layout_options
            }
          }
        ]
      },
      # Condition 3
      %OptionGroup{
        label: "Condition 3",
        options: [
          %Option{
            key: :condition_3,
            label: "Condition"
          },
          %Option{
            key: :layout_3,
            label: "Layout",
            config: %{
              type: "select",
              prompt: "--Select Layout--",
              options: layout_options
            }
          }
        ]
      },
      # Condition 4
      %OptionGroup{
        label: "Condition 4",
        options: [
          %Option{
            key: :condition_4,
            label: "Condition"
          },
          %Option{
            key: :layout_4,
            label: "Layout",
            config: %{
              type: "select",
              prompt: "--Select Layout--",
              options: layout_options
            }
          }
        ]
      },
      # Condition 5
      %OptionGroup{
        label: "Condition 5",
        options: [
          %Option{
            key: :condition_5,
            label: "Condition"
          },
          %Option{
            key: :layout_5,
            label: "Layout",
            config: %{
              type: "select",
              prompt: "--Select Layout--",
              options: layout_options
            }
          }
        ]
      },
      # Default
      %OptionGroup{
        label: "Default",
        description: fn assigns ->
          ~H"""
          The default layout is the one which will be displayed when
          none of the above conditions match.
          """
        end,
        options: [
          %Option{
            key: :default_layout,
            label: "Layout",
            config: %{
              type: "select",
              prompt: "--Select Layout--",
              options: layout_options
            }
          }
        ]
      }
    ]
  end

  @impl LayoutManager
  def init_layout_manager(%State{} = state, config) do
    polling_interval = config.interval_minutes * 60 * 1000

    state =
      state
      |> assign(:url, config.url)
      |> assign(:polling_interval, polling_interval)
      |> assign(:default_layout, config.default_layout)
      |> assign(:conditions, list_conditions(config))

    layout = evaluate_conditions(state.assigns)

    schedule_poll(polling_interval)

    {:ok, push_layout(state, layout)}
  end

  @impl true
  def handle_info(:evaluate_conditions, %{assigns: assigns} = state) do
    layout = evaluate_conditions(assigns)

    schedule_poll(assigns[:polling_interval])

    {:noreply, push_layout(state, layout)}
  end

  defp schedule_poll(polling_interval) do
    Process.send_after(self(), :evaluate_conditions, polling_interval)
  end

  defp evaluate_conditions(%{
         url: url,
         default_layout: default_layout,
         conditions: conditions
       }) do
    case Req.request(url: url, decode_body: false) do
      {:ok, response} ->
        cleaned_content =
          response.body

        %{layout: layout} =
          conditions
          |> Enum.filter(fn %{condition: condition} ->
            condition != nil and String.trim(condition) != ""
          end)
          |> Enum.find(%{layout: default_layout}, fn %{condition: condition} ->
            case Regex.compile(condition, "i") do
              {:ok, exp} ->
                Regex.match?(exp, cleaned_content)

              _ ->
                String.contains?(cleaned_content, condition)
            end
          end)

        # Return the layout
        layout

      {:error, error} ->
        Logger.error("An error occurred checking the webpage: #{inspect(error)}")
        # Since we can't evaluate whether this is true, return default layout
        default_layout
    end
  end

  defp list_conditions(config) do
    for(n <- 1..5) do
      %{
        condition:
          get_in(config, [
            "condition_#{n}"
            |> String.to_existing_atom()
            |> Access.key!()
          ]),
        layout:
          get_in(config, [
            "layout_#{n}"
            |> String.to_existing_atom()
            |> Access.key!()
          ])
      }
    end
  end
end
