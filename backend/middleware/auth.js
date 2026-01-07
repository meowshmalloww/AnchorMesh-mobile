/**
 * JWT Authentication Middleware
 */

const jwt = require('jsonwebtoken');
const Device = require('../models/Device');
const { ApiError } = require('./errorHandler');
const logger = require('../utils/logger');

/**
 * Authenticate device using JWT token
 */
async function authenticate(req, res, next) {
  try {
    // Get token from header
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new ApiError(401, 'No authentication token provided');
    }

    const token = authHeader.split(' ')[1];

    // Verify token
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // Check if device exists and is active
    const device = await Device.findOne({
      deviceId: decoded.deviceId,
      isActive: true
    });

    if (!device) {
      throw new ApiError(401, 'Device not found or inactive');
    }

    // Attach device info to request
    req.device = device;
    req.deviceId = device.deviceId;

    // Update last seen
    device.lastSeen = new Date();
    await device.save();

    next();
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      next(new ApiError(401, 'Invalid token'));
    } else if (error.name === 'TokenExpiredError') {
      next(new ApiError(401, 'Token expired'));
    } else {
      next(error);
    }
  }
}

/**
 * Optional authentication - doesn't fail if no token
 */
async function optionalAuth(req, res, next) {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return next();
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    const device = await Device.findOne({
      deviceId: decoded.deviceId,
      isActive: true
    });

    if (device) {
      req.device = device;
      req.deviceId = device.deviceId;
      device.lastSeen = new Date();
      await device.save();
    }

    next();
  } catch (error) {
    // Ignore auth errors for optional auth
    next();
  }
}

/**
 * Generate JWT token for device
 */
function generateToken(deviceId) {
  return jwt.sign(
    { deviceId },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '30d' }
  );
}

/**
 * Verify device ID header matches authenticated device
 */
function verifyDeviceId(req, res, next) {
  const headerDeviceId = req.headers['x-device-id'];

  if (headerDeviceId && req.deviceId && headerDeviceId !== req.deviceId) {
    return next(new ApiError(403, 'Device ID mismatch'));
  }

  next();
}

module.exports = {
  authenticate,
  optionalAuth,
  generateToken,
  verifyDeviceId
};
