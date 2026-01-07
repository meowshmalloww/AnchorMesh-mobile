/**
 * Global Error Handling Middleware
 */

const logger = require('../utils/logger');

/**
 * Custom error class for API errors
 */
class ApiError extends Error {
  constructor(statusCode, message, isOperational = true) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * 404 Not Found handler
 */
function notFoundHandler(req, res, next) {
  res.status(404).json({
    success: false,
    error: 'Resource not found',
    path: req.path,
    method: req.method
  });
}

/**
 * Global error handler
 */
function errorHandler(err, req, res, next) {
  // Log the error
  logger.error('Error occurred', {
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
    deviceId: req.headers['x-device-id'] || req.deviceId,
    body: req.body
  });

  // Determine status code
  let statusCode = err.statusCode || err.status || 500;

  // Handle specific error types
  if (err.name === 'ValidationError') {
    statusCode = 400;
  } else if (err.name === 'UnauthorizedError' || err.name === 'JsonWebTokenError') {
    statusCode = 401;
  } else if (err.name === 'TokenExpiredError') {
    statusCode = 401;
  } else if (err.name === 'ForbiddenError') {
    statusCode = 403;
  } else if (err.name === 'CastError') {
    statusCode = 400;
  } else if (err.code === 11000) {
    // MongoDB duplicate key error
    statusCode = 409;
  }

  // Build error response
  const errorResponse = {
    success: false,
    error: process.env.NODE_ENV === 'production' && statusCode === 500
      ? 'Internal server error'
      : err.message,
    code: err.code || undefined
  };

  // Include stack trace in development
  if (process.env.NODE_ENV !== 'production') {
    errorResponse.stack = err.stack;
  }

  // Include validation errors if present
  if (err.errors) {
    errorResponse.errors = err.errors;
  }

  res.status(statusCode).json(errorResponse);
}

/**
 * Async handler wrapper to catch errors in async route handlers
 */
function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

module.exports = {
  ApiError,
  notFoundHandler,
  errorHandler,
  asyncHandler
};
