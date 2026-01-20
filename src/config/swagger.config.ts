import { DocumentBuilder } from '@nestjs/swagger';

export const swaggerConfig = new DocumentBuilder()
  .setTitle('Incisive User API')
  .setDescription('API with role-based access control')
  .setVersion('1.0')
  .addBearerAuth(
    {
      type: 'http',
      scheme: 'bearer',
      bearerFormat: 'JWT',
      name: 'JWT',
      description: 'Enter JWT token',
      in: 'header',
    },
    'JWT-auth',
  )
  .addTag('Auth', 'Authentication endpoints')
  .addTag('Users', 'User management endpoints')
  .addTag('Health', 'Health check endpoints')
  .build();
