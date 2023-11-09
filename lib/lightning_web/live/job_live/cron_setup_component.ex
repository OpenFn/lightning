defmodule LightningWeb.JobLive.CronSetupComponent do
  @moduledoc """
  A live component for managing cron setup in a form.

  The `CronSetupComponent` provides an interactive form for configuring cron settings. It includes fields for specifying the frequency, minute, hour, weekday, monthday, and cron expression.

  ## Usage

  1. Include the `CronSetupComponent` in your live view or template.
  2. Pass the necessary assigns to the component, such as `form`, `on_change`, and `disabled`.
  3. Handle the `cron_expression_change` event to capture changes in the form inputs.
  4. Use the updated `cron_expression` in your application logic.
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

  attr :id, :string, required: true
  attr :form, :map, required: true
  attr :on_change, :any, required: true
  attr :disabled, :boolean, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="col-span-4 @md:col-span-2 grid grid-cols-4 gap-2">
      <div class="col-span-4">
        <.frequency_field
          target={@myself}
          values={@initial_values["frequencies"]}
          selected={Map.get(@cron_data, :frequency, "hourly")}
          disabled={@disabled}
        />
      </div>
      <div class="col-span-4">
        <%= if Map.get(@cron_data, :frequency) == "hourly" do %>
          <div class="grid grid-cols-2 gap-1">
            <.minute_field
              target={@myself}
              values={@initial_values["minutes"]}
              selected={Map.get(@cron_data, :minute, "00")}
              disabled={@disabled}
            />
          </div>
        <% end %>
        <%= if Map.get(@cron_data, :frequency) == "daily" do %>
          <div class="grid grid-cols-2 gap-1">
            <.time_field
              target={@myself}
              minute_values={@initial_values["minutes"]}
              hour_values={@initial_values["hours"]}
              selected_minute={Map.get(@cron_data, :minute, "00")}
              selected_hour={Map.get(@cron_data, :hour, "00")}
              disabled={@disabled}
            />
          </div>
        <% end %>
        <%= if Map.get(@cron_data, :frequency) == "weekly" do %>
          <div class="grid grid-cols-2 gap-1">
            <.weekday_field
              target={@myself}
              values={@initial_values["weekdays"]}
              selected={Map.get(@cron_data, :weekday, 1)}
              disabled={@disabled}
            />
            <.time_field
              target={@myself}
              minute_values={@initial_values["minutes"]}
              hour_values={@initial_values["hours"]}
              selected_minute={Map.get(@cron_data, :minute, "00")}
              selected_hour={Map.get(@cron_data, :hour, "00")}
              disabled={@disabled}
            />
          </div>
        <% end %>
        <%= if Map.get(@cron_data, :frequency) == "monthly" do %>
          <div class="grid grid-cols-3 gap-1">
            <.monthday_field
              target={@myself}
              values={@initial_values["minutes"]}
              selected={Map.get(@cron_data, :monthday, "01")}
              disabled={@disabled}
            />
            <.time_field
              target={@myself}
              minute_values={@initial_values["minutes"]}
              hour_values={@initial_values["hours"]}
              selected_minute={Map.get(@cron_data, :minute, "00")}
              selected_hour={Map.get(@cron_data, :hour, "00")}
              disabled={@disabled}
            />
          </div>
        <% end %>
      </div>
      <div class="hidden sm:block" aria-hidden="true">
        <div class="py-2"></div>
      </div>
      <div class="col-span-4 @md:col-span-4">
        <Form.text_field field={:cron_expression} form={@form} disabled={@disabled} />
      </div>
    </div>
    """
  end

  @impl true
  def update(
        %{id: id, form: form, on_change: on_change, disabled: disabled},
        socket
      ) do
    cron_data =
      Phoenix.HTML.Form.input_value(form, :cron_expression)
      |> get_cron_data()
      |> Map.merge(
        %{
          frequency: "daily",
          hour: "00",
          minute: "00",
          weekday: "01",
          monthday: "01"
        },
        fn _k, v1, _v2 -> v1 end
      )

    {:ok,
     socket
     |> assign(
       id: id,
       on_change: on_change,
       form: form,
       cron_data: cron_data,
       disabled: disabled,
       initial_values: %{
         "frequencies" => [
           "Every hour": "hourly",
           "Every day": "daily",
           "Every week": "weekly",
           "Every month": "monthly",
           Custom: "custom"
         ],
         "minutes" =>
           0..59
           |> Enum.map(fn x ->
             String.pad_leading(Integer.to_string(x), 2, "0")
           end),
         "hours" =>
           0..23
           |> Enum.map(fn x ->
             String.pad_leading(Integer.to_string(x), 2, "0")
           end),
         "weekdays" => [
           Monday: "01",
           Tuesday: "02",
           Wednesday: "03",
           Thursday: "04",
           Friday: "05",
           Saturday: "06",
           Sunday: "07"
         ],
         "monthdays" =>
           1..31
           |> Enum.map(fn x ->
             String.pad_leading(Integer.to_string(x), 2, "0")
           end)
       }
     )}
  end

  def get_cron_data(nil), do: %{}

  def get_cron_data(cron_expression) do
    rules = %{
      "hourly" => ~r/^(?<minute>[\d]{1,2}) \* \* \* \*$/,
      "daily" => ~r/^(?<minute>[\d]{1,2}) (?<hour>[\d]{1,2}) \* \* \*$/,
      "weekly" =>
        ~r/^(?<minute>[\d]{1,2}) (?<hour>[\d]{1,2}) \* \* (?<weekday>[\d]{1,2})$/,
      "monthly" =>
        ~r/^(?<minute>[\d]{1,2}) (?<hour>[\d]{1,2}) (?<monthday>[\d]{1,2}) \* \*$/
    }

    cond do
      String.match?(cron_expression, rules["hourly"]) ->
        process_regex(cron_expression, rules["hourly"], "hourly")

      String.match?(cron_expression, rules["daily"]) ->
        process_regex(cron_expression, rules["daily"], "daily")

      String.match?(cron_expression, rules["weekly"]) ->
        process_regex(cron_expression, rules["weekly"], "weekly")

      String.match?(cron_expression, rules["monthly"]) ->
        process_regex(cron_expression, rules["monthly"], "monthly")

      true ->
        Map.merge(%{}, %{:frequency => "custom"})
    end
  end

  defp process_regex(cron_expression, rule, key),
    do:
      Regex.named_captures(rule, cron_expression)
      |> Map.new(fn {k, v} ->
        {String.to_existing_atom(k), String.pad_leading(v, 2, "0")}
      end)
      |> Map.merge(%{:frequency => key})

  def build_cron_expression(prev, next) do
    case next do
      %{
        frequency: "hourly",
        hour: _hour,
        minute: minute,
        monthday: _monthday,
        weekday: _weekday
      } ->
        "#{minute} * * * *"

      %{
        frequency: "daily",
        hour: hour,
        minute: minute,
        monthday: _monthday,
        weekday: _weekday
      } ->
        "#{minute} #{hour} * * *"

      %{
        frequency: "weekly",
        hour: hour,
        minute: minute,
        monthday: _monthday,
        weekday: weekday
      } ->
        "#{minute} #{hour} * * #{weekday}"

      %{
        frequency: "monthly",
        hour: hour,
        minute: minute,
        monthday: monthday,
        weekday: _weekday
      } ->
        "#{minute} #{hour} #{monthday} * *"

      _ ->
        prev
    end
  end

  @impl true
  def handle_event(
        "cron_expression_change",
        %{"cron_component" => params},
        socket
      ) do
    cron_data =
      Map.merge(
        socket.assigns.cron_data,
        params
        |> Map.new(fn {k, v} ->
          {String.to_existing_atom(k), v}
        end)
      )

    cron_expression =
      build_cron_expression(
        socket.assigns.form |> Phoenix.HTML.Form.input_value(:cron_expression),
        cron_data
      )

    params =
      LightningWeb.Utils.build_params_for_field(
        socket.assigns.form,
        :cron_expression,
        cron_expression
      )

    socket.assigns.on_change.(params)

    {:noreply, socket |> assign(:cron_data, cron_data)}
  end

  def frequency_field(assigns) do
    ~H"""
    <Form.label_field
      form={:cron_component}
      field={:frequency}
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
      disabled={@disabled}
    />
    """
  end

  def minute_field(assigns) do
    ~H"""
    <div class="col-span-1">
      <Form.label_field
        form={:cron_component}
        field={:minute}
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
        disabled={@disabled}
      />
    </div>
    """
  end

  def hour_field(assigns) do
    ~H"""
    <div class="col-span-1">
      <Form.label_field form={:cron_component} field={:hour} title="Hour" for="hour" />
      <Form.select_field
        form={:cron_component}
        name={:hour}
        selected={@selected}
        prompt=""
        id="hour"
        phx-change="cron_expression_change"
        phx-target={@target}
        values={@values}
        disabled={@disabled}
      />
    </div>
    """
  end

  def weekday_field(assigns) do
    ~H"""
    <div class="col-span-2">
      <Form.label_field
        form={:cron_component}
        field={:weekday}
        title="Day"
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
        disabled={@disabled}
      />
    </div>
    """
  end

  def monthday_field(assigns) do
    ~H"""
    <div class="col-span-1">
      <Form.label_field
        form={:cron_component}
        field={:monthday}
        title="Day"
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
        disabled={@disabled}
      />
    </div>
    """
  end

  def time_field(assigns) do
    ~H"""
    <.hour_field
      target={@target}
      values={@hour_values}
      selected={@selected_hour}
      disabled={@disabled}
    />
    <.minute_field
      target={@target}
      values={@minute_values}
      selected={@selected_minute}
      disabled={@disabled}
    />
    """
  end
end
