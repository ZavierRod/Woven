# Alembic Migrations

Database schema migrations for Woven.

## What is Alembic?

Alembic tracks changes to your SQLAlchemy models and generates migration scripts to safely update your database schema without losing data.

## Directory Structure

```
alembic/
├── versions/           # Migration files (auto-generated)
│   └── xxxx_description.py
├── env.py              # Alembic environment configuration
├── script.py.mako      # Template for new migrations
└── README.md           # This file
```

## Common Commands

### Create a New Migration
After modifying a model in `app/models/`:

```bash
alembic revision --autogenerate -m "Add column X to table Y"
```

### Apply All Migrations
```bash
alembic upgrade head
```

### Rollback Last Migration
```bash
alembic downgrade -1
```

### View Migration History
```bash
alembic history
```

### View Current Revision
```bash
alembic current
```

### Create Empty Migration (for manual SQL)
```bash
alembic revision -m "Manual migration description"
```

## Migration History

| Revision | Description | Date |
|----------|-------------|------|
| `1f800961f8ae` | Initial migration - User model | Dec 2025 |

## Best Practices

### 1. Always Review Generated Migrations
Alembic's autogenerate is smart but not perfect. Always review before applying:
```bash
# Check the generated file in alembic/versions/
cat alembic/versions/xxxx_new_migration.py
```

### 2. Test Migrations Locally First
```bash
# Apply migration
alembic upgrade head

# Verify it works
python -c "from app.db.base import Base; print('OK')"

# If something's wrong, rollback
alembic downgrade -1
```

### 3. Never Edit Applied Migrations
Once a migration is in production, create a new migration to fix issues.

### 4. Add Models to `app/db/base.py`
For Alembic to detect new models, import them in `base.py`:
```python
from app.models.vault import Vault  # noqa
```

## Upcoming Migrations (per Roadmap)

### Phase 1 - Solo Vault
- [ ] Add `vaults` table
- [ ] Add `vault_media` table
- [ ] Add `vault_members` table

### Phase 2 - Pairing
- [ ] Add `friends` table
- [ ] Add `friend_invites` table

### Phase 3 - Strict Mode
- [ ] Add `access_requests` table
- [ ] Add `devices` table (for APNs tokens)

### Phase 4 - Screenshot Detection
- [ ] Add `screenshot_events` table

### Phase 5 - Safety
- [ ] Add `audit_logs` table
- [ ] Add `key_rotations` table

## Troubleshooting

### "Target database is not up to date"
```bash
alembic upgrade head
```

### "Can't locate revision"
Check if the revision file exists in `versions/`. If deleted, you may need to stamp:
```bash
alembic stamp head
```

### Circular Import Errors
Ensure all model imports in `app/db/base.py` use absolute imports.


