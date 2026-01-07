/**
 * Request Validation Middleware using express-validator
 */

const { body, param, query, validationResult } = require('express-validator');
const { ApiError } = require('./errorHandler');

/**
 * Handle validation errors
 */
function handleValidationErrors(req, res, next) {
  const errors = validationResult(req);

  if (!errors.isEmpty()) {
    const errorMessages = errors.array().map(err => ({
      field: err.path,
      message: err.msg
    }));

    return next(new ApiError(400, 'Validation failed', true));
  }

  next();
}

/**
 * Validation rules for device registration
 */
const deviceRegistrationRules = [
  body('deviceId')
    .trim()
    .notEmpty()
    .withMessage('Device ID is required')
    .isLength({ min: 8, max: 128 })
    .withMessage('Device ID must be between 8 and 128 characters'),

  body('platform')
    .trim()
    .notEmpty()
    .withMessage('Platform is required')
    .isIn(['ios', 'android', 'web'])
    .withMessage('Platform must be ios, android, or web'),

  body('appVersion')
    .optional()
    .trim()
    .isLength({ max: 20 })
    .withMessage('App version must be at most 20 characters'),

  body('osVersion')
    .optional()
    .trim()
    .isLength({ max: 50 })
    .withMessage('OS version must be at most 50 characters'),

  body('deviceModel')
    .optional()
    .trim()
    .isLength({ max: 100 })
    .withMessage('Device model must be at most 100 characters'),

  body('pushToken')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Push token must be at most 500 characters')
];

/**
 * Validation rules for SOS alert
 */
const sosAlertRules = [
  body('messageId')
    .trim()
    .notEmpty()
    .withMessage('Message ID is required')
    .isUUID()
    .withMessage('Message ID must be a valid UUID'),

  body('originatorDeviceId')
    .trim()
    .notEmpty()
    .withMessage('Originator device ID is required'),

  body('emergencyType')
    .trim()
    .notEmpty()
    .withMessage('Emergency type is required')
    .isIn(['medical', 'fire', 'security', 'natural_disaster', 'accident', 'other'])
    .withMessage('Invalid emergency type'),

  body('priority')
    .optional()
    .isIn(['low', 'medium', 'high', 'critical'])
    .withMessage('Invalid priority level'),

  body('location')
    .notEmpty()
    .withMessage('Location is required'),

  body('location.latitude')
    .isFloat({ min: -90, max: 90 })
    .withMessage('Latitude must be between -90 and 90'),

  body('location.longitude')
    .isFloat({ min: -180, max: 180 })
    .withMessage('Longitude must be between -180 and 180'),

  body('message')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Message must be at most 500 characters'),

  body('signature')
    .trim()
    .notEmpty()
    .withMessage('Signature is required'),

  body('appSignature')
    .trim()
    .notEmpty()
    .withMessage('App signature is required')
];

/**
 * Validation rules for relayed SOS
 */
const relayedSosRules = [
  ...sosAlertRules,

  body('hopCount')
    .optional()
    .isInt({ min: 0, max: 100 })
    .withMessage('Hop count must be between 0 and 100'),

  body('relayChain')
    .optional()
    .isArray()
    .withMessage('Relay chain must be an array'),

  body('relayedBy')
    .trim()
    .notEmpty()
    .withMessage('Relayed by device ID is required')
];

/**
 * Validation rules for location update
 */
const locationUpdateRules = [
  body('latitude')
    .isFloat({ min: -90, max: 90 })
    .withMessage('Latitude must be between -90 and 90'),

  body('longitude')
    .isFloat({ min: -180, max: 180 })
    .withMessage('Longitude must be between -180 and 180'),

  body('altitude')
    .optional()
    .isFloat()
    .withMessage('Altitude must be a number'),

  body('accuracy')
    .optional()
    .isFloat({ min: 0 })
    .withMessage('Accuracy must be a positive number')
];

/**
 * Validation rules for SOS cancellation
 */
const cancelSosRules = [
  param('messageId')
    .trim()
    .notEmpty()
    .withMessage('Message ID is required')
    .isUUID()
    .withMessage('Message ID must be a valid UUID')
];

module.exports = {
  handleValidationErrors,
  deviceRegistrationRules,
  sosAlertRules,
  relayedSosRules,
  locationUpdateRules,
  cancelSosRules
};
