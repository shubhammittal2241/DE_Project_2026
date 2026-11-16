# Phase 1: Problem Understanding

## 1. Overview & Context
MakeMyTrip runs on two main verticals: flight tickets and hotel reservations. This document breaks down the eight core issues (P1 to P8) reported by different teams—ranging from travelers facing slow searches to finance waiting on long reports. 

To tackle these systematically, we divide the workload into two clear buckets:
1. **Real-Time / Customer-Facing Operations:** High-concurrency operations (flight search, booking confirmation, support lookup) where users expect sub-millisecond to sub-5 ms responses.
2. **Reporting & Background Analytics:** Bulk jobs and aggregations (revenue summaries, coupon audits, partner settlements) where queries can run asynchronously under reasonable SLA thresholds (<250 ms to <5,000 ms).
