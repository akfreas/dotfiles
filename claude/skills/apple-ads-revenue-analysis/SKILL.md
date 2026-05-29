---
name: apple-ads-revenue-analysis
description: >-
  Analyze Encamera Apple Search Ads campaign performance by combining Apple Ads
  CSV spend, Supabase attribution data, and App Store Connect (asc MCP) product
  prices to compute exact gross revenue, Apple proceeds, and true ROAS per
  campaign. Invoke when the user pastes an Apple Ads CSV and asks how campaigns
  performed, how much revenue they earned, CPA, ROAS, or which campaigns to
  pause.
---

# Encamera — Apple Ads × Supabase × App Store Connect Revenue Analysis

This skill joins three data sources to compute real revenue per Apple Search Ads campaign:

1. **Apple Ads CSV** (user paste) — campaign spend, installs, Apple's reported CPA
2. **Supabase** (`iwyaxywmukbescxoownb` → `analytics_events`) — attributed in-app purchase events
3. **App Store Connect** (asc MCP) — the actual US dollar price of each SKU at time of analysis

The output is a per-campaign revenue breakdown with gross revenue, Apple commission, net proceeds, ad spend, and profit — not just a conversion count.

**Assumption:** the user's Apple Ads campaigns target US users (Encamera's campaigns are US-based). All pricing is pulled for territory `USA`. If the user indicates otherwise, pull prices for the correct territory.

---

## Step 1 — Parse the Apple Ads CSV

When the user pastes an Apple Ads CSV export, extract per campaign row:

