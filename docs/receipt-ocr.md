# Smart receipt entry

The camera and gallery routes use ML Kit once, retain word positions and open
ReceiptReviewScreen directly. Image-box selection is available through Adjust
selection. Lost-image recovery uses the same parser.

## Parsing

`receipt_ocr_parser.dart` is a pure Dart interpreter. `receiptSpatialRows` in
`ocr_scanner_service.dart` groups ML Kit words into visual rows without throwing
away their horizontal coordinates. The parser separates receipt context,
product rows, payable totals and payment details.

- Spaces never combine quantities and prices into one number.
- Dates, phone numbers, tax IDs, invoice IDs, addresses and common headings are
  excluded from product entries.
- Amount-column geometry takes precedence over a trailing tax/code column.
- Quantity times unit price is checked when all three numeric columns exist.
- Product sizes and digits within names remain part of the title.
- Wrapped names require nearby rows when geometry is available.
- Tax/discount amounts are interpreted separately; cash and change are excluded.
- Conflicting totals, uncertain columns, large amounts and inconsistent sums
  receive explicit issue markers. Confidence values are heuristic scores, not
  measured probabilities of correctness.

Clear items are preselected and compact. Only uncertain item amounts expand for
correction or an explicit check. Category detection is per item, restricted to
active categories at save time; the top category control overrides all items.
Unknown products retain General without requiring a category confirmation.

Receipts with tax/discount adjustments initially use one payable-total entry,
with the detected product names as its title. This avoids silently dropping an
adjustment or counting the total twice. Item mode remains available and requires
confirmation when its selected sum differs from the detected receipt total.
Every item selection/removal/amount edit resets that confirmation.

Saving still uses TransactionExecutor and existing wallet/ledger validation.
No raw receipt text is passed through the voice/general NLP amount parser.

## Validation

Run:

```sh
flutter test test/ocr_scanner_service_test.dart test/smart_receipt_parser_test.dart test/receipt_review_screen_test.dart
python3 tool/generate_app_catalog.py --check
python3 tool/check_home_category_scope.py
flutter analyze --no-fatal-infos --no-fatal-warnings
```

The test set includes synthetic layouts and 100 generated receipt variants.
These do not establish real-camera OCR accuracy. Device checks should include
local POS receipts, digital-payment receipts, faded/tilted photos, multiple
quantity/rate columns, product sizes, wrapped names, tax/discounts and long IDs.
Check that the saved amounts and wallet movement equal the intended purchase.
Unrecognizable text or unsupported layouts can still require correction; no
trained language model or cloud OCR service has been added.
