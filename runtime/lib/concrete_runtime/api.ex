defmodule ConcreteRuntime.API do
  @moduledoc """
  Thin HTTP surface for Godot / scripts (no Phoenix).
  """
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  get "/health" do
    send_json(conn, 200, %{ok: true, service: "concrete_runtime", beat: 1})
  end

  get "/v1/bootstrap" do
    send_json(conn, 200, ConcreteRuntime.Bootstrap.status())
  end

  post "/v1/principals" do
    name = conn.body_params["display_name"] || conn.body_params["name"]

    cond do
      not is_binary(name) or String.trim(name) == "" ->
        send_json(conn, 400, %{error: "display_name required"})

      true ->
        {:ok, principal} = ConcreteRuntime.Bootstrap.ensure_principal(String.trim(name))
        status = ConcreteRuntime.Bootstrap.status()

        send_json(conn, 200, %{
          principal: Map.take(principal, [:id, :display_name, :role]),
          has_bootstrap_capability:
            Enum.any?(status.principals, &(&1.id == principal.id and &1.has_bootstrap_capability))
        })
    end
  end

  post "/v1/capability/check" do
    principal_id = conn.body_params["principal_id"]
    action = conn.body_params["action"] || "mutate"

    cond do
      not is_binary(principal_id) ->
        send_json(conn, 400, %{error: "principal_id required"})

      true ->
        case ConcreteRuntime.Bootstrap.authorize(principal_id, action) do
          {:ok, :allowed, meaning} ->
            send_json(conn, 200, %{allowed: true, meaning: meaning, action: action})

          {:error, :capability_denied} ->
            send_json(conn, 403, %{allowed: false, error: "capability_denied", action: action})
        end
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
