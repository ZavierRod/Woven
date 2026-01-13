# Import Base and all models here so Alembic can detect them
# This file is imported by alembic/env.py

from app.db.session import Base  # noqa

# Import all models to register them with Base.metadata
from app.models.user import User  # noqa
from app.models.vault import Vault, VaultMember  # noqa
from app.models.device import DeviceToken  # noqa
from app.models.friendship import Friendship  # noqa
from app.models.access_request import AccessRequest  # noqa

