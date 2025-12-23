defmodule AguardiaWeb.ErrorJSON do
  @moduledoc """
  Renders error responses in JSON format.
  """

  def render(template, _assigns) do
    %{error: Phoenix.Controller.status_message_from_template(template)}
  end
end
