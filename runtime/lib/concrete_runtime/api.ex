defmodule ConcreteRuntime.API do
  @moduledoc """
  Thin HTTP surface for Godot / scripts (no Phoenix).
  """
  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(:fetch_query_params)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

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
    head_cid = conn.body_params["head_cid"]

    cond do
      not is_binary(principal_id) ->
        send_json(conn, 400, %{error: "principal_id required"})

      true ->
        case ConcreteRuntime.Bootstrap.authorize(principal_id, "mutate") do
          {:ok, _, _} ->
            opts = if is_binary(head_cid) and head_cid != "", do: [head_cid: head_cid], else: []

            case ConcreteRuntime.IotaIdentity.create_and_publish(opts) do
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
          {:ok, resolved} ->
            send_json(conn, 200, resolved)

          {:error, :bad_did} ->
            send_json(conn, 400, %{error: "bad_did"})

          {:error, reason} ->
            send_json(conn, 502, %{error: "resolve_failed", detail: inspect(reason)})
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
              {:ok, resolved} ->
                send_json(conn, 200, resolved)

              {:error, :unknown_identity} ->
                send_json(conn, 404, %{error: "unknown_identity"})

              {:error, :missing_controller_cap} ->
                send_json(conn, 409, %{error: "missing_controller_cap"})

              {:error, reason} ->
                send_json(conn, 502, %{error: "update_failed", detail: inspect(reason)})
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
        case ConcreteRuntime.Bootstrap.ensure_principal(String.trim(name)) do
          {:ok, principal} ->
            status = ConcreteRuntime.Bootstrap.status()

            send_json(conn, 200, %{
              principal: Map.take(principal, [:id, :display_name, :role, :public_key]),
              has_bootstrap_capability:
                Enum.any?(status.principals, &(&1.id == principal.id and &1.has_bootstrap_capability))
            })

          {:error, reason} ->
            send_json(conn, 502, %{error: "onboard_failed", detail: inspect(reason)})
        end
    end
  end

  get "/v1/directory" do
    actor_id = conn.query_params["principal_id"]

    cond do
      not is_binary(actor_id) ->
        send_json(conn, 400, %{error: "principal_id query param required"})

      true ->
        case ConcreteRuntime.UserDirectory.list(actor_id) do
          {:ok, records} ->
            send_json(conn, 200, %{kind: "data", records: records})

          {:error, :capability_denied} ->
            send_json(conn, 403, %{error: "capability_denied"})
        end
    end
  end

  get "/v1/directory/record" do
    actor_id = conn.query_params["principal_id"]
    did = conn.query_params["did"]

    cond do
      not is_binary(actor_id) or not is_binary(did) ->
        send_json(conn, 400, %{error: "principal_id and did query params required"})

      true ->
        case ConcreteRuntime.UserDirectory.get(actor_id, did) do
          {:ok, rec} ->
            send_json(conn, 200, rec)

          {:error, :capability_denied} ->
            send_json(conn, 403, %{error: "capability_denied"})

          {:error, :not_found} ->
            send_json(conn, 404, %{error: "not_found"})

          {:error, {:ipfs_unavailable, reason}} ->
            send_json(conn, 503, %{error: "ipfs_unavailable", detail: inspect(reason)})

          {:error, reason} ->
            send_iota_or_generic_error(conn, reason)
        end
    end
  end

  post "/v1/directory" do
    actor_id = conn.body_params["principal_id"]
    username = conn.body_params["username"] || conn.body_params["display_name"]

    cond do
      not is_binary(actor_id) or not is_binary(username) or String.trim(username) == "" ->
        send_json(conn, 400, %{error: "principal_id and username required"})

      true ->
        case ConcreteRuntime.UserDirectory.publish(actor_id, String.trim(username)) do
          {:ok, rec} ->
            send_json(conn, 201, rec)

          {:error, :capability_denied} ->
            send_json(conn, 403, %{error: "capability_denied"})

          {:error, :unknown_principal} ->
            send_json(conn, 404, %{error: "unknown_principal"})

          {:error, {:ipfs_unavailable, reason}} ->
            send_json(conn, 503, %{error: "ipfs_unavailable", detail: inspect(reason)})

          {:error, reason} ->
            send_iota_or_generic_error(conn, reason)
        end
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
          {:error, reason} -> send_iota_or_generic_error(conn, reason)
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
            send_iota_or_generic_error(conn, reason)
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
            send_iota_or_generic_error(conn, reason)
        end
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp send_iota_or_generic_error(conn, reason) do
    case reason do
      {:iota_identity_create_failed, detail} ->
        send_json(conn, 502, %{error: "iota_identity_create_failed", detail: inspect(detail)})

      {:iota_identity_update_failed, detail} ->
        send_json(conn, 502, %{error: "iota_identity_update_failed", detail: inspect(detail)})

      :iota_did_missing ->
        send_json(conn, 409, %{error: "iota_did_missing"})

      {:iota_head_mismatch, expected, got} ->
        send_json(conn, 502, %{
          error: "iota_head_mismatch",
          expected: expected,
          got: inspect(got)
        })

      {:iota_head_not_on_chain, source} ->
        send_json(conn, 502, %{error: "iota_head_not_on_chain", source: source})

      :iota_head_unconfirmed ->
        send_json(conn, 502, %{error: "iota_head_unconfirmed"})

      {:iota_resolve_failed, detail} ->
        send_json(conn, 502, %{error: "iota_resolve_failed", detail: inspect(detail)})

      other ->
        send_json(conn, 500, %{error: inspect(other)})
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
