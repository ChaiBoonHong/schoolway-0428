const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  serverTimestamp,
  updateDoc,
  where,
} = require("firebase/firestore");

let environment;

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId: "schoolway-test",
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "..", "firestore.rules"),
        "utf8",
      ),
    },
  });
});

test.beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "users/admin"), {
        authUid: "admin",
        role: "admin",
        isActive: true,
      }),
      setDoc(doc(db, "users/parent-a"), {
        authUid: "parent-a",
        role: "parent",
        isActive: true,
      }),
      setDoc(doc(db, "users/parent-b"), {
        authUid: "parent-b",
        role: "parent",
        isActive: true,
      }),
      setDoc(doc(db, "users/driver-a"), {
        authUid: "driver-a",
        role: "driver",
        isActive: true,
      }),
      setDoc(doc(db, "users/driver-b"), {
        authUid: "driver-b",
        role: "driver",
        isActive: true,
      }),
      setDoc(doc(db, "buses/bus-a"), {
        currentDriverUid: "driver-a",
        status: "Idle",
      }),
      setDoc(doc(db, "buses/bus-b"), {
        currentDriverUid: "driver-b",
        status: "Idle",
      }),
      setDoc(doc(db, "students/student-a"), {
        parentAuthUids: ["parent-a"],
        assignedBusId: "bus-a",
      }),
      setDoc(doc(db, "route_sessions/session-a"), {
        driverUid: "driver-a",
        busId: "bus-a",
        status: "Active",
      }),
      setDoc(doc(db, "route_sessions/session-b"), {
        driverUid: "driver-b",
        busId: "bus-b",
        status: "Active",
      }),
      setDoc(doc(db, "bus_access/bus-a/members/parent-a"), {
        uid: "parent-a",
      }),
      setDoc(doc(db, "notifications/notice-a"), {
        recipientUid: "parent-a",
        read: false,
      }),
      setDoc(doc(db, "users/parent-a/devices/phone"), {
        token: "private-token",
      }),
    ]);
  });
});

test.after(async () => {
  await environment.cleanup();
});

test("a user cannot elevate their role or read another private profile", async () => {
  const db = environment.authenticatedContext("parent-a").firestore();
  await assertFails(updateDoc(doc(db, "users/parent-a"), { role: "admin" }));
  await assertFails(getDoc(doc(db, "users/parent-b")));
  await assertSucceeds(getDoc(doc(db, "users/parent-a")));
});

test("a parent can read only linked students and buses", async () => {
  const linked = environment.authenticatedContext("parent-a").firestore();
  const unrelated = environment.authenticatedContext("parent-b").firestore();
  await assertSucceeds(getDoc(doc(linked, "students/student-a")));
  await assertSucceeds(getDoc(doc(linked, "buses/bus-a")));
  await assertFails(getDoc(doc(unrelated, "students/student-a")));
  await assertFails(getDoc(doc(unrelated, "buses/bus-a")));
});

test("an administrator can manage profiles while device tokens stay private", async () => {
  const admin = environment.authenticatedContext("admin").firestore();
  const unrelated = environment.authenticatedContext("parent-b").firestore();
  await assertSucceeds(getDoc(doc(admin, "users/parent-a")));
  await assertSucceeds(updateDoc(doc(admin, "users/parent-a"), { role: "driver" }));
  await assertFails(getDoc(doc(unrelated, "users/parent-a/devices/phone")));
});

test("a driver can update status only for the assigned bus", async () => {
  const db = environment.authenticatedContext("driver-a").firestore();
  await assertSucceeds(updateDoc(doc(db, "buses/bus-a"), { status: "Active" }));
  await assertFails(updateDoc(doc(db, "buses/bus-a"), {
    currentDriverUid: "driver-b",
  }));
  await assertFails(updateDoc(doc(db, "buses/bus-b"), { status: "Active" }));
});

