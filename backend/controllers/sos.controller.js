/**
 * SOS Controller - Handles emergency alert operations
 */

const SOSAlert = require('../models/SOSAlert');
const Device = require('../models/Device');
const { ApiError, asyncHandler } = require('../middleware/errorHandler');
const { verifySOS } = require('../services/verification');
const {
  broadcastSOSAlert,
  broadcastSOSUpdate,
  sendSOSAcknowledgment
} = require('../services/websocket');
const logger = require('../utils/logger');

// Default SOS expiry time (24 hours)
const DEFAULT_EXPIRY_HOURS = 24;

/**
 * Create new SOS alert (direct from device with internet)
 * POST /api/v1/sos/alert
 */
const createAlert = asyncHandler(async (req, res) => {
  const alertData = req.body;

  // Verify the SOS message
  const verification = verifySOS(alertData);

  if (!verification.isValid) {
    logger.warn(`SOS verification failed for ${alertData.messageId}`, {
      errors: verification.errors,
      deviceId: req.deviceId
    });
    // Still process but mark as unverified for investigation
  }

  // Check if alert already exists (duplicate)
  const existing = await SOSAlert.findOne({ messageId: alertData.messageId });
  if (existing) {
    return res.json({
      success: true,
      message: 'Alert already received',
      data: {
        alert: existing.toPublicJSON(),
        duplicate: true
      }
    });
  }

  // Create the alert
  const alert = await SOSAlert.create({
    messageId: alertData.messageId,
    originatorDeviceId: alertData.originatorDeviceId,
    emergencyType: alertData.emergencyType,
    priority: alertData.priority || 'high',
    location: alertData.location,
    message: alertData.message,
    signature: alertData.signature,
    appSignature: alertData.appSignature,
    status: 'active',
    hopCount: 0,
    relayChain: [],
    deliveredBy: req.deviceId,
    deliveredVia: 'direct',
    originatedAt: alertData.originatedAt || new Date(),
    expiresAt: new Date(Date.now() + DEFAULT_EXPIRY_HOURS * 60 * 60 * 1000),
    isVerified: verification.isValid
  });

  logger.info(`New SOS alert created: ${alert.messageId}`, {
    emergencyType: alert.emergencyType,
    priority: alert.priority,
    originatorDeviceId: alert.originatorDeviceId
  });

  // Broadcast to dashboards
  broadcastSOSAlert(alert);

  // Send acknowledgment to originating device
  sendSOSAcknowledgment(alert.originatorDeviceId, alert.messageId, 'received');

  res.status(201).json({
    success: true,
    message: 'SOS alert created',
    data: {
      alert: alert.toPublicJSON(),
      verified: verification.isValid
    }
  });
});

/**
 * Receive relayed SOS (from mesh network)
 * POST /api/v1/sos/relay
 */
const receiveRelayedAlert = asyncHandler(async (req, res) => {
  const alertData = req.body;

  // Verify the SOS message
  const verification = verifySOS(alertData);

  // Check if alert already exists
  let alert = await SOSAlert.findOne({ messageId: alertData.messageId });

  if (alert) {
    // Update relay info if we received through a shorter path
    if (alertData.hopCount < alert.hopCount) {
      alert.hopCount = alertData.hopCount;
      alert.relayChain = alertData.relayChain || [];
      await alert.save();
    }

    return res.json({
      success: true,
      message: 'Alert already received',
      data: {
        alert: alert.toPublicJSON(),
        duplicate: true
      }
    });
  }

  // Create new alert from relay
  alert = await SOSAlert.create({
    messageId: alertData.messageId,
    originatorDeviceId: alertData.originatorDeviceId,
    emergencyType: alertData.emergencyType,
    priority: alertData.priority || 'high',
    location: alertData.location,
    message: alertData.message,
    signature: alertData.signature,
    appSignature: alertData.appSignature,
    status: 'active',
    hopCount: alertData.hopCount || 0,
    relayChain: alertData.relayChain || [],
    deliveredBy: alertData.relayedBy || req.deviceId,
    deliveredVia: 'mesh_relay',
    originatedAt: alertData.originatedAt || new Date(),
    expiresAt: new Date(Date.now() + DEFAULT_EXPIRY_HOURS * 60 * 60 * 1000),
    isVerified: verification.isValid
  });

  logger.info(`Relayed SOS alert received: ${alert.messageId}`, {
    hopCount: alert.hopCount,
    deliveredBy: alert.deliveredBy,
    emergencyType: alert.emergencyType
  });

  // Broadcast to dashboards
  broadcastSOSAlert(alert);

  // Try to send acknowledgment back through relay chain
  // The originator will receive this if any device in the chain has internet
  sendSOSAcknowledgment(alert.originatorDeviceId, alert.messageId, 'received_via_relay');

  res.status(201).json({
    success: true,
    message: 'Relayed SOS alert received',
    data: {
      alert: alert.toPublicJSON(),
      verified: verification.isValid
    }
  });
});

/**
 * Cancel an SOS alert
 * POST /api/v1/sos/:messageId/cancel
 */
const cancelAlert = asyncHandler(async (req, res) => {
  const { messageId } = req.params;

  const alert = await SOSAlert.findOne({ messageId });

  if (!alert) {
    throw new ApiError(404, 'Alert not found');
  }

  // Only allow originator or admin to cancel
  if (alert.originatorDeviceId !== req.deviceId) {
    throw new ApiError(403, 'Only the originator can cancel this alert');
  }

  await alert.cancel();

  logger.info(`SOS alert cancelled: ${messageId}`);

  // Broadcast update
  broadcastSOSUpdate(alert, 'cancelled');

  res.json({
    success: true,
    message: 'Alert cancelled',
    data: {
      alert: alert.toPublicJSON()
    }
  });
});

