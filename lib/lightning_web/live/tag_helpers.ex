defmodule LightningWeb.TagHelpers do
  @moduledoc """
  Helper functions for working with tags throughout the application.
  """

  @doc """
  Updates a changeset with new tags based on an action.

  ## Actions
  - `:add`: Adds new tags from a comma-separated string
  - `:remove`: Removes a specific tag
  - `:edit`: Removes a tag and focuses the input field for editing

  ## Examples

      handle_action(socket, "add", "tag1, tag2", :workflow_template_changeset, :tags)
  """
  def handle_action(socket, params, changeset_assign, field \\ :tags) do
    {action, value} = extract_tag_action_params(params)

    changeset = Map.get(socket.assigns, changeset_assign)
    current_tags = get_tags_from_changeset(changeset, field)

    {updated_tags, should_focus, focus_value} =
      case action do
        "add" ->
          new_tags = parse_tag_input(value)
          {(current_tags ++ new_tags) |> Enum.uniq() |> Enum.sort(), false, nil}

        "remove" ->
          {Enum.reject(current_tags, &(&1 == value)), false, nil}

        "edit" ->
          {Enum.reject(current_tags, &(&1 == value)), true, value}
      end

    updated_changeset = Ecto.Changeset.put_change(changeset, field, updated_tags)

    socket =
      Phoenix.Component.assign(socket, changeset_assign, updated_changeset)

    socket =
      if should_focus do
        Phoenix.LiveView.push_event(socket, "focus_tag_input", %{
          value: focus_value
        })
      else
        socket
      end

    socket =
      if action == "add" do
        Phoenix.LiveView.push_event(socket, "clear_input", %{})
      else
        socket
      end

    socket
  end

  @doc """
  Processes tag params to ensure they're in the correct format for the schema.

  This is helpful when validating forms with tag fields.

  ## Examples

      process_tag_params(%{"tags" => "[\"tag1\",\"tag2\"]"})
      # => %{"tags" => ["tag1", "tag2"]}
  """
  def process_tag_params(params, field \\ "tags") do
    case params[field] do
      string when is_binary(string) ->
        tags =
          string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, field, tags)

      _ ->
        params
    end
  end

  defp extract_tag_action_params(%{"action" => action, "value" => value}),
    do: {action, value}

  defp get_tags_from_changeset(changeset, field) do
    Ecto.Changeset.get_field(changeset, field, [])
  end

  defp parse_tag_input(input) when is_binary(input) do
    input
    |> String.split(~r/[,]+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.sort()
  end

  defp parse_tag_input(_), do: []
end