test("a driver can query only buses assigned to their Auth UID", async () => {
  const db = environment.authenticatedContext("driver-a").firestore();
  const assignedBuses = query(
    collection(db, "buses"),
    where("currentDriverUid", "==", "driver-a"),
  );
  const snapshot = await assertSucceeds(getDocs(assignedBuses));
  assert.deepEqual(snapshot.docs.map((bus) => bus.id), ["bus-a"]);

  await assertFails(getDocs(collection(db, "buses")));
});

test("a driver cannot create a notification or another driver's GPS record", async () => {
  const db = environment.authenticatedContext("driver-a").firestore();
  await assertFails(setDoc(doc(db, "notifications/forged"), {
    recipientUid: "parent-a",
    title: "Forged",
  }));
  await assertFails(setDoc(doc(db, "gps_tracking/bus-b"), {
    driverUid: "driver-a",
    latitude: 0,
    longitude: 0,
  }));
});

test("an assigned driver can record only assigned operational data", async () => {
  const db = environment.authenticatedContext("driver-a").firestore();
  const validEvent = {
    driverUid: "driver-a",
    busId: "bus-a",
    studentId: "student-a",
    sessionId: "session-a",
    eventType: "board",
    timestamp: serverTimestamp(),
    isManual: false,
  };
  await assertSucceeds(setDoc(doc(db, "boarding_events/event-a"), validEvent));
  await assertSucceeds(setDoc(doc(db, "gps_tracking/bus-a"), {
    driverUid: "driver-a",
    latitude: 1,
    longitude: 1,
  }));
  await assertFails(setDoc(doc(db, "boarding_events/event-b"), {
    ...validEvent,
    busId: "bus-b",
  }));
  await assertFails(setDoc(doc(db, "boarding_events/wrong-session"), {
    ...validEvent,
    sessionId: "session-b",
  }));
  await assertFails(setDoc(doc(db, "boarding_events/invalid-type"), {
    ...validEvent,
    eventType: "absent",
  }));
  await assertFails(setDoc(doc(db, "boarding_events/missing-note"), {
    ...validEvent,
    isManual: true,
  }));
  await assertSucceeds(setDoc(doc(db, "boarding_events/manual-a"), {
    ...validEvent,
    isManual: true,
    manualNote: "Card forgotten",
  }));
});

test("an assigned driver can snapshot service-stop order but a parent cannot", async () => {
  const driver = environment.authenticatedContext("driver-a").firestore();
  const parent = environment.authenticatedContext("parent-a").firestore();
  const session = {
    driverUid: "driver-a",
    busId: "bus-a",
    routeId: "route-a",
    startTime: serverTimestamp(),
    status: "Active",
    gpsTrackingEnabled: true,
    tripDirection: "toSchool",
    serviceStopRouteIndices: [9, 11, 13, 15],
  };

  await assertSucceeds(
    setDoc(doc(driver, "route_sessions/session-with-stops"), session),
  );
  await assertFails(
    setDoc(doc(parent, "route_sessions/forged-session"), session),
  );
});

test("new geofence events retain route identity and service numbering", async () => {
  const driver = environment.authenticatedContext("driver-a").firestore();
  await assertSucceeds(
    setDoc(
      doc(driver, "route_sessions/session-a/geofence_events/event-a"),
      {
        type: "at_stop",
        stopIndex: 15,
        routeStopIndex: 15,
        tripOrderIndex: 0,
        serviceStopNumber: 1,
        stopLabel: "Stop 1",
        busId: "bus-a",
        driverUid: "driver-a",
        latitude: 3.1,
        longitude: 101.1,
        timestamp: serverTimestamp(),
      },
    ),
  );
});

