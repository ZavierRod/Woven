# Database Module

Database configuration, connection management, and model registry.

## Current Files

### `session.py`
Database engine and session configuration.

**Exports:**
- `engine` - SQLAlchemy engine connected to PostgreSQL
- `SessionLocal` - Session factory for database operations
- `Base` - Declarative base for all models

### `base.py`
Model registry for Alembic migrations.

**Purpose:**
- Imports all models so Alembic can detect schema changes
- Single source of truth for model registration

**Usage:**
When you create a new model, add an import here:
```python
from app.models.vault import Vault  # noqa
```

## Database Connection

**Default URL:** `postgresql://woven_user:woven_password@localhost:5433/woven`

Can be overridden via `DATABASE_URL` environment variable.

## Current Status ✅

- [x] PostgreSQL connection
- [x] Session management
- [x] Alembic integration

## Future Considerations

### Connection Pooling
For production, consider:
```python
engine = create_engine(
    settings.DATABASE_URL,
    pool_size=5,
    max_overflow=10,
    pool_pre_ping=True,
)
```

### Read Replicas
For scale, add read-only session:
```python
ReadOnlySessionLocal = sessionmaker(bind=read_replica_engine)
```

### Redis Cache
May add for:
- Access request state caching
- Rate limiting
- Session management


