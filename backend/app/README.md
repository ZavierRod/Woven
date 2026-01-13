# App Module

The main FastAPI application module for Woven.

## Structure

```
app/
├── core/           # Configuration, security, constants
├── crud/           # Database CRUD operations
├── db/             # Database connection & models registry
├── models/         # SQLAlchemy ORM models
├── routers/        # API endpoint handlers
├── schemas/        # Pydantic request/response schemas
├── services/       # Business logic & external integrations
├── deps.py         # Shared FastAPI dependencies
└── main.py         # FastAPI app entry point
```

## Key Files

### `main.py`
The FastAPI application entry point. Configures middleware, includes routers, and defines health check endpoints.

### `deps.py`
Shared dependencies used across routers:
- `get_db()` - Database session dependency

## Current Status ✅

- [x] Basic app structure
- [x] Authentication router (email/password signup & login)
- [x] User management with invite codes
- [x] Health check endpoints
- [x] Vault router & management (create, list, get, update, delete)
- [x] Vault membership (invite, accept/decline, leave)

## Future Additions (per Roadmap)

- [ ] Media upload/download endpoints
- [ ] Friends/Pairing system (dedicated friend connections)
- [ ] Access Request flow (push approvals)
- [ ] Push notification integration (APNs)
- [ ] Audit logging middleware


