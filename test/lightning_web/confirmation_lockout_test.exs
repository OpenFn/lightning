defmodule LightningWeb.ConfirmationLockoutTest do
  use ExUnit.Case, async: true

  alias LightningWeb.ConfirmationLockout

  describe "allowed_path?/1" do
    test "lets through the routes a locked-out account still needs" do
      for path_info <- [
            # The landing page. If this is false the fix is an outage.
            ["users", "confirm-required"],
            ["users", "send-confirmation-email"],
            ["users", "two-factor"],
            # Prefix matches, both carrying a token segment.
            ["users", "confirm", "sometoken"],
            ["profile", "confirm_email", "sometoken"],
            # List.starts_with?/2 is true for an equal list.
            ["users", "confirm"]
          ] do
        assert ConfirmationLockout.allowed_path?(path_info),
               "expected #{inspect(path_info)} to be allowed"
      end
    end

    test "refuses everything else, including the neighbours of the allowed prefixes" do
      for path_info <- [
            ["profile"],
            # PAT creation, and the backup-codes print page: the two routes a
            # ["profile"] prefix would have handed to a locked-out account.
            ["profile", "tokens"],
            ["profile", "auth", "backup_codes", "print"],
            ["projects"],
            []
          ] do
        refute ConfirmationLockout.allowed_path?(path_info),
               "expected #{inspect(path_info)} to be refused"
      end
    end
  end

  test "redirect_path/0 is the landing page, and allowed_path?/1 agrees" do
    assert ConfirmationLockout.redirect_path() == "/users/confirm-required"

    assert ConfirmationLockout.redirect_path()
           |> String.split("/", trim: true)
           |> ConfirmationLockout.allowed_path?()
  end

  test "the exemption list names exactly the routes that exist" do
    exempt_paths =
      LightningWeb.Router
      |> Phoenix.Router.routes()
      |> Enum.filter(&exempt?/1)
      |> Enum.map(& &1.path)
      |> Enum.uniq()
      |> Enum.sort()

    assert exempt_paths == [
             "/profile/confirm_email/:token",
             "/users/confirm",
             "/users/confirm-required",
             "/users/confirm/:token",
             "/users/send-confirmation-email",
             "/users/two-factor"
           ],
           "the lockout's exemption list and the router have drifted apart. A " <>
             "path that disappeared was renamed out from under its exemption, " <>
             "leaving locked-out users unable to reach it; a path that appeared " <>
             "was swept in by a prefix and is now exempt without anyone deciding " <>
             "it should be."
  end

  test "every exempt path stays reachable — a hooked LiveView would be exempt and unreachable at once" do
    exempt =
      LightningWeb.Router
      |> Phoenix.Router.routes()
      |> Enum.filter(&exempt?/1)

    assert exempt != []

    live_routes = Enum.filter(exempt, &live_route?/1)

    assert live_routes != [],
           "/users/confirm-required is exempt and is a LiveView, so recognising " <>
             "no exempt route as one means Phoenix's :phoenix_live_view route " <>
             "metadata has changed shape and this test inspects nothing."

    for %{verb: verb, path: path} = route <- live_routes do
      assert hook_free?(route),
             "#{verb} #{path} is exempt from the lockout but mounts under a " <>
               "live_session attaching LightningWeb.InitAssigns, which refuses " <>
               "a locked-out user at mount. Give it its own live_session " <>
               "without the hook."
    end
  end

  defp exempt?(%{path: path}) do
    path |> String.split("/", trim: true) |> ConfirmationLockout.allowed_path?()
  end

  defp live_route?(%{metadata: metadata}) do
    match?(
      %{phoenix_live_view: {_view, _action, _opts, _live_session}},
      metadata
    )
  end

  defp hook_free?(%{
         metadata: %{phoenix_live_view: {_view, _action, _opts, live_session}}
       }) do
    hooks = live_session |> Map.get(:extra, %{}) |> Map.get(:on_mount, [])

    not Enum.any?(hooks, &match?(%{id: {LightningWeb.InitAssigns, _}}, &1))
  end
end
