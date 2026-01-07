/**
 * SOS Alert Routes
 */

const express = require('express');
const router = express.Router();

const {
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
} = require('../controllers/sos.controller');

const { authenticate, optionalAuth } = require('../middleware/auth');
const {
  sosAlertRules,
  relayedSosRules,
  cancelSosRules,
  handleValidationErrors
} = require('../middleware/validator');

// All SOS routes require authentication
router.use(authenticate);

// Create new SOS alert (direct)
router.post(
  '/alert',
  sosAlertRules,
  handleValidationErrors,
  createAlert
);

// Receive relayed SOS alert (from mesh)
router.post(
  '/relay',
  relayedSosRules,
  handleValidationErrors,
  receiveRelayedAlert
);

// Get active alerts
router.get('/active', getActiveAlerts);

// Get nearby alerts
router.get('/nearby', getNearbyAlerts);

// Get SOS statistics
router.get('/stats', getStats);

// Get alerts by device
router.get('/device/:deviceId', getAlertsByDevice);

// Get specific alert
router.get('/:messageId', getAlert);

// Cancel alert
router.post(
  '/:messageId/cancel',
  cancelSosRules,
  handleValidationErrors,
  cancelAlert
);

// Acknowledge alert
router.post('/:messageId/acknowledge', acknowledgeAlert);

// Resolve alert
router.post('/:messageId/resolve', resolveAlert);

module.exports = router;
