# SchoolWay Validation Plan

This document outlines the testing strategy to ensure SchoolWay meets its operational, performance, and safety objectives.

## 1. Functional Validation
Verify that core flows work correctly across different user roles.

- **Maps & ETA**:
  - Driver App: Ensure map correctly displays the planned route, geofence radius around stops, and computes ETA accurately when approaching a stop.
  - Parent App: Verify parent can see the live position of the bus and correct ETA chips for their children's stops.
- **Automated Emergency Alerts (Stationary Bus)**:
  - Simulate bus standing still for > 8 minutes with `status=Active`.
  - Verify that an `EmergencyAlert` is created in Firestore and the Admin Dashboard shows a red badge.
- **Route History**:
  - Run a mock route session.
  - End the session.
  - Verify the admin can open "Route History", see the session, and replay the GPS breadcrumbs using the slider.
- **Stop Management & Privacy**:
  - Driver App: Check `DriverStudentsTab`. Ensure students are grouped by pickup stop.
  - Driver App: Click on a student. Ensure parent contact is hidden and "Contact School Admin" button works.

## 2. Performance Testing (Parent App Latency)
**Objective**: Ensure parents receive real-time bus tracking updates with minimal latency.
- **Methodology**: Use the integrated `latency_test.dart` script in `tool/`.
- **Metrics**: 
  - Median GPS Latency (Target: < 3 seconds)
  - 95th Percentile GPS Latency (Target: < 5 seconds)
- **Execution**: 
  - Drive a physical route or run a device simulator.
  - Have a parent app connected to the same bus.
  - Check Latency test results logs.
