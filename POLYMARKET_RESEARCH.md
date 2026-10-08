# Polymarket research (checked 2026-10-08)

CLAUDE.md asks me to report this before building the ingest. Everything marked **verified** was confirmed by calling the live API today. Everything marked **unconfirmed** needs a decision or a check from you.

## 1. Are we allowed to use it?

| Question | Finding |
|---|---|
| Is the data public? | **Verified.** The Gamma API (`https://gamma-api.polymarket.com`) answers with no key, no login, and no wallet. Polymarket's docs say the same. |
| Do the docs state rate limits? | **Unconfirmed.** The market-data docs list none. The only "rate limits" page is for their *builder program* (trading). Responses carry `cache-control: public, max-age=1200` on static lists. |
| Do the Terms of Use allow this? | **Unconfirmed.** I could not read the clauses on API or data use (the page returned only its header and navigation). I did not find a ban on reading public market data, but I have not proven that either. **Please read https://polymarket.com/tos yourself (search for "API", "data", "automated"), or ask Polymarket support / their Discord whether a free app may read the public Gamma API.** |
| Do we trade or touch money? | No. We only read market listings, start times, and outcomes. We never place orders or need a wallet. Polymarket blocks *trading* from the US; reading is unaffected. |
| Attribution required? | None found in the docs. |

**My recommendation:** build on the public Gamma API, keep our request volume low (see section 4), cache everything in our own database so the iPhone app never calls Polymarket directly, and design the ingest so it can be switched to another source (e.g. a paid sports-data feed) if the terms turn out to forbid us. The ingest is one small module, so this is cheap insurance.

## 2. Endpoints we will use (all verified)

| Purpose | Request |
|---|---|
| League tag IDs | `GET /sports` → NBA `745`, NFL `450`, MLB `100381`, NHL `899` (the `primaryTagId` field) |
| Valid market types | `GET /sports/market-types` → includes `moneyline`, `spreads`, `totals` (plus hundreds of player-prop/other types that we ignore) |
| Upcoming game markets | `GET /markets?closed=false&tag_id=745&sports_market_types=moneyline` (repeat for `spreads`, `totals`; paginate with `limit`/`offset`) |
| One market (refresh and settlement) | `GET /markets/{id}` |
| Grouping markets into a game | each market has `events[0].id` and a slug like `nba-bos-cle-2026-10-08-spread-home-1pt5` |

**Gotchas I hit:**
- The league tag also contains non-game markets (for example "Will LeBron retire…"). Filtering by `sports_market_types` removes them.
- `outcomes`, `outcomePrices`, and `clobTokenIds` come back as **JSON strings inside JSON** and must be parsed twice.
- `GET /markets?condition_ids=…` returned nothing for a closed market. Use `/markets/{id}` for lookups.
- `gameId` is `null` on markets. Game identity comes from the event.
- Spread and total lines are in `line` (for example `-1.5`, `4.5`); the question text reads "Spread: Cavaliers (-1.5)" or "Brewers vs. Padres: O/U 4.5". Outcomes are the two team names, or `["Over","Under"]`.

## 3. Real JSON (trimmed to the fields that matter)

**Resolved, normal winner** (Bucks beat Thunder):
```json
{"id":"5167474","question":"Bucks vs. Thunder","outcomes":"[\"Bucks\", \"Thunder\"]",
 "outcomePrices":"[\"1\", \"0\"]","closed":true,"active":true,
 "umaResolutionStatus":"resolved","closedTime":"2026-10-08 03:00:26+00",
 "gameStartTime":"2026-10-08 00:00:00+00","sportsMarketType":"moneyline",
 "line":null,"acceptingOrders":false}
```

**Resolved 50/50** (Yankees vs. Rays, closed before the game was played):
```json
{"id":"5279716","question":"New York Yankees vs. Tampa Bay Rays",
 "outcomePrices":"[\"0.5\", \"0.5\"]","closed":true,
 "umaResolutionStatus":"resolved","closedTime":"2026-10-08 06:12:29+00",
 "gameStartTime":"2026-10-11 00:00:00+00","sportsMarketType":"moneyline"}
```
Scanning 900 recently closed markets (up to 100 per league and market type; at least one query returned a server error, so this is not exhaustive): 892 paid 1/0 and 8 paid 0.5/0.5. So voids are rare but real, and this one closed *before* its scheduled game (a postponement), so a void can arrive before the start time too.

**Proposed but not final** (an old soccer market, still stuck months later):
```json
{"id":"689015","question":"Will Hannover 96 win on 2025-11-28?",
 "outcomePrices":"[\"0.5\", \"0.5\"]","closed":false,"active":true,
 "umaResolutionStatus":"proposed","umaEndDate":null,"closedTime":null,
 "acceptingOrders":true}
```
Note `outcomePrices` of 0.5/0.5 here does **not** mean void. This is why the finality rule requires `closed` and `resolved`, never prices alone.

**Disputed:** no example exists in the live data right now, so **I could not capture one**. Polymarket's docs say a dispute starts a new proposal round and a second dispute goes to a UMA vote (about 4–6 days total). I could not confirm the exact `umaResolutionStatus` string for it (likely `disputed`). Our rule handles this safely anyway: anything that is not `closed == true` AND `umaResolutionStatus == "resolved"` is treated as not final. I'll log every distinct status string we see so we can learn the real values.

## 4. Finality rule (as implemented in the spec)

Settle a market only when **all** are true:
1. `closed == true`
2. `umaResolutionStatus == "resolved"`
3. `outcomePrices` parses to exactly `[1,0]`, `[0,1]` (winner = the outcome priced 1), or `[0.5,0.5]` (void)

Anything else, including an unknown status string, malformed JSON, or a missing field, leaves the bet pending.

**Polling budget (keeps us a polite client):** discovery every 15 minutes (about 12 list calls per run, since 4 leagues × 3 types), and per-market refresh every 2 minutes **only** for games that have open offers or unsettled bets. For a friend-group app that is a few hundred requests per hour at most.

## 5. Other findings
- **Start times can move** (Polymarket's docs say so). We refresh `gameStartTime` before every take and in the auto-cancel job, and we also stop new takes whenever Polymarket reports `acceptingOrders == false` or `closed == true`.
- **A known bug report** says some finished games still show `closed=false, acceptingOrders=true` in the API. So we never rely on Polymarket's flags to detect "game started"; we use our own clock against `gameStartTime`.
- **Realtime websockets** (market stream `market_resolved`, sports stream) exist and are verified in the docs. As CLAUDE.md says, v1 uses polling only; the sports stream is labelled "informational, may be delayed", and I could not confirm that `market_resolved` means past-dispute-window final, so it can only ever be a hint that triggers an early poll.
- I did **not** call the websocket feeds, since v1 doesn't use them.

## 6. What I need from you
1. Read the Polymarket Terms (or ask them) and tell me it's OK, or tell me to plan for a different data source.
2. Confirm you are comfortable with the polling-only v1 approach.
