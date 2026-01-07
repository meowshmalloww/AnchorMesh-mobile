/**
 * SOS Alert Model - Stores emergency alerts
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
  }
}, { _id: false });

const relayInfoSchema = new mongoose.Schema({
  deviceId: {
    type: String,
    required: true
  },
  timestamp: {
    type: Date,
    default: Date.now
  },
  hadInternet: {
    type: Boolean,
    default: false
  }
}, { _id: false });

const sosAlertSchema = new mongoose.Schema({
  messageId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  originatorDeviceId: {
    type: String,
    required: true,
    index: true
  },
  emergencyType: {
    type: String,
    required: true,
    enum: ['medical', 'fire', 'security', 'natural_disaster', 'accident', 'other']
  },
  priority: {
    type: String,
    default: 'high',
    enum: ['low', 'medium', 'high', 'critical']
  },
  location: {
    type: locationSchema,
    required: true
  },
  message: {
    type: String,
    trim: true,
    maxlength: 500
  },
  signature: {
    type: String,
    required: true
  },
  appSignature: {
    type: String,
    required: true
  },
  status: {
    type: String,
    default: 'active',
    enum: ['active', 'acknowledged', 'responding', 'resolved', 'cancelled', 'expired']
  },
  // Relay tracking
  hopCount: {
    type: Number,
    default: 0
  },
  relayChain: {
    type: [relayInfoSchema],
    default: []
  },
  deliveredBy: {
    type: String, // Device ID that delivered to server
    index: true
  },
  deliveredVia: {
    type: String,
    enum: ['direct', 'mesh_relay'],
    default: 'direct'
  },
  // Timestamps
  originatedAt: {
    type: Date,
    required: true
  },
  receivedAt: {
    type: Date,
    default: Date.now
  },
  acknowledgedAt: {
    type: Date
  },
  resolvedAt: {
    type: Date
  },
  expiresAt: {
    type: Date,
    required: true
  },
  // Response tracking
  responders: [{
    responderId: String,
    type: {
      type: String,
      enum: ['user', 'official', 'emergency_service']
    },
    assignedAt: Date,
    acknowledgedAt: Date,
    arrivedAt: Date
  }],
  // Verification
  isVerified: {
    type: Boolean,
    default: false
  },
  verificationNotes: {
    type: String
  },
  // Additional data
  metadata: {
    type: Map,
    of: mongoose.Schema.Types.Mixed,
    default: {}
  }
}, {
  timestamps: true
});

// Indexes
sosAlertSchema.index({ status: 1, createdAt: -1 });
sosAlertSchema.index({ originatorDeviceId: 1, createdAt: -1 });
sosAlertSchema.index({ 'location.latitude': 1, 'location.longitude': 1 });
sosAlertSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 }); // TTL index

// Virtual for checking if expired
sosAlertSchema.virtual('isExpired').get(function() {
  return new Date() > this.expiresAt;
});

// Methods
sosAlertSchema.methods.acknowledge = function(responderId, responderType) {
  this.status = 'acknowledged';
  this.acknowledgedAt = new Date();

  if (responderId) {
    this.responders.push({
      responderId,
      type: responderType || 'user',
      assignedAt: new Date(),
      acknowledgedAt: new Date()
    });
  }

  return this.save();
};

sosAlertSchema.methods.resolve = function(notes) {
  this.status = 'resolved';
  this.resolvedAt = new Date();
  if (notes) {
    this.verificationNotes = notes;
  }
  return this.save();
};

sosAlertSchema.methods.cancel = function() {
  this.status = 'cancelled';
  return this.save();
};

sosAlertSchema.methods.addRelayHop = function(deviceId, hadInternet) {
  this.relayChain.push({
    deviceId,
    timestamp: new Date(),
    hadInternet
  });
  this.hopCount = this.relayChain.length;
  return this;
};

sosAlertSchema.methods.toPublicJSON = function() {
  return {
    messageId: this.messageId,
    originatorDeviceId: this.originatorDeviceId,
    emergencyType: this.emergencyType,
    priority: this.priority,
    location: this.location,
    message: this.message,
    status: this.status,
    hopCount: this.hopCount,
    originatedAt: this.originatedAt,
    receivedAt: this.receivedAt,
    acknowledgedAt: this.acknowledgedAt,
    isExpired: this.isExpired
  };
};

// Statics
sosAlertSchema.statics.findActive = function() {
  return this.find({
    status: { $in: ['active', 'acknowledged', 'responding'] },
    expiresAt: { $gt: new Date() }
  }).sort({ priority: -1, createdAt: -1 });
};

sosAlertSchema.statics.findByOriginator = function(deviceId) {
  return this.find({
    originatorDeviceId: deviceId
  }).sort({ createdAt: -1 });
};

sosAlertSchema.statics.findNearby = function(latitude, longitude, radiusKm = 10) {
  const latDelta = radiusKm / 111;
  const lonDelta = radiusKm / (111 * Math.cos(latitude * Math.PI / 180));

  return this.find({
    status: { $in: ['active', 'acknowledged', 'responding'] },
    expiresAt: { $gt: new Date() },
    'location.latitude': {
      $gte: latitude - latDelta,
      $lte: latitude + latDelta
    },
    'location.longitude': {
      $gte: longitude - lonDelta,
      $lte: longitude + lonDelta
    }
  }).sort({ priority: -1, createdAt: -1 });
};

const SOSAlert = mongoose.model('SOSAlert', sosAlertSchema);

module.exports = SOSAlert;