/**
 * Acknowledge an SOS alert (by responder)
 * POST /api/v1/sos/:messageId/acknowledge
 */
const acknowledgeAlert = asyncHandler(async (req, res) => {
  const { messageId } = req.params;
  const { responderType } = req.body;

  const alert = await SOSAlert.findOne({ messageId });

  if (!alert) {
    throw new ApiError(404, 'Alert not found');
  }

  await alert.acknowledge(req.deviceId, responderType);

  logger.info(`SOS alert acknowledged: ${messageId}`, {
    acknowledgedBy: req.deviceId
  });

  // Broadcast update
  broadcastSOSUpdate(alert, 'acknowledged');

  // Notify originator
  sendSOSAcknowledgment(alert.originatorDeviceId, messageId, 'acknowledged');

  res.json({
    success: true,
    message: 'Alert acknowledged',
    data: {
      alert: alert.toPublicJSON()
    }
  });
});

/**
 * Resolve an SOS alert
 * POST /api/v1/sos/:messageId/resolve
 */
const resolveAlert = asyncHandler(async (req, res) => {
  const { messageId } = req.params;
  const { notes } = req.body;

  const alert = await SOSAlert.findOne({ messageId });

  if (!alert) {
    throw new ApiError(404, 'Alert not found');
  }

  await alert.resolve(notes);

  logger.info(`SOS alert resolved: ${messageId}`);

  // Broadcast update
  broadcastSOSUpdate(alert, 'resolved');

  // Notify originator
  sendSOSAcknowledgment(alert.originatorDeviceId, messageId, 'resolved');

  res.json({
    success: true,
    message: 'Alert resolved',
    data: {
      alert: alert.toPublicJSON()
    }
  });
});

/**
 * Get active SOS alerts
 * GET /api/v1/sos/active
 */
const getActiveAlerts = asyncHandler(async (req, res) => {
  const { limit = 50, offset = 0 } = req.query;

  const alerts = await SOSAlert.findActive()
    .skip(parseInt(offset))
    .limit(parseInt(limit));

  const total = await SOSAlert.countDocuments({
    status: { $in: ['active', 'acknowledged', 'responding'] },
    expiresAt: { $gt: new Date() }
  });

  res.json({
    success: true,
    data: {
      alerts: alerts.map(a => a.toPublicJSON()),
      total,
      limit: parseInt(limit),
      offset: parseInt(offset)
    }
  });
});

/**
 * Get nearby SOS alerts
 * GET /api/v1/sos/nearby
 */
const getNearbyAlerts = asyncHandler(async (req, res) => {
  const { latitude, longitude, radius } = req.query;

  if (!latitude || !longitude) {
    throw new ApiError(400, 'Latitude and longitude are required');
  }

  const lat = parseFloat(latitude);
  const lon = parseFloat(longitude);
  const radiusKm = parseFloat(radius) || 10;

  const alerts = await SOSAlert.findNearby(lat, lon, radiusKm);

  res.json({
    success: true,
    data: {
      alerts: alerts.map(a => a.toPublicJSON()),
      count: alerts.length
    }
  });
});

/**
 * Get SOS alert by ID
 * GET /api/v1/sos/:messageId
 */
const getAlert = asyncHandler(async (req, res) => {
  const { messageId } = req.params;

  const alert = await SOSAlert.findOne({ messageId });

  if (!alert) {
    throw new ApiError(404, 'Alert not found');
  }

  res.json({
    success: true,
    data: {
      alert: alert.toPublicJSON()
    }
  });
});

/**
 * Get alerts by originator device
 * GET /api/v1/sos/device/:deviceId
 */
const getAlertsByDevice = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const { limit = 20 } = req.query;

  const alerts = await SOSAlert.findByOriginator(deviceId)
    .limit(parseInt(limit));

  res.json({
    success: true,
    data: {
      alerts: alerts.map(a => a.toPublicJSON()),
      count: alerts.length
    }
  });
});

/**
 * Get SOS statistics
 * GET /api/v1/sos/stats
 */
const getStats = asyncHandler(async (req, res) => {
  const now = new Date();
  const last24h = new Date(now - 24 * 60 * 60 * 1000);
  const last7d = new Date(now - 7 * 24 * 60 * 60 * 1000);

  const [
    activeCount,
    last24hCount,
    last7dCount,
    byType,
    byStatus
  ] = await Promise.all([
    SOSAlert.countDocuments({
      status: { $in: ['active', 'acknowledged', 'responding'] },
      expiresAt: { $gt: now }
    }),
    SOSAlert.countDocuments({ createdAt: { $gte: last24h } }),
    SOSAlert.countDocuments({ createdAt: { $gte: last7d } }),
    SOSAlert.aggregate([
      { $group: { _id: '$emergencyType', count: { $sum: 1 } } }
    ]),
    SOSAlert.aggregate([
      { $group: { _id: '$status', count: { $sum: 1 } } }
    ])
  ]);

  res.json({
    success: true,
    data: {
      active: activeCount,
      last24Hours: last24hCount,
      last7Days: last7dCount,
      byType: Object.fromEntries(byType.map(t => [t._id, t.count])),
      byStatus: Object.fromEntries(byStatus.map(s => [s._id, s.count]))
    }
  });
});

module.exports = {
  createAlert,
  receiveRelayedAlert,
  cancelAlert,
  acknowledgeAlert,
  resolveAlert,
  getActiveAlerts,
  getNearbyAlerts,
  getAlert,
  getAlertsByDevice,
  getStats
};
