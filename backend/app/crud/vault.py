from sqlalchemy.orm import Session
from sqlalchemy import or_, select
from typing import Optional, List
from uuid import UUID
from datetime import datetime

from app.models.vault import Vault, VaultMember, VaultType, VaultMode, MemberRole, MemberStatus
from app.schemas.vault import VaultCreate, VaultUpdate


class VaultCRUD:
    """CRUD operations for Vaults."""
    
    def get_by_id(self, db: Session, vault_id: UUID) -> Optional[Vault]:
        """Get a vault by its ID."""
        return db.query(Vault).filter(Vault.id == vault_id).first()
    
    def get_user_vaults(self, db: Session, user_id: int) -> List[Vault]:
        """Get all vaults a user owns or is a member of."""
        # Get vault IDs where user is a member (accepted)
        member_vault_ids = select(VaultMember.vault_id).where(
            VaultMember.user_id == user_id,
            VaultMember.status == MemberStatus.ACCEPTED
        ).scalar_subquery()
        
        # Get vaults user owns OR is an accepted member of
        return db.query(Vault).filter(
            or_(
                Vault.owner_id == user_id,
                Vault.id.in_(member_vault_ids)
            )
        ).order_by(Vault.created_at.desc()).all()
    
    def create(self, db: Session, vault_in: VaultCreate, owner_id: int, status: str = "ACTIVE") -> Vault:
        """Create a new vault."""
        from app.models.vault import VaultStatus
        
        vault = Vault(
            name=vault_in.name,
            type=VaultType(vault_in.type),
            mode=VaultMode(vault_in.mode),
            status=VaultStatus(status),
            owner_id=owner_id,
        )
        db.add(vault)
        db.commit()
        db.refresh(vault)
        
        # Add owner as a member with ACCEPTED status
        owner_member = VaultMember(
            vault_id=vault.id,
            user_id=owner_id,
            role=MemberRole.OWNER,
            status=MemberStatus.ACCEPTED,
            joined_at=datetime.utcnow(),
        )
        db.add(owner_member)
        db.commit()
        
        return vault
    
    def update(self, db: Session, vault: Vault, vault_update: VaultUpdate) -> Vault:
        """Update a vault."""
        update_data = vault_update.model_dump(exclude_unset=True)
        
        for field, value in update_data.items():
            if field == "mode" and value:
                setattr(vault, field, VaultMode(value))
            elif value is not None:
                setattr(vault, field, value)
        
        db.commit()
        db.refresh(vault)
        return vault
    
    def delete(self, db: Session, vault: Vault) -> None:
        """Delete a vault (cascades to members)."""
        db.delete(vault)
        db.commit()
    
    def update_last_accessed(self, db: Session, vault: Vault) -> Vault:
        """Update the last accessed timestamp."""
        vault.last_accessed_at = datetime.utcnow()
        db.commit()
        db.refresh(vault)
        return vault
    
    def get_member_count(self, db: Session, vault_id: UUID) -> int:
        """Get the number of accepted members in a vault."""
        return db.query(VaultMember).filter(
            VaultMember.vault_id == vault_id,
            VaultMember.status == MemberStatus.ACCEPTED
        ).count()
    
    def get_media_count(self, db: Session, vault_id: UUID) -> int:
        """Get the number of media items in a vault."""
        from app.models.media import VaultMedia
        return db.query(VaultMedia).filter(VaultMedia.vault_id == vault_id).count()
    
    def is_owner(self, db: Session, vault_id: UUID, user_id: int) -> bool:
        """Check if user is the owner of the vault."""
        vault = self.get_by_id(db, vault_id)
        return vault is not None and vault.owner_id == user_id
    
    def is_member(self, db: Session, vault_id: UUID, user_id: int) -> bool:
        """Check if user is an accepted member of the vault."""
        return db.query(VaultMember).filter(
            VaultMember.vault_id == vault_id,
            VaultMember.user_id == user_id,
            VaultMember.status == MemberStatus.ACCEPTED
        ).first() is not None
    
    def can_access(self, db: Session, vault_id: UUID, user_id: int) -> bool:
        """Check if user can access the vault (owner or member)."""
        return self.is_owner(db, vault_id, user_id) or self.is_member(db, vault_id, user_id)


class VaultMemberCRUD:
    """CRUD operations for Vault Members."""
    
    def get_by_id(self, db: Session, member_id: int) -> Optional[VaultMember]:
        """Get a vault member by ID."""
        return db.query(VaultMember).filter(VaultMember.id == member_id).first()
    
    def get_vault_members(self, db: Session, vault_id: UUID) -> List[VaultMember]:
        """Get all members of a vault."""
        return db.query(VaultMember).filter(
            VaultMember.vault_id == vault_id
        ).all()
    
    def get_accepted_members(self, db: Session, vault_id: UUID) -> List[VaultMember]:
        """Get accepted members of a vault."""
        return db.query(VaultMember).filter(
            VaultMember.vault_id == vault_id,
            VaultMember.status == MemberStatus.ACCEPTED
        ).all()
    
    def add_member(
        self, 
        db: Session, 
        vault_id: UUID, 
        user_id: int,
        role: MemberRole = MemberRole.MEMBER,
        status: MemberStatus = MemberStatus.PENDING
    ) -> VaultMember:
        """Add a user as a member to a vault."""
        member = VaultMember(
            vault_id=vault_id,
            user_id=user_id,
            role=role,
            status=status,
            joined_at=datetime.utcnow() if status == MemberStatus.ACCEPTED else None,
        )
        db.add(member)
        db.commit()
        db.refresh(member)
        return member
    
    def accept_membership(self, db: Session, member: VaultMember) -> VaultMember:
        """Accept a pending membership."""
        member.status = MemberStatus.ACCEPTED
        member.joined_at = datetime.utcnow()
        db.commit()
        db.refresh(member)
        return member
    
    def revoke_membership(self, db: Session, member: VaultMember) -> VaultMember:
        """Revoke a membership."""
        member.status = MemberStatus.REVOKED
        db.commit()
        db.refresh(member)
        return member
    
    def remove_member(self, db: Session, member: VaultMember) -> None:
        """Remove a member from a vault."""
        db.delete(member)
        db.commit()
    
    def get_pending_invites(self, db: Session, user_id: int) -> List[VaultMember]:
        """Get pending vault invites for a user."""
        return db.query(VaultMember).filter(
            VaultMember.user_id == user_id,
            VaultMember.status == MemberStatus.PENDING
        ).all()


# Singleton instances
vault_crud = VaultCRUD()
vault_member_crud = VaultMemberCRUD()


