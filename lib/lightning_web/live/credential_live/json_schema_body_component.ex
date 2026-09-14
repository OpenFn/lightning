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
  attr :target, :any, default: nil
  # Bumped on each retry so this component re-renders and re-reads the schema.
  attr :attempt, :integer, default: 0
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    case changeset
         |> Ecto.Changeset.get_field(:schema)
         |> Credentials.get_schema() do
      {:ok, schema} -> loaded_fieldset(assigns, changeset, schema)
      {:error, reason} -> unavailable_fieldset(assigns, reason)
    end
  end

  defp loaded_fieldset(assigns, changeset, schema) do
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

  defp unavailable_fieldset(assigns, reason) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    {render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &schema_unavailable/1,
         [reason: @reason, target: @target],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), false}
    )}
    """
  end

  attr :reason, :any, required: true
  attr :target, :any, default: nil

  def schema_unavailable(assigns) do
    ~H"""
    <div
      id="credential-schema-unavailable"
      class="flex flex-col items-center gap-2 py-8 text-sm text-gray-500"
    >
      <p :if={@reason == :not_found}>
        This adaptor isn't in the adaptor catalogue.
      </p>
      <p :if={@reason != :not_found}>Couldn't load adaptors. Please try again.</p>
      <button
        :if={@reason != :not_found}
        type="button"
        phx-click="retry_schema"
        phx-target={@target}
        class="text-primary-600 hover:text-primary-500 font-medium"
      >
        Retry
      </button>
    </div>
    """
  end

  defp inner(assigns) do
    body_form = to_form(assigns.schema_changeset, as: "credential[body]")
    assigns = assign(assigns, :body_form, body_form)

    ~H"""
    <div class="space-y-4">
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
        required: Credentials.Schema.required?(assigns.schema, assigns.field),
        schema_warning: Credentials.Schema.warning(assigns.schema, assigns.field)
      )

    ~H"""
    <div class="col-span-2">
      <.input
        type={@type}
        field={@form_field}
        label={@title}
        required={@required}
        autocomplete={if @type == "password", do: "new-password", else: "off"}
        checked={@type == "checkbox" and @form_field.value == true}
      />
      <div
        :if={@schema_warning}
        class="mt-1 flex items-start gap-1 text-xs text-yellow-700"
      >
        <span class="hero-exclamation-triangle-solid h-4 w-4 text-yellow-500 flex-shrink-0">
        </span>
        <span>
          This adaptor's configuration schema specifies an unrecognized type
          (<code>{@schema_warning}</code>) for this field;
          we'll store it as text.
        </span>
      </div>
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
