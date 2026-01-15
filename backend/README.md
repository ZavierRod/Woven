# Woven Backend

FastAPI backend for the Woven iOS application - a secure, encrypted vault for private media.

## 🏗️ Project Structure

```
backend/
├── alembic/                 # Database migrations
│   ├── versions/            # Migration files
│   ├── env.py               # Alembic configuration
│   └── README.md            # Migration guide
├── app/
│   ├── core/                # Configuration & security
│   │   ├── config.py        # Settings (env vars)
│   │   ├── security.py      # JWT & auth helpers
│   │   └── README.md
│   ├── crud/                # Database operations
│   │   ├── user.py          # User CRUD
│   │   ├── vault.py         # Vault & VaultMember CRUD
│   │   └── README.md
│   ├── db/                  # Database setup
│   │   ├── base.py          # Model registry
│   │   ├── session.py       # Engine & session
│   │   └── README.md
│   ├── models/              # SQLAlchemy models
│   │   ├── user.py          # User model
│   │   ├── vault.py         # Vault & VaultMember models
│   │   └── README.md
│   ├── routers/             # API endpoints
│   │   ├── auth.py          # /auth/* endpoints
│   │   ├── users.py         # /users/* endpoints
│   │   ├── vaults.py        # /vaults/* endpoints
│   │   └── README.md
│   ├── schemas/             # Pydantic schemas
│   │   ├── auth.py          # Auth request/response
│   │   ├── user.py          # User request/response
│   │   ├── vault.py         # Vault request/response
│   │   └── README.md
│   ├── services/            # Business logic
│   │   └── README.md
│   ├── deps.py              # Shared dependencies
│   ├── main.py              # FastAPI app
│   └── README.md
├── alembic.ini              # Alembic config
├── docker-compose.yml       # PostgreSQL container
├── .gitignore
├── README.md                # This file
└── requirements.txt         # Dependencies
```

> 📚 **Each folder has a README.md** explaining current contents and future additions based on the roadmap.

## 🚀 Quick Start

### 1. Start Database

```bash
docker compose up -d
```

### 2. Install Dependencies

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Run Migrations

```bash
# Apply all migrations
alembic upgrade head
```

### 4. Start Server

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

## 📖 API Documentation

- **Swagger UI**: http://localhost:8001/docs
- **ReDoc**: http://localhost:8001/redoc

## 🔧 Development

### Create a New Migration

After modifying models:
```bash
alembic revision --autogenerate -m "Description of changes"
alembic upgrade head
```

### Rollback a Migration

```bash
alembic downgrade -1
```

### View Migration Status

```bash
alembic current
alembic history
```

## ⚙️ Environment Variables

Create a `.env` file:

```env
DATABASE_URL=postgresql://woven_user:woven_password@localhost:5433/woven
SECRET_KEY=your-secret-key-change-in-production
DEBUG=true
```

## 📋 Current API Endpoints

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/signup` | Register with email/password |
| POST | `/auth/login` | Login with email/username + password |

### Users
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/users/me` | Get current user profile |
| GET | `/users/{invite_code}` | Find user by invite code |

### Vaults
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/vaults/` | Create a new vault |
| GET | `/vaults/` | List user's vaults |
| GET | `/vaults/{id}` | Get vault details |
| PATCH | `/vaults/{id}` | Update vault settings |
| DELETE | `/vaults/{id}` | Delete vault (owner only) |
| POST | `/vaults/{id}/invite` | Invite user to pair vault |
| GET | `/vaults/invites/pending` | Get pending invitations |
| POST | `/vaults/{id}/accept` | Accept vault invitation |
| POST | `/vaults/{id}/decline` | Decline vault invitation |
| DELETE | `/vaults/{id}/leave` | Leave vault (non-owner) |

### Media
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/media/` | Upload encrypted media file |
| GET | `/media/vault/{vault_id}` | List all media in a vault |
| GET | `/media/{id}/view-url` | Get temporary view URL |
| GET | `/media/{id}/view` | View media file (streaming, view-only) |
| DELETE | `/media/{id}` | Delete media (owner or uploader) |

### Health
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Health check |
| GET | `/health` | Detailed health check |

## 🗺️ Roadmap Status

Based on `roadmap.md`:

- [x] **Phase 0**: Project setup, Auth (email/password)
- [x] **Phase 1**: Solo Vault (create, list, update, delete) ✅
- [x] **Phase 2**: Pairing (vault invites, accept/decline, leave) ✅
- [x] **Phase 1b**: Media upload + view-only display ✅
- [ ] **Phase 1c**: On-device encryption with AES-GCM
- [ ] **Phase 2b**: Dedicated Friends system
- [ ] **Phase 3**: Strict Mode & Push Approvals
- [ ] **Phase 4**: Screenshot/Recording Detection
- [ ] **Phase 5**: Key Rotation & Revocation

## 🔐 Security Model

- **Server stores only encrypted blobs** - no plaintext media
- **AES-GCM encryption** on-device
- **Pair vaults** use 2-of-2 key splitting (XOR)
- **Strict mode** requires push approval for every unlock

See `roadmap.md` for full cryptography details.

