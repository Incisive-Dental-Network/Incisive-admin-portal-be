# Database Migrations

This folder contains SQL migration scripts for the database schema.

## Running Migrations

### Using psql (command line)
```bash
# Local development
psql -h localhost -U postgres -d your_database -f prisma/migrations/001_create_users_table.sql

# Production RDS
psql -h your-rds-endpoint.amazonaws.com -U postgres -d your_database -f prisma/migrations/001_create_users_table.sql
```

### Using npm script
```bash
# Add DATABASE_URL to .env first, then:
npm run db:migrate
```

### Using AWS RDS Query Editor
1. Go to AWS Console > RDS > Query Editor
2. Connect to your database
3. Copy and paste the SQL from the migration file
4. Execute

## Migration Files

| File | Description |
|------|-------------|
| 001_create_users_table.sql | Creates users table for authentication |

## Default Admin User

After running migrations, a default admin user is created:
- **Email:** admin@ex.com
- **Password:** (your bcrypt hashed password)

**IMPORTANT:** Change this password immediately after first login in production!

## Adding New Migrations

1. Create a new file with the next sequence number: `002_description.sql`
2. Make migrations idempotent (safe to run multiple times)
3. Test locally before running in production
4. Document the migration in this README
