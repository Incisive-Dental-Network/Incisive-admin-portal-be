import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';

/**
 * Decorator to get or generate request ID for tracing
 * Usage: @RequestId() requestId: string
 */
export const RequestId = createParamDecorator(
  (data: unknown, ctx: ExecutionContext): string => {
    const request = ctx.switchToHttp().getRequest();

    // Check for existing request ID from header
    let requestId = request.headers['x-request-id'];

    // Generate new ID if not present
    if (!requestId) {
      requestId = uuidv4();
      request.headers['x-request-id'] = requestId;
    }

    return requestId;
  },
);
