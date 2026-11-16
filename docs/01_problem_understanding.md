# Phase 1: Problem Understanding

## 1. Overview & Context
MakeMyTrip runs on two main verticals: flight tickets and hotel reservations. This document breaks down the eight core issues (P1 to P8) reported by different teams—ranging from travelers facing slow searches to finance waiting on long reports. 

To tackle these systematically, we divide the workload into two clear buckets:
1. **Real-Time / Customer-Facing Operations:** High-concurrency operations (flight search, booking confirmation, support lookup) where users expect sub-millisecond to sub-5 ms responses.
2. **Reporting & Background Analytics:** Bulk jobs and aggregations (revenue summaries, coupon audits, partner settlements) where queries can run asynchronously under reasonable SLA thresholds (<250 ms to <5,000 ms).


## 2. Business Problems & Query Mapping (P1 – P8)

| ID | Issue & What the Business Needs | Stakeholder Affected | Workload Type | Related Queries |
|:---|:---|:---|:---|:---|
| **P1** | **Flight Search & Live Seat Count:** Travelers searching for flights between two cities (e.g., Delhi to Mumbai) need instant results showing accurate seats left. Calculating remaining seats on the fly by scanning active bookings is currently causing high latency, hurting booking conversions. | Traveler, Airlines, Revenue Management | Customer-Facing / Real-Time | R01, R02, R10 |
| **P2** | **Hotel Search & Amenity Filtering:** Users filter hotels by city, star ratings, and specific JSON amenities (like swimming pool, free wifi) across custom check-in/check-out dates. These searches currently hit sequential table scans, making property discovery sluggish. | Traveler, Hotel Partners | Customer-Facing / Real-Time | R03, R04, R18, R24 |
| **P3** | **Customer Account & Support Lookup:** Travelers want quick access to their past trips and profile details upon login. Meanwhile, support executives need to pull up customer reservations instantly using `booking_ref` while on live support calls. | Traveler, Customer Support | Customer-Facing / Real-Time | R05, R06, R23 |
| **P4** | **Flight Manifests & Dispatch Ops:** Gate agents and airline dispatchers need immediate passenger manifests ordered by seat number for boarding. Operations also need to track delayed flights and calculate cancellation rates across routes without blocking checkout tables. | Airline Partners, Flight Operations | Real-Time Ops (R07, W04) & Reporting (R08, R14, R19) | R07, R08, R14, R19, W04 |
| **P5** | **Checkout Pipeline & Payment States:** Handling the booking lifecycle—inserting pending bookings, sweeping expired unconfirmed checkouts (>30 min), confirming reservations on payment webhooks, and processing cancellations/refunds cleanly without locking tables. | Payments Team, Traveler | Customer-Facing / Real-Time | R11, W01, W02, W03 |
| **P6** | **Promotional Coupon Audit:** Marketing's report to find coupons that have never been used keeps returning zero rows. This is caused by a classic SQL three-valued logic trap (`NOT IN` over nullable values). We need to fix the query logic (`NOT EXISTS`) and index it so marketing can track dead campaigns. | Marketing Team | Reporting / Analytics | R13 |
| **P7** | **Front-Desk Check-In & Hotel Utilization:** Hotel front-desk staff need to assign room numbers in batch for daily arrivals without slowing down check-ins. Operations also requires monthly room-night counts by city to calculate partner payouts. | Hotel Partners, Front Desk Staff | Real-Time Check-In (W05) & Reporting (R15) | R15, W05 |
| **P8** | **Financial Reporting, Analytics & Scale:** Heavy month-end revenue calculations, customer lifetime value aggregates, and deep pagination for support logs scan millions of rows. We need proper indexing and a clear partitioning plan so these run smoothly at 20× data volume. | Finance, Loyalty Team, Management | Reporting / Analytics | R09, R12, R16, R17, R20, R21, R22, R25 |
