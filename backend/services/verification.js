/**
 * Message Verification Service
 * Verifies that SOS messages originated from the legitimate app
 */

const crypto = require('crypto');
const logger = require('../utils/logger');

const APP_SIGNATURE_SECRET = process.env.APP_SIGNATURE_SECRET || 'default-app-secret';

/**
 * Verify app signature
 * This ensures the message came from our app
 */
function verifyAppSignature(appSignature) {
  // The app signature is a hash of the app's bundle ID + secret
  // In production, use a more sophisticated verification
  const validSignatures = generateValidAppSignatures();
  return validSignatures.includes(appSignature);
}

/**
 * Generate valid app signatures for verification
 */
function generateValidAppSignatures() {
  const bundleIds = [
    'com.sosemergency.app',
    'com.sosemergency.app.dev',
    'com.sosemergency.app.staging'
  ];

  return bundleIds.map(bundleId => {
    return crypto
      .createHmac('sha256', APP_SIGNATURE_SECRET)
      .update(bundleId)
      .digest('hex');
  });
}

/**
 * Verify message signature
 * This ensures the message wasn't tampered with
 */
function verifyMessageSignature(message, signature, publicKey) {
  try {
    // Create the message payload to verify
    const payload = createSignaturePayload(message);

    // For HMAC-based verification (simpler)
    if (!publicKey) {
      const expectedSignature = crypto
        .createHmac('sha256', APP_SIGNATURE_SECRET)
        .update(payload)
        .digest('hex');
      return signature === expectedSignature;
    }

    // For RSA/ECDSA verification (more secure)
    const verify = crypto.createVerify('SHA256');
    verify.update(payload);
    verify.end();
    return verify.verify(publicKey, signature, 'hex');
  } catch (err) {
    logger.error('Signature verification failed:', err);
    return false;
  }
}

/**
 * Create the payload string for signature verification
 */
function createSignaturePayload(message) {
  const {
    messageId,
    originatorDeviceId,
    emergencyType,
    priority,
    location,
    message: msgContent,
    originatedAt
  } = message;

  // Concatenate fields in a deterministic order
  return [
    messageId,
    originatorDeviceId,
    emergencyType,
    priority,
    location.latitude.toFixed(6),
    location.longitude.toFixed(6),
    msgContent || '',
    originatedAt
  ].join('|');
}

/**
 * Generate signature for a message (used by app)
 * This is provided for reference - actual signing happens in the app
 */
function generateMessageSignature(message) {
  const payload = createSignaturePayload(message);
  return crypto
    .createHmac('sha256', APP_SIGNATURE_SECRET)
    .update(payload)
    .digest('hex');
}

/**
 * Verify the complete SOS message
 */
function verifySOS(sosData) {
  const errors = [];

  // 1. Verify app signature
  if (!verifyAppSignature(sosData.appSignature)) {
    errors.push('Invalid app signature');
  }

  // 2. Verify message signature
  if (!verifyMessageSignature(sosData, sosData.signature)) {
    errors.push('Invalid message signature');
  }

  // 3. Check message timestamp (not too old, not in future)
  const originatedAt = new Date(sosData.originatedAt);
  const now = new Date();
  const maxAge = 24 * 60 * 60 * 1000; // 24 hours

  if (originatedAt > now) {
    errors.push('Message timestamp is in the future');
  }

  if (now - originatedAt > maxAge) {
    errors.push('Message is too old');
  }

  // 4. Check location validity
  if (!sosData.location ||
      typeof sosData.location.latitude !== 'number' ||
      typeof sosData.location.longitude !== 'number') {
    errors.push('Invalid location data');
  }

  return {
    isValid: errors.length === 0,
    errors
  };
}

/**
 * Generate app signature for a bundle ID
 * Used during app initialization
 */
function generateAppSignature(bundleId) {
  return crypto
    .createHmac('sha256', APP_SIGNATURE_SECRET)
    .update(bundleId)
    .digest('hex');
}

module.exports = {
  verifyAppSignature,
  verifyMessageSignature,
  verifySOS,
  generateMessageSignature,
  generateAppSignature,
  createSignaturePayload
};
