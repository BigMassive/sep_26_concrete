defmodule ConcreteRuntime.IotaIdentityTest do
  use ExUnit.Case, async: true

  alias ConcreteRuntime.IotaIdentity

  @ts "2026-09-08T12:00:00Z"

  test "packs and unpacks a ContentHead DID document" do
    {:ok, packed} =
      IotaIdentity.pack_document(
        head_cid: "QmTestHeadCid",
        created: @ts,
        updated: @ts
      )

    assert <<"DID", 1, 0, _rest::binary>> = packed
    {:ok, payload} = IotaIdentity.unpack_document(packed)
    assert payload["doc"]["id"] == "did:0:0"
    assert IotaIdentity.head_cid_from_payload(payload) == "QmTestHeadCid"
    assert {:ok, "QmTestHeadCid"} = IotaIdentity.head_cid_from_packed(packed)
  end

  test "packs a document without ContentHead" do
    {:ok, packed} = IotaIdentity.pack_document(created: @ts, updated: @ts)
    {:ok, payload} = IotaIdentity.unpack_document(packed)
    assert payload["doc"]["id"] == "did:0:0"
    assert IotaIdentity.head_cid_from_payload(payload) == nil
  end

  test "rejects truncated packed documents" do
    {:ok, packed} = IotaIdentity.pack_document(head_cid: "QmX", created: @ts, updated: @ts)
    short = binary_part(packed, 0, min(6, byte_size(packed)))
    assert {:error, _} = IotaIdentity.unpack_document(short)
  end

  test "python identity-doc.py pack round-trips with OTP" do
    script = Path.expand("../../scripts/identity-doc.py", __DIR__)
    assert File.exists?(script)

    {hex, 0} =
      System.cmd("python3", [
        script,
        "pack",
        "--head-cid",
        "QmPy",
        "--created",
        @ts,
        "--updated",
        @ts
      ])

    packed = Base.decode16!(String.trim(hex), case: :mixed)
    assert {:ok, "QmPy"} = IotaIdentity.head_cid_from_packed(packed)
  end

  test "match_on_chain_head accepts only matching on-chain ContentHead" do
    assert :ok =
             IotaIdentity.match_on_chain_head(
               %{head_source: "on_chain", head_cid: "QmA"},
               "QmA"
             )

    assert {:error, {:iota_head_mismatch, "QmA", "QmB"}} =
             IotaIdentity.match_on_chain_head(
               %{head_source: "on_chain", head_cid: "QmB"},
               "QmA"
             )

    assert {:error, {:iota_head_not_on_chain, "otp_cache"}} =
             IotaIdentity.match_on_chain_head(
               %{head_source: "otp_cache", head_cid: "QmA"},
               "QmA"
             )

    assert {:ok, "QmA"} =
             IotaIdentity.on_chain_head_cid(%{head_source: "on_chain", head_cid: "QmA"})

    assert {:error, {:iota_head_not_on_chain, "otp_cache"}} =
             IotaIdentity.on_chain_head_cid(%{head_source: "otp_cache", head_cid: "QmA"})
  end
end
