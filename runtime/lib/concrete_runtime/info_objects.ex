defmodule ConcreteRuntime.InfoObjects do
  @moduledoc """
  Named info objects: DID → IPFS commit head, gated by bootstrap capability.

  Stage A (ADR 0007): if the Identity package is configured, create/advance
  must land the new head on-chain or fail. Stage B: GET hydrates from
  Identity ContentHead → IPFS when the object has an iota DID; OTP
  `head_cid` is cache only. Without a package / iota DID, keep the
  Phase 1 lab DID path (`did:concrete:lab:<id>`).
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list, do: GenServer.call(__MODULE__, :list)
  def get(did), do: GenServer.call(__MODULE__, {:get, did}, 30_000)

  def create(principal_id, content, opts \\ []) do
    GenServer.call(__MODULE__, {:create, principal_id, content, opts}, 60_000)
  end

  def advance(principal_id, did, content, opts \\ []) do
    GenServer.call(__MODULE__, {:advance, principal_id, did, content, opts}, 60_000)
  end

  @impl true
  def init(opts) do
    data_dir = Keyword.fetch!(opts, :data_dir)
    path = Path.join(data_dir, "info_objects.json")
    state = load(path)
    {:ok, %{path: path, objects: state}}
  end

  @impl true
  def handle_call(:list, _from, s) do
    {:reply, Enum.map(s.objects, &public/1), s}
  end

  def handle_call({:get, did}, _from, s) do
    case Enum.find(s.objects, &(&1.did == did)) do
      nil ->
        {:reply, {:error, :not_found}, s}

      obj ->
        case hydrate(obj) do
          {:ok, public} -> {:reply, {:ok, public}, s}
          err -> {:reply, err, s}
        end
    end
  end

  def handle_call({:create, principal_id, content, opts}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "mutate"),
         :ok <- require_ipfs(),
         {:ok, checkpoint} <- optional_iota_checkpoint(),
         {:ok, obj} <- build_new(principal_id, content, opts, checkpoint),
         {:ok, obj} <- attach_iota_identity(obj) do
      objects = s.objects ++ [obj]
      persist!(s.path, objects)
      state = %{s | objects: objects}

      case hydrate(obj) do
        {:ok, public} -> {:reply, {:ok, public}, state}
        {:error, _} = err -> {:reply, err, state}
      end
    else
      {:error, :capability_denied} = err ->
        {:reply, err, s}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call({:advance, principal_id, did, content, opts}, _from, s) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "mutate"),
         :ok <- require_ipfs(),
         obj when not is_nil(obj) <- Enum.find(s.objects, &(&1.did == did)),
         {:ok, checkpoint} <- optional_iota_checkpoint(),
         {:ok, updated} <- build_advance(obj, principal_id, content, opts, checkpoint),
         {:ok, updated} <- sync_iota_head(updated) do
      objects = Enum.map(s.objects, fn o -> if o.did == did, do: updated, else: o end)
      persist!(s.path, objects)
      state = %{s | objects: objects}

      case hydrate(updated) do
        {:ok, public} -> {:reply, {:ok, public}, state}
        {:error, _} = err -> {:reply, err, state}
      end
    else
      nil ->
        {:reply, {:error, :not_found}, s}

      {:error, :capability_denied} = err ->
        {:reply, err, s}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  defp build_new(principal_id, content, opts, checkpoint) do
    label = Keyword.get(opts, :label) || "info"
    id = short_id()
    did = "did:concrete:lab:#{id}"
    message = Keyword.get(opts, :message) || "initial commit"

    with {:ok, content_cid} <-
           ConcreteRuntime.IPFS.add_json(%{
             "type" => "ConcreteContentBlob",
             "text" => content
           }),
         commit = %{
           "type" => "ConcreteCommit",
           "message" => message,
           "content_cid" => content_cid,
           "parent_cid" => nil,
           "author_principal_id" => principal_id
         },
         {:ok, head_cid} <- ConcreteRuntime.IPFS.add_json(commit),
         did_doc = %{
           "@context" => "https://www.w3.org/ns/did/v1",
           "id" => did,
           "controller" => principal_id,
           "service" => [
             %{
               "id" => "#{did}#head",
               "type" => "ContentHead",
               "serviceEndpoint" => "ipfs://#{head_cid}"
             }
           ]
         },
         {:ok, did_doc_cid} <- ConcreteRuntime.IPFS.add_json(did_doc) do
      {:ok,
       %{
         did: did,
         label: label,
         did_doc_cid: did_doc_cid,
         head_cid: head_cid,
         content_cid: content_cid,
         created_by: principal_id,
         updated_by: principal_id,
         created_at: now(),
         updated_at: now(),
         iota_checkpoint: checkpoint
       }}
    end
  end

  defp build_advance(obj, principal_id, content, opts, checkpoint) do
    message = Keyword.get(opts, :message) || "advance"

    with {:ok, content_cid} <-
           ConcreteRuntime.IPFS.add_json(%{
             "type" => "ConcreteContentBlob",
             "text" => content
           }),
         commit = %{
           "type" => "ConcreteCommit",
           "message" => message,
           "content_cid" => content_cid,
           "parent_cid" => obj.head_cid,
           "author_principal_id" => principal_id
         },
         {:ok, head_cid} <- ConcreteRuntime.IPFS.add_json(commit),
         did_doc = %{
           "@context" => "https://www.w3.org/ns/did/v1",
           "id" => obj.did,
           "controller" => obj.created_by,
           "service" => [
             %{
               "id" => "#{obj.did}#head",
               "type" => "ContentHead",
               "serviceEndpoint" => "ipfs://#{head_cid}"
             }
           ]
         },
         {:ok, did_doc_cid} <- ConcreteRuntime.IPFS.add_json(did_doc) do
      {:ok,
       %{
         obj
         | did_doc_cid: did_doc_cid,
           head_cid: head_cid,
           content_cid: content_cid,
           updated_by: principal_id,
           updated_at: now(),
           iota_checkpoint: checkpoint
       }}
    end
  end

  defp hydrate(obj) do
    with {:ok, head_cid, head_source} <- head_for_read(obj),
         {:ok, commit} <- ConcreteRuntime.IPFS.cat_json(head_cid),
         {:ok, blob} <- ConcreteRuntime.IPFS.cat_json(commit["content_cid"]) do
      {:ok,
       %{
         did: obj.did,
         label: obj.label,
         head_cid: head_cid,
         content_cid: commit["content_cid"],
         did_doc_cid: obj.did_doc_cid,
         content: blob["text"],
         commit_message: commit["message"],
         parent_cid: commit["parent_cid"],
         created_by: obj.created_by,
         updated_by: obj.updated_by,
         created_at: obj.created_at,
         updated_at: obj.updated_at,
         iota_checkpoint: obj.iota_checkpoint,
         iota_did: Map.get(obj, :iota_did),
         identity_object_id: Map.get(obj, :identity_object_id),
         head_source: head_source
       }}
    end
  end

  @doc false
  def head_for_read(obj) do
    case Map.get(obj, :iota_did) do
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
        {:ok, obj.head_cid, "otp_registry"}
    end
  end

  defp public(obj) do
    Map.take(obj, [
      :did,
      :label,
      :head_cid,
      :content_cid,
      :did_doc_cid,
      :created_by,
      :updated_by,
      :created_at,
      :updated_at,
      :iota_checkpoint,
      :iota_did,
      :identity_object_id
    ])
  end

  @doc false
  def attach_iota_identity(obj) do
    mod = identity_mod()

    if mod.configured?() do
      case mod.create_and_publish(head_cid: obj.head_cid) do
        {:ok, %{did: iota_did, identity_object_id: oid}} ->
          with :ok <- mod.require_on_chain_head(iota_did, obj.head_cid) do
            {:ok,
             Map.merge(obj, %{
               iota_did: iota_did,
               identity_object_id: oid
             })}
          end

        {:error, reason} ->
          {:error, {:iota_identity_create_failed, reason}}
      end
    else
      {:ok, obj}
    end
  end

  @doc false
  def sync_iota_head(obj) do
    mod = identity_mod()

    if mod.configured?() do
      case Map.get(obj, :iota_did) do
        did when is_binary(did) and did != "" ->
          case mod.update_head(did, obj.head_cid) do
            {:ok, resolved} ->
              with :ok <- ConcreteRuntime.IotaIdentity.match_on_chain_head(resolved, obj.head_cid) do
                {:ok, obj}
              end

            {:error, reason} ->
              {:error, {:iota_identity_update_failed, reason}}
          end

        _ ->
          {:error, :iota_did_missing}
      end
    else
      {:ok, obj}
    end
  end

  defp identity_mod do
    Application.get_env(:concrete_runtime, :iota_identity, ConcreteRuntime.IotaIdentity)
  end

  defp require_ipfs do
    case ConcreteRuntime.IPFS.ping() do
      :ok -> :ok
      {:error, reason} -> {:error, {:ipfs_unavailable, reason}}
    end
  end

  defp optional_iota_checkpoint do
    case ConcreteRuntime.Iota.latest_checkpoint() do
      {:ok, cp} -> {:ok, cp}
      {:error, _} -> {:ok, nil}
    end
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

  defp persist!(path, objects) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(Enum.map(objects, &to_json/1), pretty: true))
  end

  defp to_json(o) do
    %{
      "did" => o.did,
      "label" => o.label,
      "did_doc_cid" => o.did_doc_cid,
      "head_cid" => o.head_cid,
      "content_cid" => o.content_cid,
      "created_by" => o.created_by,
      "updated_by" => o.updated_by,
      "created_at" => o.created_at,
      "updated_at" => o.updated_at,
      "iota_checkpoint" => o.iota_checkpoint,
      "iota_did" => Map.get(o, :iota_did),
      "identity_object_id" => Map.get(o, :identity_object_id)
    }
  end

  defp from_json(m) do
    %{
      did: m["did"],
      label: m["label"],
      did_doc_cid: m["did_doc_cid"],
      head_cid: m["head_cid"],
      content_cid: m["content_cid"],
      created_by: m["created_by"],
      updated_by: m["updated_by"],
      created_at: m["created_at"],
      updated_at: m["updated_at"],
      iota_checkpoint: m["iota_checkpoint"],
      iota_did: m["iota_did"],
      identity_object_id: m["identity_object_id"]
    }
  end

  defp short_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
