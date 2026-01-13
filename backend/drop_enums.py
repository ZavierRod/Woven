#!/usr/bin/env python3
"""Script to drop PostgreSQL ENUM types that persist after downgrade."""
from sqlalchemy import create_engine, text

DATABASE_URL = "postgresql://woven_user:woven_password@localhost:5433/woven"

def drop_enums():
    engine = create_engine(DATABASE_URL)
    with engine.connect() as conn:
        # Drop ENUM types in reverse dependency order
        enums = ['memberstatus', 'memberrole', 'vaultmode', 'vaulttype']
        
        for enum_name in enums:
            try:
                conn.execute(text(f'DROP TYPE IF EXISTS {enum_name} CASCADE'))
                conn.commit()
                print(f"✅ Dropped {enum_name}")
            except Exception as e:
                print(f"⚠️  Could not drop {enum_name}: {e}")
        
        print("\n✅ All ENUM types dropped. You can now run: alembic upgrade head")

if __name__ == "__main__":
    drop_enums()

