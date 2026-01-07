/**
 * Device Controller - Handles device registration and management
 */

const Device = require('../models/Device');
const { generateToken } = require('../middleware/auth');
const { ApiError, asyncHandler } = require('../middleware/errorHandler');
const { generateAppSignature } = require('../services/verification');
const logger = require('../utils/logger');

/**
 * Register a new device or update existing
 * POST /api/v1/device/register
 */
const registerDevice = asyncHandler(async (req, res) => {
  const {
    deviceId,
    platform,
    appVersion,
    osVersion,
    deviceModel,
    pushToken,
    publicKey,
    bleCapabilities
  } = req.body;

  // Check if device already exists
  let device = await Device.findOne({ deviceId });

  if (device) {
    // Update existing device
    device.platform = platform;
    device.appVersion = appVersion || device.appVersion;
    device.osVersion = osVersion || device.osVersion;
    device.deviceModel = deviceModel || device.deviceModel;
    device.pushToken = pushToken || device.pushToken;
    device.publicKey = publicKey || device.publicKey;
    device.bleCapabilities = bleCapabilities || device.bleCapabilities;
    device.isActive = true;
    device.lastSeen = new Date();

    await device.save();

    logger.info(`Device updated: ${deviceId}`);
  } else {
    // Create new device
    device = await Device.create({
      deviceId,
      platform,
      appVersion,
      osVersion,
      deviceModel,
      pushToken,
      publicKey,
      bleCapabilities
    });

    logger.info(`New device registered: ${deviceId}`);
  }

  // Generate JWT token
  const token = generateToken(deviceId);

  // Generate app signature for this device
  const bundleId = platform === 'ios'
    ? 'com.sosemergency.app'
    : 'com.sosemergency.app';
  const appSignature = generateAppSignature(bundleId);

  res.status(device.isNew ? 201 : 200).json({
    success: true,
    data: {
      device: device.toPublicJSON(),
      token,
      appSignature,
      expiresIn: process.env.JWT_EXPIRES_IN || '30d'
    }
  });
});

/**
 * Update device location
 * PUT /api/v1/device/location
 */
const updateLocation = asyncHandler(async (req, res) => {
  const { latitude, longitude, altitude, accuracy } = req.body;

  await req.device.updateLocation({
    latitude,
    longitude,
    altitude,
    accuracy
  });

  res.json({
    success: true,
    message: 'Location updated'
  });
});

/**
 * Update push token
 * PUT /api/v1/device/push-token
 */
const updatePushToken = asyncHandler(async (req, res) => {
  const { pushToken } = req.body;

  req.device.pushToken = pushToken;
  await req.device.save();

  res.json({
    success: true,
    message: 'Push token updated'
  });
});

/**
 * Device heartbeat
 * POST /api/v1/device/heartbeat
 */
const heartbeat = asyncHandler(async (req, res) => {
  const { location, hasInternet } = req.body;

  req.device.lastSeen = new Date();

  if (location) {
    req.device.lastKnownLocation = {
      ...location,
      timestamp: new Date()
    };
  }

  if (typeof hasInternet === 'boolean') {
    req.device.hasInternetCapability = hasInternet;
  }

  await req.device.save();

  res.json({
    success: true,
    timestamp: Date.now()
  });
});

/**
 * Get device info
 * GET /api/v1/device/me
 */
const getDeviceInfo = asyncHandler(async (req, res) => {
  res.json({
    success: true,
    data: {
      device: req.device.toPublicJSON()
    }
  });
});

/**
 * Deactivate device
 * DELETE /api/v1/device/me
 */
const deactivateDevice = asyncHandler(async (req, res) => {
  req.device.isActive = false;
  await req.device.save();

  logger.info(`Device deactivated: ${req.device.deviceId}`);

  res.json({
    success: true,
    message: 'Device deactivated'
  });
});

/**
 * Get nearby active devices (for mesh coordination)
 * GET /api/v1/device/nearby
 */
const getNearbyDevices = asyncHandler(async (req, res) => {
  const { latitude, longitude, radius } = req.query;

  if (!latitude || !longitude) {
    throw new ApiError(400, 'Latitude and longitude are required');
  }

  const lat = parseFloat(latitude);
  const lon = parseFloat(longitude);
  const radiusKm = parseFloat(radius) || 10;

  const devices = await Device.findNearby(lat, lon, radiusKm);

  // Filter out the requesting device
  const filteredDevices = devices
    .filter(d => d.deviceId !== req.deviceId)
    .map(d => d.toPublicJSON());

  res.json({
    success: true,
    data: {
      devices: filteredDevices,
      count: filteredDevices.length
    }
  });
});

module.exports = {
  registerDevice,
  updateLocation,
  updatePushToken,
  heartbeat,
  getDeviceInfo,
  deactivateDevice,
  getNearbyDevices
};
