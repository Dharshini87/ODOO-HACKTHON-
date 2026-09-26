import os
import re
from typing import List, Dict, Any, Optional, Tuple
from decimal import Decimal
import pypdf
import pypdfium2 as pdfium
from PIL import Image, ImageOps, ImageEnhance
import numpy as np
from rapidocr_onnxruntime import RapidOCR

# Lazy singleton OCR instance to avoid reloading models on every request
_ocr_engine: Optional[RapidOCR] = None


def get_ocr_engine() -> RapidOCR:
    global _ocr_engine
    if _ocr_engine is None:
        _ocr_engine = RapidOCR()
    return _ocr_engine


class ReceiptItemOCR:
    def __init__(
        self,
        description: str,
        quantity: float,
        unit: str = "unit",
        sku: Optional[str] = None,
        unit_price: Optional[float] = None,
        total_price: Optional[float] = None,
        confidence: float = 0.90,
    ):
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.sku = sku
        self.unit_price = unit_price
        self.total_price = total_price
        self.confidence = confidence

    def to_dict(self) -> Dict[str, Any]:
        return {
            "description": self.description,
            "sku": self.sku,
            "quantity": self.quantity,
            "unit": self.unit,
            "unit_price": self.unit_price,
            "total_price": self.total_price,
            "confidence": round(self.confidence, 4),
        }


class ReceiptOCRResult:
    def __init__(
        self,
        supplier: Optional[str] = None,
        receipt_number: Optional[str] = None,
        receipt_date: Optional[str] = None,
        items: Optional[List[ReceiptItemOCR]] = None,
        subtotal: Optional[float] = None,
        tax: Optional[float] = None,
        total: Optional[float] = None,
        currency: Optional[str] = None,
        raw_text: str = "",
        page_count: int = 1,
        confidence: float = 0.90,
        field_confidences: Optional[Dict[str, float]] = None,
    ):
        self.supplier = supplier
        self.receipt_number = receipt_number
        self.receipt_date = receipt_date
        self.items = items or []
        self.subtotal = subtotal
        self.tax = tax
        self.total = total
        self.currency = currency
        self.raw_text = raw_text
        self.page_count = page_count
        self.confidence = confidence
        self.field_confidences = field_confidences or {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "supplier": self.supplier,
            "receipt_number": self.receipt_number,
            "receipt_date": self.receipt_date,
            "items": [it.to_dict() for it in self.items],
            "subtotal": self.subtotal,
            "tax": self.tax,
            "total": self.total,
            "currency": self.currency,
            "confidence": round(self.confidence, 4),
            "page_count": self.page_count,
            "field_confidences": {k: round(v, 4) for k, v in self.field_confidences.items()},
        }


