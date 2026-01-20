import {
  Injectable,
  NotFoundException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import {
  AdminCreateUserDto,
  AdminUpdateUserDto,
  UserQueryDto,
  AuditLogQueryDto,
  DashboardStatsDto,
} from './dto';

@Injectable()
export class AdminService {
  constructor(
    private prisma: PrismaService,
    private auditService: AuditService,
  ) {}

  /**
   * Get dashboard statistics
   */
  async getDashboardStats(): Promise<DashboardStatsDto> {
    const now = new Date();
    const todayStart = new Date(now.setHours(0, 0, 0, 0));
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const monthAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const last24Hours = new Date(Date.now() - 24 * 60 * 60 * 1000);

    // User stats
    const [
      totalUsers,
      activeUsers,
      adminCount,
      userCount,
      viewerCount,
      newUsersThisWeek,
      newUsersThisMonth,
    ] = await Promise.all([
      this.prisma.users.count(),
      this.prisma.users.count({ where: { is_active: true } }),
      this.prisma.users.count({ where: { role: 'ADMIN' } }),
      this.prisma.users.count({ where: { role: 'USER' } }),
      this.prisma.users.count({ where: { role: 'VIEWER' } }),
      this.prisma.users.count({ where: { created_at: { gte: weekAgo } } }),
      this.prisma.users.count({ where: { created_at: { gte: monthAgo } } }),
    ]);

    // Audit stats
    const [totalLogs, logsLast24Hours, loginsToday, actionCounts] = await Promise.all([
      this.prisma.audit_logs.count(),
      this.prisma.audit_logs.count({ where: { created_at: { gte: last24Hours } } }),
      this.prisma.audit_logs.count({
        where: {
          action: 'LOGIN',
          created_at: { gte: todayStart },
        },
      }),
      this.prisma.audit_logs.groupBy({
        by: ['action'],
        _count: { action: true },
      }),
    ]);

    const actionBreakdown: Record<string, number> = {};
    actionCounts.forEach((item: { action: string; _count: { action: number } }) => {
      actionBreakdown[item.action] = item._count.action;
    });

    return {
      users: {
        total: totalUsers,
        active: activeUsers,
        inactive: totalUsers - activeUsers,
        admins: adminCount,
        users: userCount,
        viewers: viewerCount,
      },
      recentActivity: {
        loginsToday,
        newUsersThisWeek,
        newUsersThisMonth,
      },
      auditSummary: {
        totalLogs,
        logsLast24Hours,
        actionBreakdown,
      },
      generatedAt: new Date(),
    };
  }

  /**
   * Get all users with filtering and pagination
   */
  async getUsers(query: UserQueryDto) {
    const { page = 1, limit = 10, search, role, isActive } = query;
    const skip = (page - 1) * limit;

    const where: any = {};

    if (search) {
      where.OR = [
        { email: { contains: search, mode: 'insensitive' } },
        { first_name: { contains: search, mode: 'insensitive' } },
        { last_name: { contains: search, mode: 'insensitive' } },
      ];
    }

    if (role) {
      where.role = role;
    }

    if (isActive !== undefined) {
      where.is_active = isActive;
    }

    const [users, total] = await Promise.all([
      this.prisma.users.findMany({
        where,
        skip,
        take: limit,
        orderBy: { created_at: 'desc' },
        select: {
          id: true,
          email: true,
          first_name: true,
          last_name: true,
          role: true,
          is_active: true,
          created_at: true,
          updated_at: true,
        },
      }),
      this.prisma.users.count({ where }),
    ]);

    return {
      data: users,
      meta: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * Get a single user by ID
   */
  async getUserById(id: string) {
    const user = await this.prisma.users.findUnique({
      where: { id },
      select: {
        id: true,
        email: true,
        first_name: true,
        last_name: true,
        role: true,
        is_active: true,
        created_at: true,
        updated_at: true,
        _count: {
          select: { audit_logs: true },
        },
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    return user;
  }

  /**
   * Create a new user (admin only)
   */
  async createUser(dto: AdminCreateUserDto, adminId: string) {
    const existingUser = await this.prisma.users.findUnique({
      where: { email: dto.email },
    });

    if (existingUser) {
      throw new ConflictException('User with this email already exists');
    }

    const hashedPassword = await bcrypt.hash(dto.password, 10);

    const user = await this.prisma.users.create({
      data: {
        email: dto.email,
        password: hashedPassword,
        first_name: dto.firstName,
        last_name: dto.lastName,
        role: dto.role || 'USER',
        is_active: dto.isActive ?? true,
      },
      select: {
        id: true,
        email: true,
        first_name: true,
        last_name: true,
        role: true,
        is_active: true,
        created_at: true,
      },
    });

    // Log the action
    await this.auditService.logCreateUser(adminId, user.id, user.email);

    return user;
  }

  /**
   * Update a user (admin only)
   */
  async updateUser(id: string, dto: AdminUpdateUserDto, adminId: string) {
    const user = await this.prisma.users.findUnique({
      where: { id },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    const updateData: any = {};

    // Map DTO fields to database fields
    if (dto.email !== undefined) updateData.email = dto.email;
    if (dto.firstName !== undefined) updateData.first_name = dto.firstName;
    if (dto.lastName !== undefined) updateData.last_name = dto.lastName;
    if (dto.role !== undefined) updateData.role = dto.role;
    if (dto.isActive !== undefined) updateData.is_active = dto.isActive;

    // Hash password if being updated
    if (dto.password) {
      updateData.password = await bcrypt.hash(dto.password, 10);
    }

    // Check for email conflict if email is being updated
    if (dto.email && dto.email !== user.email) {
      const existingUser = await this.prisma.users.findUnique({
        where: { email: dto.email },
      });
      if (existingUser) {
        throw new ConflictException('Email already in use');
      }
    }

    const updatedUser = await this.prisma.users.update({
      where: { id },
      data: updateData,
      select: {
        id: true,
        email: true,
        first_name: true,
        last_name: true,
        role: true,
        is_active: true,
        updated_at: true,
      },
    });

    // Log the action
    await this.auditService.logUpdateUser(adminId, id);

    return updatedUser;
  }

  /**
   * Delete a user (admin only)
   */
  async deleteUser(id: string, adminId: string) {
    if (id === adminId) {
      throw new ForbiddenException('You cannot delete your own account');
    }

    const user = await this.prisma.users.findUnique({
      where: { id },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    await this.prisma.users.delete({
      where: { id },
    });

    // Log the action
    await this.auditService.logDeleteUser(adminId, id, user.email);

    return { message: 'User deleted successfully' };
  }

  /**
   * Activate a user
   */
  async activateUser(id: string, adminId: string) {
    const user = await this.prisma.users.findUnique({
      where: { id },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (user.is_active) {
      return { message: 'User is already active' };
    }

    await this.prisma.users.update({
      where: { id },
      data: { is_active: true },
    });

    await this.auditService.logUpdateUser(adminId, id);

    return { message: 'User activated successfully' };
  }

  /**
   * Deactivate a user
   */
  async deactivateUser(id: string, adminId: string) {
    if (id === adminId) {
      throw new ForbiddenException('You cannot deactivate your own account');
    }

    const user = await this.prisma.users.findUnique({
      where: { id },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (!user.is_active) {
      return { message: 'User is already inactive' };
    }

    await this.prisma.users.update({
      where: { id },
      data: { is_active: false },
    });

    await this.auditService.logUpdateUser(adminId, id);

    return { message: 'User deactivated successfully' };
  }

  /**
   * Get audit logs with filtering
   */
  async getAuditLogs(query: AuditLogQueryDto) {
    const { page = 1, limit = 20, userId, action, startDate, endDate } = query;
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
        where.created_at.gte = new Date(startDate);
      }
      if (endDate) {
        where.created_at.lte = new Date(endDate);
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
}
