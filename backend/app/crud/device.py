from sqlalchemy.orm import Session
from datetime import datetime
from typing import List, Optional

from app.models.device import DeviceToken
from app.schemas.device import DeviceRegisterRequest

class CRUDDevice:
    def register_or_update(
        self, db: Session, user_id: int, device_in: DeviceRegisterRequest
    ) -> DeviceToken:
        # Check if token already exists for this device
        db_device = db.query(DeviceToken).filter(
            DeviceToken.device_id == device_in.device_id
        ).first()
        
        if db_device:
            # Update existing device
            db_device.token = device_in.token
            db_device.user_id = user_id  # Update user if device changed hands
            db_device.last_seen_at = datetime.now()
            db_device.apns_environment = device_in.apns_environment
            db_device.platform = device_in.platform
        else:
            # Create new device
            db_device = DeviceToken(
                user_id=user_id,
                device_id=device_in.device_id,
                token=device_in.token,
                platform=device_in.platform,
                apns_environment=device_in.apns_environment
            )
            db.add(db_device)
        
        db.commit()
        db.refresh(db_device)
        return db_device

    def get_user_devices(self, db: Session, user_id: int) -> List[DeviceToken]:
        return db.query(DeviceToken).filter(DeviceToken.user_id == user_id).all()

    def remove_device(self, db: Session, device_id: str):
        db.query(DeviceToken).filter(DeviceToken.device_id == device_id).delete()
        db.commit()

device_crud = CRUDDevice()
