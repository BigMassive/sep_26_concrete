defmodule ConcreteRuntime.UserIdentity do
  @moduledoc """
  ADR 0008 lab sidecar: simulate external issuance (FIPS 202 seed, HKDF,
  ML-DSA-87 index 0). Exports public key only. Seed stays in CONCRETE_VAULT_DIR
  (seL4 vault stand-in).
  """

  def onboard(username) when is_binary(username) do
    mod = Application.get_env(:concrete_runtime, :user_identity, __MODULE__)

    if mod != __MODULE__ do
      mod.onboard(username)
    else
      run_onboard(username)
    end
  end

  defp run_onboard(username) do
    {python, script} = python_and_script()

    cond do
      is_nil(script) or not File.exists?(script) ->
        {:error, :missing_user_identity_script}

      true ->
        env =
          System.get_env()
          |> Map.put("CONCRETE_VAULT_DIR", vault_dir())
          |> Enum.to_list()

        case System.cmd(python, [script, "onboard", "--username", username],
               stderr_to_stdout: true,
               cd: repo_root(),
               env: env
             ) do
          {out, 0} ->
            decode_onboard(out)

          {out, code} ->
            {:error, {:user_identity_script_failed, code, out}}
        end
    end
  end

  defp decode_onboard(out) do
    trimmed = String.trim(out)

    case Jason.decode(trimmed) do
      {:ok, %{"id" => id, "public_key" => pk, "username" => name}}
      when is_binary(id) and is_binary(pk) ->
        {:ok,
         %{
           id: id,
           public_key: pk,
           display_name: name,
           index: 0
         }}

      {:ok, map} ->
        {:error, {:bad_onboard_response, map}}

      _ ->
        trimmed
        |> String.split("\n")
        |> Enum.reverse()
        |> Enum.find_value(fn line ->
          case Jason.decode(String.trim(line)) do
            {:ok, %{"id" => id, "public_key" => pk, "username" => name}} ->
              {:ok, %{id: id, public_key: pk, display_name: name, index: 0}}

            _ ->
              nil
          end
        end) || {:error, {:json, :no_object, out}}
    end
  end

  defp python_and_script do
    root = repo_root()
    script = Path.join(root, "scripts/user-identity.py")
    venv = Path.join(root, "lab/.venv/bin/python")
    python = System.get_env("CONCRETE_USER_IDENTITY_PYTHON") || if(File.exists?(venv), do: venv, else: "python3")
    {python, script}
  end

  def vault_dir do
    System.get_env("CONCRETE_VAULT_DIR") || Path.join(repo_root(), "lab/data/vault")
  end

  defp repo_root do
    Path.expand(Path.join([__DIR__, "..", "..", ".."]))
  end
end
