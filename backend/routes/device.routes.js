/**
 * Device Routes
 */

const express = require('express');
const router = express.Router();

const {
  registerDevice,
  updateLocation,
  updatePushToken,
  heartbeat,
  getDeviceInfo,
  deactivateDevice,
  getNearbyDevices
} = require('../controllers/device.controller');

const { authenticate, optionalAuth } = require('../middleware/auth');
const {
  deviceRegistrationRules,
  locationUpdateRules,
  handleValidationErrors
} = require('../middleware/validator');

// Public routes
router.post(
  '/register',
  deviceRegistrationRules,
  handleValidationErrors,
  registerDevice
);

// Protected routes (require authentication)
router.use(authenticate);

router.get('/me', getDeviceInfo);
router.delete('/me', deactivateDevice);

router.put(
  '/location',
  locationUpdateRules,
  handleValidationErrors,
  updateLocation
);

router.put('/push-token', updatePushToken);

router.post('/heartbeat', heartbeat);

router.get('/nearby', getNearbyDevices);

module.exports = router;
