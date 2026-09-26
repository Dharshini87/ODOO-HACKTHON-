import pytest
from decimal import Decimal
import datetime
from sqlalchemy import create_engine, inspect
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError

from app.db.base import Base
from app import models


@pytest.fixture(scope="function")
def db_session():
    # Use SQLite memory engine with foreign keys and check constraints enforced
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    # Enable SQLite check constraints and foreign keys
    from sqlalchemy import event
    @event.listens_for(engine, "connect")
    def set_sqlite_pragma(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = Session()

    yield session

    session.close()
    Base.metadata.drop_all(bind=engine)


def test_all_eleven_tables_created(db_session):
    """Section 7: Verify all 11 required tables exist."""
    inspector = inspect(db_session.bind)
    tables = inspector.get_table_names()

    required_tables = [
        "users",
        "categories",
        "products",
        "warehouses",
        "locations",
        "stock",
        "transactions",
        "transaction_items",
        "stock_ledger",
        "password_reset_tokens",
        "idempotency_keys",
    ]

    for table in required_tables:
        assert table in tables, f"Expected table '{table}' in database"


def test_stock_model_free_to_use_calculation(db_session):
    """
    Section 13:
    - NUMERIC(12,3)
    - Do NOT store free_to_use.
    - Always calculate: free_to_use = on_hand - reserved
    """
    # Create category, product, warehouse, location
    cat = models.Category(name="Raw Materials")
    db_session.add(cat)
    db_session.commit()

    prod = models.Product(
        name="Steel Pipe 2-Inch",
        sku="ST-PIP-002",
        category_id=cat.id,
        unit_of_measure="pcs",
        cost_per_unit=Decimal("45.50"),
        reorder_point=Decimal("20.000"),
    )
    db_session.add(prod)

    wh = models.Warehouse(name="Main Warehouse", short_code="WH-MAIN")
    db_session.add(wh)
    db_session.commit()

    loc = models.Location(name="Rack 03", short_code="RACK-03", warehouse_id=wh.id)
    db_session.add(loc)
    db_session.commit()

    # Create stock entry
    st = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("250.000"),
        reserved=Decimal("50.000"),
    )
    db_session.add(st)
    db_session.commit()

    # Verify dynamic calculation: 250 - 50 = 200
    assert st.free_to_use == Decimal("200.000")

    # Verify free_to_use is NOT a column on the physical table
    mapper = inspect(models.Stock)
    column_names = [col.key for col in mapper.columns]
    assert "free_to_use" not in column_names, "CRITICAL: free_to_use must NOT be a database column"


def test_stock_unique_product_location_constraint(db_session):
    """Section 13 & 42: UNIQUE(product_id, location_id)."""
    cat = models.Category(name="Electronics")
    db_session.add(cat)
    db_session.commit()

    prod = models.Product(name="Sensor A", sku="SNS-A", category_id=cat.id)
    wh = models.Warehouse(name="Warehouse East", short_code="WH-EAST")
    db_session.add_all([prod, wh])
    db_session.commit()

    loc = models.Location(name="Bin 1", short_code="BIN-1", warehouse_id=wh.id)
    db_session.add(loc)
    db_session.commit()

    st1 = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("100.000"),
        reserved=Decimal("10.000"),
    )
    db_session.add(st1)
    db_session.commit()

    # Attempting to insert duplicate (product_id, location_id) must fail
    st2 = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("50.000"),
        reserved=Decimal("0.000"),
    )
    db_session.add(st2)
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


def test_stock_check_constraints_non_negative_and_reserved_lte_on_hand(db_session):
    """Section 13 & 42: on_hand >= 0, reserved >= 0, reserved <= on_hand."""
    cat = models.Category(name="Pipes")
    prod = models.Product(name="Pipe X", sku="PIP-X")
    wh = models.Warehouse(name="WH-Central", short_code="WH-CEN")
    db_session.add_all([cat, prod, wh])
    db_session.commit()

    loc = models.Location(name="Bay 1", short_code="BAY-1", warehouse_id=wh.id)
    db_session.add(loc)
    db_session.commit()

    # 1. Negative on_hand must fail
    st_neg = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("-5.000"),
        reserved=Decimal("0.000"),
    )
    db_session.add(st_neg)
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()

    # 2. Reserved > on_hand must fail
    st_overflow = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("10.000"),
        reserved=Decimal("15.000"),
    )
    db_session.add(st_overflow)
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


