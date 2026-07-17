from pydantic import BaseModel, Field, field_validator


class DeviceRegistrationV2(BaseModel):
    device_id: str = Field(min_length=8, max_length=64)
    agreement_public_key: str = Field(min_length=40, max_length=128)
    signing_public_key: str = Field(min_length=40, max_length=128)


class InvitationCreateV2(BaseModel):
    invitation_id: str = Field(min_length=8, max_length=64)
    target_user_id: int
    target_device_id: str = Field(min_length=8, max_length=64)
    token_sha256: str = Field(min_length=64, max_length=64)
    encrypted_share_envelope: str = Field(min_length=32, max_length=32768)
    created_at_ms: int
    expires_at_ms: int

    @field_validator("token_sha256")
    @classmethod
    def validate_hash(cls, value: str) -> str:
        lowered = value.lower()
        if any(character not in "0123456789abcdef" for character in lowered):
            raise ValueError("token_sha256 must be lowercase hexadecimal")
        return lowered


class PairVaultCreateV2(BaseModel):
    vault_id: str = Field(min_length=8, max_length=64)
    creator_device_id: str = Field(min_length=8, max_length=64)
    encrypted_metadata: str = Field(min_length=16, max_length=32768)
    invitation: InvitationCreateV2


class InvitationAcceptV2(BaseModel):
    token: str = Field(min_length=16, max_length=512)


class AccessRequestCreateV2(BaseModel):
    request_id: str = Field(min_length=8, max_length=64)
    requester_device_id: str = Field(min_length=8, max_length=64)
    requester_ephemeral_public_key: str = Field(min_length=40, max_length=128)
    created_at_ms: int
    expires_at_ms: int


class AccessApprovalV2(BaseModel):
    encrypted_share_envelope: str = Field(min_length=32, max_length=32768)


class PairMediaCreateV2(BaseModel):
    media_id: str = Field(min_length=8, max_length=64)
    encrypted_blob: str = Field(min_length=16, max_length=40_000_000)
    encrypted_metadata: str = Field(min_length=16, max_length=32768)
    created_at_ms: int
