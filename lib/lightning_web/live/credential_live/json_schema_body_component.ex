defmodule LightningWeb.CredentialLive.JsonSchemaBodyComponent do
  @moduledoc """
  Component for rendering JSON schema-based credential body fields.

  Receives a `schema_changeset` from the parent containing validation errors
  for touched fields. On initial render (no changeset), creates a fresh one.
  """
  use LightningWeb, :component

  alias Lightning.Credentials

  attr :form, :map, required: true
  attr :current_body, :map, default: %{}
  attr :schema_changeset, :any, default: nil
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    schema =
      changeset |> Ecto.Changeset.get_field(:schema) |> Credentials.get_schema()

    body = normalize_body(assigns.current_body)

    schema_changeset = assigns.schema_changeset || create_changeset(schema, body)

    assigns =
      assign(assigns,
        schema: schema,
        schema_changeset: schema_changeset,
        valid?: changeset.valid? and schema_changeset.valid?
      )

    ~H"""
    {render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &inner/1,
         [schema_changeset: @schema_changeset, schema: @schema],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    )}
    """
  end

  defp inner(assigns) do
    body_form = to_form(assigns.schema_changeset, as: "credential[body]")
    assigns = assign(assigns, :body_form, body_form)

    ~H"""
    <div>
      <div :for={field <- @schema.fields} class="grid grid-cols-2">
        <.schema_input form={@body_form} schema={@schema} field={field} />
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :schema, :map, required: true
  attr :field, :any, required: true

  def schema_input(assigns) do
    properties = Credentials.Schema.properties(assigns.schema, assigns.field)

    assigns =
      assign(assigns,
        form_field: assigns.form[assigns.field],
        title: Map.get(properties, "title"),
        type: input_type(properties),
        required: Credentials.Schema.required?(assigns.schema, assigns.field)
      )

    ~H"""
    <div class="col-span-2">
      <.input
        type={@type}
        field={@form_field}
        label={@title}
        required={@required}
        checked={@type == "checkbox" and @form_field.value == true}
      />
    </div>
    """
  end

  # current_body is always a map from credential_bodies or default %{}
  defp normalize_body(body) when is_map(body), do: body
  defp normalize_body(_), do: %{}

  defp create_changeset(schema, params) do
    Credentials.SchemaDocument.changeset(params, schema: schema)
  end

  defp input_type(%{"format" => "uri"}), do: "url"
  defp input_type(%{"type" => "string", "writeOnly" => true}), do: "password"
  defp input_type(%{"type" => "string"}), do: "text"
  defp input_type(%{"type" => "integer"}), do: "text"
  defp input_type(%{"type" => "object"}), do: "codearea"
  defp input_type(%{"type" => "boolean"}), do: "checkbox"

  defp input_type(%{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]}),
    do: "text"

  # Fallback for unhandled schema patterns
  defp input_type(_), do: "text"
end
