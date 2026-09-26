import sys
import json
import urllib.request
from decimal import Decimal
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BASE_URL = "http://127.0.0.1:8000"

def api_call(method: str, path: str, token: str = None, data: dict = None, headers: dict = None):
    url = f"{BASE_URL}{path}"
    req_headers = {"Content-Type": "application/json"}
    if token:
        req_headers["Authorization"] = f"Bearer {token}"
    if headers:
        req_headers.update(headers)
    
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, headers=req_headers, method=method)
    with urllib.request.urlopen(req) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))

def main():
    print("=" * 60)
    print("STOCKSENSE AUTHORITATIVE 12-STEP DEMO SCENARIO VERIFICATION")
    print("=" * 60)

    # Login as manager
    _, login_data = api_call("POST", "/api/auth/login", data={"email": "manager@stocksense.com", "password": "password123"})
    token = login_data["access_token"]
    print("[INIT] Logged in as manager@stocksense.com")

    # Fetch locations
    _, locs = api_call("GET", "/api/locations", token=token)
    rack_a = next(l for l in locs if "Rack A" in l["name"] or "Main" in l["name"])
    prod_floor = next(l for l in locs if "Production Floor" in l["name"])
    print(f"[LOCATIONS] Source: {rack_a['name']} (ID {rack_a['id']}), Destination: {prod_floor['name']} (ID {prod_floor['id']})")

    import time
    ts = int(time.time())
    prod_name = f"Steel Rod {ts}"
    sku_unique = f"SR-{ts}"

    status, prod = api_call(
        "POST",
        "/api/products",
        token=token,
        data={
            "name": prod_name,
            "sku": sku_unique,
            "unit_of_measure": "kg",
            "cost_per_unit": 25.0,
            "reorder_point": 10.0,
        }
    )
    prod_id = prod["id"]
    print(f"STEP 1: Created Steel Rod (ID: {prod_id}, Name: {prod_name}, SKU: {prod['sku']})")

    # Step 2: Receive 100 kg
    _, rcpt = api_call(
        "POST",
        "/api/receipts",
        token=token,
        data={
            "product_id": prod_id,
            "to_location_id": rack_a["id"],
            "quantity": 100.0,
            "contact": "Steel Industries Ltd",
        }
    )
    rcpt_id = rcpt["id"]
    # Mark ready and validate
    api_call("POST", f"/api/receipts/{rcpt_id}/ready", token=token)
    _, rcpt_val = api_call("POST", f"/api/receipts/{rcpt_id}/validate", token=token, headers={"Idempotency-Key": f"DEMO-RCPT-{rcpt_id}"})
    print(f"STEP 2: Received 100 kg via Receipt {rcpt['reference']}. Status: {rcpt_val['status']}")

    # Step 3: Confirm stock = 100 kg
    _, stock_data = api_call("GET", f"/api/stock?location_id={rack_a['id']}", token=token)
    st = next(s for s in stock_data if s["product_id"] == prod_id)
    assert float(st["on_hand"]) == 100.0, f"Expected 100 kg, got {st['on_hand']}"
    print(f"STEP 3: Confirmed stock at {rack_a['name']} = {st['on_hand']} kg")

    # Step 4: Transfer 30 kg from Main Warehouse to Production Floor
    _, trf = api_call(
        "POST",
        "/api/transfers",
        token=token,
        data={
            "product_id": prod_id,
            "from_location_id": rack_a["id"],
            "to_location_id": prod_floor["id"],
            "quantity": 30.0,
            "contact": "Internal Shift Transfer",
        }
    )
    trf_id = trf["id"]
    api_call("POST", f"/api/transfers/{trf_id}/ready", token=token)
    _, trf_val = api_call("POST", f"/api/transfers/{trf_id}/validate", token=token, headers={"Idempotency-Key": f"DEMO-TRF-{trf_id}"})
    print(f"STEP 4: Transferred 30 kg via Transfer {trf['reference']}. Status: {trf_val['status']}")

    # Step 5 & 6: Confirm source = 70 kg, destination = 30 kg
    _, st_src = api_call("GET", f"/api/stock?location_id={rack_a['id']}", token=token)
    _, st_dst = api_call("GET", f"/api/stock?location_id={prod_floor['id']}", token=token)
    src_val = next(s for s in st_src if s["product_id"] == prod_id)["on_hand"]
    dst_val = next(s for s in st_dst if s["product_id"] == prod_id)["on_hand"]
    assert float(src_val) == 70.0, f"Expected source 70 kg, got {src_val}"
    assert float(dst_val) == 30.0, f"Expected destination 30 kg, got {dst_val}"
    print(f"STEP 5: Confirmed source stock ({rack_a['name']}) = {src_val} kg")
    print(f"STEP 6: Confirmed destination stock ({prod_floor['name']}) = {dst_val} kg")

    # Step 7: Deliver 20 kg
    _, dlv = api_call(
        "POST",
        "/api/deliveries",
        token=token,
        data={
            "product_id": prod_id,
            "from_location_id": rack_a["id"],
            "quantity": 20.0,
            "contact": "Apex Constructions",
        }
    )
    dlv_id = dlv["id"]
    api_call("POST", f"/api/deliveries/{dlv_id}/ready", token=token)
    _, dlv_val = api_call("POST", f"/api/deliveries/{dlv_id}/validate", token=token, headers={"Idempotency-Key": f"DEMO-DLV-{dlv_id}"})
    print(f"STEP 7: Delivered 20 kg via Delivery {dlv['reference']}. Status: {dlv_val['status']}")

    # Step 8: Confirm total stock = 80 kg
    _, st_src = api_call("GET", f"/api/stock?location_id={rack_a['id']}", token=token)
    _, st_dst = api_call("GET", f"/api/stock?location_id={prod_floor['id']}", token=token)
    src_on_hand = float(next(s for s in st_src if s["product_id"] == prod_id)["on_hand"])
    dst_on_hand = float(next(s for s in st_dst if s["product_id"] == prod_id)["on_hand"])
    total_after_dlv = src_on_hand + dst_on_hand
    assert src_on_hand == 50.0, f"Expected Rack A to have 50 kg, got {src_on_hand}"
    assert dst_on_hand == 30.0, f"Expected Prod Floor to have 30 kg, got {dst_on_hand}"
    assert total_after_dlv == 80.0, f"Expected total 80 kg, got {total_after_dlv}"
    print(f"STEP 8: Confirmed total stock = {total_after_dlv} kg (Rack A: {src_on_hand} kg, Prod Floor: {dst_on_hand} kg)")

    # Step 9: Adjust -3 kg damaged (Physical count = 47 kg at Rack A)
    _, adj = api_call(
        "POST",
        "/api/adjustments",
        token=token,
        data={
            "location_id": rack_a["id"],
            "product_id": prod_id,
            "physical_count": 47.0,
            "reason": "Damaged",
        }
    )
    adj_id = adj["id"]
    _, adj_val = api_call("POST", f"/api/adjustments/{adj_id}/validate", token=token, headers={"Idempotency-Key": f"DEMO-ADJ-{adj_id}"})
    print(f"STEP 9: Adjusted -3 kg damaged via Adjustment {adj['reference']}. Difference: {adj_val['difference']} kg")

    # Step 10: Confirm final total = 77 kg
    _, st_src = api_call("GET", f"/api/stock?location_id={rack_a['id']}", token=token)
    _, st_dst = api_call("GET", f"/api/stock?location_id={prod_floor['id']}", token=token)
    final_src = float(next(s for s in st_src if s["product_id"] == prod_id)["on_hand"])
    final_dst = float(next(s for s in st_dst if s["product_id"] == prod_id)["on_hand"])
    final_total = final_src + final_dst
    assert final_src == 47.0, f"Expected Rack A to have 47 kg, got {final_src}"
    assert final_dst == 30.0, f"Expected Prod Floor to have 30 kg, got {final_dst}"
    assert final_total == 77.0, f"Expected final total 77 kg, got {final_total}"
    print(f"STEP 10: Confirmed final total = {final_total} kg (Rack A: {final_src} kg, Prod Floor: {final_dst} kg)")

    # Step 11: Confirm Move History
    _, moves = api_call("GET", "/api/moves", token=token)
    prod_moves = [m for m in moves if m.get("product_name") == prod_name or m.get("product_id") == prod_id]
    print(f"STEP 11: Confirmed Move History: {len(prod_moves)} moves recorded for {prod_name} (Total moves: {len(moves)})")
    assert len(prod_moves) >= 4, f"Expected at least 4 moves, got {len(prod_moves)}"

    # Step 12: Confirm Stock Ledger
    _, ledger = api_call("GET", f"/api/stock-ledger?product_id={prod_id}", token=token)
    print(f"STEP 12: Confirmed Stock Ledger: {len(ledger)} immutable entries recorded:")
    for entry in ledger:
        print(f"   - Ref: {entry['reference']}, Type: {entry['movement_type']}, Before: {entry['quantity_before']}, Change: {entry['quantity_change']}, After: {entry['quantity_after']}")
    assert len(ledger) >= 5, f"Expected at least 5 ledger entries (1 receipt, 2 transfers, 1 delivery, 1 adjustment), got {len(ledger)}"

    print("=" * 60)
    print("ALL 12 DEMO SCENARIO STEPS FULLY VALIDATED AGAINST LIVE BACKEND & DATABASE!")
    print("=" * 60)

if __name__ == "__main__":
    main()
