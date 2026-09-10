defmodule ConcreteRuntime.UserDirectoryTest do
  use ExUnit.Case, async: false

  alias ConcreteRuntime.UserDirectory

  defmodule FakeIssuer do
    def onboard(name) do
      id = "mldsa87:" <> name
      {:ok, %{id: id, public_key: id, display_name: name, index: 0}}
    end
  end

  defmodule Store do
    use Agent
    def start_link(_), do: Agent.start_link(fn -> %{blobs: %{}, head: nil} end, name: __MODULE__)
    def reset, do: Agent.update(__MODULE__, fn _ -> %{blobs: %{}, head: nil} end)
  end

  defmodule FakeIPFS do
    def ping, do: :ok

    def add_json(map) do
      cid = "bafy" <> Integer.to_string(:erlang.phash2(map))
      Agent.update(Store, fn s -> %{s | blobs: Map.put(s.blobs, cid, map)} end)
      {:ok, cid}
    end

    def cat_json(cid) do
      case Agent.get(Store, &Map.get(&1.blobs, cid)) do
        nil -> {:error, :not_found}
        map -> {:ok, map}
      end
    end
  end

  defmodule DownIPFS do
    def ping, do: {:error, :econnrefused}
  end

  defmodule UnconfiguredIdentity do
    def configured?, do: false
  end

  defmodule OkIdentity do
    def configured?, do: true

    def create_and_publish(opts) do
      cid = Keyword.get(opts, :head_cid)
      Agent.update(Store, fn s -> %{s | head: cid} end)

      {:ok,
       %{
         did: "did:iota:lab:0xdir",
         identity_object_id: "0xdir",
         controller_cap_id: "0xcap"
       }}
    end

    def require_on_chain_head("did:iota:lab:0xdir", _cid), do: :ok

    def resolve("did:iota:lab:0xdir") do
      cid = Agent.get(Store, & &1.head)
      {:ok, %{head_source: "on_chain", head_cid: cid}}
    end
  end

  defmodule FailIdentity do
    def configured?, do: true
    def create_and_publish(_opts), do: {:error, :forced_ptb_failure}
  end

  setup do
    Application.put_env(:concrete_runtime, :user_identity, FakeIssuer)
    Application.put_env(:concrete_runtime, :ipfs, FakeIPFS)
    Application.put_env(:concrete_runtime, :iota_identity, UnconfiguredIdentity)

    {:ok, _} = start_supervised(Store)
    Store.reset()

    dir = Path.join(System.tmp_dir!(), "concrete-dir-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    start_supervised!({ConcreteRuntime.Bootstrap, data_dir: dir})
    start_supervised!({UserDirectory, data_dir: dir})

    on_exit(fn ->
      Application.delete_env(:concrete_runtime, :user_identity)
      Application.delete_env(:concrete_runtime, :ipfs)
      Application.delete_env(:concrete_runtime, :iota_identity)
    end)

    king = ConcreteRuntime.Bootstrap.status().king.id
    {:ok, eve} = ConcreteRuntime.Bootstrap.ensure_principal("Eve")
    %{king: king, eve: eve.id}
  end

  test "King publishes a data blob, not a commit graph", %{king: king} do
    assert {:ok, rec} = UserDirectory.publish(king, "King")
    assert rec.kind == "data"
    assert rec.username == "King"
    assert rec.public_key == king
    assert rec.did =~ "did:concrete:lab:user:"
    refute Map.has_key?(rec, :head_cid)
    refute rec.did =~ "info"

    {:ok, [cid]} = Agent.get(Store, fn s -> {:ok, Map.keys(s.blobs)} end)
    {:ok, blob} = FakeIPFS.cat_json(cid)
    assert blob["type"] == "ConcreteUserDirectory"
    assert blob["kind"] == "data"
    refute blob["type"] == "ConcreteCommit"
    refute Map.has_key?(blob, "parent_cid")
    refute Map.has_key?(blob, "content_cid")

    assert {:ok, [listed]} = UserDirectory.list(king)
    assert listed.did == rec.did

    assert {:ok, got} = UserDirectory.get(king, rec.did)
    assert got.cid_source == "otp_index"
    assert got.public_key == king
    assert got.username == "King"
  end

  test "publish is idempotent per public key", %{king: king} do
    assert {:ok, a} = UserDirectory.publish(king, "King")
    assert {:ok, b} = UserDirectory.publish(king, "King")
    assert a.did == b.did
    assert {:ok, [one]} = UserDirectory.list(king)
    assert one.did == a.did
  end

  test "Eve cannot publish or list", %{king: king, eve: eve} do
    assert {:ok, _} = UserDirectory.publish(king, "King")
    assert {:error, :capability_denied} = UserDirectory.publish(eve, "Eve")
    assert {:error, :capability_denied} = UserDirectory.list(eve)
    assert {:error, :capability_denied} = UserDirectory.get(eve, "did:concrete:lab:user:x")
  end

  test "King can publish Eve as data", %{king: king, eve: eve} do
    assert {:ok, rec} = UserDirectory.publish(king, "Eve")
    assert rec.public_key == eve
    assert rec.username == "Eve"
    assert rec.kind == "data"
  end

  test "unknown username is not found", %{king: king} do
    assert {:error, :unknown_principal} = UserDirectory.publish(king, "Mallory")
  end

  test "IPFS down fails closed", %{king: king} do
    Application.put_env(:concrete_runtime, :ipfs, DownIPFS)
    assert {:error, {:ipfs_unavailable, :econnrefused}} = UserDirectory.publish(king, "King")
  end

  test "configured Identity names the blob with did:iota", %{king: king} do
    Application.put_env(:concrete_runtime, :iota_identity, OkIdentity)
    assert {:ok, rec} = UserDirectory.publish(king, "King")
    assert rec.did == "did:iota:lab:0xdir"
    assert rec.iota_did == "did:iota:lab:0xdir"
    assert rec.kind == "data"

    assert {:ok, got} = UserDirectory.get(king, rec.did)
    assert got.cid_source == "on_chain"
    assert got.public_key == king
  end

  test "configured Identity create fails closed", %{king: king} do
    Application.put_env(:concrete_runtime, :iota_identity, FailIdentity)

    assert {:error, {:iota_identity_create_failed, :forced_ptb_failure}} =
             UserDirectory.publish(king, "King")
  end
end
