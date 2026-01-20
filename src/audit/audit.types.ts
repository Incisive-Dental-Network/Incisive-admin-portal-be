export enum AuditAction {
  LOGIN = 'LOGIN',
  LOGOUT = 'LOGOUT',
  CREATE_USER = 'CREATE_USER',
  UPDATE_USER = 'UPDATE_USER',
  DELETE_USER = 'DELETE_USER',
}

export interface AuditLogEntry {
  userId: string;
  action: AuditAction;
  resource?: string; // File ID, User ID, etc.
  details?: Record<string, any>;
  ipAddress?: string;
  userAgent?: string;
}

export interface AuditQueryParams {
  userId?: string;
  action?: AuditAction;
  startDate?: Date;
  endDate?: Date;
  page?: number;
  limit?: number;
}
