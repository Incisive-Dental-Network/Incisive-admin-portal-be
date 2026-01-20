import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditAction, AuditLogEntry, AuditQueryParams } from './audit.types';

@Injectable()
export class AuditService {
  constructor(private prisma: PrismaService) {}

  /**
   * Create an audit log entry
   */
  async log(entry: AuditLogEntry): Promise<void> {
    try {
      await this.prisma.audit_logs.create({
        data: {
          user_id: entry.userId,
          action: entry.action,
          resource: entry.resource,
          details: entry.details as any,
          ip_address: entry.ipAddress,
          user_agent: entry.userAgent,
        },
      });
    } catch (error) {
      // Log error but don't throw - audit should not break the main flow
      console.error('Failed to create audit log:', error);
    }
  }

  /**
   * Query audit logs with filters
   */
  async findAll(params: AuditQueryParams) {
    const { userId, action, startDate, endDate, page = 1, limit = 20 } = params;
    const skip = (page - 1) * limit;

    const where: any = {};

    if (userId) {
      where.user_id = userId;
    }

    if (action) {
      where.action = action;
    }

    if (startDate || endDate) {
      where.created_at = {};
      if (startDate) {
        where.created_at.gte = startDate;
      }
      if (endDate) {
        where.created_at.lte = endDate;
      }
    }

    const [logs, total] = await Promise.all([
      this.prisma.audit_logs.findMany({
        where,
        skip,
        take: limit,
        orderBy: { created_at: 'desc' },
        include: {
          users: {
            select: {
              id: true,
              email: true,
              first_name: true,
              last_name: true,
            },
          },
        },
      }),
      this.prisma.audit_logs.count({ where }),
    ]);

    return {
      data: logs,
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * Get audit logs for a specific user
   */
  async findByUser(userId: string, page = 1, limit = 20) {
    return this.findAll({ userId, page, limit });
  }

  /**
   * Get audit logs for a specific resource
   */
  async findByResource(resource: string, page = 1, limit = 20) {
    const skip = (page - 1) * limit;

    const [logs, total] = await Promise.all([
      this.prisma.audit_logs.findMany({
        where: { resource },
        skip,
        take: limit,
        orderBy: { created_at: 'desc' },
        include: {
          users: {
            select: {
              id: true,
              email: true,
              first_name: true,
              last_name: true,
            },
          },
        },
      }),
      this.prisma.audit_logs.count({ where: { resource } }),
    ]);

    return {
      data: logs,
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  // Convenience methods for common actions
  async logLogin(userId: string, ipAddress?: string, userAgent?: string) {
    return this.log({ userId, action: AuditAction.LOGIN, ipAddress, userAgent });
  }

  async logLogout(userId: string) {
    return this.log({ userId, action: AuditAction.LOGOUT });
  }

  async logCreateUser(userId: string, createdUserId: string, email: string) {
    return this.log({
      userId,
      action: AuditAction.CREATE_USER,
      resource: createdUserId,
      details: { email },
    });
  }

  async logUpdateUser(userId: string, updatedUserId: string) {
    return this.log({
      userId,
      action: AuditAction.UPDATE_USER,
      resource: updatedUserId,
    });
  }

  async logDeleteUser(userId: string, deletedUserId: string, email: string) {
    return this.log({
      userId,
      action: AuditAction.DELETE_USER,
      resource: deletedUserId,
      details: { email },
    });
  }
}
