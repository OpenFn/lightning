defmodule LightningWeb.API.AiAssistantRequest do
  @moduledoc """
  What the AI assistant's routes share: finding the session a path names, and
  reading a message body (`content`, `context` and `attach`) into what
  `Lightning.AiAssistant` stores on the message.

  A message carries its own attachments and editor context in its metadata,
  so it is answered, and retried, with what it sent. `attach.code`,
  `attach.logs` and `attach.io` are each `false` unless sent. A `step_id` or
  `run_id` from another project is a `not_found` entry, never dropped.
  """
  alias Ecto.Changeset
  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatSession
  alias Lightning.Invocation
  alias Lightning.Runs
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  @not_a_uuid {"is not a UUID", validation: :cast, type: :binary_id}
  @not_an_object {"is not an object", code: :type}
  @not_a_string {"is not a string", code: :type}
  @not_a_boolean {"is not a boolean", code: :type}
  @blank {"can't be blank", code: :required}
  @default_adaptor "@openfn/language-common@latest"

  @doc """
  The session the path's `id` names, with the id of its project, once the
  caller may apply `permission` to that project. A session's project comes
  from the session itself, so an unknown id, or one that isn't a UUID, is 403
  to everyone these routes accept, as for a session they can't see.
  """
  @spec session(Plug.Conn.t(), Target.permission()) ::
          {:ok, {Ecto.UUID.t(), ChatSession.t()}} | {:error, term()}
  def session(conn, permission) do
    Target.in_project_of(
      conn.assigns.scope,
      Request.param(conn, "id"),
      permission,
      &AiAssistant.get_project_id/1,
      fn project_id, id ->
        with {:ok, session} <-
               AiAssistant.get_session_for_project(project_id, id),
             do: {:ok, {project_id, session}}
      end
    )
  end

  @doc """
  Reads the message `body` holds, under `path` in the request, for a session of
  `kind` (`"job_code"`, `"workflow"`, or `nil` when the kind is unknown) in the
  project `project_id`.

  Answers the entries the body earns, every one of them, and the message read
  from it: `content`, `context` (a map or `nil`) and `attach`.
  """
  @spec read(term(), [Errors.segment()], String.t() | nil, Ecto.UUID.t() | nil) ::
          {[Errors.entry()], map()}
  def read(body, path, kind, project_id) when is_map(body) do
    {content_entries, content} = content(body, path)
    {context_entries, context} = context(body, path, kind)
    {attach_entries, attach} = attach(body, path, kind, project_id)

    {Request.unknown_keys(body, path, [:content, :context, :attach]) ++
       content_entries ++ context_entries ++ attach_entries,
     %{content: content, context: context, attach: attach}}
  end

  def read(_body, path, _kind, _project_id),
    do: {[Errors.entry(path, @not_an_object)], nil}

  @doc """
  The metadata a message stores for `attach`, so the assistant is sent what
  this message asked for and nothing else.
  """
  @spec attach_meta(map()) :: map()
  def attach_meta(attach) do
    %{
      "message_options" => %{
        "log" => attach.logs,
        "attach_io_data" => attach.io,
        "step_id" => attach.step_id,
        "send_code" => attach.code
      }
    }
    |> put_present("follow_run_id", attach.run_id)
  end

  @doc """
  The editor's job for a saved job, `context` over what is saved, in the shape
  the assistant reads it, or `nil` to use the saved job.
  """
  @spec runtime_context(map() | nil, map()) :: map() | nil
  def runtime_context(nil, _job), do: nil

  def runtime_context(context, job) do
    %{
      "job_name" => Map.get(context, "name", job.name),
      "job_body" => Map.get(context, "body", job.body),
      "job_adaptor" => Map.get(context, "adaptor", job.adaptor)
    }
  end

  @doc """
  The job not yet saved, `id` in the workflow `workflow_id`, from `context` over
  what the session last held, in the shape the assistant reads it.
  """
  @spec unsaved_job(map() | nil, map(), Ecto.UUID.t(), Ecto.UUID.t()) :: map()
  def unsaved_job(context, held, id, workflow_id) do
    context = context || %{}

    %{
      "id" => id,
      "name" => Map.get(context, "name", held["name"]),
      "body" => Map.get(context, "body", held["body"] || ""),
      "adaptor" =>
        Map.get(context, "adaptor", held["adaptor"] || @default_adaptor),
      "workflow_id" => workflow_id
    }
  end

  defp content(body, path) do
    changeset =
      {%{}, %{content: :string}}
      |> Changeset.cast(body, [:content])
      |> Changeset.validate_required([:content])
      |> Changeset.validate_length(:content,
        min: 1,
        max: Lightning.AiAssistant.ChatMessage.max_content_length()
      )

    entries =
      changeset.errors
      |> Enum.reverse()
      |> Enum.map(fn {field, error} -> Errors.entry(path ++ [field], error) end)

    {entries, Changeset.get_change(changeset, :content)}
  end

  defp context(%{"context" => _context}, path, "workflow"),
    do:
      {[
         Errors.entry(
           path ++ ["context"],
           {"is not supported for a workflow session", code: :not_supported}
         )
       ], nil}

  defp context(%{"context" => context}, path, _kind) when is_map(context) do
    path = path ++ ["context"]

    entries =
      Request.unknown_keys(context, path, [:name, :body, :adaptor]) ++
        for key <- ["name", "body", "adaptor"],
            Map.has_key?(context, key),
            not is_binary(context[key]),
            do: Errors.entry(path ++ [key], @not_a_string)

    {entries, Map.take(context, ["name", "body", "adaptor"])}
  end

  defp context(%{"context" => _context}, path, _kind),
    do: {[Errors.entry(path ++ ["context"], @not_an_object)], nil}

  defp context(_body, _path, _kind), do: {[], nil}

  @no_attach %{code: false, logs: false, io: false, step_id: nil, run_id: nil}

  defp attach(%{"attach" => attach}, path, kind, project_id)
       when is_map(attach) do
    path = path ++ ["attach"]

    {flag_entries, flags} = flags(attach, path)
    {id_entries, ids} = ids(attach, path, project_id)
    read = Map.merge(flags, ids)

    {Request.unknown_keys(attach, path, [:code, :logs, :io, :step_id, :run_id]) ++
       flag_entries ++ id_entries ++ needs(read, attach, path, kind), read}
  end

  defp attach(%{"attach" => _attach}, path, _kind, _project_id),
    do: {[Errors.entry(path ++ ["attach"], @not_an_object)], @no_attach}

  defp attach(_body, _path, _kind, _project_id), do: {[], @no_attach}

  defp flags(attach, path) do
    Enum.reduce([:code, :logs, :io], {[], %{}}, fn flag, {entries, read} ->
      case Map.fetch(attach, Atom.to_string(flag)) do
        :error ->
          {entries, Map.put(read, flag, false)}

        {:ok, value} when is_boolean(value) ->
          {entries, Map.put(read, flag, value)}

        {:ok, _value} ->
          {entries ++ [Errors.entry(path ++ [flag], @not_a_boolean)],
           Map.put(read, flag, false)}
      end
    end)
  end

  defp ids(attach, path, project_id) do
    lookups = [
      step_id: &Invocation.get_step_for_project/2,
      run_id: &Runs.get_for_project/2
    ]

    Enum.reduce(lookups, {[], %{}}, fn {key, lookup}, {entries, read} ->
      location = path ++ [key]

      case Map.fetch(attach, Atom.to_string(key)) do
        :error ->
          {entries, Map.put(read, key, nil)}

        {:ok, value} ->
          case referenced(location, value, project_id, lookup) do
            {:ok, id} -> {entries, Map.put(read, key, id)}
            {:error, entry} -> {entries ++ [entry], Map.put(read, key, nil)}
          end
      end
    end)
  end

  defp referenced(location, value, project_id, lookup) do
    with {:ok, id} <- valid_id(location, value),
         {:ok, _record} <- found(location, project_id, id, lookup),
         do: {:ok, id}
  end

  defp valid_id(location, value) do
    case Request.id({location, value}) do
      {:ok, id} -> {:ok, id}
      {:error, _invalid} -> {:error, Errors.entry(location, @not_a_uuid)}
    end
  end

  # With no project the session can't be read, so nothing it names is found.
  defp found(location, nil, _id, _lookup),
    do: {:error, Errors.entry(location, Errors.not_visible())}

  defp found(location, project_id, id, lookup) do
    case lookup.(project_id, id) do
      {:ok, record} ->
        {:ok, record}

      {:error, :not_found} ->
        {:error, Errors.entry(location, Errors.not_visible())}
    end
  end

  # The job assistant reads logs from a run and input and output from a step.
  # The workflow assistant takes neither.
  defp needs(read, _attach, path, "workflow") do
    for flag <- [:logs, :io],
        read[flag],
        do:
          Errors.entry(
            path ++ [flag],
            {"is not supported for a workflow session", code: :not_supported}
          )
  end

  defp needs(read, attach, path, _kind) do
    for {flag, key} <- [logs: :run_id, io: :step_id],
        read[flag],
        not Map.has_key?(attach, Atom.to_string(key)),
        do: Errors.entry(path ++ [key], @blank)
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
