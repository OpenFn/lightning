defmodule Lightning.InstallAdaptorIconsTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias LightningWeb.Router.Helpers, as: Routes
  alias Mix.Tasks.Lightning.InstallAdaptorIcons

  @icons_path Application.compile_env(:lightning, :adaptor_icons_path)
              |> Path.expand()
  @adaptors_tar_url "https://github.com/OpenFn/adaptors/archive/refs/heads/main.tar.gz"

  @http_tar_path Path.expand("../fixtures/adaptors/http.tar.gz", __DIR__)
  @dhis2_tar_path Path.expand("../fixtures/adaptors/dhis2.tar.gz", __DIR__)
  @http_dhis2_tar_path Path.expand(
                         "../fixtures/adaptors/http_dhis2.tar.gz",
                         __DIR__
                       )
  setup do
    File.mkdir_p(@icons_path)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> File.rm_rf!(@icons_path) end)
  end

  @tag :capture_log
  test "generates http adaptor icons correctly" do
    mock(fn
      %{method: :get, url: @adaptors_tar_url} ->
        %Tesla.Env{status: 200, body: File.read!(@http_tar_path)}
    end)

    assert File.ls!(@icons_path) == []
    InstallAdaptorIcons.run([])

    assert_receive {:mix_shell, :info, [msg]}
    assert msg =~ "Adaptor icons installed successfully. Manifest saved at: "

    icons = File.ls!(@icons_path)
    assert length(icons) == 2
    assert "http-square.png" in icons
    assert "adaptor_icons.json" in icons

    assert File.read!(Path.join(@icons_path, "adaptor_icons.json")) ==
             Jason.encode!(%{
               http: %{
                 square:
                   Routes.static_path(
                     LightningWeb.Endpoint,
                     "/images/adaptors/http-square.png"
                   )
               }
             })
  end

  test "generates dhis2 adaptor icons correctly" do
    mock(fn
      %{method: :get, url: @adaptors_tar_url} ->
        %Tesla.Env{status: 200, body: File.read!(@dhis2_tar_path)}
    end)

    assert File.ls!(@icons_path) == []
    InstallAdaptorIcons.run([])

    assert_receive {:mix_shell, :info, [msg]}
    assert msg =~ "Adaptor icons installed successfully. Manifest saved at: "

    icons = File.ls!(@icons_path)
    assert length(icons) == 2
    assert "dhis2-square.png" in icons
    assert "adaptor_icons.json" in icons

    assert File.read!(Path.join(@icons_path, "adaptor_icons.json")) ==
             Jason.encode!(%{
               dhis2: %{
                 square:
                   Routes.static_path(
                     LightningWeb.Endpoint,
                     "/images/adaptors/dhis2-square.png"
                   )
               }
             })
  end

  @tag :capture_log
  test "generates both dhis2 and http adaptor icons correctly" do
    mock(fn
      %{method: :get, url: @adaptors_tar_url} ->
        %Tesla.Env{status: 200, body: File.read!(@http_dhis2_tar_path)}
    end)

    assert File.ls!(@icons_path) == []
    InstallAdaptorIcons.run([])

    assert_receive {:mix_shell, :info, [msg]}
    assert msg =~ "Adaptor icons installed successfully. Manifest saved at: "

    icons = File.ls!(@icons_path)
    assert length(icons) == 3
    assert "dhis2-square.png" in icons
    assert "http-square.png" in icons
    assert "adaptor_icons.json" in icons

    expected_content = %{
      dhis2: %{
        square:
          Routes.static_path(
            LightningWeb.Endpoint,
            "/images/adaptors/dhis2-square.png"
          )
      },
      http: %{
        square:
          Routes.static_path(
            LightningWeb.Endpoint,
            "/images/adaptors/http-square.png"
          )
      }
    }

    assert File.read!(Path.join(@icons_path, "adaptor_icons.json"))
           |> Jason.decode!(keys: :atoms) == expected_content
  end
end
