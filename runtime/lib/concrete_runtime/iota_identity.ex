defmodule ConcreteRuntime.IotaIdentity do
  @moduledoc """
  Phase 2: on-ledger IOTA Identity (ADR 0002 / 0006).

  Package publish + Identity::new / propose_update via labelled lab scripts
  (`iota client ptb` in Docker). DID documents are packed per IOTA DID method
  v2 (JSON encoding, `did:0:0` placeholders, ContentHead → `ipfs://<cid>`).
  Head CID is read back from on-chain `did_doc` bytes; OTP `iota_heads.json`
  stores controller-cap ids needed to sign updates.
  """

  @pkg_file_rel ["lab", "data", "iota", "identity_pkg_id.txt"]
  @heads_file "iota_heads.json"
  @did_marker "DID"
  @version 1
  @encoding_json 0

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
        identities_tracked: map_size(load_heads()),
        note:
          if configured do
            "Identity package on localnet; DID doc packed with ContentHead; head CID on-chain via propose_update"
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

  def configured? do
    case package_id() do
      id when is_binary(id) and id != "" -> true
      _ -> false
    end
  end

  @doc """
  Accept a resolve map only when ContentHead was read from chain and matches.
  OTP cache is not success (ADR 0007 stage A).
  """
  def match_on_chain_head(%{head_source: "on_chain", head_cid: cid}, expected)
      when is_binary(expected) and cid == expected,
      do: :ok

  def match_on_chain_head(%{head_source: "on_chain", head_cid: cid}, expected)
      when is_binary(expected),
      do: {:error, {:iota_head_mismatch, expected, cid}}

  def match_on_chain_head(%{head_source: source}, _expected),
    do: {:error, {:iota_head_not_on_chain, source}}

  def match_on_chain_head(_, _), do: {:error, :iota_head_unconfirmed}

  @doc """
  CID from a resolve map only when ContentHead was read from chain.
  """
  def on_chain_head_cid(%{head_source: "on_chain", head_cid: cid})
      when is_binary(cid) and cid != "",
      do: {:ok, cid}

  def on_chain_head_cid(%{head_source: source}),
    do: {:error, {:iota_head_not_on_chain, source}}

  def on_chain_head_cid(_), do: {:error, :iota_head_unconfirmed}

  def require_on_chain_head(did, expected_cid) when is_binary(did) and is_binary(expected_cid) do
    with {:ok, resolved} <- resolve(did) do
      match_on_chain_head(resolved, expected_cid)
    end
  end

  @doc """
  Pack a DID-method-v2 state-metadata document (ContentHead optional).
  """
  def pack_document(opts \\ []) do
    head_cid = Keyword.get(opts, :head_cid)
    created = Keyword.get(opts, :created) || now()
    updated = Keyword.get(opts, :updated) || created

    doc =
      if is_binary(head_cid) and head_cid != "" do
        %{
          "id" => "did:0:0",
          "service" => [
            %{
              "id" => "did:0:0#head",
              "type" => "ContentHead",
              "serviceEndpoint" => "ipfs://#{head_cid}"
            }
          ]
        }
      else
        %{"id" => "did:0:0"}
      end

    payload = %{
      "doc" => doc,
      "meta" => %{"created" => created, "updated" => updated}
    }

    json = Jason.encode!(payload)

    if byte_size(json) > 0xFFFF do
      {:error, :document_too_large}
    else
      packed =
        <<@did_marker::binary, @version::8, @encoding_json::8, byte_size(json)::little-16,
          json::binary>>

      {:ok, packed}
    end
  end

  def pack_hex(opts \\ []) do
    with {:ok, packed} <- pack_document(opts) do
      {:ok, Base.encode16(packed, case: :lower)}
    end
  end

  def unpack_document(bytes) when is_binary(bytes) do
    case bytes do
      <<@did_marker::binary, @version::8, @encoding_json::8, len::little-16,
        json::binary-size(len), _::binary>> ->
        case Jason.decode(json) do
          {:ok, map} when is_map(map) -> {:ok, map}
          {:ok, _} -> {:error, :invalid_payload}
          {:error, err} -> {:error, {:json, err}}
        end

      <<@did_marker::binary, @version::8, @encoding_json::8, len::little-16, rest::binary>>
      when byte_size(rest) < len ->
        {:error, :truncated}

      _ ->
        {:error, :invalid_packed_document}
    end
  end

  def unpack_document(_), do: {:error, :invalid_packed_document}

  def head_cid_from_payload(payload) when is_map(payload) do
    services = get_in(payload, ["doc", "service"]) || []

    Enum.find_value(services, fn
      %{"type" => "ContentHead", "serviceEndpoint" => "ipfs://" <> cid} -> cid
      %{"type" => "ContentHead", "serviceEndpoint" => cid} when is_binary(cid) -> cid
      _ -> nil
    end)
  end

  def head_cid_from_packed(bytes) do
    with {:ok, payload} <- unpack_document(bytes) do
      {:ok, head_cid_from_payload(payload)}
    end
  end

  @doc """
  Publish a new Identity object. Optional `:head_cid` is packed into the on-chain DID doc.
  """
  def create_and_publish(opts \\ []) do
    script = Path.join(repo_root(), "scripts/identity-create.sh")
    head_cid = Keyword.get(opts, :head_cid)

    cond do
      is_nil(package_id()) or package_id() == "" ->
        {:error, :package_not_configured}

      not File.exists?(script) ->
        {:error, :missing_identity_create_script}

      true ->
        with {:ok, hex} <- pack_hex(head_cid: head_cid) do
          case run_script(script, %{"IDENTITY_DOC_HEX" => hex}) do
            {:ok, %{"did" => did, "identity_object_id" => obj} = map}
            when is_binary(did) and is_binary(obj) ->
              put_head(did, %{
                "identity_object_id" => obj,
                "controller_cap_id" => map["controller_cap_id"],
                "head_cid" => head_cid,
                "package_id" => map["package_id"],
                "chain_id" => map["chain_id"],
                "digest" => map["digest"]
              })

              {:ok,
               %{
                 did: did,
                 identity_object_id: obj,
                 controller_cap_id: map["controller_cap_id"],
                 package_id: map["package_id"],
                 chain_id: map["chain_id"],
                 digest: map["digest"],
                 head_cid: head_cid
               }}

            {:ok, map} ->
              {:error, {:bad_create_response, map}}

            {:error, _} = err ->
              err
          end
        end
    end
  end

  def resolve(did) when is_binary(did) do
    with {:ok, object_id} <- object_id_from_did(did),
         {:ok, obj} <- ConcreteRuntime.Iota.get_object(object_id) do
      meta = Map.get(load_heads(), did, %{})
      {on_chain_head, document} = decode_on_chain_doc(obj, did)

      {:ok,
       %{
         did: did,
         identity_object_id: object_id,
         controller_cap_id: meta["controller_cap_id"],
         on_chain: simplify_object(obj),
         did_document: document,
         head_cid: on_chain_head || meta["head_cid"],
         head_source:
           cond do
             is_binary(on_chain_head) and on_chain_head != "" -> "on_chain"
             true -> "otp_cache"
           end,
         package_id: package_id()
       }}
    end
  end

  def update_head(did, head_cid) when is_binary(did) and is_binary(head_cid) do
    script = Path.join(repo_root(), "scripts/identity-update.sh")

    case Map.get(load_heads(), did) do
      nil ->
        {:error, :unknown_identity}

      meta ->
        cap = meta["controller_cap_id"]
        obj = meta["identity_object_id"]

        cond do
          not File.exists?(script) ->
            {:error, :missing_identity_update_script}

          not is_binary(cap) or cap == "" ->
            {:error, :missing_controller_cap}

          not is_binary(obj) or obj == "" ->
            {:error, :missing_identity_object}

          true ->
            with {:ok, hex} <- pack_hex(head_cid: head_cid),
                 {:ok, map} <-
                   run_script(script, %{
                     "IDENTITY_DOC_HEX" => hex,
                     "IDENTITY_OBJECT_ID" => obj,
                     "CONTROLLER_CAP_ID" => cap
                   }) do
              put_head(
                did,
                meta
                |> Map.put("head_cid", head_cid)
                |> Map.put("digest", map["digest"])
              )

              resolve(did)
            end
        end
    end
  end

  defp decode_on_chain_doc(obj, did) do
    case did_doc_bytes_from_object(obj) do
      bytes when is_binary(bytes) and byte_size(bytes) > 0 ->
        case unpack_document(bytes) do
          {:ok, payload} ->
            materialized = materialize_did(payload, did)
            {head_cid_from_payload(payload), materialized}

          _ ->
            {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  end

  defp did_doc_bytes_from_object(obj) when is_map(obj) do
    value = get_in(obj, ["content", "fields", "did_doc", "fields", "controlled_value"])
    decode_option_bytes(value)
  end

  defp decode_option_bytes(nil), do: nil
  defp decode_option_bytes([]), do: nil
  defp decode_option_bytes(%{"None" => _}), do: nil
  defp decode_option_bytes(%{"Some" => inner}), do: decode_bytes(inner)
  defp decode_option_bytes(%{"fields" => %{"vec" => []}}), do: nil

  defp decode_option_bytes(%{"fields" => %{"vec" => [inner | _]}}), do: decode_bytes(inner)
  defp decode_option_bytes(other), do: decode_bytes(other)

  defp decode_bytes(list) when is_list(list) do
    if Enum.all?(list, &is_integer/1) do
      :binary.list_to_bin(list)
    else
      nil
    end
  end

  defp decode_bytes("0x" <> hex), do: decode_hex(hex)
  defp decode_bytes("0X" <> hex), do: decode_hex(hex)

  defp decode_bytes(bin) when is_binary(bin) do
    case decode_hex(bin) do
      nil ->
        case Base.decode64(bin) do
          {:ok, bytes} -> bytes
          :error -> if String.starts_with?(bin, @did_marker), do: bin, else: nil
        end

      bytes ->
        bytes
    end
  end

  defp decode_bytes(_), do: nil

  defp decode_hex(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> bytes
      :error -> nil
    end
  end

  defp materialize_did(map, did) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, materialize_did(v, did)} end)
  end

  defp materialize_did(list, did) when is_list(list),
    do: Enum.map(list, &materialize_did(&1, did))

  defp materialize_did("did:0:0" <> rest, did), do: did <> rest
  defp materialize_did(other, _), do: other

  defp simplify_object(obj) when is_map(obj) do
    %{
      object_id: obj["objectId"],
      version: obj["version"],
      type: obj["type"],
      deleted: get_in(obj, ["content", "fields", "deleted"]),
      deleted_did: get_in(obj, ["content", "fields", "deleted_did"]),
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

  defp run_script(script, extra_env) do
    env =
      System.get_env()
      |> Map.merge(extra_env)
      |> Enum.to_list()

    case System.cmd(script, [], stderr_to_stdout: true, cd: repo_root(), env: env) do
      {out, 0} ->
        decode_script_json(out)

      {out, code} ->
        {:error, {:script_failed, Path.basename(script), code, out}}
    end
  end

  defp decode_script_json(out) do
    trimmed = String.trim(out)

    case Jason.decode(trimmed) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      _ ->
        trimmed
        |> String.split("\n")
        |> Enum.reverse()
        |> Enum.find_value(fn line ->
          case Jason.decode(String.trim(line)) do
            {:ok, map} when is_map(map) -> {:ok, map}
            _ -> nil
          end
        end) || {:error, {:json, :no_object, out}}
    end
  end

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

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
