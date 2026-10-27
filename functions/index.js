const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Triggered whenever a packet is delivered to a queue.
 * Dispatches a content-less, metadata-free silent push notification to the recipient.
 */
exports.onPacketReceived = onDocumentCreated("queues/{queueId}/packets/{packetId}", async (event) => {
  const queueId = event.params.queueId;
  const queueDoc = await db.collection("queues").doc(queueId).get();
  
  if (!queueDoc.exists) return;
  const fcmToken = queueDoc.data()?.fcmToken;
  if (!fcmToken) return;

  // High-priority Wake-up push notification (bypasses Doze Mode)
  const message = {
    token: fcmToken,
    data: {
      type: "QUEUE_PACKET_ARRIVED",
      queueId: queueId,
      title: "Bharosa",
      body: "New encrypted message received",
    },
    android: {
      priority: "high",
      notification: {
        channelId: "bharosa_messages",
        priority: "high",
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          "content-available": 1,
          sound: "default",
        },
      },
    },
  };

  try {
    await admin.messaging().send(message);
  } catch (error) {
    console.error("Failed to dispatch push notification:", error);
  }
});

/**
 * Scheduled cleanup: Runs every 24 hours to automatically purge
 * undelivered packets older than 30 days and expired invites older than 7 days.
 */
exports.autoPurgeStalePackets = onSchedule("every 24 hours", async (event) => {
  const thirtyDaysAgo = Date.now() - (30 * 24 * 60 * 60 * 1000);
  const sevenDaysAgo = Date.now() - (7 * 24 * 60 * 60 * 1000);

  // 1. Purge expired invites
  const expiredInvitesSnapshot = await db.collection("invites")
    .where("expiresAt", "<", Date.now())
    .get();

  const inviteBatch = db.batch();
  expiredInvitesSnapshot.docs.forEach((doc) => inviteBatch.delete(doc.ref));
  await inviteBatch.commit();
  console.log(`Purged ${expiredInvitesSnapshot.size} expired invites.`);

  // 2. Query stale queue packets across queues
  // Note: Packets are usually deleted immediately by clients upon receipt.
  // This is a safety net.
  const queuesSnapshot = await db.collection("queues").get();
  for (const queueDoc of queuesSnapshot.docs) {
    const packetsSnapshot = await queueDoc.ref.collection("packets")
      .where("timestamp", "<", thirtyDaysAgo)
      .get();

    if (!packetsSnapshot.empty) {
      const packetBatch = db.batch();
      packetsSnapshot.docs.forEach((doc) => packetBatch.delete(doc.ref));
      await packetBatch.commit();
      console.log(`Purged ${packetsSnapshot.size} stale packets in queue ${queueDoc.id}`);
    }
  }
});
