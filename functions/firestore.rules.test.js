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
  await assertSucceeds(setDoc(doc(db, "boarding_events/event-a"), {
    driverUid: "driver-a",
    busId: "bus-a",
    studentId: "student-a",
  }));
  await assertSucceeds(setDoc(doc(db, "gps_tracking/bus-a"), {
    driverUid: "driver-a",
    latitude: 1,
    longitude: 1,
  }));
  await assertFails(setDoc(doc(db, "boarding_events/event-b"), {
    driverUid: "driver-a",
    busId: "bus-b",
    studentId: "student-a",
  }));
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

test("a notification recipient can only change the read state", async () => {
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
  assert.ok(true);
});
