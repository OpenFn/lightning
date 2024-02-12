defmodule Lightning.AuthProviders.AuthConfigForm do
  @moduledoc false
  import Ecto.Changeset

  alias Lightning.AuthProviders.Handler
  alias Lightning.AuthProviders.WellKnown

  @types %{
    name: :string,
    discovery_url: :string,
    client_id: :string,
    client_secret: :string,
    redirect_uri: :string,
    redirect_host: :string,
    redirect_path_func: :function
  }

  @fields Map.keys(@types)

  defstruct @fields

  def from_auth_config(model) do
    struct(__MODULE__, Map.from_struct(model))
  end

  def change(form_model, params \\ %{}) do
    {form_model, @types}
    |> cast(params, @fields)
    |> generate_redirect_uri()
    |> validate_required(@fields)
    |> validate_format(
      :name,
      ~r/^[[:lower:]\d\-\_]+$/,
      message:
        "must be lower-case and only contain alphanumeric, dash and underscore characters"
    )
    |> validate_format(
      :discovery_url,
      ~r/^https?:\/\/[-\w\d@:%._+~#=]{1,256}.[a-zA-Z0-9()]{1,6}(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)/,
      message: "must be a valid HTTP/s URL"
    )
  end

  defp generate_redirect_uri(changeset) do
    changeset
    |> validate_required(:redirect_host)
    |> case do
      %{valid?: true} = changeset ->
        name = get_field(changeset, :name, "")
        redirect_host = get_field(changeset, :redirect_host)
        redirect_path_func = get_field(changeset, :redirect_path_func)

        put_change(
          changeset,
          :redirect_uri,
          %{URI.new!(redirect_host) | path: redirect_path_func.(name)}
          |> URI.to_string()
        )

      _ ->
        changeset
    end
  end

  def validate_provider(changeset) do
    form_model = apply_changes(changeset)

    build_provider(form_model)
    |> case do
      {:error, %{reason: :econnrefused}} ->
        changeset
        |> add_error(:discovery_url, "could not connect to discovery endpoint")

      {:error, %HTTPoison.Error{reason: message}} when is_binary(message) ->
        changeset |> add_error(:discovery_url, message)

      {:error, %Jason.DecodeError{}} ->
        changeset |> add_error(:discovery_url, "error parsing .well-known")

      {:error, message} when is_binary(message) ->
        changeset |> add_error(:discovery_url, message)

      {:ok, _provider} ->
        changeset
    end
  end

  def build_provider(form_model) do
    WellKnown.fetch(form_model.discovery_url)
    |> case do
      {:ok, wellknown} ->
        Handler.new(
          form_model.name,
          wellknown: wellknown,
          client_id: form_model.client_id,
          client_secret: form_model.client_secret,
          redirect_uri: form_model.redirect_uri
        )

      {:error, reason} ->
        {:error, reason}
    end
  end
end
