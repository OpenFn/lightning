defmodule LightningWeb.AdaptorIconControllerTest do
  # async: false — all tests share the Lightning.Adaptors supervisor name.
  use LightningWeb.ConnCase, async: false

  import Mox

  alias Lightning.Adaptors.IconCache
  alias Lightning.Adaptors.Repo, as: AdaptorsRepo
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor
  alias LightningWeb.AdaptorIconController
  alias LightningWeb.AdaptorIconURL

  setup :verify_on_exit!

  # The production `Lightning.Adaptors.Supervisor` is started in
  # `application.ex` under the name `Lightning.Adaptors` and — in test —
  # uses `Lightning.Adaptors.StrategyMock` (see `config/test.exs`). No
  # per-test supervisor start is needed.

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sha8_from_bytes(bytes) do
    :crypto.hash(:sha256, bytes)
    |> binary_part(0, 4)
    |> Base.encode16(case: :lower)
  end

  defp source, do: AdaptorsSupervisor.source(Lightning.Adaptors)

  defp unique_adaptor_name do
    "@openfn/language-test-#{System.unique_integer([:positive])}"
  end

  defp insert_adaptor(name, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: name,
          source: :npm,
          latest_version: "1.0.0",
          deprecated: false
        },
        overrides
      )

    {:ok, _adaptor} = AdaptorsRepo.upsert_adaptor(attrs)
  end

  defp write_icon(name, shape, ext, bytes) do
    {:ok, _sha} = IconCache.write!(source(), name, shape, ext, bytes)
    :ok
  end

  # ---------------------------------------------------------------------------
  # 200 — sha matches, disk warm
  # ---------------------------------------------------------------------------

  describe "show/2 — match + warm disk" do
    test "returns 200 with immutable Cache-Control", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "png icon bytes"
      sha256 = :crypto.hash(:sha256, bytes)
      sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      write_icon(name, :square, "png", bytes)

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => sha8,
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 200

      assert get_resp_header(result, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]

      assert result.resp_body == bytes
    end

    test "serves correct Content-Type for png", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "png bytes"
      sha256 = :crypto.hash(:sha256, bytes)
      sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      write_icon(name, :square, "png", bytes)

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => sha8,
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 200
      [ct] = get_resp_header(result, "content-type")
      assert ct =~ "image/png"
    end

    test "serves correct Content-Type for svg", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "<svg/>"
      sha256 = :crypto.hash(:sha256, bytes)
      sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "svg",
        icon_square_sha256: sha256
      })

      write_icon(name, :square, "svg", bytes)

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => sha8,
        "ext" => "svg"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 200
      [ct] = get_resp_header(result, "content-type")
      assert ct =~ "image/svg+xml"
    end

    test "sha8 is case-insensitive on input", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "case test bytes"
      sha256 = :crypto.hash(:sha256, bytes)
      sha8_lower = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)
      sha8_upper = String.upcase(sha8_lower)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      write_icon(name, :square, "png", bytes)

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => sha8_upper,
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 200
    end

    test "works for rectangle shape", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "rect bytes"
      sha256 = :crypto.hash(:sha256, bytes)
      sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_rectangle_ext: "png",
        icon_rectangle_sha256: sha256
      })

      write_icon(name, :rectangle, "png", bytes)

      params = %{
        "name" => name,
        "shape" => "rectangle",
        "sha8" => sha8,
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 200
      assert result.resp_body == bytes
    end
  end

  # ---------------------------------------------------------------------------
  # 200 — sha matches, disk cold (strategy fetches)
  # ---------------------------------------------------------------------------

  describe "show/2 — match + cold disk" do
    test "strategy is called, bytes written to disk, 200 returned", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "cold icon bytes"
      sha256 = :crypto.hash(:sha256, bytes)
      sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_icon,
        1,
        fn ^name, :square -> {:ok, %{data: bytes, ext: "png"}} end
      )

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => sha8,
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 200

      assert get_resp_header(result, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]

      assert result.resp_body == bytes
    end
  end

  # ---------------------------------------------------------------------------
  # 302 — stale sha8, current icon exists
  # ---------------------------------------------------------------------------

  describe "show/2 — stale sha8" do
    test "redirects 302 with no-store and current Location", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "current icon bytes"
      sha256 = :crypto.hash(:sha256, bytes)
      current_sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      stale_sha8 = "00000000"

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => stale_sha8,
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 302
      assert get_resp_header(result, "cache-control") == ["no-store"]

      encoded_name = URI.encode(name, &URI.char_unreserved?/1)

      assert get_resp_header(result, "location") == [
               "/adaptors/icons/#{encoded_name}/square-#{current_sha8}.png"
             ]
    end

    test "Location URL is lowercase even when sha8 input was uppercase", %{
      conn: conn
    } do
      name = unique_adaptor_name()
      bytes = "case url bytes"
      sha256 = :crypto.hash(:sha256, bytes)
      current_sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => "FFFFFFFF",
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 302
      [location] = get_resp_header(result, "location")

      # sha8 segment is lowercase; percent-encoded chars use uppercase hex per RFC 3986
      assert location =~ "square-#{current_sha8}.png"
    end

    test "Location matches what AdaptorIconURL.build/3 would emit", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "channel sync bytes"
      sha256 = :crypto.hash(:sha256, bytes)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      meta = %{
        icon_square_ext: "png",
        icon_square_sha256: sha256,
        icon_rectangle_ext: nil,
        icon_rectangle_sha256: nil
      }

      expected_url = AdaptorIconURL.build(name, meta, :square)

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => "00000000",
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 302
      assert get_resp_header(result, "location") == [expected_url]
    end
  end

  # ---------------------------------------------------------------------------
  # 404 cases
  # ---------------------------------------------------------------------------

  describe "show/2 — 404" do
    test "adaptor not in DB", %{conn: conn} do
      params = %{
        "name" => "nonexistent-adaptor-#{System.unique_integer([:positive])}",
        "shape" => "square",
        "sha8" => "aabbccdd",
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 404
    end

    test "ext mismatch — DB has png, URL says svg", %{conn: conn} do
      name = unique_adaptor_name()
      sha256 = :crypto.hash(:sha256, "some bytes")
      sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => sha8,
        "ext" => "svg"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 404
    end

    test "ext mismatch — DB has svg, URL says png", %{conn: conn} do
      name = unique_adaptor_name()
      sha256 = :crypto.hash(:sha256, "<svg/>")
      sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "svg",
        icon_square_sha256: sha256
      })

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => sha8,
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 404
    end

    test "stored ext is nil (no icon for shape)", %{conn: conn} do
      name = unique_adaptor_name()
      insert_adaptor(name)

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => "aabbccdd",
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 404
    end

    test "bad shape value — not square or rectangle", %{conn: conn} do
      params = %{
        "name" => unique_adaptor_name(),
        "shape" => "circle",
        "sha8" => "aabbccdd",
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 404
    end

    test "missing params — fallback clause", %{conn: conn} do
      result = AdaptorIconController.show(conn, %{"name" => "something"})

      assert result.status == 404
    end

    test "stale sha but stored ext is nil (icon removed upstream) — no redirect",
         %{
           conn: conn
         } do
      # Adaptor row exists but has no icon for the square shape.
      # Even though there's a stale sha8 in the URL, there's no canonical
      # URL to redirect to — 404 instead of 302.
      name = unique_adaptor_name()
      insert_adaptor(name)

      params = %{
        "name" => name,
        "shape" => "square",
        "sha8" => "00000000",
        "ext" => "png"
      }

      result = AdaptorIconController.show(conn, params)

      assert result.status == 404
    end
  end

  # ---------------------------------------------------------------------------
  # Full router pipeline — proves route + pipe + controller resolves.
  # The matrix above already covers the controller's behaviour by direct call.
  # ---------------------------------------------------------------------------

  describe "GET /adaptors/icons/... (full router pipeline)" do
    test "200 on sha match", %{conn: conn} do
      name = unique_adaptor_name()
      bytes = "router pipeline bytes"
      sha256 = :crypto.hash(:sha256, bytes)
      sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      insert_adaptor(name, %{
        icon_square_ext: "png",
        icon_square_sha256: sha256
      })

      write_icon(name, :square, "png", bytes)

      encoded = URI.encode(name, &URI.char_unreserved?/1)
      conn = get(conn, "/adaptors/icons/#{encoded}/square-#{sha8}.png")

      assert conn.status == 200
      assert conn.resp_body == bytes
    end

    test "404 on unknown adaptor", %{conn: conn} do
      conn = get(conn, "/adaptors/icons/nope/square-aabbccdd.png")

      assert conn.status == 404
    end
  end

  # ---------------------------------------------------------------------------
  # AdaptorIconURL.build/3
  # ---------------------------------------------------------------------------

  describe "AdaptorIconURL.build/3" do
    test "returns nil when ext is nil" do
      meta = %{
        icon_square_ext: nil,
        icon_square_sha256: :crypto.hash(:sha256, "x"),
        icon_rectangle_ext: nil,
        icon_rectangle_sha256: nil
      }

      assert AdaptorIconURL.build("@openfn/language-http", meta, :square) == nil
    end

    test "returns nil when sha256 is nil" do
      meta = %{
        icon_square_ext: "png",
        icon_square_sha256: nil,
        icon_rectangle_ext: nil,
        icon_rectangle_sha256: nil
      }

      assert AdaptorIconURL.build("@openfn/language-http", meta, :square) == nil
    end

    test "URL-encodes slashes and @ in adaptor name" do
      sha256 = :crypto.hash(:sha256, "bytes")

      meta = %{
        icon_square_ext: "png",
        icon_square_sha256: sha256,
        icon_rectangle_ext: nil,
        icon_rectangle_sha256: nil
      }

      url = AdaptorIconURL.build("@openfn/language-http", meta, :square)

      refute is_nil(url)
      assert url =~ "%40openfn%2Flanguage-http"
    end

    test "sha8 in URL is always 8 lowercase hex chars" do
      sha256 = :crypto.hash(:sha256, "bytes")
      expected_sha8 = sha256 |> binary_part(0, 4) |> Base.encode16(case: :lower)

      meta = %{
        icon_square_ext: "png",
        icon_square_sha256: sha256,
        icon_rectangle_ext: nil,
        icon_rectangle_sha256: nil
      }

      url = AdaptorIconURL.build("@openfn/language-http", meta, :square)

      # sha8 is lowercase; percent-encoded chars use uppercase hex per RFC 3986
      assert url =~ "square-#{expected_sha8}.png"
      assert expected_sha8 == String.downcase(expected_sha8)
    end

    test "builds distinct URLs for square and rectangle shapes" do
      sq_sha = :crypto.hash(:sha256, "square bytes")
      rect_sha = :crypto.hash(:sha256, "rectangle bytes")

      meta = %{
        icon_square_ext: "png",
        icon_square_sha256: sq_sha,
        icon_rectangle_ext: "svg",
        icon_rectangle_sha256: rect_sha
      }

      sq_url = AdaptorIconURL.build("@openfn/language-http", meta, :square)
      rect_url = AdaptorIconURL.build("@openfn/language-http", meta, :rectangle)

      assert sq_url =~ "square-"
      assert rect_url =~ "rectangle-"
      assert sq_url =~ ".png"
      assert rect_url =~ ".svg"
      refute sq_url == rect_url
    end

    test "sha8 matches what show/2 computes from the same sha256" do
      bytes = "verify sha8 computation"
      sha256 = :crypto.hash(:sha256, bytes)

      meta = %{
        icon_square_ext: "png",
        icon_square_sha256: sha256,
        icon_rectangle_ext: nil,
        icon_rectangle_sha256: nil
      }

      url = AdaptorIconURL.build("name", meta, :square)

      assert sha8_from_bytes(bytes) in String.split(url, ["-", "."])
    end
  end
end
