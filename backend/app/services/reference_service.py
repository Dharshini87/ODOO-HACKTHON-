from typing import Union
from sqlalchemy.orm import Session
from sqlalchemy import text
from ..models.transaction import TransactionType


TYPE_TO_CODE = {
    TransactionType.RECEIPT: "IN",
    TransactionType.DELIVERY: "OUT",
    TransactionType.TRANSFER: "TR",
    TransactionType.ADJUSTMENT: "ADJ",
    "RECEIPT": "IN",
    "DELIVERY": "OUT",
    "TRANSFER": "TR",
    "ADJUSTMENT": "ADJ",
    "receipt": "IN",
    "delivery": "OUT",
    "transfer": "TR",
    "adjustment": "ADJ",
}


def get_next_sequence_value(db: Session, seq_name: str) -> int:
    """
    Section 41:
    Use PostgreSQL sequences.
    Never use: MAX(id) + 1
    In SQLite fallback, uses atomic table counter with RETURNING.
    """
    bind = db.get_bind()
    dialect = bind.dialect.name.lower()

    if "postgres" in dialect:
        # Create sequence if not exists
        db.execute(text(f"CREATE SEQUENCE IF NOT EXISTS {seq_name} START WITH 1 INCREMENT BY 1"))
        result = db.execute(text(f"SELECT nextval('{seq_name}')")).scalar()
        return int(result)
    else:
        # SQLite atomic sequence table
        db.execute(text("""
            CREATE TABLE IF NOT EXISTS reference_sequences (
                name TEXT PRIMARY KEY,
                current_val INTEGER NOT NULL DEFAULT 0
            )
        """))
        # Atomic upsert increment
        row = db.execute(text("""
            INSERT INTO reference_sequences (name, current_val)
            VALUES (:name, 1)
            ON CONFLICT(name) DO UPDATE SET current_val = reference_sequences.current_val + 1
            RETURNING current_val
        """), {"name": seq_name}).fetchone()
        if row:
            return int(row[0])
        # Fallback if RETURNING unsupported
        curr = db.execute(text("SELECT current_val FROM reference_sequences WHERE name = :name"), {"name": seq_name}).scalar()
        return int(curr or 1)


def generate_transaction_reference(
    db: Session,
    tx_type: Union[TransactionType, str],
    warehouse_code: str = "WH",
) -> str:
    """
    Section 41:
    Backend generates references.
    Examples:
      WH/IN/0001
      WH/OUT/0001
      WH/TR/0001
      WH/ADJ/0001
    """
    code = TYPE_TO_CODE.get(tx_type, "TX")
    seq_name = f"seq_tx_{code.lower()}"
    next_val = get_next_sequence_value(db, seq_name)
    prefix = (warehouse_code or "WH").strip().upper()
    return f"{prefix}/{code}/{next_val:04d}"
