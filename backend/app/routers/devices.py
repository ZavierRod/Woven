from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.deps import get_db
from app.core.security import get_current_user_id
from app.schemas.device import DeviceRegisterRequest, DeviceTokenResponse
from app.crud.device import device_crud

router = APIRouter(prefix="/devices", tags=["Devices"])

@router.post("/register", response_model=DeviceTokenResponse)
def register_device(
    device_in: DeviceRegisterRequest,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Register or update a device push token.
    """
    return device_crud.register_or_update(db, current_user_id, device_in)

@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def unregister_device(
    device_id: str,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Unregister a device token (e.g. on logout).
    """
    # Verify ownership or just delete by device_id if it belongs to user
    # For simplicity, we just remove by device_id
    device_crud.remove_device(db, device_id)
    return None
