28. INVENTORY INTELLIGENCE
============================================================

This is the major differentiating feature.

Endpoints:

GET /api/intelligence/stockout

GET /api/intelligence/reorder

Do NOT build an LLM chatbot.

Use transparent calculations.

Stockout information:

Current Stock
Average Daily Usage
Reorder Level
Estimated Days to Reorder
Estimated Days to Stockout

If insufficient history exists:

show:

“Not enough historical movement data.”

Do not fabricate predictions.

Reorder:

Current Stock
Average Usage
Target Coverage
Recommended Reorder Quantity

Show the calculation/explanation to the user.

Do not claim machine learning unless an actual ML model is implemented.

============================================================
