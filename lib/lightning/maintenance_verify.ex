defmodule Lightning.MaintenanceVerify do
  @moduledoc """
  End-to-end smoke test for the three Maintenance admin actions.

  Wipes adaptor caches, runs each refresh synchronously, and exercises
  the HTTP endpoints through `LightningWeb.Endpoint.call/2` (no browser,
  no caching in the way).

  Intended usage:

    * From an IEx session that already has `phx.server` running:

          iex> Lightning.MaintenanceVerify.run()

    * From a standalone mix task (stop the dev server first so the Node
      worker port isn't contended):

          mix lightning.maintenance.verify

  Returns `:ok` if every step passed, `:error` otherwise. Prints one
  coloured line per step.
  """

  alias Lightning.AdaptorData
  alias Lightning.AdaptorData.Cache

  @kinds ~w(registry icon_manifest icon schema)

  @doc """
  Wipes every adaptor cache kind from both the database and Cachex.

  Useful for clicking the Maintenance buttons in the UI with a known-
  empty starting state:

      iex> Lightning.MaintenanceVerify.reset()
      :ok

  After this, the adaptor picker, icons, and credential schema dropdown
  should all be empty until you click the corresponding button.
  """
  @spec reset() :: :ok
  def reset do
    Enum.each(@kinds, fn kind ->
      AdaptorData.delete_kind(kind)
      Cache.invalidate(kind)
    end)

    :ok
  end

  @spec run() :: :ok | :error
  def run do
    steps = [
      {"reset adaptor cache (DB + Cachex)", fn -> reset() end},
      {"pre-reset state is empty", &assert_empty/0},
      {"refresh adaptor registry", &refresh_registry/0},
      {"registry persisted to DB + cache", &assert_registry/0},
      {"install adaptor icons (sync)", &refresh_icons/0},
      {"icon manifest + PNGs cached", &assert_icons/0},
      {"install credential schemas", &refresh_schemas/0},
      {"schemas persisted to DB", &assert_schemas/0},
      {"GET /images/adaptors/adaptor_icons.json serves JSON", &http_manifest/0},
      {"GET /images/adaptors/<adaptor>-square.png serves PNG", &http_icon/0}
    ]

    result =
      Enum.reduce_while(steps, :ok, fn {name, fun}, _acc ->
        case safe_call(fun) do
          :ok ->
            print_ok(name)
            {:cont, :ok}

          {:ok, detail} ->
            print_ok("#{name} #{detail}")
            {:cont, :ok}

          {:error, reason} ->
            print_fail(name, reason)
            {:halt, :error}
        end
      end)

    case result do
      :ok ->
        IO.puts("")
        IO.puts(green("All maintenance actions verified."))
        :ok

      :error ->
        IO.puts("")
        IO.puts(red("Verification failed."))
        :error
    end
  end

  # ---------------------------------------------------------------------------
  # Steps
  # ---------------------------------------------------------------------------

  defp assert_empty do
    Enum.reduce_while(@kinds, :ok, fn kind, _acc ->
      case AdaptorData.get_all(kind) do
        [] -> {:cont, :ok}
        rows -> {:halt, {:error, "#{kind} still has #{length(rows)} rows"}}
      end
    end)
  end

  defp refresh_registry do
    case Lightning.AdaptorRegistry.refresh_sync() do
      {:ok, count} when is_integer(count) and count > 0 ->
        {:ok, "(#{count} adaptors)"}

      {:ok, :local_mode} ->
        {:error, "local_adaptors_repo is enabled; unset it before verifying"}

      {:ok, other} ->
        {:error, "unexpected ok payload: #{inspect(other)}"}

      {:error, reason} ->
        {:error, "refresh_sync failed: #{inspect(reason)}"}
    end
  end

  defp assert_registry do
    case AdaptorData.get("registry", "all") do
      {:ok, entry} ->
        case Jason.decode(entry.data) do
          {:ok, list} when is_list(list) and list != [] ->
            case Cache.get("registry", "all") do
              %{data: _} -> :ok
              other -> {:error, "cache missing registry row: #{inspect(other)}"}
            end

          other ->
            {:error, "registry JSON unexpected: #{inspect(other)}"}
        end

      {:error, :not_found} ->
        {:error, "adaptor_cache_entries has no registry row"}
    end
  end

  defp refresh_icons do
    case Lightning.AdaptorIcons.refresh_sync() do
      {:ok, %{manifest: manifest, prefetched: p, skipped: s, errored: e}}
      when map_size(manifest) > 0 ->
        {:ok,
         "(manifest=#{map_size(manifest)} prefetched=#{p} skipped=#{s} errored=#{e})"}

      {:ok, %{manifest: manifest}} when map_size(manifest) == 0 ->
        {:error, "manifest is empty — did the registry refresh run first?"}

      {:error, reason} ->
        {:error, "refresh_sync failed: #{inspect(reason)}"}
    end
  end

  defp assert_icons do
    with {:ok, %{data: manifest_json}} <-
           wrap_not_found(Cache.get("icon_manifest", "all")),
         {:ok, manifest} <- Jason.decode(manifest_json),
         true <- map_size(manifest) > 0 || {:error, "manifest is empty"} do
      icons = AdaptorData.get_all("icon")

      if Enum.empty?(icons) do
        {:error, "no icons were cached (all GitHub fetches errored?)"}
      else
        {:ok, "(#{length(icons)} icons in DB)"}
      end
    end
  end

  defp refresh_schemas do
    case Lightning.CredentialSchemas.fetch_and_store() do
      {:ok, count} when is_integer(count) and count > 0 ->
        Cache.broadcast_invalidation(["schema"])
        {:ok, "(#{count} schemas)"}

      {:ok, 0} ->
        {:error, "fetch_and_store wrote 0 schemas"}

      {:error, reason} ->
        {:error, "fetch_and_store failed: #{inspect(reason)}"}
    end
  end

  defp assert_schemas do
    schemas = AdaptorData.get_all("schema")

    if schemas == [] do
      {:error, "no schemas in DB after fetch_and_store"}
    else
      {:ok, "(#{length(schemas)} rows)"}
    end
  end

  defp http_manifest do
    conn =
      Plug.Test.conn(:get, "/images/adaptors/adaptor_icons.json")
      |> LightningWeb.Endpoint.call([])

    cond do
      conn.status != 200 ->
        {:error, "status #{conn.status}"}

      conn.resp_body in [nil, "", "{}"] ->
        {:error, "manifest response empty: #{inspect(conn.resp_body)}"}

      true ->
        case Jason.decode(conn.resp_body) do
          {:ok, map} when is_map(map) and map_size(map) > 0 ->
            {:ok, "(#{map_size(map)} adaptors)"}

          other ->
            {:error, "manifest JSON invalid: #{inspect(other)}"}
        end
    end
  end

  defp http_icon do
    with {:ok, %{data: manifest_json}} <-
           wrap_not_found(Cache.get("icon_manifest", "all")),
         {:ok, manifest} <- Jason.decode(manifest_json),
         [{adaptor, _} | _] <- Enum.to_list(manifest) do
      path = "/images/adaptors/#{adaptor}-square.png"

      conn =
        Plug.Test.conn(:get, path)
        |> LightningWeb.Endpoint.call([])

      cond do
        conn.status != 200 ->
          {:error, "#{path} returned status #{conn.status}"}

        byte_size(conn.resp_body) < 100 ->
          {:error,
           "#{path} body suspiciously small (#{byte_size(conn.resp_body)} bytes)"}

        true ->
          content_type =
            Plug.Conn.get_resp_header(conn, "content-type") |> List.first()

          if content_type && String.starts_with?(content_type, "image/png") do
            {:ok, "(#{adaptor} #{byte_size(conn.resp_body)} bytes)"}
          else
            {:error, "content-type was #{inspect(content_type)}"}
          end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp wrap_not_found(nil), do: {:error, "not found"}
  defp wrap_not_found(%{data: _} = m), do: {:ok, m}

  defp safe_call(fun) do
    fun.()
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, "exit: #{inspect(reason)}"}
  end

  defp print_ok(name), do: IO.puts([green("  ✓ "), name])

  defp print_fail(name, reason) do
    IO.puts([red("  ✗ "), name, "\n    ", red(to_string(reason))])
  end

  defp green(s), do: IO.ANSI.green() <> s <> IO.ANSI.reset()
  defp red(s), do: IO.ANSI.red() <> s <> IO.ANSI.reset()
end
