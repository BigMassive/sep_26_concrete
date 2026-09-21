defmodule ConcreteRuntime.UserDirectoryTest do
  use ExUnit.Case, async: false

  alias ConcreteRuntime.UserDirectory
  alias ConcreteRuntime.TestKit

  defmodule DownIPFS do
    def ping, do: {:error, :econnrefused}
  end

  defmodule OkIdentity do
    def configured?, do: true

    def create_and_publish(opts) do
      cid = Keyword.get(opts, :head_cid)
      Agent.update(TestKit.Store, fn s -> %{s | head: cid} end)

      {:ok,
       %{
         did: "did:iota:lab:0xdir",
         identity_object_id: "0xdir",
         controller_cap_id: "0xcap"
       }}
    end

    def require_on_chain_head("did:iota:lab:0xdir", _cid), do: :ok

    def resolve("did:iota:lab:0xdir") do
      cid = Agent.get(TestKit.Store, & &1.head)
      {:ok, %{head_source: "on_chain", head_cid: cid}}
    end
  end

  defmodule FailIdentity do
    def configured?, do: true
    def create_and_publish(_opts), do: {:error, :forced_ptb_failure}
  end

  setup do
    TestKit.put_fakes()
    {:ok, _} = start_supervised(TestKit.Store)
    TestKit.Store.reset()

    dir = TestKit.tmp_dir()
    Enum.each(TestKit.children(dir), &start_supervised!/1)

    on_exit(fn -> TestKit.clear_fakes() end)

    {:ok, _} = ConcreteRuntime.Workspaces.genesis(TestKit.helen_attrs())
    king = ConcreteRuntime.Bootstrap.status().king.id

    {:ok, introduced} =
      ConcreteRuntime.Workspaces.introduce_user(king, %{
        username: "Eve",
        public_key: "mldsa87:Eve"
      })

    %{king: king, eve: introduced.principal.id}
  end

  test "King publishes a data blob, not a commit graph", %{king: king} do
    assert {:ok, rec} = UserDirectory.publish(king, "Helen")
    assert rec.kind == "data"
    assert rec.username == "Helen"
    assert rec.public_key == king
    assert rec.did =~ "did:concrete:lab:user:"
    refute Map.has_key?(rec, :head_cid)
    refute rec.did =~ "info"

    blobs = Agent.get(TestKit.Store, fn s -> Map.values(s.blobs) end)
    blob = Enum.find(blobs, &(&1["type"] == "ConcreteUserDirectory"))
    assert blob["kind"] == "data"
    refute blob["type"] == "ConcreteCommit"
    refute Map.has_key?(blob, "parent_cid")
    refute Map.has_key?(blob, "content_cid")

    assert {:ok, listed} = UserDirectory.list(king)
    assert Enum.any?(listed, &(&1.did == rec.did))

    assert {:ok, got} = UserDirectory.get(king, rec.did)
    assert got.cid_source == "otp_index"
    assert got.public_key == king
    assert got.username == "Helen"
  end

  test "publish is idempotent per public key", %{king: king} do
    assert {:ok, a} = UserDirectory.publish(king, "Helen")
    assert {:ok, b} = UserDirectory.publish(king, "Helen")
    assert a.did == b.did
    {:ok, listed} = UserDirectory.list(king)
    assert Enum.count(listed, &(&1.public_key == king)) == 1
  end

  test "Eve cannot publish or list", %{king: king, eve: eve} do
    assert {:ok, _} = UserDirectory.publish(king, "Helen")
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
    assert {:error, {:ipfs_unavailable, :econnrefused}} = UserDirectory.publish(king, "Helen")
  end

  test "configured Identity names the blob with did:iota", %{king: king} do
    Application.put_env(:concrete_runtime, :iota_identity, OkIdentity)
    assert {:ok, rec} = UserDirectory.publish(king, "Helen")
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
             UserDirectory.publish(king, "Helen")
  end
end
