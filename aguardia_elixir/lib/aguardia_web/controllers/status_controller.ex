defmodule AguardiaWeb.StatusController do
  @moduledoc """
  Controller for the /status endpoint.

  Returns server status information including uptime, public keys,
  and connected WebSocket count.
  """
  use AguardiaWeb, :controller

  alias Aguardia.ServerState

  @doc """
  GET /status

  Returns JSON with server status information matching the Rust implementation.
  """
  def index(conn, _params) do
    server_info = ServerState.info()
    websocket_count = get_websocket_count()
    loglevel = get_loglevel()

    status = %{
      started_at: server_info.started_at,
      uptime_minutes: server_info.uptime_minutes,
      uptime_days: server_info.uptime_days,
      public_x: server_info.public_x,
      public_ed: server_info.public_ed,
      loglevel: loglevel,
      version: version(),
      websockets: websocket_count,
      status: "OK"
    }

    json(conn, status)
  end

  # Get count of connected WebSockets from Registry
  defp get_websocket_count do
    Registry.count(Aguardia.SessionRegistry)
  end

  # Get configured log level as string
  defp get_loglevel do
    case Logger.level() do
      :debug -> "DEBUG"
      :info -> "INFO"
      :warning -> "WARN"
      :error -> "ERROR"
      _ -> "INFO"
    end
  end

  # Get application version
  defp version do
    Application.spec(:aguardia, :vsn) |> to_string()
  end
end
