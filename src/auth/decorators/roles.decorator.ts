import { SetMetadata } from '@nestjs/common';
import { Role } from '../constants/roles.enum';

export const ROLES_KEY = 'roles';

// Usage: @Roles(Role.ADMIN, Role.USER)
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);
