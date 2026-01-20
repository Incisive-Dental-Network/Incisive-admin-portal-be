import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Role } from '../../auth/constants/roles.enum';

export const OWNERSHIP_KEY = 'ownership';
export const CheckOwnership = (resourceUserIdField = 'uploadedBy') =>
  Reflect.metadata(OWNERSHIP_KEY, resourceUserIdField);

/**
 * Guard that checks if user owns the resource or is an admin
 * Use with @CheckOwnership() decorator on controller methods
 */
@Injectable()
export class OwnershipGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const resourceUserIdField = this.reflector.get<string>(
      OWNERSHIP_KEY,
      context.getHandler(),
    );

    // If no ownership check configured, allow access
    if (!resourceUserIdField) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    // Admins always have access
    if (user?.role === Role.ADMIN) {
      return true;
    }

    // Check if user owns the resource (resource must be attached to request by a pipe/interceptor)
    const resource = request.resource;
    if (!resource) {
      // Resource not loaded yet, allow and let service handle it
      return true;
    }

    const resourceOwnerId = resource[resourceUserIdField];
    if (resourceOwnerId !== user?.id) {
      throw new ForbiddenException('You do not have permission to access this resource');
    }

    return true;
  }
}
