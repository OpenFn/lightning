defmodule LightningWeb.CredentialLive.OAuthErrorFormatter do
  @moduledoc """
  Provides human-readable error messages for OAuth-related errors.

  This module centralizes all error message formatting to ensure
  consistent, helpful user feedback across the OAuth flow.
  """

  alias Lightning.Credentials.OauthValidation

  defmodule ErrorDisplay do
    @moduledoc """
    Structured error display information
    """
    defstruct [:header, :message, :details, :action_text, :severity]

    @type severity :: :error | :warning | :info

    @type t :: %__MODULE__{
            header: String.t(),
            message: String.t(),
            details: String.t() | nil,
            action_text: String.t(),
            severity: severity()
          }
  end

  @doc """
  Formats an OAuth validation error into user-friendly display information.

  ## Parameters
    - error: The error to format (OauthValidation.Error or other error types)
    - provider: The OAuth provider name (e.g., "Google", "GitHub")

  ## Returns
    An ErrorDisplay struct with formatted error information
  """
  @spec format_error(any(), String.t() | nil) :: ErrorDisplay.t()

  def format_error(%OauthValidation.Error{type: :invalid_token_format}, provider) do
    %ErrorDisplay{
      header: "Invalid Response Format",
      message:
        "The authorization response from #{provider || "the provider"} is in an unexpected format. This might be a temporary issue with their service.",
      details: nil,
      action_text: "Try Again",
      severity: :error
    }
  end

  def format_error(%OauthValidation.Error{type: :missing_access_token}, provider) do
    %ErrorDisplay{
      header: "Incomplete Authorization",
      message:
        "The authorization didn't complete successfully. #{provider || "The provider"} didn't provide the required access token.",
      details:
        "Make sure you completed the authorization process and granted access.",
      action_text: "Authorize Again",
      severity: :error
    }
  end

  def format_error(%OauthValidation.Error{type: :invalid_access_token}, provider) do
    %ErrorDisplay{
      header: "Invalid Access Token",
      message:
        "The access token received from #{provider || "the provider"} is invalid.",
      details: "This might indicate an issue with the authorization process.",
      action_text: "Reauthorize",
      severity: :error
    }
  end

  def format_error(
        %OauthValidation.Error{type: :missing_refresh_token},
        provider
      ) do
    %ErrorDisplay{
      header: "Account Already Connected",
      message:
        "This #{provider || "provider"} account is already connected to OpenFn.",
      details:
        "Try one of these options:\n" <>
          "1. Use your existing credential for this account\n" <>
          "2. Click 'Revoke and Reauthorize' below\n" <>
          "3. If that doesn't work, go to your #{provider || "provider"} account settings and remove OpenFn from connected apps, then try again",
      action_text: "Revoke and Reauthorize",
      severity: :warning
    }
  end

  def format_error(
        %OauthValidation.Error{type: :invalid_refresh_token},
        provider
      ) do
    %ErrorDisplay{
      header: "Invalid Refresh Token",
      message:
        "The refresh token from #{provider || "the provider"} is invalid.",
      details: "You'll need to reauthorize to continue using this credential.",
      action_text: "Reauthorize",
      severity: :error
    }
  end

  def format_error(%OauthValidation.Error{type: :missing_token_type}, provider) do
    %ErrorDisplay{
      header: "Incomplete Token Information",
      message: "#{provider || "The provider"} didn't specify the token type.",
      details:
        "This might indicate a configuration issue with the OAuth provider.",
      action_text: "Try Again",
      severity: :error
    }
  end

  def format_error(
        %OauthValidation.Error{type: :unsupported_token_type, details: details},
        provider
      ) do
    token_type = get_in(details, [:token_type]) || "unknown"

    %ErrorDisplay{
      header: "Unsupported Token Type",
      message:
        "#{provider || "The provider"} returned an unsupported token type: '#{token_type}'.",
      details:
        "We only support 'Bearer' tokens. This might be a configuration issue.",
      action_text: "Contact Support",
      severity: :error
    }
  end

  def format_error(%OauthValidation.Error{type: :missing_scope}, provider) do
    %ErrorDisplay{
      header: "No Permissions Granted",
      message:
        "You didn't grant any permissions for #{provider || "this integration"}.",
      details:
        "At least one permission is required for the credential to work properly.",
      action_text: "Authorize with Permissions",
      severity: :error
    }
  end

  def format_error(
        %OauthValidation.Error{type: :missing_scopes, details: details},
        provider
      ) do
    missing_scopes = get_in(details, [:missing_scopes]) || []
    scope_list = format_scope_list(missing_scopes)

    %ErrorDisplay{
      header: "Missing Required Permissions",
      message:
        "You didn't grant all the required permissions for #{provider || "this integration"}.",
      details:
        "Missing permissions: #{scope_list}. Please make sure to check all required permissions when authorizing.",
      action_text: "Reauthorize with All Permissions",
      severity: :error
    }
  end

  def format_error(
        %OauthValidation.Error{type: :invalid_oauth_response},
        provider
      ) do
    %ErrorDisplay{
      header: "Invalid Permission Format",
      message:
        "#{provider || "The provider"} returned permissions in an unexpected format.",
      details: "This might be a temporary issue with their service.",
      action_text: "Try Again",
      severity: :error
    }
  end

  def format_error(%OauthValidation.Error{type: :missing_expiration}, provider) do
    %ErrorDisplay{
      header: "Missing Token Expiration",
      message:
        "#{provider || "The provider"} didn't specify when the access token expires.",
      details:
        "This might cause issues with automatic token refresh, but your credential should still work.",
      action_text: "Continue Anyway",
      severity: :warning
    }
  end

  def format_error(
        %OauthValidation.Error{type: :invalid_expiration, message: message},
        provider
      ) do
    details =
      cond do
        String.contains?(message, "too far in the past") ->
          "The token appears to have already expired. You'll need to authorize again."

        String.contains?(message, "too far in the future") ->
          "The token expiration date seems incorrect (too far in the future)."

        String.contains?(message, "must be greater than 0") ->
          "The token has an invalid expiration time."

        true ->
          nil
      end

    %ErrorDisplay{
      header: "Invalid Token Expiration",
      message:
        "The token expiration from #{provider || "the provider"} is invalid.",
      details: details,
      action_text: "Reauthorize",
      severity: :error
    }
  end

  def format_error({:code_exchange_failed, _details}, provider) do
    %ErrorDisplay{
      header: "Authentication Interrupted",
      message:
        "The authentication process with #{provider || "the provider"} was interrupted.",
      details:
        "This can happen if you closed the authorization window or denied access.",
      action_text: "Start Over",
      severity: :error
    }
  end

  def format_error({:http_error, %{status: 401}}, provider) do
    %ErrorDisplay{
      header: "Authorization Expired",
      message:
        "Your authorization with #{provider || "the provider"} has expired or was revoked.",
      details: "Please sign in again to continue.",
      action_text: "Sign In Again",
      severity: :error
    }
  end

  def format_error({:http_error, %{status: 403}}, provider) do
    %ErrorDisplay{
      header: "Access Denied",
      message: "#{provider || "The provider"} denied access to your account.",
      details:
        "Make sure you have the necessary permissions in your #{provider || "provider"} account.",
      action_text: "Check Account & Try Again",
      severity: :error
    }
  end

  def format_error({:http_error, %{status: 429}}, provider) do
    %ErrorDisplay{
      header: "Too Many Requests",
      message: "We've made too many requests to #{provider || "the provider"}.",
      details: "Please wait a moment before trying again.",
      action_text: "Try Again in 30 Seconds",
      severity: :warning
    }
  end

  def format_error({:http_error, %{status: status}}, provider)
      when status >= 500 do
    %ErrorDisplay{
      header: "#{provider || "Provider"} is Having Issues",
      message:
        "#{provider || "The provider"} is experiencing technical difficulties.",
      details: "This is temporary - please try again in a few minutes.",
      action_text: "Try Again Later",
      severity: :warning
    }
  end

  def format_error({:http_error, %{error: "network_error"}}, provider) do
    %ErrorDisplay{
      header: "Connection Problem",
      message: "We couldn't connect to #{provider || "the provider"}.",
      details: "Please check your internet connection and try again.",
      action_text: "Try Again",
      severity: :error
    }
  end

  def format_error({:refresh_failed, %{status: 401}}, provider) do
    %ErrorDisplay{
      header: "Session Expired",
      message: "Your #{provider || "provider"} session has expired.",
      details: "Please sign in again to continue using this credential.",
      action_text: "Sign In Again",
      severity: :error
    }
  end

  def format_error({:refresh_failed, %{error: "invalid_grant"}}, provider) do
    %ErrorDisplay{
      header: "Refresh Token Revoked",
      message:
        "Your refresh token has been revoked by #{provider || "the provider"}.",
      details:
        "This might happen if you changed your password or revoked access to this application.",
      action_text: "Reauthorize",
      severity: :error
    }
  end

  def format_error({:userinfo_failed, _details}, provider) do
    %ErrorDisplay{
      header: "Profile Information Unavailable",
      message:
        "We successfully authenticated with #{provider || "the provider"} but couldn't fetch your profile information.",
      details: "Your credential will still work normally.",
      action_text: "Continue",
      severity: :info
    }
  end

  def format_error({:invalid_credential, details}, _provider) do
    %ErrorDisplay{
      header: "Invalid Credential Information",
      message: "The credential information is incomplete or invalid.",
      details: format_changeset_errors(details),
      action_text: "Fix Errors",
      severity: :error
    }
  end

  def format_error({:task_crashed, _reason}, provider) do
    %ErrorDisplay{
      header: "Unexpected Error",
      message:
        "An unexpected error occurred while communicating with #{provider || "the provider"}.",
      details: "Our team has been notified. Please try again.",
      action_text: "Try Again",
      severity: :error
    }
  end

  def format_error(:scope_changed, provider) do
    %ErrorDisplay{
      header: "Reauthentication Required",
      message: "You've changed the permissions for this credential.",
      details:
        "Please reauthenticate with #{provider || "the provider"} to apply these changes.",
      action_text: "Reauthenticate",
      severity: :warning
    }
  end

  def format_error(_error, provider) do
    %ErrorDisplay{
      header: "OAuth Error",
      message:
        "An error occurred during authentication with #{provider || "the provider"}.",
      details: "Please try again. If the problem persists, contact support.",
      action_text: "Try Again",
      severity: :error
    }
  end

  @spec format_scope_list([String.t()]) :: String.t()
  defp format_scope_list([]), do: "none"
  defp format_scope_list([scope]), do: "'#{scope}'"

  defp format_scope_list(scopes) do
    Enum.map_join(scopes, ", ", &"'#{&1}'")
  end

  defp format_changeset_errors(errors) when is_list(errors) do
    Enum.map_join(errors, ", ", fn {field, {message, _}} ->
      "#{field}: #{message}"
    end)
  end

  defp format_changeset_errors(_), do: nil

  @doc """
  Determines the appropriate alert type for Phoenix components based on severity.
  """
  @spec alert_type(ErrorDisplay.t()) :: String.t()
  def alert_type(%ErrorDisplay{severity: :error}), do: "danger"
  def alert_type(%ErrorDisplay{severity: :warning}), do: "warning"
  def alert_type(%ErrorDisplay{severity: :info}), do: "info"
end
