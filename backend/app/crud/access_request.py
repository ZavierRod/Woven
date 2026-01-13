from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import Optional, List
from uuid import UUID

from app.models.access_request import AccessRequest, AccessRequestStatus
from app.schemas.access_request import AccessRequestCreate

class CRUDAccessRequest:
    def create(
        self, db: Session, obj_in: AccessRequestCreate, requester_id: int, approver_id: int, expires_minutes: int = 5
    ) -> AccessRequest:
        expires_at = datetime.utcnow() + timedelta(minutes=expires_minutes)
        db_obj = AccessRequest(
            vault_id=obj_in.vault_id,
            requester_id=requester_id,
            approver_id=approver_id,
            requester_public_key=obj_in.requester_public_key,
            status=AccessRequestStatus.PENDING,
            expires_at=expires_at
        )
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        return db_obj

    def get(self, db: Session, id: int) -> Optional[AccessRequest]:
        return db.query(AccessRequest).filter(AccessRequest.id == id).first()

    def get_pending_by_vault(self, db: Session, vault_id: UUID) -> List[AccessRequest]:
        return db.query(AccessRequest).filter(
            AccessRequest.vault_id == vault_id,
            AccessRequest.status == AccessRequestStatus.PENDING
        ).all()

    def approve(self, db: Session, db_obj: AccessRequest, encrypted_share: str) -> AccessRequest:
        db_obj.status = AccessRequestStatus.APPROVED
        db_obj.encrypted_share = encrypted_share
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        return db_obj

    def deny(self, db: Session, db_obj: AccessRequest) -> AccessRequest:
        db_obj.status = AccessRequestStatus.DENIED
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        return db_obj

access_request_crud = CRUDAccessRequest()
