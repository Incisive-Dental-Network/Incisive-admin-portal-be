import { createParamDecorator, ExecutionContext } from '@nestjs/common';

/**
 * Decorator to get current authenticated user from request
 * Usage: @CurrentUser() user: User
 * Usage: @CurrentUser('id') userId: string
 */
export const CurrentUser = createParamDecorator(
  (data: string | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user;

    if (!user) {
      return null;
    }

    // If specific field requested, return only that field
    if (data) {
      return user[data];
    }

    return user;
  },
);
