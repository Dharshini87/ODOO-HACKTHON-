import re
from typing import Dict, Any, List, Optional
from decimal import Decimal
from difflib import SequenceMatcher

from .. import models
from .ocr_service import ReceiptOCRResult, ReceiptParser


def string_similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, a.lower().strip(), b.lower().strip()).ratio()


def normalize_supplier(name: Optional[str]) -> str:
    if not name:
        return ""
    clean = name.lower()
    # Remove common business suffixes and special characters
    clean = re.sub(r"\b(pvt|ltd|limited|inc|incorporated|corp|corporation|llc|gmbh|co|company|enterprises)\b", "", clean)
    clean = re.sub(r"[^a-z0-9\s]", " ", clean)
    return " ".join(clean.split())


class ReceiptMatchingService:
    """
    Receipt Matching Engine (Sections 16 - 25).
    Compares physical extracted receipt against digital StockSense Transaction.
    NEVER mutates inventory or database state.
    Returns clear, structured comparison payloads.
    """

    @classmethod
    def compare(
        cls,
        tx: models.Transaction,
        ocr_result: ReceiptOCRResult,
    ) -> Dict[str, Any]:
        issues: List[str] = []
        overall_status = "MATCH"
        
        # 1. Supplier Comparison (Section 17)
        system_supplier = tx.party_name or tx.contact or "Vendor"
        ocr_supplier = ocr_result.supplier or "Unknown Supplier"
        
        norm_sys_sup = normalize_supplier(system_supplier)
        norm_ocr_sup = normalize_supplier(ocr_supplier)
        
        supplier_sim = string_similarity(norm_sys_sup, norm_ocr_sup) if norm_sys_sup and norm_ocr_sup else 0.0
        contains_match = (norm_sys_sup in norm_ocr_sup or norm_ocr_sup in norm_sys_sup) if (len(norm_sys_sup) >= 3 and len(norm_ocr_sup) >= 3) else False
        
        # Word overlap check (e.g. "ABC Steel Industries" vs "ABC Steel")
        sys_tokens = [t for t in norm_sys_sup.split() if len(t) >= 3]
        ocr_tokens = [t for t in norm_ocr_sup.split() if len(t) >= 3]
        overlap_count = sum(1 for t in sys_tokens if t in ocr_tokens or any(string_similarity(t, ot) > 0.8 for ot in ocr_tokens))
        token_match = (overlap_count >= max(1, len(sys_tokens) - 1)) if sys_tokens else False

        supplier_match = contains_match or (supplier_sim >= 0.70) or token_match

        # If digital supplier is generic ("Vendor"), we don't treat it as a hard failure, but log if specific
        if system_supplier.lower() not in ["vendor", "supplier", "default vendor"] and not supplier_match:
            supplier_status = "MISMATCH"
            issues.append(f"Supplier mismatch: digital receipt specifies '{system_supplier}', but physical receipt reads '{ocr_supplier}'.")
            overall_status = "REVIEW_REQUIRED"
        else:
            supplier_status = "MATCH"

        # 2. Receipt Number Comparison (Section 18)
        system_ref = tx.reference or ""
        ocr_ref = ocr_result.receipt_number or ""
        
        ref_match = False
        explicit_vendor_ref_in_system = False

        # Check if the system has an explicit supplier invoice reference recorded
        candidates = [system_ref]
        if tx.contact:
            candidates.append(tx.contact)
        if tx.reason:
            candidates.append(tx.reason)
        if tx.party_name:
            candidates.append(tx.party_name)

        for cand in candidates:
            if not cand:
                continue
            if ocr_ref and (ocr_ref.lower() in cand.lower() or cand.lower() in ocr_ref.lower() or string_similarity(cand, ocr_ref) >= 0.80):
                ref_match = True
                explicit_vendor_ref_in_system = True
                break
            # Check if candidate looks like a vendor invoice (e.g. INV-..., BILL-...)
            if re.search(r"\b(inv|bill|rcpt|po|ord)[-_0-9a-z]+\b", cand, re.IGNORECASE):
                explicit_vendor_ref_in_system = True

        if ocr_ref:
            if ref_match:
                receipt_num_status = "MATCH"
            elif explicit_vendor_ref_in_system:
                # Digital receipt explicitly recorded a supplier invoice number and it differs
                receipt_num_status = "MISMATCH"
                issues.append(f"Receipt number mismatch: digital record specifies invoice '{system_ref}', physical receipt reads '{ocr_ref}'.")
                overall_status = "REVIEW_REQUIRED"
            else:
                # System only has internal auto-generated WH/IN/xxxx reference
                receipt_num_status = "MATCH"
        else:
            receipt_num_status = "MATCH"

        # 3. Item & Quantity Comparison (Section 19, 20, 21, 22)
        items_result: List[Dict[str, Any]] = []
        
        system_items = tx.items or []
        ocr_items = ocr_result.items or []

        matched_ocr_indices = set()

        for sys_item in system_items:
            prod_name = sys_item.product.name if sys_item.product else "Unknown Product"
            prod_sku = sys_item.product.sku if sys_item.product else ""
            sys_qty = float(sys_item.quantity)
            sys_unit = ReceiptParser.normalize_unit(sys_item.product.unit_of_measure if sys_item.product else "unit")

            best_ocr_item: Optional[Any] = None
            best_ocr_idx = -1
            best_match_score = -1.0

            # Match priority: 1. SKU, 2. Exact name, 3. Fuzzy description
            for idx, ocr_it in enumerate(ocr_items):
                if idx in matched_ocr_indices:
                    continue
                score = 0.0
                if ocr_it.sku and prod_sku and ocr_it.sku.lower() == prod_sku.lower():
                    score = 1.0
                else:
                    sim = string_similarity(prod_name, ocr_it.description)
                    norm_prod = prod_name.lower().replace("-", " ")
                    norm_desc = ocr_it.description.lower().replace("-", " ")
                    if norm_prod in norm_desc or norm_desc in norm_prod:
                        score = max(sim, 0.85)
                    else:
                        score = sim

                if score > best_match_score and score >= 0.40:
                    best_match_score = score
                    best_ocr_item = ocr_it
                    best_ocr_idx = idx

            if best_ocr_item:
                matched_ocr_indices.add(best_ocr_idx)
                ocr_qty = float(best_ocr_item.quantity)
                ocr_unit = ReceiptParser.normalize_unit(best_ocr_item.unit)
                diff = round(ocr_qty - sys_qty, 3)

                # Unit check
                unit_matches = (sys_unit == ocr_unit)

                # Quantity check
                qty_matches = (abs(diff) < 0.001)

                if qty_matches and unit_matches:
                    it_status = "MATCH"
                else:
                    it_status = "MISMATCH"
                    overall_status = "REVIEW_REQUIRED"
                    if not qty_matches:
                        issues.append(
                            f"Quantity mismatch for '{prod_name}': System has {sys_qty} {sys_unit}, physical receipt has {ocr_qty} {ocr_unit} (Difference: {diff:+g} {sys_unit})."
                        )
                    if not unit_matches:
                        issues.append(
                            f"Unit mismatch for '{prod_name}': System expects '{sys_unit}', physical receipt indicates '{ocr_unit}'."
                        )

                items_result.append({
                    "product_id": sys_item.product_id,
                    "product_name": prod_name,
                    "sku": prod_sku,
                    "status": it_status,
                    "system_quantity": sys_qty,
                    "ocr_quantity": ocr_qty,
                    "difference": diff,
                    "system_unit": sys_unit,
                    "ocr_unit": ocr_unit,
                    "confidence": best_ocr_item.confidence,
                })
            else:
                # System item not found on physical receipt
                overall_status = "REVIEW_REQUIRED"
                issues.append(f"Product '{prod_name}' ({prod_sku}) was not identified on the uploaded physical receipt.")
                items_result.append({
                    "product_id": sys_item.product_id,
                    "product_name": prod_name,
                    "sku": prod_sku,
                    "status": "NOT_FOUND",
                    "system_quantity": sys_qty,
                    "ocr_quantity": None,
                    "difference": -sys_qty,
                    "system_unit": sys_unit,
                    "ocr_unit": None,
                    "confidence": 0.0,
                })

        # Check for unmapped physical items
        for idx, ocr_it in enumerate(ocr_items):
            if idx not in matched_ocr_indices:
                issues.append(f"Additional item detected on physical receipt: '{ocr_it.description}' (Qty: {ocr_it.quantity} {ocr_it.unit}).")
                if overall_status == "MATCH":
                    overall_status = "REVIEW_REQUIRED"

        # 4. Confidence Evaluation (Section 23)
        if ocr_result.confidence < 0.70 and overall_status == "MATCH":
            overall_status = "LOW_CONFIDENCE"
            issues.append(f"OCR extraction confidence ({round(ocr_result.confidence * 100, 1)}%) is below acceptable threshold; human review advised.")

        return {
            "status": overall_status,
            "confidence": round(ocr_result.confidence, 4),
            "supplier": {
                "status": supplier_status,
                "system": system_supplier,
                "ocr": ocr_supplier,
            },
            "receipt_number": {
                "status": receipt_num_status,
                "system": system_ref,
                "ocr": ocr_ref,
            },
            "receipt_date": {
                "system": tx.schedule_date.strftime("%Y-%m-%d") if tx.schedule_date else None,
                "ocr": ocr_result.receipt_date,
            },
            "items": items_result,
            "issues": issues,
            "extracted_document": ocr_result.to_dict(),
        }
