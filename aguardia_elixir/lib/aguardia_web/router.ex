defmodule AguardiaWeb.Router do
  use AguardiaWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # API routes
  scope "/", AguardiaWeb do
    pipe_through(:api)

    get("/status", StatusController, :index)
  end

  # WebSocket routes are handled by Plug directly in the endpoint
  # These patterns match the Rust implementation:
  # - /ws/user/v1/:public_ed - User connections (login flow if not registered)
  # - /ws/device/v1/:public_ed - Device connections (must be pre-registered)

  # Note: The actual WebSocket upgrade is handled by AguardiaWeb.SocketPlug
  # which is plugged in the endpoint before the router
end
