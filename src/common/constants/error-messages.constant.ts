export const ErrorMessages = {
  // Authentication
  INVALID_CREDENTIALS: 'Invalid email or password',
  UNAUTHORIZED: 'Unauthorized access',
  TOKEN_EXPIRED: 'Token has expired',
  INVALID_TOKEN: 'Invalid or expired token',
  REFRESH_TOKEN_INVALID: 'Invalid refresh token',

  // Authorization
  FORBIDDEN: 'You do not have permission to perform this action',
  ADMIN_ONLY: 'This action requires admin privileges',
  OWNER_ONLY: 'You can only access your own resources',

  // User
  USER_NOT_FOUND: 'User not found',
  USER_EXISTS: 'User with this email already exists',
  USER_DEACTIVATED: 'User account is deactivated',
  CANNOT_DELETE_SELF: 'You cannot delete your own account',

  // General
  INTERNAL_ERROR: 'Internal server error',
  NOT_FOUND: 'Resource not found',
  BAD_REQUEST: 'Bad request',
  RATE_LIMIT: 'Too many requests. Please try again later',
} as const;
