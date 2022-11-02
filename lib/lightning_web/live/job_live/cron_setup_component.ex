defmodule LightningWeb.JobLive.CronSetupComponent do
  @moduledoc """
  CronSetupComponent
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

  @impl true
  def update(%{form: form, parent: parent}, socket) do
    parsed_cron_expression =
      Phoenix.HTML.Form.input_value(form, :trigger_cron_expression)
      |> parse_cron_expression()

    cron_types = %{
      frequency: :string,
      monthday: :integer,
      weekday: :integer,
      hour: :integer,
      minute: :integer
    }

    cron_data =
      {parsed_cron_expression, cron_types}
      |> Ecto.Changeset.cast(%{}, Map.keys(cron_types))

    {:ok,
     socket
     |> assign(:parent, parent)
     |> assign(:form, form)
     |> assign(:cron_data, cron_data)}
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

  defp process_regex(cron_expression, rule, key),
    do:
      Regex.named_captures(rule, cron_expression)
      |> Map.new(fn {k, v} -> {String.to_atom(k), String.to_integer(v)} end)
      |> Map.merge(%{:frequency => key})

  @impl true
  def handle_event(
        "cron_expression_change",
        %{"cron_component" => params},
        socket
      ) do
    cron_data =
      Ecto.Changeset.change(
        socket.assigns.cron_data,
        params
        |> Map.new(fn {k, v} -> {String.to_atom(k), String.to_atom(v)} end)
      )

    current_cron_expression =
      socket.assigns.form |> Map.get(:data) |> Map.get(:trigger_cron_expression)

    next_cron_expression =
      to_cron_string(
        cron_data,
        current_cron_expression
      )

    if next_cron_expression != current_cron_expression do
      {mod, id} = socket.assigns.parent
      send_update(mod, id: id, cron_expression: next_cron_expression)
    end

    {:noreply, socket |> assign(:cron_data, cron_data)}
  end

  defp to_cron_string(cron_changeset, curr_cron_expression) do
    cron_changeset |> IO.inspect(label: "Changeset")
    case cron_changeset.changes |> IO.inspect(label: "Changes") do
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

    # curr_expression =
    # Enum.reduce(
    #   [index],
    #   prev_expression,
    #   &List.replace_at(&2, &1, String.to_integer(cron_value))
    # )
    # |> Enum.join(" ")

    # data =
    # socket.assigns.form
    # |> Map.get(:data)
    # |> Map.put(:trigger_cron_expression, curr_expression)

    # Map.put(socket.assigns.form, :data, data)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-flow-col auto-cols-max gap-1">
      <Form.label_field
        form={:cron_component}
        id={:frequency}
        title="Frequency"
        for="frequency"
      />
      <Form.select_field
        form={:cron_component}
        name={:frequency}
        selected={@cron_data |> Ecto.Changeset.get_field(:frequency, :hourly)}
        prompt=""
        id="frequency"
        phx-change="cron_expression_change"
        phx-target={@myself}
        values={
          [
            "Every hour": :hourly,
            "Every day": :daily,
            "Every week": :weekly,
            "Every month": :monthly,
            Custom: :custom
          ]
        }
      />
      <br />
      <%= if @cron_data |> Ecto.Changeset.get_field(:frequency, :hourly) == :hourly do %>
        <div class="grid grid-flow-col auto-cols-max gap-1">
          <Form.label_field
            form={:cron_component}
            id={:minute}
            title="Minute"
            for="minute"
          />
          <Form.select_field
            form={:cron_component}
            name={:minute}
            selected={@cron_data |> Ecto.Changeset.get_field(:minute, 0)}
            prompt=""
            id="minute"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={0..59}
          />
        </div>
      <% end %>
      <%= if @cron_data |> Ecto.Changeset.get_field(:frequency, :daily) == :daily do %>
        <div class="grid grid-flow-col auto-cols-max gap-4">
          <Form.label_field
            form={:cron_component}
            id={:hour}
            title="Hour"
            for="hour"
          />
          <Form.select_field
            form={:cron_component}
            name={:hour}
            selected={@cron_data |> Ecto.Changeset.get_field(:hour, 0)}
            prompt=""
            id="hour"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={0..23}
          />
          <Form.label_field
            form={:cron_component}
            id={:minute}
            title="Minute"
            for="minute"
          />
          <Form.select_field
            form={:cron_component}
            name={:minute}
            selected={@cron_data |> Ecto.Changeset.get_field(:minute, 0)}
            prompt=""
            id="minute"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={0..59}
          />
        </div>
      <% end %>
      <%= if @cron_data |> Ecto.Changeset.get_field(:frequency, :weekly) == :weekly do %>
        <div class="grid grid-flow-col auto-cols-max gap-4">
          <Form.label_field
            form={:cron_component}
            id={:weekday}
            title="Wekkday"
            for="weekday"
          />
          <Form.select_field
            form={:cron_component}
            name={:weekday}
            selected={@cron_data |> Ecto.Changeset.get_field(:weekday, 1)}
            prompt=""
            id="weekday"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={
              [
                Monday: 1,
                Tuesday: 2,
                Wednesday: 3,
                Thursday: 4,
                Friday: 5,
                Saturday: 6,
                Sunday: 7
              ]
            }
          />
          <Form.label_field
            form={:cron_component}
            id={:hour}
            title="Hour"
            for="hour"
          />
          <Form.select_field
            form={:cron_component}
            name={:hour}
            selected={@cron_data |> Ecto.Changeset.get_field(:hour, 0)}
            prompt=""
            id="hour"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={0..23}
          />
          <Form.label_field
            form={:cron_component}
            id={:minute}
            title="Minute"
            for="minute"
          />
          <Form.select_field
            form={:cron_component}
            name={:minute}
            selected={@cron_data |> Ecto.Changeset.get_field(:minute, 0)}
            prompt=""
            id="minute"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={0..59}
          />
        </div>
      <% end %>
      <%= if @cron_data |> Ecto.Changeset.get_field(:frequency, :monthly) == :monthly do %>
        <div class="grid grid-flow-col auto-cols-max gap-4">
          <Form.label_field
            form={:cron_component}
            id={:monthday}
            title="Monthday"
            for="monthday"
          />
          <Form.select_field
            form={:cron_component}
            name={:monthday}
            selected={@cron_data |> Ecto.Changeset.get_field(:monthday, 1)}
            prompt=""
            id="monthday"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={1..31}
          />
          <Form.label_field
            form={:cron_component}
            id={:hour}
            title="Hour"
            for="hour"
          />
          <Form.select_field
            form={:cron_component}
            name={:hour}
            selected={@cron_data |> Ecto.Changeset.get_field(:hour, 0)}
            prompt=""
            id="hour"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={0..23}
          />
          <Form.label_field
            form={:cron_component}
            id={:minute}
            title="Minute"
            for="minute"
          />
          <Form.select_field
            form={:cron_component}
            name={:minute}
            selected={@cron_data |> Ecto.Changeset.get_field(:minute, 0)}
            prompt=""
            id="minute"
            phx-change="cron_expression_change"
            phx-target={@myself}
            values={0..59}
          />
        </div>
      <% end %>
      <%= if @cron_data |> Ecto.Changeset.get_field(:frequency, :custom) == :custom do %>
        <Form.text_field id={:trigger_cron_expression} form={@form} />
      <% end %>
    </div>
    """
  end
end
