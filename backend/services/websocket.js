/**
 * WebSocket Service for Real-time Dashboard Updates
 */

const WebSocket = require('ws');
const jwt = require('jsonwebtoken');
const logger = require('../utils/logger');

let wss = null;
const clients = new Map(); // deviceId -> WebSocket
const dashboardClients = new Set(); // Dashboard connections

/**
 * Initialize WebSocket server
 */
function initWebSocket(server) {
  wss = new WebSocket.Server({
    server,
    path: '/ws',
    verifyClient: (info, callback) => {
      // Allow all connections initially, authenticate after
      callback(true);
    }
  });

  wss.on('connection', (ws, req) => {
    logger.info('WebSocket connection established');

    let deviceId = null;
    let isDashboard = false;
    let isAuthenticated = false;

    // Set up ping/pong for connection health
    ws.isAlive = true;
    ws.on('pong', () => {
      ws.isAlive = true;
    });

    ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString());

        switch (message.type) {
          case 'auth':
            // Authenticate device connection
            try {
              const decoded = jwt.verify(message.token, process.env.JWT_SECRET);
              deviceId = decoded.deviceId;
              isAuthenticated = true;
              clients.set(deviceId, ws);

              ws.send(JSON.stringify({
                type: 'auth_success',
                deviceId
              }));

              logger.info(`Device authenticated via WebSocket: ${deviceId}`);
            } catch (err) {
              ws.send(JSON.stringify({
                type: 'auth_failed',
                error: 'Invalid token'
              }));
            }
            break;

          case 'dashboard_auth':
            // Dashboard authentication (separate auth mechanism)
            if (message.apiKey === process.env.DASHBOARD_API_KEY) {
              isDashboard = true;
              isAuthenticated = true;
              dashboardClients.add(ws);

              ws.send(JSON.stringify({
                type: 'dashboard_auth_success'
              }));

              logger.info('Dashboard connected via WebSocket');
            } else {
              ws.send(JSON.stringify({
                type: 'auth_failed',
                error: 'Invalid API key'
              }));
            }
            break;

          case 'heartbeat':
            ws.send(JSON.stringify({
              type: 'heartbeat_ack',
              timestamp: Date.now()
            }));
            break;

          case 'location_update':
            if (isAuthenticated && deviceId) {
              // Broadcast location to dashboards
              broadcastToDashboards({
                type: 'device_location_update',
                deviceId,
                location: message.location,
                timestamp: Date.now()
              });
            }
            break;

          default:
            logger.debug(`Unknown WebSocket message type: ${message.type}`);
        }
      } catch (err) {
        logger.error('WebSocket message error:', err);
        ws.send(JSON.stringify({
          type: 'error',
          error: 'Invalid message format'
        }));
      }
    });

    ws.on('close', () => {
      if (deviceId) {
        clients.delete(deviceId);
        logger.info(`Device disconnected: ${deviceId}`);
      }
      if (isDashboard) {
        dashboardClients.delete(ws);
        logger.info('Dashboard disconnected');
      }
    });

    ws.on('error', (err) => {
      logger.error('WebSocket error:', err);
    });

    // Send welcome message
    ws.send(JSON.stringify({
      type: 'welcome',
      message: 'Connected to SOS Mesh Server',
      timestamp: Date.now()
    }));
  });

  // Heartbeat interval to detect dead connections
  const heartbeatInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (ws.isAlive === false) {
        return ws.terminate();
      }
      ws.isAlive = false;
      ws.ping();
    });
  }, parseInt(process.env.WS_HEARTBEAT_INTERVAL) || 30000);

  wss.on('close', () => {
    clearInterval(heartbeatInterval);
  });

  logger.info('WebSocket server initialized');
  return wss;
}

/**
 * Broadcast message to all dashboard clients
 */
function broadcastToDashboards(message) {
  const payload = JSON.stringify(message);
  dashboardClients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
    }
  });
}

/**
 * Send message to specific device
 */
function sendToDevice(deviceId, message) {
  const client = clients.get(deviceId);
  if (client && client.readyState === WebSocket.OPEN) {
    client.send(JSON.stringify(message));
    return true;
  }
  return false;
}

/**
 * Broadcast new SOS alert to dashboards
 */
function broadcastSOSAlert(alert) {
  broadcastToDashboards({
    type: 'new_sos_alert',
    alert: alert.toPublicJSON ? alert.toPublicJSON() : alert,
    timestamp: Date.now()
  });
}

/**
 * Broadcast SOS status update
 */
function broadcastSOSUpdate(alert, updateType) {
  broadcastToDashboards({
    type: 'sos_update',
    updateType,
    alert: alert.toPublicJSON ? alert.toPublicJSON() : alert,
    timestamp: Date.now()
  });
}

/**
 * Send acknowledgment to originating device
 */
function sendSOSAcknowledgment(deviceId, messageId, status) {
  sendToDevice(deviceId, {
    type: 'sos_acknowledged',
    messageId,
    status,
    timestamp: Date.now()
  });
}

/**
 * Get connected client count
 */
function getStats() {
  return {
    totalConnections: wss ? wss.clients.size : 0,
    deviceConnections: clients.size,
    dashboardConnections: dashboardClients.size
  };
}

module.exports = {
  initWebSocket,
  broadcastToDashboards,
  sendToDevice,
  broadcastSOSAlert,
  broadcastSOSUpdate,
  sendSOSAcknowledgment,
  getStats
};