class ReceiptParser:
    """
    Parses unstructured lines and extracted blocks into structured receipt entities.
    Extracts:
      - Supplier
      - Receipt/Invoice Number
      - Date
      - Items (Description, SKU, Quantity, Unit)
      - Financials (Subtotal, Tax, Total, Currency)
    """

    SUPPLIER_KEYWORDS = ["supplier", "vendor", "from", "sold by", "company", "issuer", "billed by"]
    INVOICE_KEYWORDS = ["invoice", "receipt", "bill", "doc", "reference", "ref no", "inv no", "order no"]
    UNIT_MAP = {
        "kg": "kg", "kgs": "kg", "kilogram": "kg", "kilograms": "kg",
        "g": "g", "gram": "g", "grams": "g",
        "unit": "unit", "units": "unit", "un": "unit",
        "pcs": "pcs", "pc": "pcs", "piece": "pcs", "pieces": "pcs",
        "m": "m", "meter": "m", "meters": "m",
        "l": "L", "ltr": "L", "liter": "L", "liters": "L", "litre": "L", "litres": "L",
        "box": "box", "boxes": "box", "pack": "pack", "packs": "pack",
    }

    @classmethod
    def normalize_unit(cls, u: Optional[str]) -> str:
        if not u:
            return "unit"
        clean = u.strip().lower().rstrip(".,")
        return cls.UNIT_MAP.get(clean, clean)

    @classmethod
    def parse(cls, lines_with_scores: List[Tuple[str, float]], page_count: int = 1) -> ReceiptOCRResult:
        full_text = "\n".join([line for line, _ in lines_with_scores])
        lines = [line.strip() for line, _ in lines_with_scores if line.strip()]

        supplier = None
        supplier_conf = 0.85
        receipt_number = None
        receipt_num_conf = 0.85
        receipt_date = None
        receipt_date_conf = 0.85
        total_val = None
        currency_val = None

        field_confidences: Dict[str, float] = {}

        # 1. Supplier Extraction
        # Look for explicit label: "Supplier: XYZ" or top lines before invoice details
        for text, score in lines_with_scores:
            low = text.lower()
            for kw in cls.SUPPLIER_KEYWORDS:
                if kw in low:
                    m = re.search(rf"{kw}\s*[:\-]?\s*([A-Za-z0-9\s&.,'()\-]+)", text, re.IGNORECASE)
                    if m and len(m.group(1).strip()) > 2:
                        raw_sup = m.group(1).strip()
                        supplier = re.sub(r"^[^a-zA-Z0-9]+", "", raw_sup).strip().rstrip(".,")
                        supplier_conf = max(supplier_conf, float(score))
                        break
            if supplier:
                break

        # If not explicitly labeled, examine top 3 header lines (often the company header)
        if not supplier and len(lines) > 0:
            for text, score in lines_with_scores[:4]:
                t = text.strip()
                low = t.lower()
                # Exclude lines that look like document titles or phone/date/address
                if (
                    not any(k in low for k in ["invoice", "receipt", "tax", "date", "phone", "email", "bill to", "ship to", "page"])
                    and not re.search(r"^\d", t)
                    and len(t) > 3
                ):
                    supplier = re.sub(r"^[^a-zA-Z0-9]+", "", t).strip().rstrip(".,")
                    supplier_conf = float(score) * 0.90
                    break

        # 2. Receipt / Invoice Number Extraction
        for text, score in lines_with_scores:
            # Pattern: INV-2026-00123, WH/IN/0001, REC-1234, etc.
            m = re.search(r"(?:invoice|receipt|inv|bill|ref|order)?\s*(?:no|number|#)?\s*[:.\-]?\s*([A-Z0-9\/\-]{4,25})", text, re.IGNORECASE)
            if m:
                cand = m.group(1).strip()
                # Filter out pure words or numbers that are dates
                if any(c.isdigit() for c in cand) and not re.match(r"^\d{4}\-\d{2}\-\d{2}$", cand):
                    receipt_number = cand
                    receipt_num_conf = float(score)
                    break

        if not receipt_number:
            # Direct regex search for common invoice formats: e.g. INV-xxxx, WH/IN/xxxx
            m = re.search(r"\b([A-Z]{2,4}[\/\-][A-Z0-9]{2,4}[\/\-][0-9]{3,8})\b", full_text)
            if m:
                receipt_number = m.group(1)
                receipt_num_conf = 0.92

        # 3. Date Extraction (YYYY-MM-DD, DD/MM/YYYY, DD-Mon-YYYY)
        date_patterns = [
            r"\b(\d{4}[-/]\d{1,2}[-/]\d{1,2})\b",
            r"\b(\d{1,2}[-/]\d{1,2}[-/]\d{4})\b",
            r"\b(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4})\b",
        ]
        for pat in date_patterns:
            m = re.search(pat, full_text, re.IGNORECASE)
            if m:
                receipt_date = m.group(1).strip()
                receipt_date_conf = 0.90
                break

        # 4. Total Amount / Currency
        total_m = re.search(r"(?:total|amount|grand\s+total|net\s+amount)\s*[:.\-]?\s*([$€£₹A-Z]{0,3})\s*([0-9,]+\.?[0-9]*)", full_text, re.IGNORECASE)
        if total_m:
            curr = total_m.group(1).strip()
            if curr:
                currency_val = curr
            amt_str = total_m.group(2).replace(",", "").strip()
            try:
                total_val = float(amt_str)
            except ValueError:
                pass

        # 5. Items Extraction (Line Items: description, SKU, quantity, unit)
        items: List[ReceiptItemOCR] = []
        
        # Unit keywords regex
        unit_regex_str = r"(kg|kgs|kilogram|kilograms|g|gram|grams|pcs|pc|piece|pieces|unit|units|un|boxes|box|m|meter|meters|liters|liter|litre|litres|l)"
        
        for text, score in lines_with_scores:
            line_clean = text.strip()
            # Try to match patterns like:
            # "Steel Rod - 100 kg"
            # "Steel Rod (SR-001): 100 kg"
            # "1. Steel Rod 100 kg"
            # "Steel Rod | SKU: STL-01 | Qty: 100 kg"
            # "Steel Rod 100.00 kg @ $25.00"

            # Check if line contains a quantity followed by unit or unit keyword
            qty_unit_match = re.search(
                rf"(?:qty|quantity)?\s*[:\-]?\s*(\d+(?:\.\d+)?)\s*{unit_regex_str}\b",
                line_clean,
                re.IGNORECASE,
            )
            if qty_unit_match:
                qty_val = float(qty_unit_match.group(1))
                unit_val = cls.normalize_unit(qty_unit_match.group(2))

                # Product description is usually the text before or around the quantity
                pre_text = line_clean[:qty_unit_match.start()].strip()
                # Clean leading numbering like "1.", "1 -", "Item 1:"
                pre_text = re.sub(r"^(?:item\s*)?\d+[\.\:\-]\s*", "", pre_text, flags=re.IGNORECASE)
                
                # Check for SKU inside description, e.g. "Steel Rod (SR-001)" or "SKU: SR-001"
                sku_val = None
                sku_m = re.search(r"\((?:sku:?\s*)?([A-Z0-9\-]+)\)", pre_text, re.IGNORECASE)
                if sku_m:
                    sku_val = sku_m.group(1)
                    pre_text = re.sub(r"\((?:sku:?\s*)?[A-Z0-9\-]+\)", "", pre_text, flags=re.IGNORECASE).strip()
                else:
                    sku_m2 = re.search(r"\bSKU\s*[:\-]?\s*([A-Z0-9\-]+)", line_clean, re.IGNORECASE)
                    if sku_m2:
                        sku_val = sku_m2.group(1)

                desc = pre_text.strip(" -:|")
                if not desc and qty_unit_match.end() < len(line_clean):
                    # Description might be after quantity
                    post_text = line_clean[qty_unit_match.end():].strip(" -:|")
                    if post_text:
                        desc = post_text

                if not desc:
                    desc = "Supplier Item"

                # Check for price if present
                price_m = re.search(r"[@x]\s*[$€£₹]?\s*(\d+(?:\.\d+)?)", line_clean)
                unit_price = float(price_m.group(1)) if price_m else None

                items.append(
                    ReceiptItemOCR(
                        description=desc,
                        quantity=qty_val,
                        unit=unit_val,
                        sku=sku_val,
                        unit_price=unit_price,
                        confidence=float(score),
                    )
                )

        # Fallback if no item pattern matched: search for any "number + unit"
        if not items:
            m = re.search(rf"(\d+(?:\.\d+)?)\s*{unit_regex_str}\b", full_text, re.IGNORECASE)
            if m:
                qty_val = float(m.group(1))
                unit_val = cls.normalize_unit(m.group(2))
                items.append(
                    ReceiptItemOCR(
                        description="Receipt Product",
                        quantity=qty_val,
                        unit=unit_val,
                        confidence=0.75,
                    )
                )

        # Overall confidence calculation
        scores = [s for _, s in lines_with_scores if s > 0]
        base_conf = float(np.mean(scores)) if scores else 0.85
        
        if supplier:
            field_confidences["supplier"] = supplier_conf
        if receipt_number:
            field_confidences["receipt_number"] = receipt_num_conf
        if receipt_date:
            field_confidences["receipt_date"] = receipt_date_conf
        if items:
            field_confidences["items"] = float(np.mean([it.confidence for it in items]))

        overall_conf = float(np.mean(list(field_confidences.values()))) if field_confidences else base_conf

        return ReceiptOCRResult(
            supplier=supplier,
            receipt_number=receipt_number,
            receipt_date=receipt_date,
            items=items,
            subtotal=None,
            tax=None,
            total=total_val,
            currency=currency_val,
            raw_text=full_text,
            page_count=page_count,
            confidence=overall_conf,
            field_confidences=field_confidences,
        )


