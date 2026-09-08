defmodule ConcreteRuntime.IotaIdentity do
  @moduledoc """
  Phase 2: on-ledger IOTA Identity (ADR 0002 / 0006).

  Package publish + Identity::new via lab scripts; resolve via JSON-RPC.
  Head CID is tracked in OTP (`iota_heads.json`) until document encode/update
  lands with a typed Identity SDK.
  """

  @pkg_file_rel ["lab", "data", "iota", "identity_pkg_id.txt"]
  @heads_file "iota_heads.json"

  def status do
    pkg = package_id()
    iota_ok = ConcreteRuntime.Iota.ping() == :ok
    configured = is_binary(pkg) and pkg != ""

    %{
      naming_mode: if(configured, do: "did:iota+lab", else: "did:concrete:lab"),
      iota_identity: %{
        target_method: "did:iota",
        package_id: pkg,
        package_configured: configured,
        rpc_reachable: iota_ok,
        publish_ready: configured and iota_ok,
        heads_tracked: map_size(load_heads()),
        note:
          if configured do
            "Identity package on localnet; create via Identity::new; head CID tracked in OTP until on-chain doc update"
          else
            "Run ./scripts/identity-publish.sh then restart node-up"
          end
      }
    }
  end

  def package_id do
    case System.get_env("IOTA_IDENTITY_PKG_ID") do
      id when is_binary(id) and id != "" ->
        String.trim(id)

      _ ->
        path = Path.join([repo_root() | @pkg_file_rel])

        case File.read(path) do
          {:ok, body} -> String.trim(body)
          _ -> nil
        end
    end
  end

  @doc """
  Publish a new Identity object (empty doc). Requires package id + lab iota image.
  """
  def create_and_publish(_opts \\ []) do
    script = Path.join(repo_root(), "scripts/identity-create.sh")

    cond do
      is_nil(package_id()) or package_id() == "" ->
        {:error, :package_not_configured}

      not File.exists?(script) ->
        {:error, :missing_identity_create_script}

      true ->
        case System.cmd(script, [], stderr_to_stdout: true, cd: repo_root()) do
          {out, 0} ->
            case Jason.decode(String.trim(out)) do
              {:ok, %{"did" => did, "identity_object_id" => obj} = map}
              when is_binary(did) and is_binary(obj) ->
                put_head(did, %{
                  "identity_object_id" => obj,
                  "head_cid" => nil,
                  "package_id" => map["package_id"],
                  "chain_id" => map["chain_id"],
                  "digest" => map["digest"]
                })

                {:ok,
                 %{
                   did: did,
                   identity_object_id: obj,
                   package_id: map["package_id"],
                   chain_id: map["chain_id"],
                   digest: map["digest"]
                 }}

              {:ok, map} ->
                {:error, {:bad_create_response, map}}

              {:error, err} ->
                {:error, {:json, err, out}}
            end

          {out, code} ->
            {:error, {:identity_create_failed, code, out}}
        end
    end
  end

  def resolve(did) when is_binary(did) do
    with {:ok, object_id} <- object_id_from_did(did),
         {:ok, obj} <- ConcreteRuntime.Iota.get_object(object_id) do
      meta = Map.get(load_heads(), did, %{})

      {:ok,
       %{
         did: did,
         identity_object_id: object_id,
         on_chain: simplify_object(obj),
         head_cid: meta["head_cid"],
         package_id: package_id()
       }}
    end
  end

  def update_head(did, head_cid) when is_binary(did) and is_binary(head_cid) do
    case Map.get(load_heads(), did) do
      nil ->
        {:error, :unknown_identity}

      meta ->
        put_head(did, Map.put(meta, "head_cid", head_cid))
        resolve(did)
    end
  end

  defp simplify_object(obj) when is_map(obj) do
    %{
      object_id: obj["objectId"],
      version: obj["version"],
      type: obj["type"],
      deleted: get_in(obj, ["content", "fields", "deleted"]),
      created: get_in(obj, ["content", "fields", "created"]),
      updated: get_in(obj, ["content", "fields", "updated"])
    }
  end

  defp object_id_from_did("did:iota:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [_chain, obj] -> {:ok, obj}
      _ -> {:error, :bad_did}
    end
  end

  defp object_id_from_did(_), do: {:error, :bad_did}

  defp load_heads do
    path = heads_path()

    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp put_head(did, meta) do
    path = heads_path()
    File.mkdir_p!(Path.dirname(path))
    next = Map.put(load_heads(), did, meta)
    File.write!(path, Jason.encode!(next, pretty: true))
    :ok
  end

  defp heads_path do
    data = System.get_env("CONCRETE_DATA_DIR") || Path.join(repo_root(), "lab/data/node")
    Path.join(data, @heads_file)
  end

  defp repo_root do
    Path.expand(Path.join([__DIR__, "..", "..", ".."]))
  end
end
