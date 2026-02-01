import {
  Injectable,
  NotFoundException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';
import {
  AdminCreateUserDto,
  AdminUpdateUserDto,
  UserQueryDto,
  DashboardStatsDto,
} from './dto';

@Injectable()
export class AdminService {
  constructor(private prisma: PrismaService) {}

  /**
   * Get dashboard statistics
   */
  async getDashboardStats(): Promise<DashboardStatsDto> {
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const monthAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

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
        newUsersThisWeek,
        newUsersThisMonth,
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

    return { message: 'User deactivated successfully' };
  }
}
