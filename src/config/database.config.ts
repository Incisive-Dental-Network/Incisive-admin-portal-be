import { registerAs } from '@nestjs/config';

export default registerAs('database', () => ({
  host: process.env.DB_HOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
  name: process.env.DB_NAME || 'postgres',
  ssl: process.env.DB_SSL === 'true',
  url: process.env.DATABASE_URL,
}));
