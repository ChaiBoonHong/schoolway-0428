# SchoolWay Stress Test Plan

This document outlines the testing strategy to ensure SchoolWay can handle high traffic/load under pressure.

## 3. Stress Testing (High Traffic Load)
**Objective**: Evaluate how the system and Firestore perform with multiple concurrent buses and parents.

- **Methodology**: 
  - Write a Node.js/Python script to simulate 50 active buses pushing GPS updates every 5 seconds.
  - Or use a Dart script running on desktop to simulate concurrent background isolates making Firestore writes.

- **Metrics**:
  - **Firestore Write Rate limits**: Measure if writes are delayed or rejected under high concurrency.
  - **Firestore Read Costs**: Evaluate if caching or data aggregation is needed if reads skyrocket.
  - **App Responsiveness**: Test UI responsiveness for parents with multiple children on different buses while heavy load is simulated on the backend.

- **Execution Steps**: 
  1. Use Firebase Local Emulator Suite first to simulate 100 concurrent connections without incurring billing costs.
  2. Implement a mock data generator that creates 50 active `route_sessions` and updates their `last_location` simultaneously.
  3. Run the stress test and monitor the Emulators UI for bandwidth and document reads/writes spikes.
  4. Once validated locally, run a scaled-down version on a staging Firebase project to verify cloud network latency during load.
