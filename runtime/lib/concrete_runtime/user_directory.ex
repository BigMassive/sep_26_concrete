defmodule ConcreteRuntime.UserDirectory do
  @moduledoc """
  ADR 0008 stage 3: `{public_key, username}` as **data** on IPFS, named with a
  DID. Not an info object — no commit graph, facets, or per-object ACLs.
  Reads and writes are gated by the bootstrap capability.
  """
  use GenServer

  @blob_type "ConcreteUserDirectory"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list(actor_id) when is_binary(actor_id) do
    GenServer.call(__MODULE__, {:list, actor_id})
  end

  def get(actor_id, did) when is_binary(actor_id) and is_binary(did) do
    GenServer.call(__MODULE__, {:get, actor_id, did}, 30_000)
  end

  def publish(actor_id, username) when is_binary(actor_id) and is_binary(username) do
    GenServer.call(__MODULE__, {:publish, actor_id, username}, 60_000)
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "user_directory.json")
    {:ok, %{path: path, records: load(path)}}
  end

  @impl true
  def handle_call({:list, actor_id}, _from, s) do
    case ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate") do
      {:ok, _, _} -> {:reply, {:ok, Enum.map(s.records, &public/1)}, s}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:get, actor_id, did}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate"),
         rec when not is_nil(rec) <- find_record(s.records, did),
         {:ok, public} <- hydrate(rec) do
      {:reply, {:ok, public}, s}
    else
      nil -> {:reply, {:error, :not_found}, s}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:publish, actor_id, username}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate"),
         {:ok, subject} <- lookup_principal(username),
         :ok <- require_ipfs() do
      case find_by_public_key(s.records, subject.id) do
        rec when not is_nil(rec) ->
          {:reply, {:ok, public(rec)}, s}

        nil ->
          case write_record(subject) do
            {:ok, rec} ->
              records = s.records ++ [rec]
              persist!(s.path, records)
              {:reply, {:ok, public(rec)}, %{s | records: records}}

            {:error, _} = err ->
              {:reply, err, s}
          end
      end
    else
      {:error, _} = err -> {:reply, err, s}
    end
  end

  defp write_record(subject) do
    blob = %{
      "type" => @blob_type,
      "kind" => "data",
      "public_key" => subject.id,
      "username" => subject.display_name
    }

    with {:ok, cid} <- ipfs().add_json(blob),
         {:ok, rec} <- attach_name(cid, subject) do
      {:ok, rec}
    end
  end

  defp attach_name(cid, subject) do
    mod = identity_mod()

    if mod.configured?() do
      case mod.create_and_publish(head_cid: cid) do
        {:ok, created} ->
          did = created.did

          with :ok <- mod.require_on_chain_head(did, cid) do
            {:ok,
             %{
               did: did,
               iota_did: did,
               cid: cid,
               public_key: subject.id,
               username: subject.display_name,
               identity_object_id: created.identity_object_id,
               controller_cap_id: Map.get(created, :controller_cap_id),
               kind: "data"
             }}
          end

        {:error, reason} ->
          {:error, {:iota_identity_create_failed, reason}}
      end
    else
      did = "did:concrete:lab:user:#{short_id()}"

      {:ok,
       %{
         did: did,
         iota_did: nil,
         cid: cid,
         public_key: subject.id,
         username: subject.display_name,
         kind: "data"
       }}
    end
  end

  defp hydrate(rec) do
    with {:ok, cid, source} <- cid_for_read(rec),
         {:ok, blob} <- ipfs().cat_json(cid) do
      if blob["type"] == @blob_type do
        {:ok,
         public(rec)
         |> Map.put(:cid, cid)
         |> Map.put(:cid_source, source)
         |> Map.put(:public_key, blob["public_key"] || rec.public_key)
         |> Map.put(:username, blob["username"] || rec.username)}
      else
        {:error, {:not_directory_blob, blob["type"]}}
      end
    end
  end

  defp cid_for_read(rec) do
    case iota_name(rec) do
      did when is_binary(did) and did != "" ->
        case identity_mod().resolve(did) do
          {:ok, resolved} ->
            case ConcreteRuntime.IotaIdentity.on_chain_head_cid(resolved) do
              {:ok, cid} -> {:ok, cid, "on_chain"}
              {:error, _} = err -> err
            end

          {:error, reason} ->
            {:error, {:iota_resolve_failed, reason}}
        end

      _ ->
        {:ok, rec.cid, "otp_index"}
    end
  end

  defp lookup_principal(username) do
    status = ConcreteRuntime.Bootstrap.status()

    case Enum.find(status.principals, &(&1.display_name == username)) do
      nil -> {:error, :unknown_principal}
      p -> {:ok, p}
    end
  end

  defp find_record(records, did) do
    Enum.find(records, fn r -> r.did == did or iota_name(r) == did end)
  end

  defp find_by_public_key(records, pk) do
    Enum.find(records, &(&1.public_key == pk))
  end

  defp public(rec) do
    %{
      did: rec.did,
      iota_did: iota_name(rec),
      cid: rec.cid,
      public_key: rec.public_key,
      username: rec.username,
      kind: "data",
      identity_object_id: Map.get(rec, :identity_object_id),
      controller_cap_id: Map.get(rec, :controller_cap_id)
    }
  end

  defp iota_name(rec) do
    case Map.get(rec, :iota_did) do
      did when is_binary(did) and did != "" -> did
      _ ->
        did = Map.get(rec, :did)

        if is_binary(did) and String.starts_with?(did, "did:iota:"), do: did, else: nil
    end
  end

  defp require_ipfs do
    case ipfs().ping() do
      :ok -> :ok
      {:error, reason} -> {:error, {:ipfs_unavailable, reason}}
    end
  end

  defp identity_mod do
    Application.get_env(:concrete_runtime, :iota_identity, ConcreteRuntime.IotaIdentity)
  end

  defp ipfs do
    Application.get_env(:concrete_runtime, :ipfs, ConcreteRuntime.IPFS)
  end

  defp load(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&from_json/1)
    else
      []
    end
  end

  defp persist!(path, records) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(Enum.map(records, &to_json/1), pretty: true))
  end

  defp to_json(r) do
    %{
      "did" => r.did,
      "iota_did" => iota_name(r),
      "cid" => r.cid,
      "public_key" => r.public_key,
      "username" => r.username,
      "kind" => "data",
      "identity_object_id" => Map.get(r, :identity_object_id),
      "controller_cap_id" => Map.get(r, :controller_cap_id)
    }
  end

  defp from_json(m) do
    %{
      did: m["did"],
      iota_did: m["iota_did"],
      cid: m["cid"],
      public_key: m["public_key"],
      username: m["username"],
      kind: "data",
      identity_object_id: m["identity_object_id"],
      controller_cap_id: m["controller_cap_id"]
    }
  end

  defp short_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
