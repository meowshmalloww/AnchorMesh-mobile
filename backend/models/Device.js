/**
 * Device Model - Stores registered devices
 */

const mongoose = require('mongoose');

const locationSchema = new mongoose.Schema({
  latitude: {
    type: Number,
    required: true,
    min: -90,
    max: 90
  },
  longitude: {
    type: Number,
    required: true,
    min: -180,
    max: 180
  },
  altitude: {
    type: Number,
    default: null
  },
  accuracy: {
    type: Number,
    default: null
  },
  timestamp: {
    type: Date,
    default: Date.now
  }
}, { _id: false });

const deviceSchema = new mongoose.Schema({
  deviceId: {
    type: String,
    required: true,
    unique: true,
    trim: true,
    index: true
  },
  platform: {
    type: String,
    required: true,
    enum: ['ios', 'android', 'web']
  },
  appVersion: {
    type: String,
    trim: true
  },
  osVersion: {
    type: String,
    trim: true
  },
  deviceModel: {
    type: String,
    trim: true
  },
  pushToken: {
    type: String,
    trim: true
  },
  publicKey: {
    type: String,
    trim: true
  },
  lastKnownLocation: {
    type: locationSchema,
    default: null
  },
  hasInternetCapability: {
    type: Boolean,
    default: true
  },
  bleCapabilities: {
    supportsExtended: {
      type: Boolean,
      default: false
    },
    supportsMesh: {
      type: Boolean,
      default: true
    }
  },
  isActive: {
    type: Boolean,
    default: true
  },
  lastSeen: {
    type: Date,
    default: Date.now
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  metadata: {
    type: Map,
    of: String,
    default: {}
  }
}, {
  timestamps: true
});

// Indexes for common queries
deviceSchema.index({ lastSeen: -1 });
deviceSchema.index({ isActive: 1, lastSeen: -1 });
deviceSchema.index({ 'lastKnownLocation.latitude': 1, 'lastKnownLocation.longitude': 1 });

// Methods
deviceSchema.methods.updateLocation = function(location) {
  this.lastKnownLocation = {
    ...location,
    timestamp: new Date()
  };
  this.lastSeen = new Date();
  return this.save();
};

deviceSchema.methods.toPublicJSON = function() {
  return {
    deviceId: this.deviceId,
    platform: this.platform,
    lastKnownLocation: this.lastKnownLocation,
    hasInternetCapability: this.hasInternetCapability,
    bleCapabilities: this.bleCapabilities,
    lastSeen: this.lastSeen
  };
};

// Statics
deviceSchema.statics.findActive = function() {
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000); // 24 hours
  return this.find({
    isActive: true,
    lastSeen: { $gte: cutoff }
  });
};

deviceSchema.statics.findNearby = function(latitude, longitude, radiusKm = 10) {
  // Simple bounding box query (for precise geo queries, use 2dsphere index)
  const latDelta = radiusKm / 111; // ~111km per degree latitude
  const lonDelta = radiusKm / (111 * Math.cos(latitude * Math.PI / 180));

  return this.find({
    isActive: true,
    'lastKnownLocation.latitude': {
      $gte: latitude - latDelta,
      $lte: latitude + latDelta
    },
    'lastKnownLocation.longitude': {
      $gte: longitude - lonDelta,
      $lte: longitude + lonDelta
    }
  });
};

const Device = mongoose.model('Device', deviceSchema);

module.exports = Device;
