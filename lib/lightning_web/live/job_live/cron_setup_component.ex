defmodule LightningWeb.JobLive.CronSetupComponent do
  @moduledoc """
  CronSetupComponent
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

  @impl true
  def update(%{form: form, parent: parent}, socket) do
    cron_expression =
      Phoenix.HTML.Form.input_value(form, :trigger_cron_expression)

    parsed_cron_expression =
      parse_cron_expression(cron_expression)
      |> IO.inspect(label: "parsed_cron_expression")
      |> Map.merge(
        %{
          frequency: :daily,
          hour: "00",
          minute: "00",
          weekday: "01",
          monthday: "01"
        },
        fn _k, v1, _v2 -> v1 end
      )
      |> IO.inspect(label: "parsed_cron_expression")

    {:ok,
     socket
     |> assign(:parent, parent)
     |> assign(:form, form)
     |> assign(:cron_expression, cron_expression)
     |> assign(:cron_data, parsed_cron_expression)
     |> assign(:initial_values, %{
       :frequencies => [
         "Every hour": :hourly,
         "Every day": :daily,
         "Every week": :weekly,
         "Every month": :monthly,
         Custom: :custom
       ],
       :minutes =>
         0..59
         |> Enum.map(fn x ->
           String.pad_leading(Integer.to_string(x), 2, "0")
         end),
       :hours =>
         0..23
         |> Enum.map(fn x ->
           String.pad_leading(Integer.to_string(x), 2, "0")
         end),
       :weekdays => [
         Monday: "01",
         Tuesday: "02",
         Wednesday: "03",
         Thursday: "04",
         Friday: "05",
         Saturday: "06",
         Sunday: "07"
       ],
       :monthdays =>
         1..31
         |> Enum.map(fn x ->
           String.pad_leading(Integer.to_string(x), 2, "0")
         end)
     })}
  end

  def parse_cron_expression(nil), do: %{}

  def parse_cron_expression(cron_expression) do
    rules = %{
      :hourly => ~r/^(?<minute>[\d]{1,2}) \* \* \* \*$/,
      :daily => ~r/^(?<minute>[\d]{1,2}) (?<hour>[\d]{1,2}) \* \* \*$/,
      :weekly =>
        ~r/^(?<minute>[\d]{1,2}) (?<hour>[\d]{1,2}) \* \* (?<weekday>[\d]{1,2})$/,
      :monthly =>
        ~r/^(?<minute>[\d]{1,2}) (?<hour>[\d]{1,2}) (?<monthday>[\d]{1,2}) \* \*$/
    }

    cond do
      String.match?(cron_expression, rules[:hourly]) ->
        process_regex(cron_expression, rules[:hourly], :hourly)

      String.match?(cron_expression, rules[:daily]) ->
        process_regex(cron_expression, rules[:daily], :daily)

      String.match?(cron_expression, rules[:weekly]) ->
        process_regex(cron_expression, rules[:weekly], :weekly)

      String.match?(cron_expression, rules[:monthly]) ->
        process_regex(cron_expression, rules[:monthly], :monthly)

      true ->
        Map.merge(%{}, %{:frequency => :custom})
    end
  end

  defp pad_value(value, pad \\ 2),
    do:
      if(is_binary(value), do: String.pad_leading(value, pad, "0"), else: value)

  defp process_regex(cron_expression, rule, key),
    do:
      Regex.named_captures(rule, cron_expression)
      |> Map.new(fn {k, v} ->
        {String.to_atom(k), String.pad_leading(v, 2, "0")}
      end)
      |> Map.merge(%{:frequency => key})

  defp update_cron(cron, new_value, index) do
    Enum.reduce(
      [index],
      String.split(cron),
      &List.replace_at(&2, &1, String.to_integer(new_value))
    )
    |> Enum.join(" ")
  end

  @impl true
  def handle_event(
        "cron_expression_change",
        %{"cron_component" => params},
        socket
      ) do
    current_cron_expression =
      socket.assigns.form
      |> Map.get(:data)
      |> Map.get(:trigger_cron_expression)

    cron_data =
      Map.merge(
        socket.assigns.cron_data,
        params
        |> Map.new(fn {k, v} -> {String.to_atom(k), String.to_atom(v)} end)
      )
      |> IO.inspect(label: "cron_data")

    next_cron_expression =
      case cron_data do
        %{
          frequency: :hourly,
          hour: _hour,
          minute: minute,
          monthday: _monthday,
          weekday: _weekday
        } ->
          "#{minute} * * * *"

        %{
          frequency: :daily,
          hour: hour,
          minute: minute,
          monthday: _monthday,
          weekday: _weekday
        } ->
          "#{minute} #{hour} * * *"

        %{
          frequency: :weekly,
          hour: hour,
          minute: minute,
          monthday: _monthday,
          weekday: weekday
        } ->
          "#{minute} #{hour} * * #{weekday}"

        %{
          frequency: :monthly,
          hour: hour,
          minute: minute,
          monthday: monthday,
          weekday: _weekday
        } ->
          "#{minute} #{hour} #{monthday} * *"

        _ ->
          current_cron_expression |> IO.inspect(label: "custom")
      end

    # IO.inspect(params, label: "params")

    # current_cron_expression =
    #   socket.assigns.form
    #   |> Map.get(:data)
    #   |> Map.get(:trigger_cron_expression)
    #   |> IO.inspect(label: "current_cron_expression")

    # next_cron_expression =
    #   case params do
    #     %{"minute" => minute} ->
    #       update_cron(current_cron_expression, minute, 0)

    #     %{"hour" => hour} ->
    #       update_cron(current_cron_expression, hour, 1)

    #     %{"weekday" => weekday} ->
    #       update_cron(current_cron_expression, weekday, 4)

    #     %{"monthday" => monthday} ->
    #       update_cron(current_cron_expression, monthday, 2)

    #     _ ->
    #       current_cron_expression
    #   end
    #   |> IO.inspect(label: "next_cron_expression")

    # next_cron_expression =
    #   to_cron_string(
    #     cron_data,
    #     current_cron_expression
    #   )
    #   |> IO.inspect(label: "next_cron_expression")

    if Map.get(cron_data, :frequency) != :custom do
      IO.inspect(next_cron_expression, label: "sending next_cron_expression")
      {mod, id} = socket.assigns.parent
      send_update(mod, id: id, cron_expression: next_cron_expression)
    end

    {:noreply, socket |> assign(:cron_data, cron_data)}
  end

  defp to_cron_string(cron_changeset, curr_cron_expression) do
    IO.inspect(cron_changeset, label: "cron_changeset")

    case cron_changeset.changes |> IO.inspect(label: "cron changes") do
      %{frequency: :hourly, minute: minute} ->
        "#{minute} * * * *"

      %{frequency: :daily, hour: hour, minute: minute} ->
        "#{minute} #{hour} * * *"

      %{frequency: :weekly, weekday: weekday, hour: hour, minute: minute} ->
        "#{minute} #{hour} * * #{weekday}"

      %{frequency: :monthly, monthday: monthday, hour: hour, minute: minute} ->
        "#{minute} #{hour} #{monthday} * *"

      _ ->
        curr_cron_expression
    end
  end

  def frequency_field(assigns) do
    ~H"""
    <Form.label_field
      form={:cron_component}
      id={:frequency}
      title="Frequency"
      for="frequency"
    />
    <Form.select_field
      form={:cron_component}
      name={:frequency}
      selected={@selected}
      prompt=""
      id="frequency"
      phx-change="cron_expression_change"
      phx-target={@target}
      values={@values}
    />
    """
  end

  def minute_field(assigns) do
    ~H"""
    <Form.label_field
      form={:cron_component}
      id={:minute}
      title="Minute"
      for="minute"
    />
    <Form.select_field
      form={:cron_component}
      name={:minute}
      selected={@selected}
      prompt=""
      id="minute"
      phx-change="cron_expression_change"
      phx-target={@target}
      values={@values}
    />
    """
  end

  def hour_field(assigns) do
    ~H"""
    <Form.label_field form={:cron_component} id={:hour} title="Hour" for="hour" />
    <Form.select_field
      form={:cron_component}
      name={:hour}
      selected={@selected}
      prompt=""
      id="hour"
      phx-change="cron_expression_change"
      phx-target={@target}
      values={@values}
    />
    """
  end

  def weekday_field(assigns) do
    ~H"""
    <Form.label_field
      form={:cron_component}
      id={:weekday}
      title="Weekday"
      for="weekday"
    />
    <Form.select_field
      form={:cron_component}
      name={:weekday}
      selected={@selected}
      prompt=""
      id="weekday"
      phx-change="cron_expression_change"
      phx-target={@target}
      values={@values}
    />
    """
  end

  def monthday_field(assigns) do
    ~H"""
    <Form.label_field
      form={:cron_component}
      id={:monthday}
      title="Monthday"
      for="monthday"
    />
    <Form.select_field
      form={:cron_component}
      name={:monthday}
      selected={@selected}
      prompt=""
      id="monthday"
      phx-change="cron_expression_change"
      phx-target={@target}
      values={@values}
    />
    """
  end

  def time_field(assigns) do
    ~H"""
    <.hour_field target={@target} values={@hour_values} selected={@selected_hour} />
    <.minute_field
      target={@target}
      values={@minute_values}
      selected={@selected_minute}
    />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-flow-col auto-cols-max gap-1">
      <.frequency_field
        target={@myself}
        values={@initial_values[:frequencies]}
        selected={Map.get(@cron_data, :frequency, :hourly)}
      />
      <br />
      <%= if Map.get(@cron_data, :frequency) == :hourly do %>
        <div class="grid grid-flow-col auto-cols-max ggap-1">
          <.minute_field
            target={@myself}
            values={@initial_values[:minutes]}
            selected={Map.get(@cron_data, :minute, "00")}
          />
        </div>
      <% end %>
      <%= if Map.get(@cron_data, :frequency) == :daily do %>
        <div class="grid grid-flow-col auto-cols-max gap-1">
          <.time_field
            target={@myself}
            minute_values={@initial_values[:minutes]}
            hour_values={@initial_values[:hours]}
            selected_minute={Map.get(@cron_data, :minute, "00")}
            selected_hour={Map.get(@cron_data, :hour, "00")}
          />
        </div>
      <% end %>
      <%= if Map.get(@cron_data, :frequency) == :weekly do %>
        <div class="grid grid-flow-col auto-cols-max gap-1">
          <.weekday_field
            target={@myself}
            values={@initial_values[:weekdays]}
            selected={Map.get(@cron_data, :weekday, 1)}
          />
          <.time_field
            target={@myself}
            minute_values={@initial_values[:minutes]}
            hour_values={@initial_values[:hours]}
            selected_minute={Map.get(@cron_data, :minute, "00")}
            selected_hour={Map.get(@cron_data, :hour, "00")}
          />
        </div>
      <% end %>
      <%= if Map.get(@cron_data, :frequency) == :monthly do %>
        <div class="grid grid-flow-col auto-cols-max gap-1">
          <.monthday_field
            target={@myself}
            values={@initial_values[:minutes]}
            selected={Map.get(@cron_data, :monthday, "01")}
          />
          <.time_field
            target={@myself}
            minute_values={@initial_values[:minutes]}
            hour_values={@initial_values[:hours]}
            selected_minute={Map.get(@cron_data, :minute, "00")}
            selected_hour={Map.get(@cron_data, :hour, "00")}
          />
        </div>
      <% end %>
      <%= if Map.get(@cron_data, :frequency) == :custom do %>
        <%= text_input(:cron_component, :cron_expression,
          phx_change: "cron_expression_change",
          phx_target: @myself,
          value: @cron_expression,
          class:
            "mt-1 focus:ring-primary-500 focus:border-primary-500 block w-full shadow-sm sm:text-sm border-secondary-300 rounded-md"
        ) %>
      <% end %>
    </div>
    """
  end
end
