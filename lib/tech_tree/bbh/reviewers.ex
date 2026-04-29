defmodule TechTree.BBH.Reviewers do
  @moduledoc false

  alias Ecto.Multi
  alias TechTree.BBH.{Helpers, OrcidLinkRequest, ReviewerProfile}
  alias TechTree.Repo

  def start_reviewer_orcid_link(agent_claims) do
    wallet = Helpers.required_wallet(agent_claims)
    request_id = "orcid_req_" <> Helpers.unique_suffix()
    expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

    %OrcidLinkRequest{}
    |> OrcidLinkRequest.changeset(%{
      request_id: request_id,
      wallet_address: wallet,
      state: :pending,
      expires_at: expires_at
    })
    |> Repo.insert()
    |> case do
      {:ok, request} ->
        {:ok,
         %{
           request_id: request.request_id,
           state: enum_value(request.state),
           start_url:
             "#{TechTreeWeb.Endpoint.url()}/auth/orcid/start?request_id=#{request.request_id}",
           reviewer: reviewer_profile_payload(Repo.get(ReviewerProfile, wallet))
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_reviewer_orcid_link_status(agent_claims, request_id) when is_binary(request_id) do
    wallet = Helpers.required_wallet(agent_claims)

    case Repo.get(OrcidLinkRequest, request_id) do
      nil ->
        {:error, :orcid_request_not_found}

      %OrcidLinkRequest{} = request ->
        request = maybe_expire_orcid_request(request)

        if request.wallet_address != wallet do
          {:error, :orcid_request_not_found}
        else
          {:ok,
           %{
             request_id: request.request_id,
             state: enum_value(request.state),
             start_url:
               if(request.state == :pending,
                 do:
                   "#{TechTreeWeb.Endpoint.url()}/auth/orcid/start?request_id=#{request.request_id}",
                 else: nil
               ),
             reviewer: reviewer_profile_payload(Repo.get(ReviewerProfile, wallet))
           }}
        end
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def apply_reviewer(agent_claims, attrs) when is_map(attrs) do
    wallet = Helpers.required_wallet(agent_claims)
    domain_tags = Helpers.fetch_value(attrs, "domain_tags")

    with true <-
           is_list(domain_tags) || {:error, ArgumentError.exception("domain_tags is required")},
         %ReviewerProfile{} = profile <-
           Repo.get(ReviewerProfile, wallet) || {:error, :reviewer_orcid_required},
         true <-
           (profile.orcid_auth_kind == "oauth_authenticated" and is_binary(profile.orcid_id)) ||
             {:error, :reviewer_orcid_required},
         {:ok, updated} <-
           profile
           |> ReviewerProfile.changeset(%{
             domain_tags: Enum.map(domain_tags, &to_string/1),
             payout_wallet: Helpers.optional_binary(attrs, "payout_wallet"),
             experience_summary: Helpers.optional_binary(attrs, "experience_summary")
           })
           |> Repo.update() do
      {:ok, reviewer_profile_payload(updated)}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def get_reviewer(agent_claims) do
    wallet = Helpers.required_wallet(agent_claims)

    {:ok,
     reviewer_profile_payload(
       Repo.get(ReviewerProfile, wallet) ||
         %ReviewerProfile{wallet_address: wallet, vetting_status: :pending, domain_tags: []}
     )}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def approve_reviewer(wallet_address, admin_ref, status)
      when status in ["approved", "rejected", :approved, :rejected] do
    status = enum_atom(status)

    profile =
      Repo.get(ReviewerProfile, wallet_address) ||
        %ReviewerProfile{wallet_address: wallet_address, domain_tags: []}

    profile
    |> ReviewerProfile.changeset(%{
      vetting_status: status,
      vetted_by: admin_ref,
      vetted_at: DateTime.utc_now()
    })
    |> Repo.insert_or_update()
    |> case do
      {:ok, updated} -> {:ok, reviewer_profile_payload(updated)}
      {:error, reason} -> {:error, reason}
    end
  end

  def complete_orcid_link(request_id) when is_binary(request_id) do
    case Repo.get(OrcidLinkRequest, request_id) do
      nil ->
        {:error, :orcid_request_not_found}

      %OrcidLinkRequest{} = request ->
        request = maybe_expire_orcid_request(request)

        if request.state != :pending do
          {:error, :orcid_request_expired}
        else
          orcid_id = Helpers.generated_orcid_id(request.wallet_address)
          orcid_name = "Reviewer #{String.slice(request.wallet_address, -4, 4)}"

          Multi.new()
          |> Multi.update(
            :request,
            OrcidLinkRequest.changeset(request, %{
              state: :authenticated,
              authenticated_at: DateTime.utc_now()
            })
          )
          |> Multi.run(:reviewer, fn repo, _changes ->
            profile =
              repo.get(ReviewerProfile, request.wallet_address) ||
                %ReviewerProfile{wallet_address: request.wallet_address, domain_tags: []}

            profile
            |> ReviewerProfile.changeset(%{
              orcid_id: orcid_id,
              orcid_auth_kind: "oauth_authenticated",
              orcid_name: orcid_name,
              vetting_status: profile.vetting_status || :pending
            })
            |> repo.insert_or_update()
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{reviewer: reviewer}} -> {:ok, reviewer_profile_payload(reviewer)}
            {:error, _step, reason, _changes} -> {:error, reason}
          end
        end
    end
  end

  def require_approved_reviewer(agent_claims) do
    wallet = Helpers.required_wallet(agent_claims)

    case Repo.get(ReviewerProfile, wallet) do
      %ReviewerProfile{vetting_status: :approved} = profile -> {:ok, profile}
      %ReviewerProfile{} -> {:error, :reviewer_not_approved}
      nil -> {:error, :reviewer_not_approved}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def reviewer_profile_payload(nil), do: nil

  def reviewer_profile_payload(%ReviewerProfile{} = profile) do
    %{
      wallet_address: profile.wallet_address,
      orcid_id: profile.orcid_id,
      orcid_auth_kind: profile.orcid_auth_kind,
      orcid_name: profile.orcid_name,
      vetting_status: enum_value(profile.vetting_status),
      domain_tags: profile.domain_tags || [],
      payout_wallet: profile.payout_wallet,
      experience_summary: profile.experience_summary,
      vetted_by: profile.vetted_by,
      vetted_at: profile.vetted_at
    }
  end

  defp maybe_expire_orcid_request(%OrcidLinkRequest{} = request) do
    if request.state == :pending and
         DateTime.compare(request.expires_at, DateTime.utc_now()) == :lt do
      {:ok, updated} =
        request
        |> OrcidLinkRequest.changeset(%{state: :expired})
        |> Repo.update()

      updated
    else
      request
    end
  end

  defp enum_atom(value) when is_binary(value), do: String.to_existing_atom(value)
  defp enum_atom(value), do: value

  defp enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_value(value), do: value
end