class OCRService:
    """
    Orchestrates PDF text extraction, rasterization, image preprocessing,
    and RapidOCR execution behind a clean service interface (Section 9, 10, 11, 12).
    """

    @classmethod
    def extract_from_file(cls, file_path: str) -> ReceiptOCRResult:
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"File not found: {file_path}")

        _, ext = os.path.splitext(file_path)
        ext = ext.lower()

        if ext == ".pdf":
            return cls._process_pdf(file_path)
        elif ext in [".png", ".jpg", ".jpeg"]:
            return cls._process_image(file_path)
        else:
            raise ValueError(f"Unsupported file format: {ext}")

    @classmethod
    def _process_pdf(cls, pdf_path: str) -> ReceiptOCRResult:
        # Step 1: Check whether selectable embedded text exists (Section 11)
        extracted_lines: List[Tuple[str, float]] = []
        page_count = 1

        try:
            reader = pypdf.PdfReader(pdf_path)
            page_count = len(reader.pages)
            embedded_text = ""
            for idx, page in enumerate(reader.pages):
                txt = page.extract_text() or ""
                embedded_text += txt + "\n"

            embedded_text_clean = embedded_text.strip()
            # If significant selectable text exists (> 35 chars)
            if len(embedded_text_clean) > 35:
                for line in embedded_text_clean.splitlines():
                    l_s = line.strip()
                    if l_s:
                        extracted_lines.append((l_s, 0.98))  # Embedded text has near-perfect OCR confidence
                if len(extracted_lines) >= 2:
                    return ReceiptParser.parse(extracted_lines, page_count=page_count)
        except Exception:
            # Fallback to rasterization if pypdf encounters corrupted text streams
            pass

        # Step 2: Render PDF pages to images using pypdfium2 and run RapidOCR (Section 11)
        doc = pdfium.PdfDocument(pdf_path)
        page_count = len(doc)
        ocr = get_ocr_engine()

        for page in doc:
            # Render page at 200 DPI (scale=2) for high OCR quality
            pil_img = page.render(scale=2).to_pil()
            cls._preprocess_image(pil_img)
            img_arr = np.array(pil_img)

            ocr_res, _ = ocr(img_arr)
            if ocr_res:
                for item in ocr_res:
                    text = item[1].strip()
                    conf = float(item[2])
                    if text:
                        extracted_lines.append((text, conf))
        doc.close()

        return ReceiptParser.parse(extracted_lines, page_count=page_count)

    @classmethod
    def _process_image(cls, img_path: str) -> ReceiptOCRResult:
        ocr = get_ocr_engine()
        pil_img = Image.open(img_path)
        cls._preprocess_image(pil_img)
        img_arr = np.array(pil_img)

        extracted_lines: List[Tuple[str, float]] = []
        ocr_res, _ = ocr(img_arr)
        if ocr_res:
            for item in ocr_res:
                text = item[1].strip()
                conf = float(item[2])
                if text:
                    extracted_lines.append((text, conf))

        return ReceiptParser.parse(extracted_lines, page_count=1)

    @classmethod
    def _preprocess_image(cls, img: Image.Image) -> Image.Image:
        """
        Enhances contrast and readability for noisy/skewed receipts (Section 12).
        """
        # Convert to RGB if RGBA
        if img.mode == "RGBA":
            img = img.convert("RGB")
        # Enhance contrast slightly for OCR clarity
        enhancer = ImageEnhance.Contrast(img)
        return enhancer.enhance(1.2)
