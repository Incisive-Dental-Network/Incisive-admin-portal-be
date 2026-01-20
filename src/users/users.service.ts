import {
  Injectable,
  NotFoundException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';
import { CreateUserDto, UpdateUserDto } from './dto';
import { Role } from '../auth/constants/roles.enum';

@Injectable()
export class UsersService {
  constructor(private prisma: PrismaService) {}

  async create(createUserDto: CreateUserDto) {
    const { email, password, firstName, lastName, role } = createUserDto;

    // Check if user already exists
    const existingUser = await this.prisma.users.findUnique({
      where: { email },
    });

    if (existingUser) {
      throw new ConflictException('User with this email already exists');
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10);

    const user = await this.prisma.users.create({
      data: {
        email,
        password: hashedPassword,
        first_name: firstName,
        last_name: lastName,
        role: role || 'USER',
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

  async findAll(page = 1, limit = 10) {
    const skip = (page - 1) * limit;

    const [users, total] = await Promise.all([
      this.prisma.users.findMany({
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
        },
      }),
      this.prisma.users.count(),
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

  async findOne(id: string) {
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

  async findByEmail(email: string) {
    return this.prisma.users.findUnique({
      where: { email },
    });
  }

  async update(id: string, updateUserDto: UpdateUserDto, currentUserId: string, currentUserRole: Role) {
    // Check if user exists
    const user = await this.prisma.users.findUnique({
      where: { id },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Only admins can update other users
    if (id !== currentUserId && currentUserRole !== Role.ADMIN) {
      throw new ForbiddenException('You can only update your own profile');
    }

    // Only admins can change roles
    if (updateUserDto.role && currentUserRole !== Role.ADMIN) {
      throw new ForbiddenException('Only admins can change user roles');
    }

    // Only admins can activate/deactivate users
    if (updateUserDto.isActive !== undefined && currentUserRole !== Role.ADMIN) {
      throw new ForbiddenException('Only admins can activate/deactivate users');
    }

    // Prepare update data - map DTO fields to database fields
    const updateData: any = {};
    if (updateUserDto.firstName !== undefined) updateData.first_name = updateUserDto.firstName;
    if (updateUserDto.lastName !== undefined) updateData.last_name = updateUserDto.lastName;
    if (updateUserDto.role !== undefined) updateData.role = updateUserDto.role;
    if (updateUserDto.isActive !== undefined) updateData.is_active = updateUserDto.isActive;

    // Hash password if being updated
    if (updateUserDto.password) {
      updateData.password = await bcrypt.hash(updateUserDto.password, 10);
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

  async remove(id: string, currentUserId: string) {
    // Prevent self-deletion
    if (id === currentUserId) {
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
}