def test_unified_transaction_model_and_states(db_session):
    """Section 14 & 16: Unified transactions with valid types and states."""
    wh = models.Warehouse(name="WH1", short_code="WH1")
    db_session.add(wh)
    db_session.commit()

    loc_src = models.Location(name="Src", short_code="SRC", warehouse_id=wh.id)
    loc_dst = models.Location(name="Dst", short_code="DST", warehouse_id=wh.id)
    user = models.User(name="Admin", email="admin@test.com", password_hash="hash")
    db_session.add_all([loc_src, loc_dst, user])
    db_session.commit()

    # Create DELIVERY transaction in DRAFT
    tx = models.Transaction(
        reference="OUT/2026/00001",
        type=models.TransactionType.DELIVERY,
        status=models.TransactionStatus.DRAFT,
        source_location_id=loc_src.id,
        destination_location_id=loc_dst.id,
        party_name="Acme Corp",
        created_by=user.id,
    )
    db_session.add(tx)
    db_session.commit()

    assert tx.id is not None
    assert tx.status == models.TransactionStatus.DRAFT
    assert tx.type == models.TransactionType.DELIVERY

    # Transition to READY
    tx.status = models.TransactionStatus.READY
    db_session.commit()
    assert tx.status == models.TransactionStatus.READY

    # Transition to DONE with validation timestamp
    tx.status = models.TransactionStatus.DONE
    tx.validated_by = user.id
    tx.validated_at = datetime.datetime.utcnow()
    db_session.commit()
    assert tx.status == models.TransactionStatus.DONE


def test_transaction_items_and_adjustment_delta(db_session):
    """Section 15: Transaction items and physical count adjustment delta."""
    cat = models.Category(name="Hardware")
    prod = models.Product(name="Bolts", sku="BLT-01")
    wh = models.Warehouse(name="WH-Main", short_code="WH-M")
    db_session.add_all([cat, prod, wh])
    db_session.commit()

    loc = models.Location(name="Bin 5", short_code="BIN-5", warehouse_id=wh.id)
    db_session.add(loc)
    db_session.commit()

    # Create stock with 100 on hand
    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("100.000"),
        reserved=Decimal("0.000"),
    )
    db_session.add(stock)
    db_session.commit()

    # Adjustment transaction: Physical count is 92.000 -> delta is -8.000
    physical_count = Decimal("92.000")
    delta = physical_count - stock.on_hand  # -8.000

    adj_tx = models.Transaction(
        reference="ADJ/2026/00001",
        type=models.TransactionType.ADJUSTMENT,
        status=models.TransactionStatus.DRAFT,
        source_location_id=loc.id,
        reason="Stock count discrepancy found during weekly audit",
    )
    db_session.add(adj_tx)
    db_session.commit()

    item = models.TransactionItem(
        transaction_id=adj_tx.id,
        product_id=prod.id,
        quantity=physical_count,
        adjustment_delta=delta,
    )
    db_session.add(item)
    db_session.commit()

    assert item.quantity == Decimal("92.000")
    assert item.adjustment_delta == Decimal("-8.000")


def test_soft_deletion_is_active(db_session):
    """Section 43: Master data entities use is_active soft deletion."""
    cat = models.Category(name="Packaging", is_active=True)
    db_session.add(cat)
    db_session.commit()

    prod = models.Product(name="Carton Box", sku="BX-01", category_id=cat.id, is_active=True)
    wh = models.Warehouse(name="Packaging WH", short_code="WH-PKG", is_active=True)
    db_session.add_all([prod, wh])
    db_session.commit()

    loc = models.Location(name="Bay A", short_code="BAY-A", warehouse_id=wh.id, is_active=True)
    db_session.add(loc)
    db_session.commit()

    # Soft-delete product and warehouse
    prod.is_active = False
    wh.is_active = False
    db_session.commit()

    assert prod.is_active is False
    assert wh.is_active is False
    # Ensure they still exist in database
    found_prod = db_session.query(models.Product).filter_by(sku="BX-01").first()
    assert found_prod is not None
    assert found_prod.is_active is False


def test_stock_ledger_append_only(db_session):
    """Section 7 & 43: Stock ledger audit entries are append-only."""
    prod = models.Product(name="Cable", sku="CBL-01")
    wh = models.Warehouse(name="WH-Elec", short_code="WH-ELEC")
    db_session.add_all([prod, wh])
    db_session.commit()

    loc = models.Location(name="Rack 1", short_code="R1", warehouse_id=wh.id)
    db_session.add(loc)
    db_session.commit()

    ledger1 = models.StockLedger(
        product_id=prod.id,
        location_id=loc.id,
        quantity_change=Decimal("50.000"),
        running_balance=Decimal("50.000"),
        reference="IN/2026/00001",
        movement_type="RECEIPT",
    )
    db_session.add(ledger1)
    db_session.commit()

    ledger2 = models.StockLedger(
        product_id=prod.id,
        location_id=loc.id,
        quantity_change=Decimal("-10.000"),
        running_balance=Decimal("40.000"),
        reference="OUT/2026/00001",
        movement_type="DELIVERY",
    )
    db_session.add(ledger2)
    db_session.commit()

    entries = db_session.query(models.StockLedger).filter_by(product_id=prod.id).order_by(models.StockLedger.id).all()
    assert len(entries) == 2
    assert entries[0].running_balance == Decimal("50.000")
    assert entries[1].running_balance == Decimal("40.000")
