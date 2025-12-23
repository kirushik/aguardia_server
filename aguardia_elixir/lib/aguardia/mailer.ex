defmodule Aguardia.Mailer do
  @moduledoc """
  Email delivery using Swoosh.

  Sends verification codes and other transactional emails.
  """
  use Swoosh.Mailer, otp_app: :aguardia

  alias Swoosh.Email

  require Logger

  @doc """
  Send an email with the given parameters.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec send_email(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_email(to, subject, html_body) do
    from = get_from_address()

    email =
      Email.new()
      |> Email.to(to)
      |> Email.from(from)
      |> Email.subject(subject)
      |> Email.html_body(html_body)

    case deliver(email) do
      {:ok, _} ->
        Logger.info("Email sent to #{to}: #{subject}")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to send email to #{to}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Send a login verification code email.
  """
  @spec send_login_code(String.t(), String.t()) :: :ok | {:error, term()}
  def send_login_code(to, code) do
    html_body = """
    <p>Your Aguardia login code is: <b>#{code}</b></p>
    <p>This code will expire in #{div(Application.get_env(:aguardia, :email_code_expired_sec, 600), 60)} minutes.</p>
    """

    send_email(to, "Aguardia login code", html_body)
  end

  # Get the from address from configuration
  defp get_from_address do
    config = Application.get_env(:aguardia, Aguardia.Mailer, [])
    Keyword.get(config, :from, "noreply@aguardia.local")
  end
end
