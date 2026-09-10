defmodule ConcreteRuntime.InfoObjectsIotaTest do
  use ExUnit.Case, async: false

  alias ConcreteRuntime.InfoObjects

  defmodule Unconfigured do
    def configured?, do: false
  end

  defmodule FailCreate do
    def configured?, do: true
    def create_and_publish(_opts), do: {:error, :forced_ptb_failure}
  end

  defmodule CreateWithoutOnChainHead do
    def configured?, do: true
    def create_and_publish(_opts), do: {:ok, %{did: "did:iota:lab:0x1", identity_object_id: "0x1"}}
    def require_on_chain_head(_did, _cid), do: {:error, {:iota_head_not_on_chain, "otp_cache"}}
  end

  defmodule OkCreate do
    def configured?, do: true

    def create_and_publish(_opts),
      do: {:ok, %{did: "did:iota:lab:0x1", identity_object_id: "0x1", controller_cap_id: "0xcap"}}

    def require_on_chain_head(_did, _cid), do: :ok
  end

  defmodule FailUpdate do
    def configured?, do: true
    def update_head(_did, _cid), do: {:error, :forced_ptb_failure}
  end

  defmodule UpdateOtpCache do
    def configured?, do: true

    def update_head(_did, cid) do
      {:ok, %{head_source: "otp_cache", head_cid: cid}}
    end
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:concrete_runtime, :iota_identity)
    end)

    :ok
  end

  test "unconfigured Identity keeps the lab-DID path" do
    Application.put_env(:concrete_runtime, :iota_identity, Unconfigured)
    obj = %{head_cid: "QmNew", did: "did:concrete:lab:x"}

    assert {:ok, ^obj} = InfoObjects.attach_iota_identity(obj)
    assert {:ok, ^obj} = InfoObjects.sync_iota_head(obj)
  end

  test "configured Identity create fails closed on PTB error" do
    Application.put_env(:concrete_runtime, :iota_identity, FailCreate)
    obj = %{head_cid: "QmNew"}

    assert {:error, {:iota_identity_create_failed, :forced_ptb_failure}} =
             InfoObjects.attach_iota_identity(obj)
  end

  test "configured Identity create fails if ContentHead is not on-chain" do
    Application.put_env(:concrete_runtime, :iota_identity, CreateWithoutOnChainHead)
    obj = %{head_cid: "QmNew"}

    assert {:error, {:iota_head_not_on_chain, "otp_cache"}} =
             InfoObjects.attach_iota_identity(obj)
  end

  test "configured Identity create attaches iota_did after on-chain confirm" do
    Application.put_env(:concrete_runtime, :iota_identity, OkCreate)
    obj = %{head_cid: "QmNew", did: "did:concrete:lab:x"}

    assert {:ok, attached} = InfoObjects.attach_iota_identity(obj)
    assert attached.iota_did == "did:iota:lab:0x1"
    assert attached.identity_object_id == "0x1"
    assert attached.head_cid == "QmNew"
    assert attached.did == "did:iota:lab:0x1"
    assert attached.controller_cap_id == "0xcap"
  end

  test "configured Identity advance fails closed without iota_did" do
    Application.put_env(:concrete_runtime, :iota_identity, FailUpdate)
    obj = %{head_cid: "QmNew", did: "did:concrete:lab:x"}

    assert {:error, :iota_did_missing} = InfoObjects.sync_iota_head(obj)
  end

  test "configured Identity advance fails closed on PTB error" do
    Application.put_env(:concrete_runtime, :iota_identity, FailUpdate)
    obj = %{head_cid: "QmNew", iota_did: "did:iota:lab:0x1"}

    assert {:error, {:iota_identity_update_failed, :forced_ptb_failure}} =
             InfoObjects.sync_iota_head(obj)
  end

  test "configured Identity advance rejects OTP-cache as success" do
    Application.put_env(:concrete_runtime, :iota_identity, UpdateOtpCache)
    obj = %{head_cid: "QmNew", iota_did: "did:iota:lab:0x1"}

    assert {:error, {:iota_head_not_on_chain, "otp_cache"}} = InfoObjects.sync_iota_head(obj)
  end

  defmodule ResolveOnChain do
    def resolve("did:iota:lab:0x1") do
      {:ok, %{head_source: "on_chain", head_cid: "QmChain"}}
    end
  end

  defmodule ResolveOtpCache do
    def resolve(_did) do
      {:ok, %{head_source: "otp_cache", head_cid: "QmCached"}}
    end
  end

  defmodule ResolveFail do
    def resolve(_did), do: {:error, :rpc_down}
  end

  test "read uses on-chain ContentHead when iota_did is present" do
    Application.put_env(:concrete_runtime, :iota_identity, ResolveOnChain)
    obj = %{head_cid: "QmStale", iota_did: "did:iota:lab:0x1"}

    assert {:ok, "QmChain", "on_chain"} = InfoObjects.head_for_read(obj)
  end

  test "read does not fall back to OTP head when chain is missing" do
    Application.put_env(:concrete_runtime, :iota_identity, ResolveOtpCache)
    obj = %{head_cid: "QmStale", iota_did: "did:iota:lab:0x1"}

    assert {:error, {:iota_head_not_on_chain, "otp_cache"}} = InfoObjects.head_for_read(obj)
  end

  test "read fails closed if Identity resolve fails" do
    Application.put_env(:concrete_runtime, :iota_identity, ResolveFail)
    obj = %{head_cid: "QmStale", iota_did: "did:iota:lab:0x1"}

    assert {:error, {:iota_resolve_failed, :rpc_down}} = InfoObjects.head_for_read(obj)
  end

  test "read uses OTP registry when there is no iota_did" do
    obj = %{head_cid: "QmLab", did: "did:concrete:lab:x"}
    assert {:ok, "QmLab", "otp_registry"} = InfoObjects.head_for_read(obj)
  end

  test "API did is iota when iota_did is present; leftovers stay findable by lab DID" do
    leftover = %{
      did: "did:concrete:lab:x",
      iota_did: "did:iota:lab:0x1",
      head_cid: "QmA"
    }

    fresh = %{did: "did:iota:lab:0x2", iota_did: "did:iota:lab:0x2", head_cid: "QmB"}
    objs = [leftover, fresh]

    assert leftover == InfoObjects.find_object(objs, "did:concrete:lab:x")
    assert leftover == InfoObjects.find_object(objs, "did:iota:lab:0x1")
    assert fresh == InfoObjects.find_object(objs, "did:iota:lab:0x2")
  end

  test "iota index record drops authoritative head fields" do
    indexed =
      InfoObjects.index_record(%{
        did: "did:iota:lab:0x1",
        iota_did: "did:iota:lab:0x1",
        identity_object_id: "0x1",
        controller_cap_id: "0xcap",
        label: "plaque",
        head_cid: "QmShouldNotPersist",
        content_cid: "QmAlsoDrop",
        did_doc_cid: "QmDoc"
      })

    refute Map.has_key?(indexed, :head_cid)
    refute Map.has_key?(indexed, :content_cid)
    refute Map.has_key?(indexed, :did_doc_cid)
    assert indexed == %{
             did: "did:iota:lab:0x1",
             iota_did: "did:iota:lab:0x1",
             identity_object_id: "0x1",
             controller_cap_id: "0xcap",
             label: "plaque"
           }
  end

  test "lab leftover index record keeps head_cid" do
    obj = %{did: "did:concrete:lab:x", head_cid: "QmLab", label: "plaque"}
    assert InfoObjects.index_record(obj) == obj
  end
end
