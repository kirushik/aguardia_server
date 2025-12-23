defmodule CORSPlug do
  @moduledoc """
  Simple CORS plug that allows all origins (matching Rust implementation).
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "*")
    |> put_resp_header("access-control-max-age", "3600")
    |> handle_preflight()
  end

  defp handle_preflight(%{method: "OPTIONS"} = conn) do
    conn
    |> send_resp(204, "")
    |> halt()
  end

  defp handle_preflight(conn), do: conn
end

defmodule AguardiaWeb.SocketPlug do
  @moduledoc """
  Plug to handle WebSocket upgrade requests for the Aguardia protocol.

  Routes:
  - /ws/user/v1/:public_ed - User connections (with login flow)
  - /ws/device/v1/:public_ed - Device connections (must be pre-registered)
  """
  import Plug.Conn

  alias Aguardia.Crypto

  def init(opts), do: opts

  def call(%{request_path: "/ws/user/v1/" <> public_ed} = conn, _opts) do
    handle_ws_upgrade(conn, public_ed, :user)
  end

  def call(%{request_path: "/ws/device/v1/" <> public_ed} = conn, _opts) do
    handle_ws_upgrade(conn, public_ed, :device)
  end

  def call(conn, _opts), do: conn

  defp handle_ws_upgrade(conn, public_ed_hex, mode) do
    case Crypto.hex_decode32(public_ed_hex) do
      {:ok, public_ed} ->
        state = %AguardiaWeb.SocketHandler.State{
          mode: mode,
          public_ed: public_ed,
          login_stage: 0,
          last_activity: System.monotonic_time(:second)
        }

        conn
        |> WebSockAdapter.upgrade(AguardiaWeb.SocketHandler, state, timeout: 60_000)
        |> halt()

      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid public_ed"}))
        |> halt()
    end
  end
end

defmodule AguardiaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :aguardia

  @session_options [
    store: :cookie,
    key: "_aguardia_key",
    signing_salt: "aguardia_salt",
    same_site: "Lax"
  ]

  # WebSocket upgrade plug - must come before other processing
  plug(AguardiaWeb.SocketPlug)

  # Serve static files from configured site_dir
  plug(Plug.Static,
    at: "/",
    from: {:aguardia, "priv/static"},
    gzip: false,
    only: AguardiaWeb.static_paths()
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)

  # CORS - allow all origins (matching Rust implementation)
  plug(CORSPlug)

  plug(AguardiaWeb.Router)

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
end
