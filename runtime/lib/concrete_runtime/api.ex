defmodule ConcreteRuntime.API do
  @moduledoc """
  Thin HTTP surface for Godot / scripts (no Phoenix).
  """
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug :fetch_query_params
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  get "/health" do
    ipfs = ConcreteRuntime.IPFS.ping()
    iota = ConcreteRuntime.Iota.ping()

    send_json(conn, 200, %{
      ok: true,
      service: "concrete_runtime",
      slice: "frozen",
      phase: 2,
      ipfs: ipfs == :ok,
      iota: iota == :ok,
      naming: ConcreteRuntime.IotaIdentity.status()
    })
  end

  get "/v1/identity/status" do
    send_json(conn, 200, ConcreteRuntime.IotaIdentity.status())
  end

  post "/v1/identity" do
    principal_id = conn.body_params["principal_id"]

    cond do
      not is_binary(principal_id) ->
        send_json(conn, 400, %{error: "principal_id required"})

      true ->
        case ConcreteRuntime.Bootstrap.authorize(principal_id, "mutate") do
          {:ok, _, _} ->
            case ConcreteRuntime.IotaIdentity.create_and_publish() do
              {:ok, created} ->
                send_json(conn, 201, created)

              {:error, :package_not_configured} ->
                send_json(conn, 503, %{error: "package_not_configured"})

              {:error, reason} ->
                send_json(conn, 502, %{error: "identity_create_failed", detail: inspect(reason)})
            end

          {:error, :capability_denied} ->
            send_json(conn, 403, %{error: "capability_denied"})
        end
    end
  end

  get "/v1/identity/resolve" do
    did = conn.query_params["did"]

    cond do
      not is_binary(did) ->
        send_json(conn, 400, %{error: "did query param required"})

      true ->
        case ConcreteRuntime.IotaIdentity.resolve(did) do
          {:ok, resolved} -> send_json(conn, 200, resolved)
          {:error, :bad_did} -> send_json(conn, 400, %{error: "bad_did"})
          {:error, reason} -> send_json(conn, 502, %{error: "resolve_failed", detail: inspect(reason)})
        end
    end
  end

  post "/v1/identity/head" do
    principal_id = conn.body_params["principal_id"]
    did = conn.body_params["did"]
    head_cid = conn.body_params["head_cid"]

    cond do
      not is_binary(principal_id) or not is_binary(did) or not is_binary(head_cid) ->
        send_json(conn, 400, %{error: "principal_id, did, head_cid required"})

      true ->
        case ConcreteRuntime.Bootstrap.authorize(principal_id, "mutate") do
          {:ok, _, _} ->
            case ConcreteRuntime.IotaIdentity.update_head(did, head_cid) do
              {:ok, resolved} -> send_json(conn, 200, resolved)
              {:error, :unknown_identity} -> send_json(conn, 404, %{error: "unknown_identity"})
              {:error, reason} -> send_json(conn, 502, %{error: "update_failed", detail: inspect(reason)})
            end

          {:error, :capability_denied} ->
            send_json(conn, 403, %{error: "capability_denied"})
        end
    end
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

  get "/v1/info_objects" do
    send_json(conn, 200, %{objects: ConcreteRuntime.InfoObjects.list()})
  end

  get "/v1/info_object" do
    did = conn.query_params["did"]

    cond do
      not is_binary(did) ->
        send_json(conn, 400, %{error: "did query param required"})

      true ->
        case ConcreteRuntime.InfoObjects.get(did) do
          {:ok, obj} -> send_json(conn, 200, obj)
          {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
          {:error, reason} -> send_json(conn, 502, %{error: inspect(reason)})
        end
    end
  end

  post "/v1/info_objects" do
    principal_id = conn.body_params["principal_id"]
    content = conn.body_params["content"]
    label = conn.body_params["label"]

    cond do
      not is_binary(principal_id) or not is_binary(content) ->
        send_json(conn, 400, %{error: "principal_id and content required"})

      true ->
        opts = if is_binary(label), do: [label: label], else: []

        case ConcreteRuntime.InfoObjects.create(principal_id, content, opts) do
          {:ok, obj} ->
            send_json(conn, 201, obj)

          {:error, :capability_denied} ->
            send_json(conn, 403, %{error: "capability_denied"})

          {:error, {:ipfs_unavailable, reason}} ->
            send_json(conn, 503, %{error: "ipfs_unavailable", detail: inspect(reason)})

          {:error, reason} ->
            send_json(conn, 500, %{error: inspect(reason)})
        end
    end
  end

  post "/v1/info_objects/advance" do
    principal_id = conn.body_params["principal_id"]
    did = conn.body_params["did"]
    content = conn.body_params["content"]
    message = conn.body_params["message"]

    cond do
      not is_binary(principal_id) or not is_binary(did) or not is_binary(content) ->
        send_json(conn, 400, %{error: "principal_id, did, and content required"})

      true ->
        opts = if is_binary(message), do: [message: message], else: []

        case ConcreteRuntime.InfoObjects.advance(principal_id, did, content, opts) do
          {:ok, obj} ->
            send_json(conn, 200, obj)

          {:error, :capability_denied} ->
            send_json(conn, 403, %{error: "capability_denied"})

          {:error, :not_found} ->
            send_json(conn, 404, %{error: "not_found"})

          {:error, {:ipfs_unavailable, reason}} ->
            send_json(conn, 503, %{error: "ipfs_unavailable", detail: inspect(reason)})

          {:error, reason} ->
            send_json(conn, 500, %{error: inspect(reason)})
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
