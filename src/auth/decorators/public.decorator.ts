import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

// Usage: @Public() - skips JWT auth for this route
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