| Field | CSV Column |
|---|---|
| Campaign ID | `Campaign ID` |
| Campaign Name | `Campaign Name` |
| Status | `Status` |
| Spend | `Spend` |
| Installs (Total) | `Installs (Total)` |
| Avg CPA (Apple's own) | `Avg CPA (Total)` |
| Start Date / End Date | `Start Date`, `End Date` |

Ignore rows where Campaign ID is empty (totals rows).

The **date range** comes from the CSV header lines, not per-row dates. Look for:
`"Start Date: Mar 25, 2026"` and `"End Date: Apr 23, 2026"`.

---

## Step 2 — Query Supabase for attributed purchases

Scope to the same date range as the Apple Ads CSV. Apple Ads end dates are **inclusive** — add 1 day for the SQL upper bound.

```sql
SELECT
  properties->>'apple_ads_campaign_id'    AS campaign_id,
  properties->>'apple_ads_attribution'    AS attributed,
  event_type,
  COUNT(*)                                 AS purchases
FROM analytics_events
WHERE
  category = 'purchase_completed'
  AND created_at >= '<START_DATE>'
  AND created_at <  '<END_DATE_EXCLUSIVE>'
GROUP BY campaign_id, attributed, event_type
ORDER BY campaign_id NULLS LAST, purchases DESC;
```

Key columns:
- `properties->>'apple_ads_attribution'` — `'true'` if attributed to Apple Ads
- `properties->>'apple_ads_campaign_id'` — joins to the CSV Campaign ID
- `properties->>'apple_ads_ad_group_id'` — for deeper ad-group analysis
- `properties->>'apple_ads_country_or_region'` — campaign region

Use `created_at` (the partition key), not `client_timestamp`.

---

## Step 3 — Pull current US prices from App Store Connect (asc MCP)

This is the new step. Revenue requires prices — do not hardcode them; pull live via the asc MCP.

### 3a. List product catalog

Call these in parallel to enumerate all SKUs the app sells:

- `mcp__asc__list_in_app_purchases` — returns one-time IAPs (lifetimes, consumables)
- `mcp__asc__list_subscription_groups` → `mcp__asc__list_subscriptions` (group_id) — returns all subscriptions

Note each SKU's `product_id` (the string that matches `event_type` from Supabase) and its `id` (the numeric ASC id needed for price lookup).

### 3b. Fetch US price per SKU

Only fetch for SKUs that actually appeared in the Supabase results. Call in parallel:

- **Non-consumable / consumable IAPs:** `mcp__asc__get_iap_price_schedule(iap_id, territory="USA")`
- **Subscriptions:** `mcp__asc__get_subscription_prices(subscription_id)` — then filter the result to `territory == "USA"`

Subscription prices do not accept a territory filter on the call; they return all territories — filter in post.

### 3c. Build product_id → US price map

Example (values will vary — always fetch live):

```
subscription.yearly.premium.1899              → $17.99
subscription.yearly.unlimitedkeysandphotos    → $19.99
subscription.monthly.premium.299              → $2.99
subscription.monthly.unlimitedkeysandphotos   → $3.99
purchase.lifetimelimited                       → $49.99
purchase.lifetimeunlimitedbasic                → $99.99
```

The `event_type` from Supabase may be the bare `product_id` or a suffix of it — match on equality or suffix. If a Supabase `event_type` doesn't resolve to an ASC product, flag it explicitly rather than silently dropping it.

---

## Step 4 — Compute revenue per campaign

For each `(campaign_id, event_type)` pair from Supabase:

```
gross_revenue  = purchases × us_price[product_id]
apple_cut      = gross_revenue × commission_rate
net_revenue    = gross_revenue − apple_cut
profit         = net_revenue − ad_spend
roas_net       = net_revenue / ad_spend
roas_gross     = gross_revenue / ad_spend
true_cpa       = ad_spend / attributed_purchases
```

### Apple commission rate

Default to **15%** (Small Business Program) when presenting the primary numbers — Encamera is a small indie app and is likely enrolled. **Always also show the 30% scenario** in the caveats so the cofounder can sanity-check. If the user has told you elsewhere whether they're enrolled in SBP, use that and note it.

Subscription renewals drop to 15% after 1 year even outside SBP — but within the reporting window these are all first-year purchases, so use the single rate the user indicates.

---

## Step 5 — Present results

### Per-campaign revenue table

```
### Campaign `XXXXXXXXX` — "Campaign Name" [STATUS]

| Line item                        | Units | US Price | Amount    |
|----------------------------------|------:|---------:|----------:|
| Yearly subscription              |     N |   $17.99 |   $XXX.XX |
| Unlimited Basic Lifetime         |     N |   $99.99 |   $XXX.XX |
| Limited Lifetime                 |     N |   $49.99 |    $XX.XX |
| **Gross revenue**                |       |          | **$XXX.XX** |
| Apple commission (15% SBP)       |       |          | −$XX.XX   |
| **Net revenue (proceeds)**       |       |          | **$XXX.XX** |
| Ad spend                         |       |          | −$XX.XX   |
| **Profit (pre-costs)**           |       |          | **$XXX.XX** |

ROAS: ~X.X× net · ~X.X× gross · True CPA: $X.XX (vs Apple's reported $X.XX)
```

### Zero-revenue campaigns

Short table — campaigns with spend but zero attributed purchases. Profit = −spend.

### Organic / unattributed

One section for `apple_ads_attribution IS NULL` purchases, broken down by product. Do **not** compute revenue per-campaign for these — they have no campaign. Do show total organic gross revenue for context vs paid.

### Overall totals

```
| | Gross | Net | Spend | Profit |
|---|---|---|---|---|
| All paid campaigns | $XXX | $XXX | $XXX | ±$XXX |
```

### Bottom line + caveats

Always end with:

1. **Bottom line** — one paragraph naming which campaigns carried the program and which bled money.
2. **Caveats** — must include:
   - Which yearly SKU was assumed (if the Supabase `event_type` was ambiguous between `subscription.yearly.premium.1899` and `subscription.yearly.unlimitedkeysandphotos`). Quantify the swing.
   - The 15% vs 30% commission scenario — give both net totals so the user sees the sensitivity.
   - Renewal revenue is not included (yearly subs will renew ~1 year out at 85% proceeds).
   - Organic purchases are unattributed and excluded from paid ROAS.

---

## Product ID → label map

For the line-item table rows, translate `event_type` to readable labels:

| event_type / suffix | Label |
|---|---|
| `subscription.yearly.unlimitedkeysandphotos` | Yearly subscription (legacy) |
| `subscription.monthly.unlimitedkeysandphotos` | Monthly subscription (legacy) |
| `subscription.yearly.premium.1899` | Yearly subscription |
| `subscription.monthly.premium.299` | Monthly subscription |
| `subscription.weekly.premium` | Weekly subscription |
| `purchase.lifetimelimited` | Limited Lifetime |
| `purchase.lifetimeunlimitedbasic` | Unlimited Basic Lifetime |
| `purchase.lifetimeunlimitedbasicfamily` | Unlimited Basic Family (removed from sale) |

---

## Key analytics notes

- **Apple's CPA ≠ True Revenue CPA.** Apple counts all installs as conversions. True CPA uses actual purchase count from Supabase.
- **`campaign_id` is the join key** between Apple Ads and Supabase.
- **Campaigns with Apple installs but zero Supabase purchases** = users who installed but haven't paid yet, or attribution-window mismatch. Show them with profit = −spend.
- **NULL `campaign_id`** rows in Supabase = organic / unattributed. Always surface — don't drop.
- **Always fetch live prices** via asc MCP. Encamera changes prices and adds SKUs; hardcoding lies.
- If the asc MCP is not connected, say so explicitly and fall back to a prices-unknown presentation rather than guessing.

---

## Execution order

1. Parse CSV → extract campaigns + date range.
2. Run Supabase query → get attributed purchases by (campaign_id, event_type).
3. **In parallel:** list ASC catalog (IAPs + subscription groups).
4. **In parallel:** fetch US prices for every distinct `event_type` seen in step 2.
5. Compute gross / net / profit / ROAS per campaign.
6. Render the per-campaign tables, zero-revenue table, organic section, totals, bottom line, and caveats.

---

## PDF export

When the user asks for a PDF (e.g. "generate a PDF", "make me a PDF I can share with my cofounder", "export this"), render the same content as a shareable PDF and write it to the current working directory. Filename convention: `Encamera_Ad_Campaign_Revenue_<START>-<END>.pdf` (e.g. `Encamera_Ad_Campaign_Revenue_Mar25-Apr23.pdf`).

### Tooling

Use **reportlab** via Python. If not installed: `pip3 install --quiet --user reportlab`. Do not use pandoc, wkhtmltopdf, or weasyprint — they are not installed on this machine and reportlab is a pure-Python install that works reliably.

Write the generator as a single Python script in the cwd (e.g. `generate_campaign_report.py`), run it, then offer to delete the script. Do not leave the script behind silently.

### Page 1+ — the shareable report (for the cofounder)

Professional presentation. Sections in order:
1. Title + date range + subtitle ("US users · attributed in-app purchases matched to Apple Ads spend").
2. US prices table (product, SKU, price) — so the numbers are verifiable at a glance.
3. One table per campaign with attributed purchases: line items, gross, Apple commission, net, ad spend, profit. Bold the summary rows. ROAS + True CPA caption below.
4. Zero-revenue campaigns table.
5. Organic / unattributed section.
6. Overall totals table.
7. **Bottom line** paragraph.
8. **Caveats & assumptions** bullet list.

Use tasteful styling: dark header rows (`#1f2937`), alternating row shading, bold summary rows shaded (`#f3f4f6`), right-aligned numeric columns, callouts in orange (`#b45309`) for losing campaigns.

### Final page — "Work shown" appendix (debug/reference only)

Always append a **single final page** with the raw work. This is deliberately dense and small-print — not for normal human consumption, but so the cofounder (or future-you) can audit exactly how the numbers were derived. **Must fit on one page.** If it doesn't fit, shrink the font further or tighten margins rather than spilling to a second page.

Styling: font size 7pt, leading 9pt, monospace (`Courier`) for SQL and calculations, grey rule separating sections. Header: "Appendix — Work Shown (reference / debug)".

Contents, in this order:

1. **Inputs** — Apple Ads CSV date range, spend per campaign, install counts (one line per campaign).
2. **Supabase SQL** — the exact query that was run, with the real date bounds substituted in. Monospace block.
3. **Supabase result** — one line per `(campaign_id, event_type, purchases)` tuple. Include the NULL-campaign_id rows.
4. **ASC price lookups** — for each distinct `event_type` observed, one line: `product_id → $price (ASC id <id>, territory USA)`. If a product_id didn't resolve, note it.
5. **Per-campaign arithmetic** — one compact block per campaign showing the exact math:
   ```
   CAMPAIGN 2143555151 "Brand"
     8 × $17.99 = $143.92  (yearly)
     5 × $99.99 = $499.95  (lifetime unlimited)
     1 × $49.99 =  $49.99  (lifetime limited)
     gross = $693.86
     apple cut (15%) = $693.86 × 0.15 = $104.08
     net = $693.86 − $104.08 = $589.78
     profit = $589.78 − $17.57 = $572.21
     ROAS = $589.78 / $17.57 = 33.6×
   ```
6. **Assumptions used** — commission rate chosen (15% vs 30%), which yearly SKU was assumed when ambiguous, any SKUs that failed to resolve. One line each.
7. **Data source timestamps** — when the ASC prices were fetched, when the Supabase query ran (ISO timestamps). So the reader knows this is a point-in-time snapshot.

Keep it terse — no prose, no full sentences, just labeled blocks. Think of it as a log file printed on paper. The goal is that anyone can replay the analysis by running the SQL, pulling the same ASC prices, and redoing the arithmetic.

### After writing

Confirm file path + size in the cwd. Offer one-line to delete the generator script. Do not open the PDF automatically.
