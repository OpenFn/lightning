defmodule LightningWeb.API.Errors do
  @moduledoc """
  Turns an invalid changeset into error entries and a problem.

  A context function reports invalid data as a changeset.
  `LightningWeb.API.FallbackController` hands it to `problem/3`, which makes one
  entry per error and picks the response code from the entries. Each entry
  points at the part of the request it is about, such as a body key, a position
  in a list, or a path segment, using the request's key names rather than the
  schema's. Web code that checks the request itself builds entries with
  `entry/2` and returns them through `refuse/1`.

  An entry's code comes from the error's `code:` option, or from Ecto's own
  options. An error with neither raises. There is no fallback code.
  """
  alias Ecto.Changeset
  alias LightningWeb.API.Problem

  require Logger

  @type segment :: atom() | String.t() | non_neg_integer()
  @type location ::
          [segment()]
          | {:parameter, String.t()}
          | {:header, String.t()}
          | {:path, String.t()}
  @type entry :: %{
          required(:code) => atom(),
          required(:detail) => String.t(),
          optional(:pointer | :parameter | :header | :path) => String.t()
        }

  @validation_codes %{
    required: :required,
    format: :format,
    inclusion: :not_allowed,
    subset: :not_allowed,
    exclusion: :reserved,
    number: :out_of_range,
    confirmation: :mismatch,
    acceptance: :must_accept,
    unsafe_unique: :taken
  }

  @length_codes %{min: :too_short, max: :too_long, is: :wrong_length}

  @constraint_codes %{
    unique: :taken,
    exclusion: :taken,
    foreign: :not_found,
    assoc: :not_found,
    check: :invalid
  }

  @doc """
  Every error in `changeset` and its children, as entries.

  `renames` maps an Ecto field to the request's key, at any depth:
  `%{project_users: :members}`. An error whose options carry `key:` is placed
  there instead of at its field: one request key, or a list of the request's
  keys and positions below the error's level.

  `path:` lists the top-level request keys the request sent as path segments
  rather than in its body, so their errors name the segment: `path: [:key]`.

  Raises `ArgumentError` for an error with no code, and for an error on a
  child the request didn't send, since neither can be placed in the request.
  """
  @spec from_changeset(Changeset.t(), %{atom() => atom()}, path: [atom()]) ::
          [entry()]
  def from_changeset(%Changeset{} = changeset, renames \\ %{}, opts \\ []) do
    path_keys = Keyword.get(opts, :path, [])

    changeset
    |> walk([], renames, nil)
    |> Enum.map(fn {location, error} ->
      entry(in_path(location, path_keys), error)
    end)
  end

  @doc """
  The problem for a refused changeset. The first rule that matches wins
  (spec §4, "A changeset's status"):

    1. any error coded `storage_failed`: 500 `internal`, since the server
       failed, not the request (spec §6.2);
    2. any error coded `not_ready`: 503 `not_ready`, with no entries;
    3. every error `exceeds_limit`: 402 `exceeds_limit`;
    4. otherwise 422 `invalid`, without any `exceeds_limit` entries.

  A value in the body that must be unique and is already in use is a `taken`
  entry in the 422 like any other problem with the body. 409 is only for the
  state of the record the URL names.
  """
  @spec problem(Changeset.t(), %{atom() => atom()}, path: [atom()]) ::
          Problem.t()
  def problem(changeset, renames \\ %{}, opts \\ [])

  def problem(%Changeset{valid?: true}, _renames, _opts) do
    raise ArgumentError, "a changeset with no errors is not a problem"
  end

  def problem(%Changeset{} = changeset, renames, opts) do
    entries = from_changeset(changeset, renames, opts)
    codes = Enum.map(entries, & &1.code)

    cond do
      :storage_failed in codes ->
        Logger.error("An API action could not delete stored files")
        Problem.new(:internal)

      :not_ready in codes ->
        Problem.new(:not_ready, retry_after: 5)

      Enum.all?(codes, &(&1 == :exceeds_limit)) ->
        Problem.new(:exceeds_limit, errors: entries)

      true ->
        Problem.new(:invalid,
          errors: Enum.reject(entries, &(&1.code == :exceeds_limit))
        )
    end
  end

  @doc """
  `:ok` when there are no entries, otherwise a 422 `invalid` problem holding
  them all, for a producer that checks the request itself (spec §9.6).
  """
  @spec refuse([entry()]) :: :ok | {:error, Problem.t()}
  def refuse([]), do: :ok
  def refuse(entries), do: {:error, Problem.new(:invalid, errors: entries)}

  @doc """
  The 400 `invalid_parameter` problem for a refused changeset over a route's
  query parameters, with one entry per error, each naming its parameter
  (spec §9.4).
  """
  @spec parameters(Changeset.t()) :: Problem.t()
  def parameters(%Changeset{valid?: true}) do
    raise ArgumentError, "a changeset with no errors is not a problem"
  end

  def parameters(%Changeset{errors: errors}) do
    entries =
      errors
      |> Enum.reverse()
      |> Enum.map(fn {field, error} ->
        entry({:parameter, Atom.to_string(field)}, error)
      end)

    Problem.new(:invalid_parameter, errors: entries)
  end

  @doc """
  `{:ok, value}` passed through, or `{:error, changeset}` over a route's query
  parameters turned into its 400 `invalid_parameter` problem (spec §9.4).
  """
  @spec refuse_parameters({:ok, value} | {:error, Changeset.t()}) ::
          {:ok, value} | {:error, Problem.t()}
        when value: term()
  def refuse_parameters({:ok, _value} = ok), do: ok

  def refuse_parameters({:error, %Changeset{} = changeset}),
    do: {:error, parameters(changeset)}

  @doc """
  One entry, for a producer that validates the request itself (spec §7 items
  3 and 4).

  `error` is shaped as a changeset error, `{message, opts}`, and is coded and
  interpolated the same way. `location` is a list of the request's keys and
  positions, or `{:parameter, name}`, or `{:header, name}`, or `{:path, name}`
  for a path segment, named by its route parameter. A `path` names a segment,
  never carries its text.
  """
  @spec entry(location(), {String.t(), keyword()}) :: entry()
  def entry(location, {message, opts}) do
    location
    |> place()
    |> Map.merge(%{
      code: code(location, message, opts),
      detail: interpolate(message, opts)
    })
  end

  @doc """
  The error for a reference in the body that matches nothing the caller can
  see. Something missing and something hidden get the same error (spec §4).
  """
  @spec not_visible() :: {String.t(), keyword()}
  def not_visible, do: {"names nothing you can see", code: :not_found}

  @doc """
  An RFC 6901 JSON Pointer in URI-fragment form: each key has `~` written
  `~0` and `/` written `~1`, then the whole is percent-encoded wherever a
  character isn't allowed in a fragment (spec §3).
  """
  @spec pointer([segment()]) :: String.t()
  def pointer(segments) do
    path = Enum.map_join(segments, &("/" <> escape(to_string(&1))))
    "#" <> URI.encode(path, &fragment_char?/1)
  end

  defp escape(key),
    do: key |> String.replace("~", "~0") |> String.replace("/", "~1")

  defp fragment_char?(char),
    do: URI.char_unreserved?(char) or char in ~c"!$&'()*+,;=:@/?"

  defp place({:parameter, name}), do: %{parameter: name}
  defp place({:header, name}), do: %{header: String.downcase(name)}
  defp place({:path, name}), do: %{path: name}
  defp place(segments) when is_list(segments), do: %{pointer: pointer(segments)}

  defp code(location, message, opts) do
    opts[:code] || ecto_code(opts) ||
      raise ArgumentError,
            "the error #{inspect(message)} at #{inspect(location)} has no code: " <>
              "give it code: in its options (error-format spec §6.3)"
  end

  defp ecto_code(opts) do
    case Map.new(opts) do
      %{validation: :cast, type: type} -> cast_code(type)
      %{validation: :length, kind: kind} -> Map.get(@length_codes, kind)
      %{validation: validation} -> Map.get(@validation_codes, validation)
      %{constraint: constraint} -> Map.get(@constraint_codes, constraint)
      %{type: type} when type in [:map, {:array, :map}] -> :type
      _untagged -> nil
    end
  end

  # A value outside an enum's set is refused like validate_inclusion, not as
  # a value of the wrong type (spec §6.2). `__enum_map__/0` is what ecto_enum's
  # defenum modules export.
  defp cast_code({:array, type}), do: cast_code(type)
  defp cast_code({:parameterized, {Ecto.Enum, _params}}), do: :not_allowed

  defp cast_code(type) when is_atom(type) do
    if Code.ensure_loaded?(type) and function_exported?(type, :__enum_map__, 0),
      do: :not_allowed,
      else: :type
  end

  defp cast_code(_type), do: :type

  defp interpolate(message, opts) do
    Regex.replace(~r"%{(\w+)}", message, fn whole, key ->
      Enum.find_value(opts, whole, fn {name, value} ->
        if Atom.to_string(name) == key, do: to_string(value)
      end)
    end)
  end

  # A placed error is `{location, {message, opts}}`. `duplicate_of` is the
  # location of the earlier request item holding the same primary key, when
  # this changeset is a later one.
  defp walk(%Changeset{} = changeset, path, renames, duplicate_of) do
    own =
      changeset.errors
      |> Enum.reverse()
      |> Enum.map(fn {field, error} ->
        {error_location(changeset, path, field, error, renames),
         duplicate(changeset, field, error, duplicate_of)}
      end)

    children =
      for {field, {tag, _relation}} <- changeset.types,
          tag in [:assoc, :embed],
          Map.has_key?(changeset.changes, field),
          placed <-
            walk_relation(
              Map.fetch!(changeset.changes, field),
              path ++ [Map.get(renames, field, field)],
              renames
            ),
          do: placed

    own ++ children
  end

  # Only children with params came from the request, and positions count
  # only those (spec §7 item 3, plan D1).
  defp walk_relation(children, path, renames) when is_list(children) do
    {from_request, not_sent} = Enum.split_with(children, &from_request?/1)
    Enum.each(not_sent, &refuse_errors(&1, path))

    {placed, _firsts} =
      from_request
      |> Enum.with_index()
      |> Enum.flat_map_reduce(%{}, fn {child, index}, firsts ->
        key = primary_key(child)
        first = Map.get(firsts, key, index)
        duplicate_of = if first != index and nil not in key, do: path ++ [first]

        {walk(child, path ++ [index], renames, duplicate_of),
         Map.put_new(firsts, key, index)}
      end)

    placed
  end

  defp walk_relation(%Changeset{} = child, path, renames) do
    if from_request?(child) do
      walk(child, path, renames, nil)
    else
      refuse_errors(child, path)
    end
  end

  defp walk_relation(nil, _path, _renames), do: []

  defp from_request?(%Changeset{params: params}), do: params != nil

  defp refuse_errors(%Changeset{} = child, path) do
    if child.valid? do
      []
    else
      raise ArgumentError,
            "a child under #{pointer(path)} that the request didn't send has " <>
              "errors, so they can't be placed in the request. Its producer " <>
              "builds its own entries with Errors.entry/2 (error-format spec §7)"
    end
  end

  defp primary_key(%Changeset{data: %schema{}} = child) do
    Enum.map(schema.__schema__(:primary_key), &Changeset.get_field(child, &1))
  end

  defp error_location(_changeset, path, :base, {_message, opts}, _renames),
    do: path ++ List.wrap(opts[:key])

  defp error_location(changeset, path, field, {_message, opts}, renames) do
    path ++
      List.wrap(
        opts[:key] || Map.get(renames, field) ||
          request_key(changeset, field, opts[:constraint])
      )
  end

  defp in_path([key] = location, path_keys) do
    if key in path_keys, do: {:path, to_string(key)}, else: location
  end

  defp in_path(location, _path_keys), do: location

  # assoc_constraint puts its error on the association, but the request sent
  # the foreign key, and keys are the request's (spec §3 rule 2).
  defp request_key(%Changeset{data: %schema{}}, field, :assoc) do
    case schema.__schema__(:association, field) do
      %Ecto.Association.BelongsTo{owner_key: owner_key} -> owner_key
      _other -> field
    end
  end

  defp request_key(_changeset, field, _constraint), do: field

  # Ecto's duplicate-key check in cast_assoc and cast_embed is its one error
  # with no options: "has already been taken", on the later child's primary
  # key (spec §6.2).
  defp duplicate(
         %Changeset{data: %schema{}},
         field,
         {_message, []} = error,
         earlier
       )
       when earlier != nil do
    if field in schema.__schema__(:primary_key),
      do: {"names the same id as " <> pointer(earlier), [code: :duplicate]},
      else: error
  end

  defp duplicate(_changeset, _field, error, _earlier), do: error
end
