defmodule ConcreteRuntime.IotaIdentity do
  @moduledoc """
  Phase 2: on-ledger IOTA Identity (ADR 0002 / 0006).

  Frozen slice uses `did:concrete:lab:` + IPFS DID docs. This module reports
  readiness for Identity package publish and reserves create/resolve/update APIs.
  """

  @doc """
  Lab naming / Identity readiness for health and Phase 2 progress.
  """
  def status do
    pkg = System.get_env("IOTA_IDENTITY_PKG_ID")
    iota_ok = ConcreteRuntime.Iota.ping() == :ok

    %{
      naming_mode: "did:concrete:lab",
      iota_identity: %{
        target_method: "did:iota",
        package_id: pkg,
        package_configured: is_binary(pkg) and pkg != "",
        rpc_reachable: iota_ok,
        publish_ready: false,
        note:
          "Publish Identity Move package to localnet and set IOTA_IDENTITY_PKG_ID; see docs/08-phase2-iota-identity.md"
      }
    }
  end

  def create_and_publish(_opts), do: {:error, :not_implemented}
  def resolve(_did), do: {:error, :not_implemented}
  def update_head(_did, _head_cid), do: {:error, :not_implemented}
end
