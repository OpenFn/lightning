defmodule LightningWeb.CredentialLive.JsonSchemaBodyComponent do
  use LightningWeb, :component

  alias Lightning.Credentials

  attr :form, :map, required: true
  slot :inner_block

  def fieldset(%{form: form} = assigns) do
    changeset = form.source
    schema = changeset |> Ecto.Changeset.get_field(:schema) |> get_schema()

    schema_changeset =
      create_schema_changeset(
        schema,
        changeset |> Ecto.Changeset.get_field(:body) || %{}
      )

    assigns =
      assigns
      |> assign(
        changeset: changeset,
        schema: schema,
        form: form,
        schema_changeset: schema_changeset,
        valid?: changeset.valid? and schema_changeset.valid?
      )

    ~H"""
    <%= render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &inner/1,
         [form: @form, schema_changeset: @schema_changeset, schema: @schema],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    ) %>
    """
  end

  defp inner(assigns) do
    ~H"""
    <fieldset>
      <legend class="contents text-base font-medium text-gray-900">
        Details
      </legend>
      <p class="text-sm text-gray-500">
        Configuration for this credential.
      </p>

      <div
        :for={
          body_form <-
            Phoenix.HTML.FormData.to_form(:credential, @form, :body,
              default: @schema_changeset
            )
        }
        class="mt-4 space-y-4"
      >
        <div :for={field <- @schema.fields} class="grid grid-cols-2">
          <.schema_input form={body_form} schema={@schema} field={field} />
        </div>
      </div>
    </fieldset>
    """
  end

  defp get_schema(schema_name) do
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    File.read("#{schemas_path}/#{schema_name}.json")
    |> case do
      {:ok, raw_json} ->
        Credentials.Schema.new(raw_json, schema_name)

      {:error, reason} ->
        raise "Error reading credential schema. Got: #{reason |> inspect()}"
    end
  end

  defp create_schema_changeset(schema, params) do
    Credentials.SchemaDocument.changeset(%{}, params, schema: schema)
  end

  attr :form, :map, required: true
  attr :schema, :map, required: true
  attr :field, :any, required: true

  def schema_input(%{form: form, schema: schema, field: field} = assigns) do
    properties = Credentials.Schema.properties(schema, field)

    value = form.data |> Ecto.Changeset.get_field(field)
    errors = Keyword.get_values(form.data.errors, field)

    type =
      case properties do
        %{"format" => "uri"} -> :url_input
        %{"type" => "string", "writeOnly" => true} -> :password_input
        %{"type" => "string"} -> :text_input
        %{"type" => "integer"} -> :text_input
        %{"type" => "boolean"} -> :text_input
        %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]} -> :text_input
      end

    required = Credentials.Schema.required?(schema, field)

    assigns =
      assigns
      |> assign(
        value: value,
        errors: errors,
        title: properties |> Map.get("title"),
        required: required,
        type: type
      )

    ~H"""
    <LightningWeb.Components.Form.label_field
      form={@form}
      field={@field}
      title={@title}
    />
    <span :if={@required} class="text-sm text-secondary-700 text-right">
      Required
    </span>
    <div class="col-span-2">
      <%= apply(Phoenix.HTML.Form, @type, [
        @form,
        @field,
        [
          value: @value || "",
          class: ~w(mt-1 focus:ring-primary-500 focus:border-primary-500 block
               w-full shadow-sm sm:text-sm border-secondary-300 rounded-md)
        ]
      ]) %>
      <span
        :for={error <- @errors}
        phx-feedback_for={input_id(@form, @field)}
        class="block w-full text-sm text-secondary-700"
      >
        <%= translate_error(error) %>
      </span>
    </div>
    """
  end
end
