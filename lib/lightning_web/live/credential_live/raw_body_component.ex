defmodule LightningWeb.CredentialLive.RawBodyComponent do
  @moduledoc """
  Component for rendering raw JSON credential body fields.

  Validates that the body is non-empty and valid JSON. Uses a changeset
  to integrate with Phoenix's form error display mechanism.
  """
  use LightningWeb, :component

  alias Lightning.Credentials.CredentialBody

  attr :form, :map, required: true
  attr :current_body, :map, default: %{}
  attr :touched, :boolean, default: false
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    {body_json, body_changeset} =
      validate_body(assigns.current_body, assigns.touched)

    assigns =
      assign(assigns,
        body_json: body_json,
        body_changeset: body_changeset,
        valid?: changeset.valid? and body_changeset.valid?
      )

    ~H"""
    {render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &inner/1,
         [form: @form, body_json: @body_json, body_changeset: @body_changeset],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    )}
    """
  end

  defp inner(assigns) do
    # Create a form from the changeset so errors display properly
    body_form = to_form(assigns.body_changeset, as: "body")
    body_field = body_form[:value]

    # Override the field name to match what the parent form expects
    body_field = %{body_field | name: "credential[body]", id: "credential_body"}

    assigns = assign(assigns, :body_field, body_field)

    ~H"""
    <fieldset>
      <.input
        type="codearea"
        field={@body_field}
        value={@body_json}
        label="Credential Body"
        required={true}
      />
    </fieldset>
    """
  end

  defp validate_body(body, touched) do
    {body_json, valid?, error} = parse_body(body)

    # Build a changeset to hold validation state
    types = %{value: :string}
    params = %{"value" => body_json}

    changeset =
      {%{}, types}
      |> Ecto.Changeset.cast(params, [:value])
      |> maybe_add_error(valid?, error, touched)
      |> validate_sensitive_values_count(body, touched)
      |> maybe_set_action(touched)

    {body_json, changeset}
  end

  defp validate_sensitive_values_count(changeset, body, true = _touched?) do
    case parse_for_validation(body) do
      {:ok, parsed_body} ->
        case CredentialBody.validate_sensitive_values_count(parsed_body) do
          :ok ->
            changeset

          {:error, message} ->
            Ecto.Changeset.add_error(changeset, :value, message)
        end

      {:error, _} ->
        changeset
    end
  end

  defp validate_sensitive_values_count(changeset, _body, _touched) do
    changeset
  end

  defp parse_for_validation(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp parse_for_validation(body) when is_map(body), do: {:ok, body}
  defp parse_for_validation(_), do: {:error, :invalid}

  defp parse_body(body) when is_binary(body) do
    trimmed = String.trim(body)

    if trimmed == "" do
      # Empty string - show default empty JSON object
      {"{}", false, "can't be blank"}
    else
      case Jason.decode(trimmed) do
        {:ok, _} -> {body, true, nil}
        {:error, _} -> {body, false, "Invalid JSON format"}
      end
    end
  end

  defp parse_body(body) when is_map(body) and body != %{} do
    {Jason.encode!(body, pretty: true), true, nil}
  end

  defp parse_body(body) when is_map(body) do
    # Empty map - show default empty JSON object
    {"{}", false, "can't be blank"}
  end

  defp parse_body(_), do: {"{}", false, "can't be blank"}

  defp maybe_add_error(changeset, true, _error, _touched), do: changeset
  defp maybe_add_error(changeset, false, _error, false), do: changeset

  defp maybe_add_error(changeset, false, error, true) do
    Ecto.Changeset.add_error(changeset, :value, error)
  end

  defp maybe_set_action(changeset, false), do: changeset

  defp maybe_set_action(changeset, true),
    do: Map.put(changeset, :action, :validate)
end
