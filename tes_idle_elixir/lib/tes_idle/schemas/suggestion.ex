defmodule TesIdle.Schemas.Suggestion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "suggestions" do
    field :suggestion_type, :string
    field :title, :string
    field :content, :string
    field :status, :string, default: "pending"
    field :admin_comment, :string
    field :reviewed_at, :naive_datetime

    belongs_to :user, TesIdle.Schemas.User, type: :binary_id

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, [:suggestion_type, :title, :content, :status, :admin_comment, :user_id])
    |> validate_required([:suggestion_type, :title, :content, :user_id])
  end
end