test("a driver can query only their attendance events", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "boarding_events/seed-a"), {
      driverUid: "driver-a",
      busId: "bus-a",
      studentId: "student-a",
      sessionId: "session-a",
      eventType: "board",
      timestamp: serverTimestamp(),
      isManual: false,
    });
  });

  const driver = environment.authenticatedContext("driver-a").firestore();
  const constrained = query(
    collection(driver, "boarding_events"),
    where("sessionId", "==", "session-a"),
    where("driverUid", "==", "driver-a"),
  );
  const snapshot = await assertSucceeds(getDocs(constrained));
  assert.deepEqual(snapshot.docs.map((event) => event.id), ["seed-a"]);
  const unrelated = environment.authenticatedContext("driver-b").firestore();
  await assertFails(getDocs(query(
    collection(unrelated, "boarding_events"),
    where("sessionId", "==", "session-a"),
    where("driverUid", "==", "driver-a"),
  )));
  await assertFails(getDocs(query(
    collection(driver, "boarding_events"),
    where("sessionId", "==", "session-a"),
  )));
});

test("only the session driver can create and read stop arrival events", async () => {
  const assigned = environment.authenticatedContext("driver-a").firestore();
  const unrelated = environment.authenticatedContext("driver-b").firestore();
  const eventPath = "route_sessions/session-a/geofence_events/arrival-a";
  const event = {
    type: "at_stop",
    stopIndex: 0,
    stopLabel: "Stop 1",
    busId: "bus-a",
    driverUid: "driver-a",
    latitude: 3.1,
    longitude: 101.1,
  };

  await assertSucceeds(setDoc(doc(assigned, eventPath), event));
  await assertSucceeds(getDoc(doc(assigned, eventPath)));
  await assertFails(getDoc(doc(unrelated, eventPath)));
  await assertFails(setDoc(doc(unrelated, `${eventPath}-forged`), event));
});

test("a notification recipient can only change the read state and delete", async () => {
  const recipient = environment.authenticatedContext("parent-a").firestore();
  const other = environment.authenticatedContext("parent-b").firestore();
  await assertSucceeds(getDoc(doc(recipient, "notifications/notice-a")));
  await assertSucceeds(updateDoc(doc(recipient, "notifications/notice-a"), {
    read: true,
  }));
  await assertFails(updateDoc(doc(recipient, "notifications/notice-a"), {
    recipientUid: "parent-b",
  }));
  await assertFails(getDoc(doc(other, "notifications/notice-a")));
  await assertFails(deleteDoc(doc(other, "notifications/notice-a")));
  await assertSucceeds(deleteDoc(doc(recipient, "notifications/notice-a")));
  assert.ok(true);
});

test("routing-cache documents are server-only and never readable or writable by roles", async () => {
  const admin = environment.authenticatedContext("admin").firestore();
  const driver = environment.authenticatedContext("driver-a").firestore();
  const parent = environment.authenticatedContext("parent-a").firestore();
  const cacheDoc = {
    sessionId: "session-a",
    routeId: "route-a",
    polyline: "encoded",
    stopEtas: [{ stopIndex: 0, label: "Stop 1", etaMinutes: 5 }],
  };
  await assertFails(getDoc(doc(admin, "routing_cache/session-a")));
  await assertFails(getDoc(doc(driver, "routing_cache/session-a")));
  await assertFails(getDoc(doc(parent, "routing_cache/session-a")));
  await assertFails(setDoc(doc(admin, "routing_cache/forged"), cacheDoc));
  await assertFails(setDoc(doc(driver, "routing_cache/forged"), cacheDoc));
  await assertFails(setDoc(doc(parent, "routing_cache/forged"), cacheDoc));
  await assertFails(getDocs(collection(admin, "routing_cache")));
});

test("planned routes remain readable by signed-in users and writable only by admins", async () => {
  const admin = environment.authenticatedContext("admin").firestore();
  const parent = environment.authenticatedContext("parent-a").firestore();
  const route = {
    name: "Route A",
    stops: [
      { latitude: 3.1, longitude: 101.7 },
      { latitude: 3.2, longitude: 101.8 },
    ],
  };
  await assertSucceeds(setDoc(doc(admin, "planned_routes/route-a"), route));
  await assertSucceeds(getDoc(doc(parent, "planned_routes/route-a")));
  await assertFails(setDoc(doc(parent, "planned_routes/forged"), route));
});
